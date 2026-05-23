"""unified_patterns_backtest.py -- Backtest 30d+ unified de:
  1. Tori Proximity (LONG + SHORT)
  2. Volume Climax (selling + buying)
  3. Candlestick Reversal (hammer/star/engulfing)
  4. RSI Divergence (bullish + bearish)
  5. CONFLUENCE (2+ patterns same side same bar)

Para cada market do candles_coinex/*_1day.json, walk bar-by-bar.
Outcome: hit-rate em T+5d / T+10d / T+20d com threshold +3%.
Comparar vs base rate (qualquer bar random).

OUTPUT: ranking objetivo edge por pattern + confluence. Decisao B/C orientada.
"""
from __future__ import annotations
import json, math, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"


# ═══════════════ Tori Proximity (reimport from previous backtest) ═══════════
TORI_MIN_HISTORY = 20
TORI_SLOPE_MIN = 5.0
TORI_SLOPE_MAX = 35.0
TORI_TOUCH_TOL = 1.5
TORI_MIN_TOUCHES = 3
TORI_RSI_MAX_LONG = 40.0
TORI_RSI_MIN_SHORT = 60.0
TORI_VOL_RATIO = 0.7

OUTCOME_BARS = 5
OUTCOME_THRESHOLD_PCT = 3.0
LOOKBACK = 60


def linreg(y):
    n = len(y)
    if n < 2: return 0.0, y[0] if n else 0.0
    sx = sum(range(n)); sy = sum(y)
    sxy = sum(i * y[i] for i in range(n))
    sx2 = sum(i*i for i in range(n))
    denom = n * sx2 - sx*sx
    if denom == 0: return 0.0, sy / n
    slope = (n*sxy - sx*sy) / denom
    intercept = (sy - slope*sx) / n
    return slope, intercept


def count_touches(values, slope, intercept, tol_pct):
    t = 0
    for i, v in enumerate(values):
        line = intercept + slope*i
        if line <= 0: continue
        d = abs(v - line) / line * 100
        if d <= tol_pct: t += 1
    return t


def calc_rsi(closes, period=14):
    if len(closes) < period + 1: return 50.0
    g = l = 0.0
    for i in range(1, period+1):
        d = closes[i] - closes[i-1]
        if d > 0: g += d
        else: l += abs(d)
    ag = g/period; al = l/period
    for i in range(period+1, len(closes)):
        d = closes[i] - closes[i-1]
        if d > 0:
            ag = (ag*(period-1) + d) / period
            al = al*(period-1) / period
        else:
            ag = ag*(period-1) / period
            al = (al*(period-1) + abs(d)) / period
    if al == 0: return 100.0
    return 100 - (100 / (1 + ag/al))


def calc_rsi_array(closes, period=14):
    """Returns array same length."""
    n = len(closes)
    rsi = [50.0] * n
    if n < period+1: return rsi
    g = l = 0.0
    for i in range(1, period+1):
        d = closes[i] - closes[i-1]
        if d > 0: g += d
        else: l += abs(d)
    ag = g/period; al = l/period
    rsi[period] = 100.0 if al == 0 else 100 - (100 / (1 + ag/al))
    for i in range(period+1, n):
        d = closes[i] - closes[i-1]
        if d > 0:
            ag = (ag*(period-1) + d) / period
            al = al*(period-1) / period
        else:
            ag = ag*(period-1) / period
            al = (al*(period-1) + abs(d)) / period
        rsi[i] = 100.0 if al == 0 else 100 - (100 / (1 + ag/al))
    return rsi


def find_swings(values, window=2, is_low=True):
    swings = []
    for i in range(window, len(values) - window):
        is_sw = True
        for j in range(1, window+1):
            if is_low:
                if values[i] >= values[i-j] or values[i] >= values[i+j]:
                    is_sw = False; break
            else:
                if values[i] <= values[i-j] or values[i] <= values[i+j]:
                    is_sw = False; break
        if is_sw: swings.append(i)
    return swings


