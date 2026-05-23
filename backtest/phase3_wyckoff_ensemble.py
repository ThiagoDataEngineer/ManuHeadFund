"""phase3_wyckoff_ensemble.py -- ST + Spring detectors A/B vs SC-only.

Phase 3 do Chained A/B v6 (conditional, fires se Gate B PASS).

T7 ST (Secondary Test): after SC, look for retest of low WITHOUT new low (within 5-10 bars)
T8 Spring: after SC, minor new low + strong reversal (close > prior low by margin)

Ensemble: SC + ST OR SC + Spring = trade signal.
A/B vs SC-only.
"""
from __future__ import annotations
import sys, time, json
import numpy as np
sys.path.insert(0, "backtest")
from lib_methodology_fast import (load_universe, build_btc_regime_index_fast,
                                   walk_signals_fast, rsi_vectorized, COSTS_PCT,
                                   LOOKBACK, MULT, CLOSE_REJ, RSI_CONF)


def detect_sc(volumes, highs, lows, closes, rsi_series, lookback=20):
    """Selling Climax detector (same as wyckoff_spring_score predicate)."""
    n = len(volumes)
    if n <= lookback: return False
    vol_window = volumes[-lookback:-1]
    avg = vol_window.mean() if len(vol_window) > 0 else 0
    if avg <= 0 or volumes[-1] < MULT * avg: return False
    prior_lows = lows[-lookback:-1]
    if lows[-1] >= prior_lows.min(): return False
    rng = highs[-1] - lows[-1]
    if rng <= 0: return False
    if closes[-1] <= lows[-1] + rng * CLOSE_REJ: return False
    return rsi_series[-1] < RSI_CONF


def detect_st_after(candles_np, sc_idx, st_lookahead=10):
    """Secondary Test: within st_lookahead bars after SC, did price retest SC_low WITHOUT new low?
    Returns ST bar idx or -1 if no ST."""
    if sc_idx + st_lookahead >= len(candles_np["closes"]):
        return -1
    sc_low = candles_np["lows"][sc_idx]
    sc_close = candles_np["closes"][sc_idx]
    # Scan bars after SC
    for j in range(sc_idx + 2, min(sc_idx + 1 + st_lookahead, len(candles_np["closes"]))):
        low_j = candles_np["lows"][j]
        close_j = candles_np["closes"][j]
        # ST: low touches near SC_low (within 2%) but doesn't break + closes higher
        proximity = abs(low_j - sc_low) / sc_low
        if proximity <= 0.02 and low_j >= sc_low * 0.99 and close_j > low_j * 1.01:
            return j
    return -1


def detect_spring_after(candles_np, sc_idx, spring_lookahead=10):
    """Spring: minor new low below SC_low + strong reversal close (above prior bar high).
    Returns Spring bar idx or -1."""
    if sc_idx + spring_lookahead >= len(candles_np["closes"]):
        return -1
    sc_low = candles_np["lows"][sc_idx]
    for j in range(sc_idx + 2, min(sc_idx + 1 + spring_lookahead, len(candles_np["closes"]))):
        low_j = candles_np["lows"][j]
        close_j = candles_np["closes"][j]
        prev_high = candles_np["highs"][j-1]
        # Spring: new low BELOW SC_low + close ABOVE previous high
        if low_j < sc_low and close_j > prev_high:
            return j
    return -1


