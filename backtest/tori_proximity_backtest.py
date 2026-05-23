"""tori_proximity_backtest.py -- viabilidade da camada anticipatoria.

Reimplementa lib_tori_proximity em Python (pure math), roda historicamente sobre
candles 1day cache (journal/candles_coinex/*_1day.json), classifica cada bar como
TOO_EARLY/ON_LINE/MISSED, e mede hit-rate de setup_ripening -> bounce real.

Output: relatorio quantitativo decidindo GO/NO-GO para NEAR-class scanner + SHORT exec.

Gate decisorio:
  - Hit-rate setup_ripening (LONG) -> price up >=3% em 5 bars  : >= 40% = GO
  - Hit-rate setup_ripening (SHORT) -> price down >=3% em 5 bars: >= 40% = GO
  - Falsos positivos (ripening + price move opposite): <= 30%
  - Sample size minimo: >= 30 events por side
"""
from __future__ import annotations
import json, sys, math
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

# Mirror lib_tori_proximity defaults
MIN_HISTORY = 20
SLOPE_DEG_MIN = 5.0
SLOPE_DEG_MAX = 35.0
TOUCH_TOL_PCT = 1.5
MIN_TOUCHES = 3
PROX_PCT_MIN_LONG = -3.0
PROX_PCT_MAX_LONG = 5.0
PROX_PCT_MIN_SHORT = -5.0
PROX_PCT_MAX_SHORT = 3.0
RSI_MAX_LONG = 40.0
RSI_MIN_SHORT = 60.0
VOL_RATIO = 0.7
LOOKBACK = 80
OUTCOME_BARS = 5
OUTCOME_THRESHOLD_PCT = 3.0


def linear_regression(y):
    n = len(y)
    if n < 2:
        return 0.0, y[0] if n else 0.0
    sx = sum(range(n))
    sy = sum(y)
    sxy = sum(i * y[i] for i in range(n))
    sx2 = sum(i * i for i in range(n))
    denom = n * sx2 - sx * sx
    if denom == 0:
        return 0.0, sy / n
    slope = (n * sxy - sx * sy) / denom
    intercept = (sy - slope * sx) / n
    return slope, intercept


def count_touches(values, slope, intercept, tol_pct):
    touches = 0
    for i, v in enumerate(values):
        line = intercept + slope * i
        if line <= 0:
            continue
        diff_pct = abs(v - line) / line * 100
        if diff_pct <= tol_pct:
            touches += 1
    return touches


def calc_rsi(closes, period=14):
    if len(closes) < period + 1:
        return 50.0
    g = l = 0.0
    for i in range(1, period + 1):
        d = closes[i] - closes[i - 1]
        if d > 0: g += d
        else:     l += abs(d)
    ag = g / period; al = l / period
    for i in range(period + 1, len(closes)):
        d = closes[i] - closes[i - 1]
        if d > 0:
            ag = (ag * (period - 1) + d) / period
            al = al * (period - 1) / period
        else:
            ag = ag * (period - 1) / period
            al = (al * (period - 1) + abs(d)) / period
    if al == 0:
        return 100.0
    return 100 - (100 / (1 + ag / al))