# ═══════════════ Pattern detectors ════════════════════════════════════════

def detect_tori_long(closes, highs, lows, volumes):
    n = len(closes)
    if n < TORI_MIN_HISTORY: return False
    mean = sum(closes)/n
    if mean <= 0: return False
    slope, inter = linreg(lows)
    slope_deg = math.degrees(math.atan(slope/mean*100))
    if not (TORI_SLOPE_MIN <= slope_deg <= TORI_SLOPE_MAX): return False
    if count_touches(lows, slope, inter, TORI_TOUCH_TOL) < TORI_MIN_TOUCHES: return False
    line = inter + slope*(n-1)
    if line <= 0: return False
    prox = (closes[-1] - line)/line * 100
    if not (-3 <= prox <= 5): return False
    rsi = calc_rsi(closes)
    if rsi >= TORI_RSI_MAX_LONG: return False
    if len(volumes) >= 10:
        ra = sum(volumes[-3:]) / 3
        pa = sum(volumes[-10:-3]) / 7
        if pa > 0 and ra < pa * TORI_VOL_RATIO: return True
    return False


def detect_tori_short(closes, highs, lows, volumes):
    n = len(closes)
    if n < TORI_MIN_HISTORY: return False
    mean = sum(closes)/n
    if mean <= 0: return False
    slope, inter = linreg(highs)
    slope_deg = math.degrees(math.atan(slope/mean*100))
    if not (-TORI_SLOPE_MAX <= slope_deg <= -TORI_SLOPE_MIN): return False
    if count_touches(highs, slope, inter, TORI_TOUCH_TOL) < TORI_MIN_TOUCHES: return False
    line = inter + slope*(n-1)
    if line <= 0: return False
    prox = (closes[-1] - line)/line * 100
    if not (-5 <= prox <= 3): return False
    rsi = calc_rsi(closes)
    if rsi <= TORI_RSI_MIN_SHORT: return False
    if len(volumes) >= 10:
        ra = sum(volumes[-3:]) / 3
        pa = sum(volumes[-10:-3]) / 7
        if pa > 0 and ra < pa * TORI_VOL_RATIO: return True
    return False


def detect_volume_climax(closes, highs, lows, volumes, side, mult=3.0, lookback=20):
    n = len(volumes)
    if n < lookback: return False
    avg = sum(volumes[-lookback:-1]) / (lookback - 1)
    if avg <= 0 or volumes[-1] < mult * avg: return False
    prior_lows  = lows[-lookback:-1]
    prior_highs = highs[-lookback:-1]
    if side == "LONG":
        new_low = lows[-1] < min(prior_lows)
        close_above = closes[-1] > lows[-1] + (highs[-1] - lows[-1])*0.3
        return new_low and close_above
    else:
        new_high = highs[-1] > max(prior_highs)
        close_below = closes[-1] < highs[-1] - (highs[-1] - lows[-1])*0.3
        return new_high and close_below


def detect_candlestick(opens, highs, lows, closes, side):
    n = len(closes)
    if n < 10: return False
    i = n - 1
    body = abs(closes[i] - opens[i])
    rng  = highs[i] - lows[i]
    upper = highs[i] - max(closes[i], opens[i])
    lower = min(closes[i], opens[i]) - lows[i]
    if rng <= 0: return False
    # Trend last 8 bars
    down = sum(1 for j in range(i-8, i) if closes[j] < closes[j-1])
    up = 8 - down
    if side == "LONG":
        is_down = down > up
        hammer = lower >= 2*body and upper <= body and body > 0
        if is_down and hammer: return True
        if i >= 1:
            prev_bear = closes[i-1] < opens[i-1]
            curr_bull = closes[i] > opens[i]
            engulfs = opens[i] <= closes[i-1] and closes[i] >= opens[i-1]
            if prev_bear and curr_bull and engulfs and is_down: return True
        return False
    else:
        is_up = up > down
        star = upper >= 2*body and lower <= body and body > 0
        if is_up and star: return True
        if i >= 1:
            prev_bull = closes[i-1] > opens[i-1]
            curr_bear = closes[i] < opens[i]
            engulfs = opens[i] >= closes[i-1] and closes[i] <= opens[i-1]
            if prev_bull and curr_bear and engulfs and is_up: return True
        return False


