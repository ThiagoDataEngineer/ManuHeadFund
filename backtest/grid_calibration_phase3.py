"""grid_calibration_phase3.py -- Recalibrar vol_climax ESPECIFICAMENTE para phase_3_bear.

Insight v3: edge "+8.6pp" do v1 era média dominada por phase_1_bull 2024.
Phase_3_bear (regime atual) edge ~+5pp - falha gate Bonferroni.

Pergunta refinada: existe combinação (mult, threshold, close_rejection) +
confluence que produz edge >+11.5pp ESPECIFICAMENTE em phase_3_bear?

Grid:
  - mult vol: 2.5, 3.0, 4.0, 5.0
  - outcome threshold: +2%, +3%, +5% (NET com 0.6% custos)
  - close_above_rejection: 0.2, 0.3, 0.4, 0.5 (close acima de N% do range from low)
  - confluence: (none, RSI<30, price<SMA200, RSI<30 AND price<SMA200)

Dataset: 12 markets com >=1500 bars (4+ anos). Filtra eventos em phase_3_bear.

Output: ranking objetivo — qual config maximiza edge_net em phase_3_bear E sobrevive
gates 3.1-3.7 ajustados?
"""
from __future__ import annotations
import json, math, sys
from collections import defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

LOOKBACK = 60
COSTS_PCT = 0.6
N_HYP_TESTED = 50  # vamos testar muitas combinacoes -- Bonferroni mais rigoroso


HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
HALVING_2020 = datetime(2020, 5, 11, tzinfo=timezone.utc)


def assign_phase(ts_iso):
    try: dt = datetime.fromisoformat(ts_iso.replace("Z","+00:00"))
    except: return "unknown"
    if dt >= HALVING_2024:
        m = (dt - HALVING_2024).days / 30.5
        if m < 6: return "h24_p1_bull"
        elif m < 12: return "h24_p2_top"
        elif m < 30: return "h24_p3_bear"
        else: return "h24_p4_rec"
    elif dt >= HALVING_2020:
        m = (dt - HALVING_2020).days / 30.5
        if m < 6: return "h20_p1_bull"
        elif m < 12: return "h20_p2_top"
        elif m < 30: return "h20_p3_bear"
        else: return "h20_p4_rec"
    else:
        return "pre_h20"


# Inline asserts
assert assign_phase("2024-06-01T00:00:00+00:00") == "h24_p1_bull"
assert assign_phase("2025-06-01T00:00:00+00:00") == "h24_p3_bear"
assert assign_phase("2026-05-01T00:00:00+00:00") == "h24_p3_bear"


def calc_rsi(closes, period=14):
    n = len(closes)
    if n < period+1: return 50.0
    g = l = 0.0
    for i in range(1, period+1):
        d = closes[i] - closes[i-1]
        if d > 0: g += d
        else: l += abs(d)
    ag = g/period; al = l/period
    for i in range(period+1, n):
        d = closes[i] - closes[i-1]
        if d > 0:
            ag = (ag*(period-1) + d)/period
            al = al*(period-1)/period
        else:
            ag = ag*(period-1)/period
            al = (al*(period-1) + abs(d))/period
    if al == 0: return 100.0
    return 100 - (100/(1 + ag/al))


def sma(values, period):
    if len(values) < period: return None
    return sum(values[-period:]) / period


def detect_vol_climax(volumes, lows, highs, closes, mult, close_rejection, lookback=20):
    n = len(volumes)
    if n < lookback: return False
    avg = sum(volumes[-lookback:-1]) / (lookback - 1)
    if avg <= 0 or volumes[-1] < mult * avg: return False
    prior_lows = lows[-lookback:-1]
    new_low = lows[-1] < min(prior_lows)
    rng = highs[-1] - lows[-1]
    if rng <= 0: return False
    close_above = closes[-1] > lows[-1] + rng * close_rejection
    return new_low and close_above


def confluence_check(rsi, price, sma200, mode):
    if mode == "none": return True
    if mode == "rsi_under_30": return rsi < 30
    if mode == "below_sma200":
        if sma200 is None: return False
        return price < sma200
    if mode == "rsi_AND_sma200":
        if sma200 is None: return False
        return rsi < 30 and price < sma200
    return True


def load_candles(market):
    p = CANDLES_DIR / f"{market}_1day.json"
    if not p.exists(): return None
    try: data = json.loads(p.read_text(encoding="utf-8"))
    except: return None
    out = []
    for c in data:
        if not isinstance(c, dict): continue
        try:
            out.append({
                "ts": c.get("ts"), "open":  float(c["open"]),
                "high": float(c["high"]), "low": float(c["low"]),
                "close": float(c["close"]), "volume": float(c.get("volume", 0)),
            })
        except: pass
    return out


