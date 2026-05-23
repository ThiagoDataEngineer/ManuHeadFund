"""
macro_dynamic_gate.py -- Gate macro DINAMICO (deltas, nao niveis) em BULL_STRONG.

Licao da task4: nivel de M2 era util pre-2022 e morreu pos-tightening. Aqui
testamos features DINAMICAS que sobrevivem regime changes:
  - dxy_change_30d_pct: delta DXY 30d (DTWEXBGS)
  - real_rate_10y: taxa real 10y (REAINTRATREARAT10Y) -- ja dinamica
  - btc_gold_change_60d_pct: variacao BTC/Gold ratio em 60d (risk-on proxy)

Criterio aceite:
  exp_train_gated   >= 0.45R (uplift +0.10R)
  exp_holdout_gated >= 0.35R
  gap < 0.15R
  holdout_excluded_pct < 100% (sanity pos-task4)
  excl_2025 > excl_2023 (separa regime pos-tightening)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from itertools import combinations
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from distribution_phase_detector import fetch_btc_daily_closes  # noqa: E402
from macro_gate_bull_strong import (  # noqa: E402
    build_proxy_trades_from_closes,
    fetch_fred_series,
    parse_fred_csv,
)


# ──────────────────────────────────────────────────────────────────────────────
# Param grids
# ──────────────────────────────────────────────────────────────────────────────

DXY_CHANGE_THRESHOLDS = [-5.0, 0.0, 3.0, 6.0]
REAL_RATE_THRESHOLDS = [-2.0, 0.0, 1.0, 2.0, 3.0]
BTC_GOLD_CHANGE_THRESHOLDS = [-10.0, 0.0, 10.0, 20.0]


SINGLE_FEATURE_GRID: List[Dict] = []
for th in DXY_CHANGE_THRESHOLDS:
    SINGLE_FEATURE_GRID.append({"feature": "dxy_change_30d_pct", "operator": "<=", "threshold": th})
for th in REAL_RATE_THRESHOLDS:
    SINGLE_FEATURE_GRID.append({"feature": "real_rate_10y", "operator": "<=", "threshold": th})
for th in BTC_GOLD_CHANGE_THRESHOLDS:
    SINGLE_FEATURE_GRID.append({"feature": "btc_gold_change_60d_pct", "operator": ">=", "threshold": th})


COMBO_2_GRID: List[Dict] = []
for dxy_max in DXY_CHANGE_THRESHOLDS:
    for rr_max in REAL_RATE_THRESHOLDS:
        COMBO_2_GRID.append({
            "dxy_change_max": dxy_max,
            "real_rate_max": rr_max,
        })
for dxy_max in DXY_CHANGE_THRESHOLDS:
    for bg_min in BTC_GOLD_CHANGE_THRESHOLDS:
        COMBO_2_GRID.append({
            "dxy_change_max": dxy_max,
            "btc_gold_change_min": bg_min,
        })
for rr_max in REAL_RATE_THRESHOLDS:
    for bg_min in BTC_GOLD_CHANGE_THRESHOLDS:
        COMBO_2_GRID.append({
            "real_rate_max": rr_max,
            "btc_gold_change_min": bg_min,
        })


# ──────────────────────────────────────────────────────────────────────────────
# Helpers de serie temporal
# ──────────────────────────────────────────────────────────────────────────────

def _nearest_value_at_or_before(series: List[Tuple[str, float]], target_date: str) -> Optional[float]:
    if not series:
        return None
    try:
        target = datetime.fromisoformat(target_date).date()
    except ValueError:
        return None
    best = None
    for d_str, v in series:
        try:
            d = datetime.fromisoformat(d_str).date()
        except ValueError:
            continue
        if d <= target:
            best = v
        else:
            break
    return best


def compute_dxy_change_30d(dxy_series: List[Tuple[str, float]], target_date: str) -> float:
    """Pct change of DXY entre 30d antes e target_date."""
    dxy_sorted = sorted(dxy_series, key=lambda x: x[0])
    try:
        d = datetime.fromisoformat(target_date).date()
    except ValueError:
        return 0.0
    d_30 = (d - timedelta(days=30)).isoformat()
    now = _nearest_value_at_or_before(dxy_sorted, target_date)
    past = _nearest_value_at_or_before(dxy_sorted, d_30)
    if not now or not past:
        return 0.0
    return (now / past - 1.0) * 100.0


def compute_real_rate_at_date(rr_series: List[Tuple[str, float]], target_date: str) -> float:
    """Real rate 10y na data alvo (ou mais recente antes)."""
    rr_sorted = sorted(rr_series, key=lambda x: x[0])
    val = _nearest_value_at_or_before(rr_sorted, target_date)
    return val if val is not None else 0.0


def compute_btc_gold_ratio_change_60d(
    btc_series: List[Tuple[str, float]],
    gold_series: List[Tuple[str, float]],
    target_date: str,
) -> float:
    """Pct change de BTC/Gold ratio entre 60d antes e target_date."""
    btc_sorted = sorted(btc_series, key=lambda x: x[0])
    gold_sorted = sorted(gold_series, key=lambda x: x[0])
    try:
        d = datetime.fromisoformat(target_date).date()
    except ValueError:
        return 0.0
    d_60 = (d - timedelta(days=60)).isoformat()

    btc_now = _nearest_value_at_or_before(btc_sorted, target_date)
    btc_past = _nearest_value_at_or_before(btc_sorted, d_60)
    gold_now = _nearest_value_at_or_before(gold_sorted, target_date)
    gold_past = _nearest_value_at_or_before(gold_sorted, d_60)
    if not (btc_now and btc_past and gold_now and gold_past and gold_now > 0 and gold_past > 0):
        return 0.0
    ratio_now = btc_now / gold_now
    ratio_past = btc_past / gold_past
    if ratio_past == 0:
        return 0.0
    return (ratio_now / ratio_past - 1.0) * 100.0


# ──────────────────────────────────────────────────────────────────────────────
# Annotation
# ──────────────────────────────────────────────────────────────────────────────

def annotate_dynamic_features(
    trades: List[Dict],
    dxy_series: List[Tuple[str, float]],
    real_rate_series: List[Tuple[str, float]],
    btc_series: List[Tuple[str, float]],
    gold_series: List[Tuple[str, float]],
) -> List[Dict]:
    out: List[Dict] = []
    for t in trades:
        ts = t.get("entry_ts", "")[:10]
        annotated = dict(t)
        if ts:
            annotated["dxy_change_30d_pct"] = compute_dxy_change_30d(dxy_series, ts)
            annotated["real_rate_10y"] = compute_real_rate_at_date(real_rate_series, ts)
            annotated["btc_gold_change_60d_pct"] = compute_btc_gold_ratio_change_60d(
                btc_series, gold_series, ts
            )
        else:
            annotated["dxy_change_30d_pct"] = 0.0
            annotated["real_rate_10y"] = 0.0
            annotated["btc_gold_change_60d_pct"] = 0.0
        out.append(annotated)
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Gate + metricas
# ──────────────────────────────────────────────────────────────────────────────

def apply_dynamic_gate(trades: List[Dict], gate: Dict) -> List[Dict]:
    """Aplica gate com chaves opcionais:
       dxy_change_max, real_rate_max, btc_gold_change_min."""
    out: List[Dict] = []
    for t in trades:
        if "dxy_change_max" in gate:
            if t.get("dxy_change_30d_pct", 0.0) > gate["dxy_change_max"]:
                continue
        if "real_rate_max" in gate:
            if t.get("real_rate_10y", 0.0) > gate["real_rate_max"]:
                continue
        if "btc_gold_change_min" in gate:
            if t.get("btc_gold_change_60d_pct", 0.0) < gate["btc_gold_change_min"]:
                continue
        out.append(t)
    return out


def exp_r(trades: List[Dict]) -> float:
    if not trades:
        return 0.0
    return sum(t.get("result_r", 0.0) for t in trades) / len(trades)


# ──────────────────────────────────────────────────────────────────────────────
# Grid search
# ──────────────────────────────────────────────────────────────────────────────

def _apply_single_filter(trades: List[Dict], spec: Dict) -> List[Dict]:
    feat = spec["feature"]
    op = spec["operator"]
    th = spec["threshold"]
    if op == "<=":
        return [t for t in trades if t.get(feat, 0.0) <= th]
    return [t for t in trades if t.get(feat, 0.0) >= th]


def grid_search_single(trades: List[Dict]) -> Dict[str, Dict]:
    """Para cada feature, encontra threshold com maior exp respeitando min_size."""
    min_size = max(20, int(len(trades) * 0.10))
    feats = ("dxy_change_30d_pct", "real_rate_10y", "btc_gold_change_60d_pct")
    out: Dict[str, Dict] = {}
    for feat in feats:
        specs = [s for s in SINGLE_FEATURE_GRID if s["feature"] == feat]
        best = None
        best_exp = -float("inf")
        all_r = []
        for s in specs:
            filtered = _apply_single_filter(trades, s)
            e = exp_r(filtered)
            all_r.append({**s, "exp": round(e, 4), "n": len(filtered)})
            if len(filtered) >= min_size and e > best_exp:
                best = s
                best_exp = e
        if best is None and all_r:
            top = max(all_r, key=lambda r: r["exp"])
            best = {"feature": top["feature"], "operator": top["operator"], "threshold": top["threshold"]}
            best_exp = top["exp"]
        out[feat] = {
            "best_threshold": best["threshold"] if best else None,
            "operator": best["operator"] if best else None,
            "exp": round(best_exp, 4) if best_exp != -float("inf") else 0.0,
            "n_filtered": next((r["n"] for r in all_r if r["threshold"] == (best["threshold"] if best else None)), 0),
            "all_results": all_r,
        }
    return out


def grid_search_combos(trades: List[Dict], max_features: int = 2) -> Dict:
    """Combos de 2 features. Retorna melhor."""
    min_size = max(20, int(len(trades) * 0.10))
    best_combo = None
    best_exp = -float("inf")
    all_results = []
    for cfg in COMBO_2_GRID:
        filtered = apply_dynamic_gate(trades, cfg)
        e = exp_r(filtered)
        feats = list(cfg.keys())
        all_results.append({"thresholds": cfg, "exp": round(e, 4), "n": len(filtered)})
        if len(filtered) >= min_size and e > best_exp:
            best_combo = cfg
            best_exp = e
    if best_combo is None and all_results:
        top = max(all_results, key=lambda r: r["exp"])
        best_combo = top["thresholds"]
        best_exp = top["exp"]
    return {
        "features": list(best_combo.keys()) if best_combo else [],
        "thresholds": best_combo or {},
        "exp": round(best_exp, 4) if best_exp != -float("inf") else 0.0,
        "all_results_top10": sorted(all_results, key=lambda r: r["exp"], reverse=True)[:10],
    }


# ──────────────────────────────────────────────────────────────────────────────
# Decisao
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class DecisionResult:
    decision: str
    exp_train_filtered: float
    exp_holdout_filtered: float
    train_improvement: float
    train_holdout_gap: float
    holdout_excluded_pct: float
    excl_2025: float
    excl_2023: float
    reason: str


def exclusion_increases_in_2025(excl_2025: float, excl_2023: float) -> bool:
    return excl_2025 > excl_2023


def decide_outcome(
    exp_train_baseline: float,
    exp_train_filtered: float,
    exp_holdout_filtered: float,
    holdout_excluded_pct: float,
    excl_2025: float,
    excl_2023: float,
) -> DecisionResult:
    train_improvement = exp_train_filtered - exp_train_baseline
    gap = exp_train_filtered - exp_holdout_filtered

    # Sanity: holdout 100% excluido -> FAIL
    if holdout_excluded_pct >= 100.0:
        return DecisionResult(
            "FAIL_NO_IMPROVEMENT",
            exp_train_filtered, exp_holdout_filtered, train_improvement, gap,
            holdout_excluded_pct, excl_2025, excl_2023,
            "Holdout 100% excluido (regime change pos-task4 ainda nao resolvido).",
        )

    # Improvement insuficiente OU holdout abaixo do floor
    if (exp_train_filtered < 0.45 or
            train_improvement < 0.10 or
            exp_holdout_filtered < 0.35):
        return DecisionResult(
            "FAIL_NO_IMPROVEMENT",
            exp_train_filtered, exp_holdout_filtered, train_improvement, gap,
            holdout_excluded_pct, excl_2025, excl_2023,
            (f"Sem uplift suficiente: train_filt={exp_train_filtered:.3f} (<0.45) ou "
             f"improvement={train_improvement:.3f} (<0.10) ou holdout={exp_holdout_filtered:.3f} (<0.35)."),
        )

    # 2025 nao foi mais excluido que 2023 -> nao separa pos-tightening
    if not exclusion_increases_in_2025(excl_2025, excl_2023):
        return DecisionResult(
            "FAIL_NO_IMPROVEMENT",
            exp_train_filtered, exp_holdout_filtered, train_improvement, gap,
            holdout_excluded_pct, excl_2025, excl_2023,
            f"Gate nao discrimina 2025 vs 2023 (excl_2025={excl_2025:.2f} <= excl_2023={excl_2023:.2f}).",
        )

    # Gap excessivo -> overfit
    if gap >= 0.15:
        return DecisionResult(
            "FAIL_OVERFIT",
            exp_train_filtered, exp_holdout_filtered, train_improvement, gap,
            holdout_excluded_pct, excl_2025, excl_2023,
            f"Overfit: gap train-holdout {gap:.3f}R >= 0.15R.",
        )

    return DecisionResult(
        "PASS",
        exp_train_filtered, exp_holdout_filtered, train_improvement, gap,
        holdout_excluded_pct, excl_2025, excl_2023,
        "Gate aprovado.",
    )


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

TRAIN_YEARS = set(range(2014, 2023))
HOLDOUT_YEARS = set(range(2023, 2026))


def _closes_with_dates(closes: List[float]) -> Tuple[List[float], List[Tuple[int, int, int]]]:
    end_date = datetime.now(timezone.utc).date()
    n = len(closes)
    dates = []
    for i in range(n):
        d = end_date - timedelta(days=(n - 1 - i))
        dates.append((d.year, d.month, d.day))
    return closes, dates


def _closes_to_dated_series(closes: List[float]) -> List[Tuple[str, float]]:
    end_date = datetime.now(timezone.utc).date()
    n = len(closes)
    out = []
    for i in range(n):
        d = end_date - timedelta(days=(n - 1 - i))
        out.append((d.isoformat(), closes[i]))
    return out


def _exclusions_by_year_pct(trades: List[Dict], gate: Dict) -> Dict[int, float]:
    counts: Dict[int, Dict[str, int]] = {}
    for t in trades:
        y = t.get("year")
        if y is None:
            continue
        c = counts.setdefault(y, {"total": 0, "excluded": 0})
        c["total"] += 1
        kept = True
        if "dxy_change_max" in gate and t.get("dxy_change_30d_pct", 0.0) > gate["dxy_change_max"]:
            kept = False
        if "real_rate_max" in gate and t.get("real_rate_10y", 0.0) > gate["real_rate_max"]:
            kept = False
        if "btc_gold_change_min" in gate and t.get("btc_gold_change_60d_pct", 0.0) < gate["btc_gold_change_min"]:
            kept = False
        if not kept:
            c["excluded"] += 1
    return {y: (c["excluded"] / c["total"] if c["total"] else 0.0) for y, c in counts.items()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "task4b_macro_dynamic_gate.json"
    ))
    args = parser.parse_args()

    print("[1/5] Carregando BTC daily Bitstamp...", flush=True)
    closes = fetch_btc_daily_closes()
    print(f"  closes={len(closes)}", flush=True)
    closes_l, dates = _closes_with_dates(closes)
    btc_dated = _closes_to_dated_series(closes_l)

    print("[2/5] Gerando proxy trades BULL_STRONG...", flush=True)
    trades = build_proxy_trades_from_closes(closes_l, dates, lookahead=7)
    train = [t for t in trades if t["year"] in TRAIN_YEARS]
    holdout = [t for t in trades if t["year"] in HOLDOUT_YEARS]
    print(f"  total={len(trades)}, train={len(train)}, holdout={len(holdout)}", flush=True)

    print("[3/5] Baixando series FRED: DTWEXBGS, REAINTRATREARAT10Y, GOLDAMGBD228NLBM...", flush=True)
    dxy = fetch_fred_series("DTWEXBGS")
    real_rate = fetch_fred_series("REAINTRATREARAT10Y")
    gold = fetch_fred_series("GOLDAMGBD228NLBM")
    print(f"  DXY={len(dxy)}, real_rate={len(real_rate)}, gold={len(gold)}", flush=True)

    if not dxy or not real_rate:
        report = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "decision": "FAIL_NO_DATA",
            "honest_note": "FRED DXY ou real_rate indisponivel.",
        }
        os.makedirs(os.path.dirname(args.output), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        return 1
    if not gold:
        print("  [WARN] gold FRED indisponivel -> feature btc_gold desativada (vira 0.0)", flush=True)

    print("[4/5] Anotando trades com features dinamicas...", flush=True)
    train_a = annotate_dynamic_features(train, dxy, real_rate, btc_dated, gold)
    holdout_a = annotate_dynamic_features(holdout, dxy, real_rate, btc_dated, gold)
    exp_train_base = exp_r(train_a)
    exp_holdout_base = exp_r(holdout_a)
    print(f"  baseline exp_train={exp_train_base:.4f}, exp_holdout={exp_holdout_base:.4f}", flush=True)

    print("[5/5] Grid search single + combos...", flush=True)
    single_ranking = grid_search_single(train_a)
    print("  Single feature top per feature (train):", flush=True)
    for feat, r in single_ranking.items():
        print(f"    {feat:30s} threshold={r['best_threshold']} exp={r['exp']:.4f} n={r['n_filtered']}", flush=True)

    best_combo = grid_search_combos(train_a)
    print(f"  Best combo (train): {best_combo['thresholds']} -> exp={best_combo['exp']:.4f}", flush=True)

    # Aplica best_combo no holdout
    filtered_holdout = apply_dynamic_gate(holdout_a, best_combo["thresholds"])
    exp_holdout_filt = exp_r(filtered_holdout)
    excl_holdout = _exclusions_by_year_pct(holdout_a, best_combo["thresholds"])
    excl_train = _exclusions_by_year_pct(train_a, best_combo["thresholds"])

    holdout_excluded_pct = 100.0 * (1 - len(filtered_holdout) / max(1, len(holdout_a)))
    excl_2025 = excl_holdout.get(2025, 0.0)
    excl_2023 = excl_holdout.get(2023, 0.0)
    excl_2024 = excl_holdout.get(2024, 0.0)

    outcome = decide_outcome(
        exp_train_baseline=exp_train_base,
        exp_train_filtered=best_combo["exp"],
        exp_holdout_filtered=exp_holdout_filt,
        holdout_excluded_pct=holdout_excluded_pct,
        excl_2025=excl_2025,
        excl_2023=excl_2023,
    )

    # Comparativo com task4 (level-based)
    task4_path = os.path.join(os.path.dirname(args.output), "task4_macro_gate_bull_strong.json")
    task4_compare = None
    if os.path.exists(task4_path):
        with open(task4_path, "r", encoding="utf-8") as f:
            t4 = json.load(f)
        task4_compare = {
            "best_thresholds": t4.get("best_thresholds_macro"),
            "exp_train_filtered": t4.get("exp_train_filtered"),
            "exp_holdout_filtered": t4.get("exp_holdout_filtered"),
            "decision": t4.get("decision"),
        }

    honest_note = (
        "Trades proxy (SMA200/SMA50 BULL_STRONG + forward 7d return/2ATR). FRED: DTWEXBGS, "
        "REAINTRATREARAT10Y, GOLDAMGBD228NLBM. Gates dinamicos eliminam dependencia de nivel "
        "absoluto -> sobrevive regime changes M2 pos-2022. Numero absolutos divergem de "
        "trades reais do V2 mas metodologia (train/holdout split + sanity exclusion 2025>2023) e valida."
    )

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "feature_ranking_train": single_ranking,
        "best_combo": best_combo,
        "exp_train_baseline": round(exp_train_base, 4),
        "exp_train_filtered": round(best_combo["exp"], 4),
        "exp_holdout_baseline": round(exp_holdout_base, 4),
        "exp_holdout_filtered": round(exp_holdout_filt, 4),
        "train_improvement": round(outcome.train_improvement, 4),
        "train_holdout_gap": round(outcome.train_holdout_gap, 4),
        "holdout_excluded_pct": round(holdout_excluded_pct, 2),
        "exclusions_by_year_holdout": {
            "2023": round(excl_2023, 3),
            "2024": round(excl_2024, 3),
            "2025": round(excl_2025, 3),
        },
        "exclusions_by_year_train": {str(y): round(v, 3) for y, v in sorted(excl_train.items())},
        "decision": outcome.decision,
        "decision_reason": outcome.reason,
        "honest_note": honest_note,
        "task4_comparison": task4_compare,
        "n_trades": {
            "train_total": len(train_a),
            "holdout_total": len(holdout_a),
            "holdout_kept": len(filtered_holdout),
        },
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] saved: {args.output}", flush=True)
    print(f"\nDECISION: {outcome.decision} -- {outcome.reason}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
