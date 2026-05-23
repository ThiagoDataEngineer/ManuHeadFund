"""
benchmark_baseline_v2_with_filter.py -- Aplica detector pos-distribuicao
no baseline V2 LONG-only em 14 anos BTC.

Sem filtro: 9098 trades, exp 0.226R, pf 1.35, positive_years 66.7%, max_dd 382R.
Com filtro:
  - SAFE        : opera normal (sizing 100%)
  - WARNING     : sizing 50% (corta peso, mantem trade)
  - DANGER/BEAR : NAO opera

Estrategia de simulacao com filtro:
  1. Pega per-year baseline metrics do journal/benchmark_long_14y_results.json
  2. Pega closes BTCUSD Bitstamp diarios para 14y (2012-2025)
  3. Para cada dia, classifica detect_distribution_phase
  4. Para cada ano, calcula % do tempo em cada estado
  5. Estima metricas com filtro:
       trades_filtered     = trades_yr * (pct_safe + 0.5*pct_warning)
       expectancy_filtered = if pct_safe+warning > 0 ELSE 0
       max_dd_filtered     = max_dd_yr * (pct_safe+warning)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Dict, List, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from distribution_phase_detector import (  # noqa: E402
    detect_distribution_phase,
    fetch_btc_daily_closes,
)


BASELINE_14Y_JSON = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "journal", "benchmark_long_14y_results.json"
)

OUTPUT_JSON = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "journal", "task1_distribution_filter_results.json"
)


def load_baseline() -> Dict:
    with open(BASELINE_14Y_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def classify_days_by_year(closes_all: List[float], year_start: int, year_end: int) -> Dict[int, Dict]:
    """Para cada ano, classifica cada dia e retorna distribuicao de estados.

    Returns: { year: {safe_pct, warning_pct, danger_pct, bear_pct, n_days} }
    """
    n_total = len(closes_all)
    if n_total == 0:
        return {}

    # closes_all eh ordenado ASC. Precisamos mapear closes para datas.
    # Bitstamp daily closes alinhados a 1 close/dia. Computamos data assumindo
    # series termina hoje e cada close = 1 dia para tras.
    end_date = datetime.now(timezone.utc).date()
    # Mapa: idx -> year
    from datetime import timedelta
    idx_to_year: Dict[int, int] = {}
    for i in range(n_total):
        d = end_date - timedelta(days=(n_total - 1 - i))
        idx_to_year[i] = d.year

    result: Dict[int, Dict] = {}
    counts: Dict[int, Dict[str, int]] = {}
    # Classifica para cada idx onde temos >= 220 historico
    for i in range(220, n_total):
        y = idx_to_year[i]
        if y < year_start or y > year_end:
            continue
        window = closes_all[i - 220:i + 1]
        r = detect_distribution_phase(daily_closes=window, fear_greed=50, funding_rate_8h=0.0)
        if y not in counts:
            counts[y] = {"SAFE": 0, "WARNING": 0, "DANGER": 0, "BEAR_CONFIRMED": 0}
        counts[y][r["state"]] = counts[y].get(r["state"], 0) + 1

    for y, c in counts.items():
        total = sum(c.values())
        if total == 0:
            continue
        result[y] = {
            "safe_pct": c["SAFE"] / total,
            "warning_pct": c["WARNING"] / total,
            "danger_pct": c["DANGER"] / total,
            "bear_pct": c["BEAR_CONFIRMED"] / total,
            "n_days": total,
        }
    return result


def apply_filter_to_year(
    year_metrics: Dict,
    state_distribution: Dict,
) -> Dict:
    """Aplica filtro a um ano: sizing 50% em WARNING, 0% em DANGER/BEAR."""
    trades = year_metrics["trades"]
    exp_r = year_metrics["expectancy_r"]
    max_dd = year_metrics["max_drawdown_r"]
    pf = year_metrics["profit_factor"]

    safe_pct = state_distribution.get("safe_pct", 1.0)
    warn_pct = state_distribution.get("warning_pct", 0.0)
    danger_pct = state_distribution.get("danger_pct", 0.0)
    bear_pct = state_distribution.get("bear_pct", 0.0)

    # Trades preservados (proporcional ao tempo em SAFE+WARNING)
    trades_kept = trades * (safe_pct + warn_pct)
    # Sizing efetivo medio: SAFE pct + 0.5*WARNING pct
    avg_sizing = safe_pct + 0.5 * warn_pct
    # Expectancy preservado (mesmo edge nos trades operados, escalado por sizing)
    exp_filtered = exp_r * (avg_sizing / max(0.01, safe_pct + warn_pct)) if (safe_pct + warn_pct) > 0 else 0.0
    # Equity final = trades_filtered * exp_filtered (em R)
    final_eq = trades_kept * exp_filtered
    # DD proporcional a tempo operado (assume DD reduz quando paramos)
    max_dd_filtered = max_dd * avg_sizing
    # PF: mantemos (mesmo edge per trade)
    pf_filtered = pf

    return {
        "trades_original": trades,
        "trades_filtered": round(trades_kept, 1),
        "trades_skipped": round(trades - trades_kept, 1),
        "expectancy_r_original": exp_r,
        "expectancy_r_filtered": round(exp_filtered, 4),
        "final_equity_r_filtered": round(final_eq, 2),
        "max_dd_r_original": max_dd,
        "max_dd_r_filtered": round(max_dd_filtered, 2),
        "pf_original": pf,
        "pf_filtered": pf_filtered,
        "state_distribution": state_distribution,
    }


def build_report(baseline: Dict, closes: List[float]) -> Dict:
    by_year = baseline.get("by_year", [])
    years = [y["year"] for y in by_year]
    state_dist = classify_days_by_year(closes, min(years), max(years))

    filtered_by_year: List[Dict] = []
    total_trades_filtered = 0.0
    total_trades_skipped_danger = 0.0
    total_eq_filtered = 0.0
    total_eq_baseline = 0.0
    positive_years_filtered = 0
    max_dd_filtered_overall = 0.0
    pf_weighted_num = 0.0
    pf_weighted_den = 0.0

    for y_row in by_year:
        y = y_row["year"]
        dist = state_dist.get(y, {"safe_pct": 1.0, "warning_pct": 0.0,
                                  "danger_pct": 0.0, "bear_pct": 0.0, "n_days": 0})
        f = apply_filter_to_year(y_row, dist)
        f["year"] = y
        filtered_by_year.append(f)

        total_trades_filtered += f["trades_filtered"]
        total_trades_skipped_danger += y_row["trades"] * (dist.get("danger_pct", 0) + dist.get("bear_pct", 0))
        total_eq_filtered += f["final_equity_r_filtered"]
        total_eq_baseline += y_row["trades"] * y_row["expectancy_r"]
        if f["expectancy_r_filtered"] > 0:
            positive_years_filtered += 1
        if f["max_dd_r_filtered"] > max_dd_filtered_overall:
            max_dd_filtered_overall = f["max_dd_r_filtered"]
        # PF aggregate: weight por trades filtered
        if f["trades_filtered"] > 0:
            pf_weighted_num += f["pf_filtered"] * f["trades_filtered"]
            pf_weighted_den += f["trades_filtered"]

    exp_filtered_overall = total_eq_filtered / total_trades_filtered if total_trades_filtered > 0 else 0.0
    pf_filtered_overall = pf_weighted_num / pf_weighted_den if pf_weighted_den > 0 else 0.0
    positive_years_pct_filtered = (positive_years_filtered / len(by_year)) * 100.0 if by_year else 0.0

    total_baseline = baseline["total"]

    without_filter = {
        "trades": total_baseline["trades"],
        "exp": round(total_baseline["expectancy_r"], 4),
        "pf": round(total_baseline["profit_factor"], 3),
        "positive_years_pct": baseline.get("positive_years_pct", 0.0),
        "max_dd": round(total_baseline["max_drawdown_r"], 2),
    }
    with_filter = {
        "trades": round(total_trades_filtered, 1),
        "exp": round(exp_filtered_overall, 4),
        "pf": round(pf_filtered_overall, 3),
        "positive_years_pct": round(positive_years_pct_filtered, 1),
        "max_dd": round(max_dd_filtered_overall, 2),
    }

    pos_delta = with_filter["positive_years_pct"] - without_filter["positive_years_pct"]
    pf_delta = with_filter["pf"] - without_filter["pf"]
    dd_reduction = (1.0 - with_filter["max_dd"] / without_filter["max_dd"]) * 100.0 if without_filter["max_dd"] > 0 else 0.0

    go_passed = with_filter["positive_years_pct"] >= 80.0 and with_filter["pf"] >= 1.7

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "without_filter": without_filter,
        "with_filter": with_filter,
        "improvement": {
            "positive_years_delta": round(pos_delta, 1),
            "pf_delta": round(pf_delta, 3),
            "dd_reduction_pct": round(dd_reduction, 2),
            "trades_skipped_in_danger_phase": round(total_trades_skipped_danger, 1),
        },
        "go_criterion": {
            "rule": "positive_years_pct >= 80% AND pf >= 1.7",
            "passed": go_passed,
        },
        "by_year": filtered_by_year,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=OUTPUT_JSON)
    args = parser.parse_args()

    print("[1/3] Carregando baseline 14y...")
    baseline = load_baseline()
    print(f"  baseline trades={baseline['total']['trades']}, exp={baseline['total']['expectancy_r']:.4f}")

    print("[2/3] Baixando closes BTC diarios (Bitstamp)...")
    closes = fetch_btc_daily_closes()
    print(f"  closes={len(closes)}")

    print("[3/3] Classificando dias e aplicando filtro...")
    report = build_report(baseline, closes)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print(f"\n[OK] saved: {args.output}\n")
    print(json.dumps({
        "without_filter": report["without_filter"],
        "with_filter": report["with_filter"],
        "improvement": report["improvement"],
        "go_criterion": report["go_criterion"],
    }, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
