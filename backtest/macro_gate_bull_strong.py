"""
macro_gate_bull_strong.py -- Gate macro (DXY + M2 YoY) em trades BULL_STRONG.

Hipotese: 2025 degradou (+0.23R vs +0.61R em 2023) por regime macro diferente.
Test: gate DXY<X AND M2_YoY>Y melhora exp no train E generaliza pro holdout
sem overfit.

Pipeline:
  1. Construir/carregar trades BULL_STRONG (entry_ts, result_r, year)
  2. Baixar DXY (FRED DTWEXBGS) + M2 (FRED M2SL)
  3. Anotar cada trade com DXY level, DXY MoM, M2 YoY
  4. Grid search no train; aplica best no holdout
  5. Decide PASS/FAIL_OVERFIT/FAIL_NO_IMPROVEMENT

Sem DB direto: gera proxy trades BULL_STRONG via classificador SMA+EMA
sobre BTC daily, com result_r = forward 7-day return / ATR.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from typing import Dict, List, Optional, Sequence, Tuple

import requests

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from distribution_phase_detector import _sma, fetch_btc_daily_closes  # noqa: E402


# ──────────────────────────────────────────────────────────────────────────────
# Grid de parametros macro
# ──────────────────────────────────────────────────────────────────────────────

DXY_M2_PARAM_GRID: List[Dict] = []
# DXY DTWEXBGS range historico: 85-130 (mean ~106). Grid centrado nessa faixa.
for dxy_max in (100.0, 105.0, 110.0, 115.0, 120.0, 130.0):
    for m2_min in (-5.0, 0.0, 3.0, 6.0, 9.0):
        DXY_M2_PARAM_GRID.append({"dxy_max": dxy_max, "m2_yoy_min": m2_min})


# ──────────────────────────────────────────────────────────────────────────────
# BULL_STRONG day classifier
# ──────────────────────────────────────────────────────────────────────────────

def classify_bull_strong_day(closes: Sequence[float]) -> bool:
    """BULL_STRONG: price > SMA200 AND SMA50 > SMA200; rising se ha 230d."""
    if len(closes) < 220:
        return False
    current = closes[-1]
    sma200 = _sma(closes, 200)
    sma50 = _sma(closes, 50)
    if not (sma200 and sma50):
        return False
    if current <= sma200 or sma50 <= sma200:
        return False
    if len(closes) >= 230:
        sma200_30d_ago = _sma(closes[:-30], 200)
        if sma200_30d_ago and sma200 <= sma200_30d_ago * 1.01:
            return False
    return True


def build_proxy_trades_from_closes(
    closes: Sequence[float],
    dates: Sequence[Tuple[int, int, int]],
    lookahead: int = 7,
    atr_window: int = 14,
) -> List[Dict]:
    """Gera trades BULL_STRONG proxy: cada dia BULL_STRONG -> trade entry,
    result_r = forward N-day return / typical_daily_move (proxy de R).
    """
    closes = list(closes)
    n = len(closes)
    if len(dates) != n:
        return []
    trades: List[Dict] = []
    for i in range(220, n - lookahead):
        window = closes[max(0, i - 220):i + 1]
        if not classify_bull_strong_day(window):
            continue
        entry = closes[i]
        exit_price = closes[i + lookahead]
        # Proxy ATR via std dev of last 14 daily changes
        if i >= atr_window:
            changes = [abs(closes[j] - closes[j - 1]) for j in range(i - atr_window + 1, i + 1)]
            atr = sum(changes) / atr_window if changes else 1.0
        else:
            atr = 1.0
        if atr == 0:
            continue
        # 2 ATR de stop suposto -> result_r = (exit - entry) / (2 * atr)
        r = (exit_price - entry) / (2 * atr)
        y, m, d = dates[i]
        trades.append({
            "entry_ts": f"{y:04d}-{m:02d}-{d:02d}",
            "result_r": r,
            "regime": "BULL_STRONG",
            "year": y,
            "entry_price": entry,
        })
    return trades


# ──────────────────────────────────────────────────────────────────────────────
# FRED CSV
# ──────────────────────────────────────────────────────────────────────────────

FRED_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id={series}"


def parse_fred_csv(csv_text: str) -> List[Tuple[str, float]]:
    """Parse 'DATE,VALUE' lines, pula '.' missing."""
    out: List[Tuple[str, float]] = []
    reader = csv.reader(io.StringIO(csv_text))
    header = next(reader, None)
    if not header:
        return out
    for row in reader:
        if len(row) < 2:
            continue
        date_str = row[0].strip()
        val_str = row[1].strip()
        if val_str in (".", "", "NA"):
            continue
        try:
            out.append((date_str, float(val_str)))
        except ValueError:
            continue
    return out


def fetch_fred_series(series_id: str) -> List[Tuple[str, float]]:
    """Baixa FRED CSV publico."""
    try:
        r = requests.get(FRED_URL.format(series=series_id), timeout=20)
        r.raise_for_status()
        return parse_fred_csv(r.text)
    except Exception:
        return []


# ──────────────────────────────────────────────────────────────────────────────
# Annotacao macro
# ──────────────────────────────────────────────────────────────────────────────

def _nearest_value_at_or_before(series: List[Tuple[str, float]], target_date: str) -> Optional[float]:
    """Procura value mais recente em series com data <= target_date.
    series assumido em ordem cronologica ASC.
    """
    if not series:
        return None
    target = datetime.fromisoformat(target_date).date()
    # Linear simples (series sao pequenas)
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


def annotate_trades_with_macro(
    trades: List[Dict],
    dxy_series: List[Tuple[str, float]],
    m2_series: List[Tuple[str, float]],
) -> List[Dict]:
    """Adiciona dxy_level, dxy_mom_change_pct, m2_yoy_change_pct."""
    # Series ordenadas asc
    dxy_sorted = sorted(dxy_series, key=lambda x: x[0])
    m2_sorted = sorted(m2_series, key=lambda x: x[0])

    out: List[Dict] = []
    for t in trades:
        entry_ts = t.get("entry_ts", "")[:10]
        if not entry_ts:
            out.append(t)
            continue

        dxy_now = _nearest_value_at_or_before(dxy_sorted, entry_ts)
        # MoM: 30 dias antes
        try:
            d = datetime.fromisoformat(entry_ts).date()
            d_mom = (d - timedelta(days=30)).isoformat()
            d_yoy = (d - timedelta(days=365)).isoformat()
        except ValueError:
            d_mom = d_yoy = entry_ts
        dxy_mom = _nearest_value_at_or_before(dxy_sorted, d_mom)
        m2_now = _nearest_value_at_or_before(m2_sorted, entry_ts)
        m2_yoy_base = _nearest_value_at_or_before(m2_sorted, d_yoy)

        annotated = dict(t)
        annotated["dxy_level"] = dxy_now if dxy_now else 0.0
        annotated["dxy_mom_change_pct"] = (
            (dxy_now / dxy_mom - 1.0) * 100.0 if dxy_now and dxy_mom else 0.0
        )
        annotated["m2_yoy_change_pct"] = (
            (m2_now / m2_yoy_base - 1.0) * 100.0 if m2_now and m2_yoy_base else 0.0
        )
        out.append(annotated)
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Gate + metricas
# ──────────────────────────────────────────────────────────────────────────────

def apply_macro_gate(trades: List[Dict], gate: Dict) -> List[Dict]:
    """Mantem trades com dxy_level <= gate['dxy_max'] AND m2_yoy >= gate['m2_yoy_min']."""
    return [
        t for t in trades
        if t.get("dxy_level", 0.0) <= gate["dxy_max"]
        and t.get("m2_yoy_change_pct", 0.0) >= gate["m2_yoy_min"]
    ]


def exp_r(trades: List[Dict]) -> float:
    if not trades:
        return 0.0
    return sum(t.get("result_r", 0.0) for t in trades) / len(trades)


def grid_search(
    train_trades: List[Dict],
    grid: List[Dict],
) -> Tuple[Dict, float, List[Dict]]:
    best_cfg = None
    best_exp = -float("inf")
    all_results: List[Dict] = []
    min_size = max(20, int(len(train_trades) * 0.10))
    for cfg in grid:
        filtered = apply_macro_gate(train_trades, cfg)
        e = exp_r(filtered)
        all_results.append({**cfg, "exp": round(e, 4), "n": len(filtered)})
        if len(filtered) >= min_size and e > best_exp:
            best_exp = e
            best_cfg = cfg
    # Fallback se nenhum config passar min-size: pega o cfg com maior exp entre
    # os que tem N>=1
    if best_cfg is None:
        viable = [r for r in all_results if r["n"] >= 1]
        if viable:
            top = max(viable, key=lambda r: r["exp"])
            best_cfg = {"dxy_max": top["dxy_max"], "m2_yoy_min": top["m2_yoy_min"]}
            best_exp = top["exp"]
        else:
            best_cfg = grid[-1]  # menos restritivo
            best_exp = 0.0
    return best_cfg, best_exp, all_results


def compute_exclusions_by_year(trades: List[Dict], gate: Dict) -> Dict[int, Dict]:
    out: Dict[int, Dict] = {}
    for t in trades:
        y = t.get("year")
        if y is None:
            continue
        if y not in out:
            out[y] = {"total": 0, "excluded": 0, "kept": 0}
        out[y]["total"] += 1
        if (t.get("dxy_level", 0.0) <= gate["dxy_max"]
                and t.get("m2_yoy_change_pct", 0.0) >= gate["m2_yoy_min"]):
            out[y]["kept"] += 1
        else:
            out[y]["excluded"] += 1
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Decisao
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class DecisionOutcome:
    decision: str  # PASS | FAIL_OVERFIT | FAIL_NO_IMPROVEMENT
    exp_train_filtered: float
    exp_holdout_filtered: float
    train_improvement: float
    train_holdout_gap: float
    reason: str


def decide_outcome(
    exp_train_baseline: float,
    exp_train_filtered: float,
    exp_holdout_filtered: float,
) -> DecisionOutcome:
    train_improvement = exp_train_filtered - exp_train_baseline
    train_holdout_gap = exp_train_filtered - exp_holdout_filtered

    # FAIL_NO_IMPROVEMENT primeiro: se train_improvement insuficiente OU
    # holdout abaixo do floor, gate nao serve -- independente do gap.
    if train_improvement < 0.10 or exp_holdout_filtered < 0.30:
        return DecisionOutcome(
            decision="FAIL_NO_IMPROVEMENT",
            exp_train_filtered=exp_train_filtered,
            exp_holdout_filtered=exp_holdout_filtered,
            train_improvement=train_improvement,
            train_holdout_gap=train_holdout_gap,
            reason=(f"Sem melhora suficiente: train_improvement={train_improvement:.3f}R "
                    f"(<0.10) ou holdout {exp_holdout_filtered:.3f}R (<0.30)."),
        )
    # Aqui train_improvement >= 0.10 E holdout >= 0.30. Decide PASS vs OVERFIT
    # pelo gap.
    if train_holdout_gap >= 0.20:
        return DecisionOutcome(
            decision="FAIL_OVERFIT",
            exp_train_filtered=exp_train_filtered,
            exp_holdout_filtered=exp_holdout_filtered,
            train_improvement=train_improvement,
            train_holdout_gap=train_holdout_gap,
            reason=f"Overfit: gap train-holdout {train_holdout_gap:.3f}R >= 0.20R.",
        )
    return DecisionOutcome(
        decision="PASS",
        exp_train_filtered=exp_train_filtered,
        exp_holdout_filtered=exp_holdout_filtered,
        train_improvement=train_improvement,
        train_holdout_gap=train_holdout_gap,
        reason="Gate aprovado: train melhora >=+0.10R, holdout >=+0.30R, gap <0.20R.",
    )


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def _closes_with_dates(closes: List[float]) -> Tuple[List[float], List[Tuple[int, int, int]]]:
    end_date = datetime.now(timezone.utc).date()
    n = len(closes)
    dates = []
    for i in range(n):
        d = end_date - timedelta(days=(n - 1 - i))
        dates.append((d.year, d.month, d.day))
    return closes, dates


TRAIN_YEARS = set(range(2014, 2023))
HOLDOUT_YEARS = set(range(2023, 2026))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "journal", "task4_macro_gate_bull_strong.json"
    ))
    args = parser.parse_args()

    print("[1/5] Carregando closes BTC daily Bitstamp...", flush=True)
    closes = fetch_btc_daily_closes()
    print(f"  closes={len(closes)}", flush=True)
    closes, dates = _closes_with_dates(closes)

    print("[2/5] Gerando proxy trades BULL_STRONG (lookahead 7d)...", flush=True)
    trades = build_proxy_trades_from_closes(closes, dates, lookahead=7)
    train = [t for t in trades if t["year"] in TRAIN_YEARS]
    holdout = [t for t in trades if t["year"] in HOLDOUT_YEARS]
    print(f"  total={len(trades)}, train={len(train)}, holdout={len(holdout)}", flush=True)

    print("[3/5] Baixando DXY (DTWEXBGS) + M2 (M2SL) de FRED...", flush=True)
    dxy = fetch_fred_series("DTWEXBGS")
    m2 = fetch_fred_series("M2SL")
    print(f"  DXY={len(dxy)} pontos, M2={len(m2)} pontos", flush=True)

    if not dxy or not m2:
        report = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "decision": "FAIL_NO_DATA",
            "honest_note": "FRED indisponivel. Sem dados macro nao da pra avaliar gate.",
        }
        os.makedirs(os.path.dirname(args.output), exist_ok=True)
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        print(f"\n[SAIDA] {args.output}")
        return 1

    print("[4/5] Anotando trades com macro features...", flush=True)
    train = annotate_trades_with_macro(train, dxy, m2)
    holdout = annotate_trades_with_macro(holdout, dxy, m2)

    exp_train_base = exp_r(train)
    exp_holdout_base = exp_r(holdout)
    print(f"  baseline exp_train={exp_train_base:.4f}, exp_holdout={exp_holdout_base:.4f}", flush=True)

    print("[5/5] Grid search no train + avaliacao no holdout...", flush=True)
    best_cfg, best_exp_train, all_results = grid_search(train, DXY_M2_PARAM_GRID)
    filtered_holdout = apply_macro_gate(holdout, best_cfg)
    exp_holdout_filt = exp_r(filtered_holdout)
    print(f"  best gate: {best_cfg}", flush=True)
    print(f"  exp_train_filtered={best_exp_train:.4f} (n={len(apply_macro_gate(train, best_cfg))})", flush=True)
    print(f"  exp_holdout_filtered={exp_holdout_filt:.4f} (n={len(filtered_holdout)})", flush=True)

    excl_train = compute_exclusions_by_year(train, best_cfg)
    excl_holdout = compute_exclusions_by_year(holdout, best_cfg)

    outcome = decide_outcome(exp_train_base, best_exp_train, exp_holdout_filt)
    print(f"\n  DECISION: {outcome.decision} -- {outcome.reason}", flush=True)

    honest_note = (
        "Trades proxy gerados via classificador BULL_STRONG simples sobre BTC daily Bitstamp "
        "(SMA200/SMA50 + slope) + forward 7d return / 2-ATR como R. NAO sao trades reais do "
        "signal_generator V2. Util pra testar metodologia do gate macro; estimativas absolutas "
        "podem divergir de trades reais. FRED DTWEXBGS = Nominal Broad Dollar Index."
    )

    report = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "best_thresholds_macro": best_cfg,
        "exp_train_baseline": round(exp_train_base, 4),
        "exp_train_filtered": round(best_exp_train, 4),
        "exp_holdout_baseline": round(exp_holdout_base, 4),
        "exp_holdout_filtered": round(exp_holdout_filt, 4),
        "train_improvement": round(outcome.train_improvement, 4),
        "train_holdout_gap": round(outcome.train_holdout_gap, 4),
        "trades_excluded_by_year": {
            "train": {str(k): v for k, v in sorted(excl_train.items())},
            "holdout": {str(k): v for k, v in sorted(excl_holdout.items())},
        },
        "decision": outcome.decision,
        "decision_reason": outcome.reason,
        "honest_note": honest_note,
        "n_trades": {
            "train_total": len(train),
            "train_kept": len(apply_macro_gate(train, best_cfg)),
            "holdout_total": len(holdout),
            "holdout_kept": len(filtered_holdout),
        },
        "all_grid_results": all_results,
    }

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n[OK] saved: {args.output}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