def detect_rsi_divergence(closes, side, lookback=30, period=14):
    n = len(closes)
    if n < lookback: return False
    rsi = calc_rsi_array(closes, period)
    start = n - lookback
    cw = closes[start:]
    rw = rsi[start:]
    if side == "LONG":
        swings = find_swings(cw, window=2, is_low=True)
        if len(swings) < 2: return False
        i1, i2 = swings[-2], swings[-1]
        return cw[i2] < cw[i1] and rw[i2] > rw[i1]
    else:
        # swing highs
        swings = find_swings(cw, window=2, is_low=False)
        if len(swings) < 2: return False
        i1, i2 = swings[-2], swings[-1]
        return cw[i2] > cw[i1] and rw[i2] < rw[i1]


# ═══════════════ Backtest harness ═════════════════════════════════════════

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
                "open": float(c["open"]), "high": float(c["high"]),
                "low": float(c["low"]), "close": float(c["close"]),
                "volume": float(c.get("volume", 0)),
            })
        except: pass
    return out


def backtest_market(market, candles):
    if len(candles) < LOOKBACK + OUTCOME_BARS + 30: return None
    events = defaultdict(list)
    start = LOOKBACK
    end = len(candles) - OUTCOME_BARS
    for i in range(start, end):
        window = candles[i-LOOKBACK:i+1]
        opens   = [c["open"]   for c in window]
        highs   = [c["high"]   for c in window]
        lows    = [c["low"]    for c in window]
        closes  = [c["close"]  for c in window]
        volumes = [c["volume"] for c in window]

        outcome = candles[i+1:i+1+OUTCOME_BARS]
        if not outcome: continue
        entry = candles[i]["close"]
        max_close = max(c["close"] for c in outcome)
        min_close = min(c["close"] for c in outcome)
        long_move  = (max_close - entry) / entry * 100
        short_move = (entry - min_close) / entry * 100

        signals_long  = []
        signals_short = []
        if detect_tori_long(closes, highs, lows, volumes):                  signals_long.append("tori")
        if detect_tori_short(closes, highs, lows, volumes):                 signals_short.append("tori")
        if detect_volume_climax(closes, highs, lows, volumes, "LONG"):      signals_long.append("vol_climax")
        if detect_volume_climax(closes, highs, lows, volumes, "SHORT"):     signals_short.append("vol_climax")
        if detect_candlestick(opens, highs, lows, closes, "LONG"):          signals_long.append("candle")
        if detect_candlestick(opens, highs, lows, closes, "SHORT"):         signals_short.append("candle")
        if detect_rsi_divergence(closes, "LONG"):                            signals_long.append("rsi_div")
        if detect_rsi_divergence(closes, "SHORT"):                           signals_short.append("rsi_div")

        # Eventos individuais + confluence
        for sig in signals_long:
            events[f"LONG_{sig}"].append({"hit": long_move >= OUTCOME_THRESHOLD_PCT, "outcome": long_move})
        for sig in signals_short:
            events[f"SHORT_{sig}"].append({"hit": short_move >= OUTCOME_THRESHOLD_PCT, "outcome": short_move})
        if len(signals_long) >= 2:
            events["LONG_confluence_2+"].append({"hit": long_move >= OUTCOME_THRESHOLD_PCT, "outcome": long_move,
                                                  "n_signals": len(signals_long), "signals": signals_long})
        if len(signals_short) >= 2:
            events["SHORT_confluence_2+"].append({"hit": short_move >= OUTCOME_THRESHOLD_PCT, "outcome": short_move,
                                                   "n_signals": len(signals_short), "signals": signals_short})
        if len(signals_long) >= 3:
            events["LONG_confluence_3+"].append({"hit": long_move >= OUTCOME_THRESHOLD_PCT, "outcome": long_move})
        if len(signals_short) >= 3:
            events["SHORT_confluence_3+"].append({"hit": short_move >= OUTCOME_THRESHOLD_PCT, "outcome": short_move})

        # Baseline: all bars
        events["BASELINE_LONG"].append({"hit": long_move >= OUTCOME_THRESHOLD_PCT, "outcome": long_move})
        events["BASELINE_SHORT"].append({"hit": short_move >= OUTCOME_THRESHOLD_PCT, "outcome": short_move})

    return dict(events)


