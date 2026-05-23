"""blacklist_bull_weak_60d_predicate.py -- Predicate em 9 markets blacklisted, 60d.

Replica WSS predicate (vol_climax + RSI<30) em ultimos ~60 bars dos markets
que estao sendo blacklisted por BULL_WEAK+LONG. Mede outcome real.

Filter regime BULL_WEAK proxy: market price > price 60d ago AND change_7d in [-5, +5]
(uptrend estructural + momentum fraco = BULL_WEAK semantica).
"""
from __future__ import annotations
import json
import numpy as np
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
COSTS_PCT = 0.6
WINDOW_BARS = 3
LOOKBACK = 60
DAYS_60 = 60  # last 60 bars analyzed

# Markets atualmente blacklisted (per decisions.csv ultimo dia)
BLOCKED_MARKETS = ["BCHUSDT", "BTCUSDT", "CFGUSDT", "INJUSDT", "PENDLEUSDT",
                   "RENDERUSDT", "SKYUSDT", "XMRUSDT", "XRPUSDT"]

# Predicate constants (matches WSS refined)
MULT = 2.5
CLOSE_REJ = 0.3
RSI_CONF = 30.0


def load_candles(market):
    f = CANDLES_DIR / f"{market}_1day.json"
    if not f.exists(): return []
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(d, list): return d
    except: pass
    return []


def rsi_vectorized(closes_np, period=14):
    n = len(closes_np)
    if n < period + 1: return np.full(n, 50.0)
    deltas = np.diff(closes_np)
    gains = np.where(deltas > 0, deltas, 0.0)
    losses = np.where(deltas < 0, -deltas, 0.0)
    rsi = np.full(n, 50.0)
    avg_gain = gains[:period].mean(); avg_loss = losses[:period].mean()
    if avg_loss == 0: rsi[period] = 100.0
    else: rsi[period] = 100 - (100 / (1 + avg_gain/avg_loss))
    for i in range(period+1, n):
        avg_gain = (avg_gain*(period-1) + gains[i-1]) / period
        avg_loss = (avg_loss*(period-1) + losses[i-1]) / period
        rsi[i] = 100.0 if avg_loss == 0 else 100 - (100/(1+avg_gain/avg_loss))
    return rsi


def is_bull_weak_proxy(closes, i, sma_window=60):
    """BULL_WEAK proxy: price > price_60d_ago (uptrend) AND change_7d in [-5, +5] (weak)."""
    if i < sma_window or i < 7: return False
    price = closes[i]
    price_60d = closes[i - sma_window]
    if price <= price_60d: return False  # not uptrend
    change_7d = (price - closes[i-7]) / closes[i-7] * 100
    return -5.0 <= change_7d <= 5.0  # weak momentum