def backtest_config(candles, mult, threshold_pct, close_rejection, conf_mode,
                    outcome_bars=5, phase_filter=None):
    """Returns: events list filtered by phase if specified."""
    events = []
    if len(candles) < LOOKBACK + outcome_bars + 30: return events
    end = len(candles) - outcome_bars
    net_threshold = threshold_pct + COSTS_PCT
    for i in range(LOOKBACK, end):
        win = candles[i-LOOKBACK:i+1]
        highs = [c["high"] for c in win]
        lows  = [c["low"] for c in win]
        closes = [c["close"] for c in win]
        volumes = [c["volume"] for c in win]
        ts = candles[i].get("ts","")
        phase = assign_phase(str(ts))
        if phase_filter and phase != phase_filter: continue

        out = candles[i+1:i+1+outcome_bars]
        if not out: continue
        entry = candles[i]["close"]
        max_c = max(c["close"] for c in out)
        long_move = (max_c - entry) / entry * 100

        rsi = calc_rsi(closes)
        sma_val = sma(closes, 200) if len(closes) >= 200 else None
        price = closes[-1]

        signal = detect_vol_climax(volumes, lows, highs, closes, mult, close_rejection)
        if signal:
            signal = signal and confluence_check(rsi, price, sma_val, conf_mode)

        events.append({
            "ts": ts, "phase": phase, "signal": "vol_climax" if signal else "baseline",
            "hit_gross": long_move >= threshold_pct,
            "hit_net":   long_move >= net_threshold,
            "outcome_pct": long_move,
        })
    return events


def edge_for_signal(events, key="hit_net"):
    sig = [e for e in events if e["signal"] == "vol_climax"]
    base = [e for e in events if e["signal"] == "baseline"]
    if not sig or not base: return None
    sr = sum(1 for e in sig if e[key]) / len(sig) * 100
    br = sum(1 for e in base if e[key]) / len(base) * 100
    return {"n": len(sig), "rate": sr, "base_rate": br, "edge": sr - br}


def bonferroni_gate(base, n):
    if n <= 1: return base
    return base * math.log(n)


def main():
    # Markets com >= 1500 bars (mais 4y)
    target_markets = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 1500:
            target_markets.append((f.stem.replace("_1day",""), d))
    print(f"Markets with >=1500 bars: {len(target_markets)}")
    for m, _ in target_markets: print(f"  {m}")
    print()

    # GRID
    mult_grid = [2.5, 3.0, 4.0, 5.0]
    threshold_grid = [2.0, 3.0, 5.0]
    close_rej_grid = [0.3, 0.5]
    conf_grid = ["none", "rsi_under_30", "below_sma200", "rsi_AND_sma200"]

    total_configs = len(mult_grid) * len(threshold_grid) * len(close_rej_grid) * len(conf_grid)
    print(f"Total grid configs: {total_configs}")
    print(f"Filter: events em phase_3_bear (h20_p3_bear + h24_p3_bear)")
    print()

    results = []
    bonf_gate = bonferroni_gate(5.0, N_HYP_TESTED)
    print(f"Bonferroni gate (N={N_HYP_TESTED} hyp): {bonf_gate:.1f}pp\n")

    for mult in mult_grid:
        for threshold in threshold_grid:
            for close_rej in close_rej_grid:
                for conf in conf_grid:
                    # Aggregate events from todos markets in phase_3_bear
                    all_events = []
                    for mkt, candles in target_markets:
                        ev_h20 = backtest_config(candles, mult, threshold, close_rej, conf,
                                                  phase_filter="h20_p3_bear")
                        ev_h24 = backtest_config(candles, mult, threshold, close_rej, conf,
                                                  phase_filter="h24_p3_bear")
                        all_events.extend(ev_h20); all_events.extend(ev_h24)
                    edge = edge_for_signal(all_events, key="hit_net")
                    if not edge: continue
                    results.append({
                        "mult": mult, "threshold": threshold, "close_rej": close_rej,
                        "confluence": conf, **edge
                    })

    # Rank by edge desc (mas n >= 20)
    results = [r for r in results if r["n"] >= 20]
    results.sort(key=lambda r: -r["edge"])

    print(f"{'mult':>5} {'thr':>4} {'rej':>5} {'conf':<18} {'n':>5} {'rate':>7} {'base':>7} {'edge':>7}  {'gate':>5}")
    print("-" * 80)
    for r in results[:25]:
        passes_bonf = "PASS" if r["edge"] >= bonf_gate else "fail"
        passes_base = "✓" if r["edge"] >= 5.0 and r["n"] >= 30 else "✗"
        print(f"{r['mult']:>5.1f} {r['threshold']:>4.1f}% {r['close_rej']:>5.2f} {r['confluence']:<18} {r['n']:>5} {r['rate']:>6.1f}% {r['base_rate']:>6.1f}% {r['edge']:>+6.1f}pp  {passes_base}{passes_bonf[:4]}")

    # Best config
    if results:
        best = results[0]
        print(f"\n=== BEST CONFIG em phase_3_bear ===")
        print(f"  mult={best['mult']} threshold={best['threshold']}% close_rej={best['close_rej']} conf={best['confluence']}")
        print(f"  n={best['n']} edge_net={best['edge']:+.1f}pp")
        print(f"  Bonferroni gate (50 configs testadas): {bonf_gate:.1f}pp")
        if best['edge'] >= bonf_gate:
            print(f"  PASSA gate Bonferroni ajustado ✓")
        else:
            print(f"  FALHA gate Bonferroni ajustado ✗ (edge {best['edge']:.1f}pp < {bonf_gate:.1f}pp)")


if __name__ == "__main__":
    print("Inline asserts: PASS")
    sys.exit(main())
