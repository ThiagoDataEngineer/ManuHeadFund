"""
validate_strict_v3_phase.py -- Compara strict_v2 vs strict_v3 phase-aware em 14y BTC.

Simula LONG entries com fees+slippage realistas. Strategy:
  strict_v2: BULL_STRONG only (+ TRANSITION_UP+Mon - aproximado aqui como BULL_STRONG only)
  strict_v3: strict_v2 + BULL_WEAK conditional (phase in {1_bull, 4_recovery} + soft trendline)

Output: comparacao de metricas total e por phase.
"""
from __future__ import annotations

import json, math, os, sys
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from trendline_filter import get_trendline_score
from signal_generator import apply_regime_filter


CANDLES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "btcusd_bitstamp_1day.json")

HALVING_2024 = datetime.fromisoformat("2024-04-19")
HALVING_2020 = datetime.fromisoformat("2020-05-11")
HALVING_2016 = datetime.fromisoformat("2016-07-09")
HALVING_2012 = datetime.fromisoformat("2012-11-28")
HALVINGS = [("halving_2012", HALVING_2012), ("halving_2016", HALVING_2016),
            ("halving_2020", HALVING_2020), ("halving_2024", HALVING_2024)]

SMA200 = 200
MOM_W = 20
ATR_P = 14
HOLDOUT = 20
RR = 5.0
FEE = 0.0020; SLIP = 0.0010
COST_PER_SIDE = FEE + SLIP


def classify_regime(closes, idx):
    if idx < SMA200: return "NO_HIST"
    sma = sum(closes[idx - SMA200 + 1:idx + 1]) / SMA200
    if sma <= 0: return "SIDEWAYS"
    cur = closes[idx]
    dist = (cur - sma) / sma
    if idx < MOM_W: return "NO_HIST"
    prev = closes[idx - MOM_W]
    mom = (cur - prev) / prev if prev > 0 else 0
    if dist > 0.20 and mom > 0.10: return "BULL_STRONG"
    if dist > 0 and mom > 0 and dist < 0.20: return "BULL_WEAK"
    if dist < -0.20 and mom < -0.10: return "BEAR_STRONG"
    if dist < 0 and mom < 0: return "BEAR_WEAK"
    if abs(dist) < 0.05: return "SIDEWAYS"
    if dist > 0: return "TRANSITION_UP"
    return "TRANSITION_DOWN"


def get_halving_phase(date_str: str) -> str:
    dt = datetime.fromisoformat(date_str.replace("+00:00", "")) if "+" in date_str else datetime.fromisoformat(date_str)
    last = None
    for _, hdt in HALVINGS:
        if hdt <= dt: last = hdt
    if last is None: return "pre_2012"
    months = (dt - last).days / 30.44
    if months < 12: return "phase_1_bull"
    if months < 18: return "phase_2_top"
    if months < 30: return "phase_3_bear"
    return "phase_4_recovery"


def get_dow(date_str: str) -> int:
    """0=Sun..6=Sat (BRT). Backtest historico usa UTC, BRT ~ UTC-3 mas 1day candle = whole day"""
    dt = datetime.fromisoformat(date_str.replace("+00:00", "")) if "+" in date_str else datetime.fromisoformat(date_str)
    py_weekday = dt.weekday()  # 0=Mon..6=Sun
    # converte pra 0=Sun..6=Sat
    return (py_weekday + 1) % 7


def compute_atr(highs, lows, idx):
    if idx < ATR_P: return 0.0
    return sum(highs[j] - lows[j] for j in range(idx - ATR_P + 1, idx + 1)) / ATR_P


def simulate_long(entry, stop, target, fwd):
    risk = entry - stop
    if risk <= 0: return 0.0
    cost_r = (2 * COST_PER_SIDE * entry) / risk
    for c in fwd:
        if c["low"] <= stop: return -1.0 - cost_r
        if c["high"] >= target: return (target - entry) / risk - cost_r
    if fwd:
        return (fwd[-1]["close"] - entry) / risk - cost_r
    return 0.0


def trendline_soft_check(closes, highs, lows, i, lookback=30) -> bool:
    start = max(0, i - lookback + 1)
    score = get_trendline_score(closes[start:i+1], highs[start:i+1], lows[start:i+1])
    return (score["touches"] >= 3) and (5.0 <= score["slope_deg"] <= 15.0)


def aggregate(r_series):
    n = len(r_series)
    if n == 0: return {"n": 0}
    wins = [r for r in r_series if r > 0]
    losses = [r for r in r_series if r < 0]
    exp = sum(r_series) / n
    pf = sum(wins) / abs(sum(losses)) if losses else 999.0
    mean = exp; std = math.sqrt(sum((r-mean)**2 for r in r_series) / max(1, n-1))
    sharpe = (mean / std * math.sqrt(252)) if std > 0 else 0.0
    eq = 0; peak = 0; dd = 0
    for r in r_series:
        eq += r; peak = max(peak, eq); dd = max(dd, peak - eq)
    return {
        "n": n, "exp_R": round(exp, 4), "win_rate": round(len(wins)/n, 4),
        "PF": round(pf, 4), "Sharpe": round(sharpe, 4), "maxDD_R": round(dd, 4),
        "total_R": round(sum(r_series), 4),
    }