def main():
    t0 = time.time()
    print("=== PHASE 3 — Wyckoff Ensemble (SC + ST/Spring) ===\n")
    md = load_universe(min_bars=300, include_external=True)
    print(f"Universe: {len(md)} markets")
    btc = build_btc_regime_index_fast()
    print(f"BTC regime: {len(btc)} days\n")

    sc_only_events = []
    sc_plus_st_events = []
    sc_plus_spring_events = []

    window = 3  # outcome window same as predicate
    for market, candles in md:
        n = len(candles)
        if n < LOOKBACK + window + 30: continue
        highs = np.array([c["high"] for c in candles])
        lows = np.array([c["low"] for c in candles])
        closes = np.array([c["close"] for c in candles])
        volumes = np.array([c["volume"] for c in candles])
        ts_list = [c.get("ts", "") for c in candles]
        rsi_series = rsi_vectorized(closes)
        cnp = {"highs": highs, "lows": lows, "closes": closes}

        end = n - window
        for i in range(LOOKBACK, end):
            sc = detect_sc(volumes[:i+1], highs[:i+1], lows[:i+1], closes[:i+1], rsi_series[:i+1])
            if not sc: continue
            ts = ts_list[i]

            # SC-only outcome (entry at i, exit max-close in 3 bars)
            entry = closes[i]
            slc = closes[i+1:i+1+window]
            if len(slc) < window: continue
            outcome_sc = (slc.max() - entry) / entry * 100
            sc_only_events.append({"ts": ts, "market": market, "outcome": outcome_sc})

            # Check ST after SC
            st_idx = detect_st_after(cnp, i, st_lookahead=10)
            if st_idx > 0 and st_idx + window < n:
                # Entry at ST bar close, exit max-close in next 3 bars
                st_entry = closes[st_idx]
                st_slc = closes[st_idx+1:st_idx+1+window]
                if len(st_slc) >= window:
                    outcome_st = (st_slc.max() - st_entry) / st_entry * 100
                    sc_plus_st_events.append({"ts": ts_list[st_idx], "market": market, "outcome": outcome_st})

            # Check Spring after SC
            sp_idx = detect_spring_after(cnp, i, spring_lookahead=10)
            if sp_idx > 0 and sp_idx + window < n:
                sp_entry = closes[sp_idx]
                sp_slc = closes[sp_idx+1:sp_idx+1+window]
                if len(sp_slc) >= window:
                    outcome_sp = (sp_slc.max() - sp_entry) / sp_entry * 100
                    sc_plus_spring_events.append({"ts": ts_list[sp_idx], "market": market, "outcome": outcome_sp})

    def summarize(name, events):
        if not events:
            print(f"  {name}: no events")
            return None
        outs = [e["outcome"] - COSTS_PCT for e in events]
        wins = sum(1 for o in outs if o >= 1.0)
        ev = sum(outs) / len(outs)
        hit = wins / len(events) * 100
        days = len(set(e["ts"][:10] for e in events))
        print(f"  {name:<20} n_events={len(events):>4} n_days={days:>3} EV_net={ev:+.2f}% hit={hit:.0f}%")
        return {"n": len(events), "days": days, "ev_net": round(ev, 2), "hit_pct": round(hit, 1)}

    print("\n=== T7 + T8 Results (after SC, with Wyckoff confluence) ===")
    print(f"  {'Strategy':<20} {'n_events':>8} {'n_days':>6} {'EV_net':>8} {'hit%':>5}")
    print(f"  {'-'*52}")
    r_sc = summarize("SC-only (baseline)", sc_only_events)
    r_st = summarize("SC+ST ensemble", sc_plus_st_events)
    r_sp = summarize("SC+Spring ensemble", sc_plus_spring_events)

    # Save
    from pathlib import Path
    Path("journal/phase3_wyckoff_results.json").write_text(
        json.dumps({"sc_only": r_sc, "sc_plus_st": r_st, "sc_plus_spring": r_sp}, indent=2),
        encoding="utf-8"
    )

    # GATE C verdict
    print("\n=== GATE C verdict ===")
    if r_sc and r_st and r_st["ev_net"] > r_sc["ev_net"] and r_st["n"] >= 10:
        print(f"  ST ensemble BEATS SC-only (+{r_st['ev_net']-r_sc['ev_net']:.1f}pp lift). ADOPT.")
    elif r_sc and r_st:
        print(f"  ST ensemble no better than SC-only ({r_st['ev_net']} vs {r_sc['ev_net']}). Skip ST.")
    if r_sc and r_sp and r_sp["ev_net"] > r_sc["ev_net"] and r_sp["n"] >= 10:
        print(f"  Spring ensemble BEATS SC-only (+{r_sp['ev_net']-r_sc['ev_net']:.1f}pp lift). ADOPT.")
    elif r_sc and r_sp:
        print(f"  Spring ensemble no better than SC-only ({r_sp['ev_net']} vs {r_sc['ev_net']}). Skip Spring.")

    print(f"\nTotal time: {time.time()-t0:.1f}s")


if __name__ == "__main__":
    main()