def evaluate_window(closes, highs, lows, volumes):
    """Returns dict with LONG + SHORT eval at last bar of window."""
    n = len(closes)
    if n < MIN_HISTORY:
        return None
    mean_price = sum(closes) / n
    if mean_price <= 0:
        return None

    result = {"long": None, "short": None}

    # LONG: regression em lows
    slope, intercept = linear_regression(lows)
    slope_pct = (slope / mean_price) * 100
    slope_deg = math.degrees(math.atan(slope_pct))
    touches = count_touches(lows, slope, intercept, TOUCH_TOL_PCT)
    if SLOPE_DEG_MIN <= slope_deg <= SLOPE_DEG_MAX and touches >= MIN_TOUCHES:
        action_line = intercept + slope * (n - 1)
        if action_line > 0:
            price = closes[-1]
            prox = (price - action_line) / action_line * 100
            rsi = calc_rsi(closes)
            # vol drying
            vol_dry = False
            if len(volumes) >= 10:
                recent = volumes[-3:]; prior = volumes[-10:-3]
                ra = sum(recent) / len(recent); pa = sum(prior) / len(prior)
                if pa > 0:
                    vol_dry = ra < pa * VOL_RATIO
            ripening = (PROX_PCT_MIN_LONG <= prox <= PROX_PCT_MAX_LONG) and rsi < RSI_MAX_LONG and vol_dry
            result["long"] = {
                "slope_deg": slope_deg, "touches": touches,
                "proximity_pct": prox, "rsi": rsi,
                "vol_drying": vol_dry, "ripening": ripening,
                "action_line": action_line,
            }

    # SHORT: regression em highs
    slope, intercept = linear_regression(highs)
    slope_pct = (slope / mean_price) * 100
    slope_deg = math.degrees(math.atan(slope_pct))
    touches = count_touches(highs, slope, intercept, TOUCH_TOL_PCT)
    if -SLOPE_DEG_MAX <= slope_deg <= -SLOPE_DEG_MIN and touches >= MIN_TOUCHES:
        action_line = intercept + slope * (n - 1)
        if action_line > 0:
            price = closes[-1]
            prox = (price - action_line) / action_line * 100
            rsi = calc_rsi(closes)
            vol_dry = False
            if len(volumes) >= 10:
                recent = volumes[-3:]; prior = volumes[-10:-3]
                ra = sum(recent) / len(recent); pa = sum(prior) / len(prior)
                if pa > 0:
                    vol_dry = ra < pa * VOL_RATIO
            ripening = (PROX_PCT_MIN_SHORT <= prox <= PROX_PCT_MAX_SHORT) and rsi > RSI_MIN_SHORT and vol_dry
            result["short"] = {
                "slope_deg": slope_deg, "touches": touches,
                "proximity_pct": prox, "rsi": rsi,
                "vol_drying": vol_dry, "ripening": ripening,
                "action_line": action_line,
            }
    return result


def load_candles(market):
    p = CANDLES_DIR / f"{market}_1day.json"
    if not p.exists():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None
    out = []
    for c in data:
        if not isinstance(c, dict): continue
        try:
            out.append({
                "ts": c.get("ts"),
                "open": float(c["open"]),
                "high": float(c["high"]),
                "low":  float(c["low"]),
                "close": float(c["close"]),
                "volume": float(c.get("volume", 0)),
            })
        except Exception: pass
    return out


def backtest_market(market, candles):
    """Walks bar by bar over last 90 bars (~30 days), classifying ripening + outcome."""
    if len(candles) < LOOKBACK + OUTCOME_BARS + 30:
        return None
    events = {"long": [], "short": []}
    start_i = LOOKBACK
    end_i = len(candles) - OUTCOME_BARS  # need OUTCOME_BARS forward for outcome
    for i in range(start_i, end_i):
        window = candles[i - LOOKBACK : i + 1]
        closes = [c["close"] for c in window]
        highs  = [c["high"]  for c in window]
        lows   = [c["low"]   for c in window]
        vols   = [c["volume"] for c in window]
        ev = evaluate_window(closes, highs, lows, vols)
        if not ev: continue

        outcome_bars = candles[i + 1 : i + 1 + OUTCOME_BARS]
        if not outcome_bars: continue
        entry_price = candles[i]["close"]

        # LONG outcome: max close in next OUTCOME_BARS vs entry
        max_close = max(b["close"] for b in outcome_bars)
        long_move = (max_close - entry_price) / entry_price * 100
        # SHORT outcome: min close
        min_close = min(b["close"] for b in outcome_bars)
        short_move = (entry_price - min_close) / entry_price * 100

        if ev["long"]:
            events["long"].append({
                "idx": i,
                "ripening": ev["long"]["ripening"],
                "proximity_pct": ev["long"]["proximity_pct"],
                "rsi": ev["long"]["rsi"],
                "outcome_pct": long_move,
                "hit": long_move >= OUTCOME_THRESHOLD_PCT,
            })
        if ev["short"]:
            events["short"].append({
                "idx": i,
                "ripening": ev["short"]["ripening"],
                "proximity_pct": ev["short"]["proximity_pct"],
                "rsi": ev["short"]["rsi"],
                "outcome_pct": short_move,
                "hit": short_move >= OUTCOME_THRESHOLD_PCT,
            })
    return events


def summary(events_by_market):
    """Aggregates ripening hit-rate across markets."""
    agg = {"long": {"ripening": [], "not_ripening": []},
           "short": {"ripening": [], "not_ripening": []}}
    for mkt, events in events_by_market.items():
        for side in ("long", "short"):
            for ev in events.get(side, []):
                key = "ripening" if ev["ripening"] else "not_ripening"
                agg[side][key].append(ev)
    return agg