def run():
    with open(CANDLES_PATH) as f: candles = json.load(f)
    closes = [c["close"] for c in candles]
    highs = [c["high"] for c in candles]
    lows = [c["low"] for c in candles]

    # Series por modo + por regime/phase
    v2_r: List[float] = []
    v3_r: List[float] = []
    v3_extra_bull_weak_r: List[float] = []  # so as entradas BULL_WEAK extra que v3 admite
    per_phase = defaultdict(lambda: {"v2": [], "v3": []})

    n_bull_strong = n_bull_weak = n_v3_admits_bw = 0

    for i in range(SMA200, len(candles) - HOLDOUT):
        regime = classify_regime(closes, i)
        if regime not in ("BULL_STRONG", "BULL_WEAK", "TRANSITION_UP"): continue

        entry = closes[i]
        atr_v = compute_atr(highs, lows, i)
        if atr_v <= 0: continue
        stop = entry - 2.0 * atr_v
        target = entry + RR * (entry - stop)
        fwd = candles[i+1:i+1+HOLDOUT]
        r = simulate_long(entry, stop, target, fwd)

        ts = candles[i]["ts"]
        phase = get_halving_phase(ts)
        dow_brt = get_dow(ts)

        # strict_v2 simulado: BULL_STRONG sempre, TRANSITION_UP so Mon (dow=1)
        v2_signal, _ = apply_regime_filter("COMPRA", regime, mode="strict_v2",
                                            day_of_week_brt=dow_brt)
        if v2_signal == "COMPRA":
            v2_r.append(r)
            per_phase[phase]["v2"].append(r)

        # strict_v3 phase-aware
        tl_pass = None
        if regime == "BULL_WEAK":
            tl_pass = trendline_soft_check(closes, highs, lows, i)
            n_bull_weak += 1

        v3_signal, v3_reason = apply_regime_filter(
            "COMPRA", regime, mode="strict_v3",
            day_of_week_brt=dow_brt,
            halving_phase=phase, trendline_soft_passes=tl_pass,
        )
        if v3_signal == "COMPRA":
            v3_r.append(r)
            per_phase[phase]["v3"].append(r)
            if regime == "BULL_WEAK":
                v3_extra_bull_weak_r.append(r)
                n_v3_admits_bw += 1

        if regime == "BULL_STRONG": n_bull_strong += 1

    return {
        "counts": {
            "n_bull_strong_candles": n_bull_strong,
            "n_bull_weak_candles": n_bull_weak,
            "n_v3_admits_bull_weak": n_v3_admits_bw,
            "v3_bw_admit_rate": round(n_v3_admits_bw / n_bull_weak, 4) if n_bull_weak else 0,
        },
        "metrics": {
            "strict_v2_total": aggregate(v2_r),
            "strict_v3_total": aggregate(v3_r),
            "v3_extra_bull_weak": aggregate(v3_extra_bull_weak_r),
        },
        "per_phase": {
            phase: {"v2": aggregate(p["v2"]), "v3": aggregate(p["v3"])}
            for phase, p in sorted(per_phase.items())
        },
    }


def main():
    print("=" * 80)
    print("Validate strict_v3 phase-aware vs strict_v2 (14y BTCUSD, realista)")
    print("=" * 80)
    r = run()

    c = r["counts"]
    print(f"\nBULL_STRONG candles: {c['n_bull_strong_candles']}")
    print(f"BULL_WEAK candles:   {c['n_bull_weak_candles']} (v3 admite {c['n_v3_admits_bull_weak']} = {c['v3_bw_admit_rate']*100:.1f}%)")

    m = r["metrics"]
    print("\n--- TOTAL ---")
    for label, key in [("strict_v2", "strict_v2_total"), ("strict_v3", "strict_v3_total"),
                        ("v3 extra (bull_weak only)", "v3_extra_bull_weak")]:
        d = m[key]
        if d.get("n", 0) == 0:
            print(f"  {label:<28}: 0 trades")
            continue
        print(f"  {label:<28}: n={d['n']:>4} exp={d['exp_R']:+.4f}R win={d['win_rate']*100:5.1f}% PF={d['PF']:6.2f} Sharpe={d['Sharpe']:6.2f} DD={d['maxDD_R']:6.2f}R total={d['total_R']:+8.2f}R")

    print("\n--- POR PHASE ---")
    for phase, p in r["per_phase"].items():
        v2 = p["v2"]; v3 = p["v3"]
        if v2.get("n", 0) == 0 and v3.get("n", 0) == 0: continue
        v2_str = f"v2:n={v2.get('n',0):>3} exp={v2.get('exp_R',0):+.3f}R" if v2.get("n", 0) > 0 else "v2:0"
        v3_str = f"v3:n={v3.get('n',0):>3} exp={v3.get('exp_R',0):+.3f}R" if v3.get("n", 0) > 0 else "v3:0"
        delta = ""
        if v3.get("n", 0) > 0 and v2.get("n", 0) > 0:
            delta_n = v3["n"] - v2["n"]
            delta_total = v3["total_R"] - v2["total_R"]
            delta = f"  delta:+{delta_n} trades, {delta_total:+.2f}R"
        print(f"  {phase:<22} {v2_str:<25} | {v3_str:<25}{delta}")

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "journal", "validate_strict_v3_phase_results.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f: json.dump(r, f, indent=2)
    print(f"\n[save] {out}")


if __name__ == "__main__":
    main()