def main():
    print("=== Blacklist BULL_WEAK+LONG re-validation (60d predicate scan) ===\n")
    print(f"Markets analyzed: {BLOCKED_MARKETS}\n")

    all_signals = []
    per_market = defaultdict(list)

    for market in BLOCKED_MARKETS:
        candles = load_candles(market)
        if len(candles) < LOOKBACK + WINDOW_BARS + 30:
            print(f"  {market}: insufficient candles ({len(candles)})")
            continue

        # Numpy arrays
        highs = np.array([c["high"] for c in candles])
        lows = np.array([c["low"] for c in candles])
        closes = np.array([c["close"] for c in candles])
        volumes = np.array([c["volume"] for c in candles])
        ts_list = [c.get("ts", "")[:10] for c in candles]
        rsi = rsi_vectorized(closes)

        n = len(candles)
        # Last 60 bars (excluding last 3 to allow outcome window)
        start = max(LOOKBACK, n - DAYS_60 - WINDOW_BARS)
        end = n - WINDOW_BARS

        signals_market = 0
        for i in range(start, end):
            # Predicate: vol_climax + new low + close above + RSI < 30
            lb = 20
            vol_window = volumes[i-lb:i]
            avg = vol_window.mean() if len(vol_window) > 0 else 0
            if avg <= 0 or volumes[i] < MULT * avg: continue
            prior_lows = lows[i-lb:i]
            if lows[i] >= prior_lows.min(): continue
            rng = highs[i] - lows[i]
            if rng <= 0: continue
            if closes[i] <= lows[i] + rng * CLOSE_REJ: continue
            if rsi[i] >= RSI_CONF: continue

            # Filter: BULL_WEAK regime proxy
            if not is_bull_weak_proxy(closes, i, sma_window=60): continue

            # Compute outcome 3-bar window
            entry = closes[i]
            future_max = closes[i+1:i+1+WINDOW_BARS].max()
            outcome_pct = (future_max - entry) / entry * 100
            net = outcome_pct - COSTS_PCT
            sig = {
                "market": market, "ts": ts_list[i],
                "entry": entry, "outcome_pct": outcome_pct, "net": net,
                "win": net >= 1.0
            }
            all_signals.append(sig)
            per_market[market].append(sig)
            signals_market += 1

        if signals_market > 0:
            print(f"  {market}: {signals_market} signals em BULL_WEAK proxy")

    if not all_signals:
        print("\nNo signals found em BULL_WEAK proxy condition em ultimos 60 bars.")
        print("This may mean:")
        print("  (a) Last 60 bars nao houve condicoes BULL_WEAK suficientes")
        print("  (b) Predicate raro neste subset (sample size pequeno)")
        return

    print(f"\n=== Aggregate results ({len(all_signals)} signals) ===")
    nets = [s["net"] for s in all_signals]
    wins = sum(1 for s in all_signals if s["win"])
    mean_ev = np.mean(nets)
    print(f"  Mean EV (net):     {mean_ev:+.2f}%")
    print(f"  Median EV:         {np.median(nets):+.2f}%")
    print(f"  Hit rate (>=+1%):  {wins/len(all_signals)*100:.0f}%  ({wins}/{len(all_signals)})")
    print(f"  Best:              {max(nets):+.2f}%")
    print(f"  Worst:             {min(nets):+.2f}%")
    print(f"  Stddev:            {np.std(nets):.2f}%")

    print(f"\n=== Per-market ===")
    print(f"  {'Market':<14} {'n':>3} {'mean':>8} {'hit%':>6}")
    for mkt in sorted(per_market.keys()):
        sigs = per_market[mkt]
        evs = [s["net"] for s in sigs]
        ws = sum(1 for s in sigs if s["win"])
        print(f"  {mkt:<14} {len(sigs):>3} {np.mean(evs):>+7.2f}% {ws/len(sigs)*100:>5.0f}%")

    print(f"\n=== VERDICT ===")
    print(f"  Blacklist baseline (2025 phase_2_top): -0.4R avg = ~-0.6pp net")
    print(f"  Counterfactual EV (60d BULL_WEAK proxy): {mean_ev:+.2f}%")
    print()
    if mean_ev > 1.0 and len(all_signals) >= 10:
        print(f"  -> RELAX BLACKLIST: lift POSITIVO {mean_ev:+.2f}pp em {len(all_signals)} signals")
        print(f"     Action: SKIP -> PAPER tier (paper-only, sem hard skip)")
    elif mean_ev > 0:
        print(f"  -> WEAK SIGNAL: mildly positive {mean_ev:+.2f}pp, n={len(all_signals)}")
        print(f"     Action: monitor, considerar PAPER tier se sample crescer")
    elif mean_ev > -0.5:
        print(f"  -> KEEP MONITORING: neutro {mean_ev:+.2f}pp")
        print(f"     Action: re-test mensalmente, keep blacklist por agora")
    else:
        print(f"  -> BLACKLIST VINDICATED: negative {mean_ev:+.2f}pp")
        print(f"     Action: keep hard SKIP, doc justification")

    # Save
    out = ROOT / "journal/blacklist_bull_weak_60d_results.json"
    out.write_text(json.dumps({
        "analyzed_markets": BLOCKED_MARKETS,
        "n_signals": len(all_signals),
        "mean_ev_net_pct": round(mean_ev, 2),
        "hit_rate_pct": round(wins/len(all_signals)*100, 1) if all_signals else 0,
        "per_market": {m: {"n": len(per_market[m]), "mean_ev": round(np.mean([s["net"] for s in per_market[m]]), 2)}
                       for m in per_market}
    }, indent=2), encoding="utf-8")
    print(f"\nSaved: {out}")


if __name__ == "__main__":
    main()