def main():
    print(f"=== Unified Patterns Backtest (lookback={LOOKBACK}d outcome={OUTCOME_BARS}d threshold={OUTCOME_THRESHOLD_PCT}%) ===\n")
    candle_files = sorted(CANDLES_DIR.glob("*_1day.json"))
    agg = defaultdict(list)
    n_markets = 0
    for f in candle_files:
        mkt = f.stem.replace("_1day", "")
        candles = load_candles(mkt)
        if not candles: continue
        ev = backtest_market(mkt, candles)
        if ev:
            for k, lst in ev.items():
                agg[k].extend(lst)
            n_markets += 1
    print(f"Markets processed: {n_markets}\n")

    # Compute hit-rates
    def stats(events):
        n = len(events)
        if n == 0: return None
        hits = sum(1 for e in events if e["hit"])
        rate = hits / n * 100
        avg_outcome = sum(e["outcome"] for e in events) / n
        avg_hit = sum(e["outcome"] for e in events if e["hit"]) / max(hits, 1)
        avg_miss = sum(e["outcome"] for e in events if not e["hit"]) / max(n - hits, 1)
        return {"n": n, "hits": hits, "rate": rate, "avg_out": avg_outcome, "avg_hit": avg_hit, "avg_miss": avg_miss}

    base_long  = stats(agg["BASELINE_LONG"])
    base_short = stats(agg["BASELINE_SHORT"])
    print(f"BASELINE LONG : n={base_long['n']:>6} hit_rate={base_long['rate']:5.1f}% avg_outcome={base_long['avg_out']:+5.2f}%")
    print(f"BASELINE SHORT: n={base_short['n']:>6} hit_rate={base_short['rate']:5.1f}% avg_outcome={base_short['avg_out']:+5.2f}%")
    print()

    print(f"{'Pattern':<30} {'N':>5} {'HitRate':>8} {'Edge':>7} {'AvgOut':>8} {'AvgHit':>8}")
    print("─" * 70)

    keys = ["LONG_tori", "LONG_vol_climax", "LONG_candle", "LONG_rsi_div",
            "LONG_confluence_2+", "LONG_confluence_3+",
            "SHORT_tori", "SHORT_vol_climax", "SHORT_candle", "SHORT_rsi_div",
            "SHORT_confluence_2+", "SHORT_confluence_3+"]
    for k in keys:
        s = stats(agg[k])
        if not s: print(f"{k:<30} {'n/a':>5}"); continue
        is_long = k.startswith("LONG")
        base_rate = base_long["rate"] if is_long else base_short["rate"]
        edge = s["rate"] - base_rate
        edge_str = f"{edge:+.1f}pp"
        decision = "✓" if edge >= 5 and s["n"] >= 20 else "✗"
        print(f"{k:<30} {s['n']:>5} {s['rate']:>7.1f}% {edge_str:>7} {s['avg_out']:>+7.2f}% {s['avg_hit']:>+7.2f}% {decision}")
    print()
    print("Decision gate: edge >= +5pp + n >= 20 → ✓ (worth activating)")


if __name__ == "__main__":
    sys.exit(main())