def main():
    print(f"=== Tori Proximity Backtest (lookback={LOOKBACK}d, outcome={OUTCOME_BARS}d, threshold={OUTCOME_THRESHOLD_PCT}%) ===\n")
    candle_files = sorted(CANDLES_DIR.glob("*_1day.json"))
    print(f"Markets cache: {len(candle_files)}")
    events_by_market = {}
    for f in candle_files:
        mkt = f.stem.replace("_1day", "")
        candles = load_candles(mkt)
        if not candles: continue
        bt = backtest_market(mkt, candles)
        if bt:
            events_by_market[mkt] = bt
    print(f"Markets com dados suficientes: {len(events_by_market)}\n")

    agg = summary(events_by_market)
    for side in ("long", "short"):
        ripe = agg[side]["ripening"]
        not_ripe = agg[side]["not_ripening"]
        print(f"=== {side.upper()} side ===")
        print(f"  ripening events: {len(ripe)}")
        print(f"  not-ripening events: {len(not_ripe)}")
        if ripe:
            hits = sum(1 for e in ripe if e["hit"])
            hit_rate = hits / len(ripe) * 100
            avg_outcome = sum(e["outcome_pct"] for e in ripe) / len(ripe)
            avg_outcome_hits = sum(e["outcome_pct"] for e in ripe if e["hit"]) / max(hits, 1)
            print(f"  RIPENING hit-rate: {hit_rate:.1f}% ({hits}/{len(ripe)}) -- avg outcome all: {avg_outcome:+.2f}% / wins only: {avg_outcome_hits:+.2f}%")
        if not_ripe:
            hits_nr = sum(1 for e in not_ripe if e["hit"])
            base_rate = hits_nr / len(not_ripe) * 100
            print(f"  base-rate (not-ripening): {base_rate:.1f}% ({hits_nr}/{len(not_ripe)})")
        if ripe and not_ripe:
            ripe_hit = sum(1 for e in ripe if e["hit"]) / len(ripe)
            nr_hit = sum(1 for e in not_ripe if e["hit"]) / len(not_ripe)
            edge_pct_pts = (ripe_hit - nr_hit) * 100
            print(f"  edge (ripening vs baseline): {edge_pct_pts:+.1f} pct-pts")
        print()

    # Gate decisorio
    # Predicate diagnostico relaxado: so slope + proximity (sem RSI/vol_dry)
    print("=== DIAGNOSTICO PREDICATE LAX (slope + proximity apenas) ===")
    for side in ("long", "short"):
        all_events = agg[side]["ripening"] + agg[side]["not_ripening"]
        if not all_events: continue
        # Proximity range zone -- por construcao do walker, todos events tem trendline valida.
        if side == "long":
            in_zone = [e for e in all_events if PROX_PCT_MIN_LONG <= e["proximity_pct"] <= PROX_PCT_MAX_LONG]
        else:
            in_zone = [e for e in all_events if PROX_PCT_MIN_SHORT <= e["proximity_pct"] <= PROX_PCT_MAX_SHORT]
        if not in_zone:
            print(f"  {side.upper()}: lax 0 events (proximity zone vazia)")
            continue
        hits = sum(1 for e in in_zone if e["hit"])
        hit_rate = hits / len(in_zone) * 100
        not_in = [e for e in all_events if e not in in_zone]
        nz_hits = sum(1 for e in not_in if e["hit"]) if not_in else 0
        nz_rate = nz_hits / len(not_in) * 100 if not_in else 0
        edge = hit_rate - nz_rate
        print(f"  {side.upper()}: lax n={len(in_zone)} hit-rate {hit_rate:.1f}% vs out-zone n={len(not_in)} {nz_rate:.1f}% -- edge {edge:+.1f}pp")
    print()

    print("=== DECISAO GO/NO-GO (predicate 4-AND original) ===")
    for side in ("long", "short"):
        ripe = agg[side]["ripening"]
        if not ripe:
            print(f"  {side.upper()}: NO-GO -- sample size 0")
            continue
        if len(ripe) < 30:
            print(f"  {side.upper()}: NO-GO -- sample {len(ripe)} < 30 (precisa mais historico)")
            continue
        hits = sum(1 for e in ripe if e["hit"])
        hit_rate = hits / len(ripe) * 100
        decision = "GO" if hit_rate >= 40 else "NO-GO"
        print(f"  {side.upper()}: {decision} -- hit-rate {hit_rate:.1f}% (gate 40%) com n={len(ripe)}")


if __name__ == "__main__":
    main()
