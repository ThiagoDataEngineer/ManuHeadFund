"""
benchmark_bull_weak_trendline.py -- Multi-variant backtest 14y BTCUSD Bitstamp.

Hipotese refinada: testar 3 variantes de trendline (none / A+ 20-35deg / soft 5-15deg)
                    com e sem fees+slippage realistas.

Sub-analise: BULL_WEAK por ano + por halving cycle phase.

Output: journal/benchmark_bull_weak_trendline_results.json
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
from collections import defaultdict
from typing import Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from trendline_filter import get_trendline_score


CANDLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "btcusd_bitstamp_1day.json")

SMA200_PERIOD = 200
MOM_WINDOW = 20
ATR_PERIOD = 14
TRENDLINE_LOOKBACK = 30
HOLDOUT_BARS = 20
RR_TARGET = 5.0
BULL_WEAK_DIST_MAX = 0.20

# Realismo: fees CoinEx taker 0.20% + slippage tipico 0.10%
FEE_TAKER = 0.0020
SLIPPAGE = 0.0010
COST_PCT_PER_SIDE = FEE_TAKER + SLIPPAGE   # 0.30% por lado

# Halvings BTC (data UTC)
HALVINGS = [
    ("halving_2012", "2012-11-28"),
    ("halving_2016", "2016-07-09"),
    ("halving_2020", "2020-05-11"),
    ("halving_2024", "2024-04-19"),
]


def classify_regime(closes: List[float], idx: int) -> str:
    if idx < SMA200_PERIOD: return "NO_HIST"
    sma = sum(closes[idx - SMA200_PERIOD + 1:idx + 1]) / SMA200_PERIOD
    if sma <= 0: return "SIDEWAYS"
    cur = closes[idx]
    dist = (cur - sma) / sma
    if idx < MOM_WINDOW: return "NO_HIST"
    prev = closes[idx - MOM_WINDOW]
    mom = (cur - prev) / prev if prev > 0 else 0

    if dist > 0.20 and mom > 0.10: return "BULL_STRONG"
    if dist > 0 and mom > 0 and dist < BULL_WEAK_DIST_MAX: return "BULL_WEAK"
    if dist < -0.20 and mom < -0.10: return "BEAR_STRONG"
    if dist < 0 and mom < 0: return "BEAR_WEAK"
    if abs(dist) < 0.05: return "SIDEWAYS"
    return "TRANSITION"


def compute_atr(highs: List[float], lows: List[float], idx: int) -> float:
    if idx < ATR_PERIOD: return 0.0
    s = sum(highs[j] - lows[j] for j in range(idx - ATR_PERIOD + 1, idx + 1))
    return s / ATR_PERIOD


def simulate_long_r(entry: float, stop: float, target: float,
                    fwd_candles: List[Dict], apply_fees: bool = False) -> float:
    risk = entry - stop
    if risk <= 0: return 0.0

    # Custos em R: 2x (cost_per_side) sobre preco / risco
    cost_r = (2 * COST_PCT_PER_SIDE * entry) / risk if apply_fees else 0.0

    for c in fwd_candles:
        if c["low"] <= stop:
            return -1.0 - cost_r
        if c["high"] >= target:
            return (target - entry) / risk - cost_r

    if fwd_candles:
        last = fwd_candles[-1]["close"]
        return (last - entry) / risk - cost_r
    return 0.0


def trendline_variant_check(closes: List[float], highs: List[float],
                              lows: List[float], start: int, end: int,
                              slope_min: float, slope_max: float,
                              min_touches: int = 3) -> bool:
    score = get_trendline_score(closes[start:end+1], highs[start:end+1], lows[start:end+1])
    if score["touches"] < min_touches: return False
    sd = score["slope_deg"]
    return slope_min <= sd <= slope_max


def aggregate(r_series: List[float]) -> Dict:
    n = len(r_series)
    if n == 0:
        return {"n": 0, "expectancy_r": 0.0, "win_rate": 0.0, "profit_factor": 0.0,
                "sharpe_annual": 0.0, "max_dd_r": 0.0, "total_r": 0.0}
    wins = [r for r in r_series if r > 0]
    losses = [r for r in r_series if r < 0]
    exp = sum(r_series) / n
    win_rate = len(wins) / n
    gross_win = sum(wins); gross_loss = abs(sum(losses))
    pf = gross_win / gross_loss if gross_loss > 0 else 999.0
    mean = exp
    std = math.sqrt(sum((r - mean)**2 for r in r_series) / max(1, n - 1))
    sharpe_annual = (mean / std * math.sqrt(252)) if std > 0 else 0.0
    equity = 0.0; peak = 0.0; max_dd = 0.0
    for r in r_series:
        equity += r
        if equity > peak: peak = equity
        dd = peak - equity
        if dd > max_dd: max_dd = dd
    return {
        "n": n,
        "expectancy_r": round(exp, 4),
        "win_rate": round(win_rate, 4),
        "profit_factor": round(pf, 4),
        "sharpe_annual": round(sharpe_annual, 4),
        "max_dd_r": round(max_dd, 4),
        "total_r": round(sum(r_series), 4),
    }


def halving_phase(date_str: str) -> str:
    """Retorna fase do ciclo halving baseada na data do candle."""
    from datetime import datetime
    dt = datetime.fromisoformat(date_str.replace("Z", "+00:00") if "T" in date_str else date_str)
    dt = dt.replace(tzinfo=None) if dt.tzinfo else dt
    # Encontra halving mais recente <= dt
    last_halving = None
    last_name = "pre_halving"
    for name, hd in HALVINGS:
        hdt = datetime.fromisoformat(hd)
        if hdt <= dt:
            last_halving = hdt
            last_name = name
    if last_halving is None: return "pre_2012"
    months_since = (dt - last_halving).days / 30.44
    if months_since < 12: phase = "phase_1_bull"
    elif months_since < 18: phase = "phase_2_top"
    elif months_since < 30: phase = "phase_3_bear"
    else: phase = "phase_4_recovery"
    return f"{last_name}::{phase}"


VARIANTS = {
    "plain": (None, None),
    "aplus_20_35": (20.0, 35.0),
    "soft_5_15": (5.0, 15.0),
    "mid_15_25": (15.0, 25.0),
}


def run_backtest(apply_fees: bool = False) -> Dict:
    with open(CANDLES_PATH, "r", encoding="utf-8") as f:
        candles = json.load(f)
    closes = [c["close"] for c in candles]
    highs = [c["high"] for c in candles]
    lows = [c["low"] for c in candles]

    # r_series por variant
    variant_r = {v: [] for v in VARIANTS}
    # sub-analysis: por ano e por phase
    per_year_r = defaultdict(lambda: defaultdict(list))   # year -> variant -> list
    per_phase_r = defaultdict(lambda: defaultdict(list))  # phase -> variant -> list

    n_bull_weak = 0
    for i in range(SMA200_PERIOD, len(candles) - HOLDOUT_BARS):
        regime = classify_regime(closes, i)
        if regime != "BULL_WEAK": continue
        n_bull_weak += 1

        entry = closes[i]
        atr = compute_atr(highs, lows, i)
        if atr <= 0: continue
        stop = entry - 2.0 * atr
        target = entry + RR_TARGET * (entry - stop)
        fwd = candles[i + 1:i + 1 + HOLDOUT_BARS]
        r = simulate_long_r(entry, stop, target, fwd, apply_fees=apply_fees)

        ts = candles[i]["ts"]
        year = ts[:4]
        phase = halving_phase(ts)

        tl_lookback = min(TRENDLINE_LOOKBACK, i + 1)
        tl_start = i - tl_lookback + 1
        score = get_trendline_score(closes[tl_start:i+1], highs[tl_start:i+1], lows[tl_start:i+1])

        for variant_name, (smin, smax) in VARIANTS.items():
            if smin is None:
                passes = True  # plain
            else:
                passes = (score["touches"] >= 3) and (smin <= score["slope_deg"] <= smax)
            if passes:
                variant_r[variant_name].append(r)
                per_year_r[year][variant_name].append(r)
                per_phase_r[phase][variant_name].append(r)

    metrics = {v: aggregate(variant_r[v]) for v in VARIANTS}
    per_year_metrics = {y: {v: aggregate(per_year_r[y][v]) for v in VARIANTS} for y in sorted(per_year_r)}
    per_phase_metrics = {p: {v: aggregate(per_phase_r[p][v]) for v in VARIANTS} for p in sorted(per_phase_r)}

    return {
        "config": {
            "apply_fees": apply_fees,
            "fee_taker": FEE_TAKER,
            "slippage": SLIPPAGE,
            "cost_pct_per_side": COST_PCT_PER_SIDE,
            "rr_target": RR_TARGET,
            "holdout_bars": HOLDOUT_BARS,
            "trendline_lookback": TRENDLINE_LOOKBACK,
            "variants": {v: {"slope_min": s[0], "slope_max": s[1]} for v, s in VARIANTS.items()},
        },
        "n_bull_weak_candles": n_bull_weak,
        "metrics_by_variant": metrics,
        "per_year": per_year_metrics,
        "per_halving_phase": per_phase_metrics,
    }


def _print_variant_row(label: str, m: Dict):
    print(f"  {label:<18} n={m['n']:>5} exp={m['expectancy_r']:+.4f}R win={m['win_rate']*100:5.1f}% PF={m['profit_factor']:6.2f} Sharpe={m['sharpe_annual']:6.2f} DD={m['max_dd_r']:6.2f}R total={m['total_r']:+8.2f}R")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=None)
    parser.add_argument("--fees", action="store_true", help="Apply fees+slippage")
    parser.add_argument("--no-subanalysis", action="store_true", help="Skip year/phase breakdown")
    args = parser.parse_args()

    out = args.output or os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                       "journal", "benchmark_bull_weak_trendline_results.json")

    print("=" * 80)
    print(f"Benchmark BULL_WEAK + Trendline variants (14y BTCUSD Bitstamp) | fees={args.fees}")
    print("=" * 80)

    # Roda DUAS vezes: ideal (sem fees) e realista (com fees), pra comparar
    result_no_fees = run_backtest(apply_fees=False)
    result_with_fees = run_backtest(apply_fees=True)

    print(f"\nBULL_WEAK candles encontrados: {result_no_fees['n_bull_weak_candles']}")

    print("\n--- IDEAL (sem fees+slippage) ---")
    for v in VARIANTS:
        _print_variant_row(v, result_no_fees["metrics_by_variant"][v])

    print(f"\n--- REALISTA (fees {FEE_TAKER*100:.2f}% + slip {SLIPPAGE*100:.2f}% por lado) ---")
    for v in VARIANTS:
        _print_variant_row(v, result_with_fees["metrics_by_variant"][v])

    # Sub-analise: phases halving
    if not args.no_subanalysis:
        print("\n--- POR HALVING PHASE (REALISTA) ---")
        for phase, vmetrics in result_with_fees["per_halving_phase"].items():
            plain = vmetrics["plain"]
            if plain["n"] < 10: continue
            print(f"\n  [{phase}] n_plain={plain['n']}")
            for v in VARIANTS:
                _print_variant_row("  " + v, vmetrics[v])

        print("\n--- POR ANO (REALISTA, plain only, anos com n>=20) ---")
        for year, vmetrics in result_with_fees["per_year"].items():
            plain = vmetrics["plain"]
            if plain["n"] < 20: continue
            print(f"  {year}  n={plain['n']:>3} exp={plain['expectancy_r']:+.4f}R Sharpe={plain['sharpe_annual']:6.2f} total={plain['total_r']:+7.2f}R")

    final = {
        "ideal": result_no_fees,
        "realistic": result_with_fees,
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(final, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out}")


if __name__ == "__main__":
    main()
