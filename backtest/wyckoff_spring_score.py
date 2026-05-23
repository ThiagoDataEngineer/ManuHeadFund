"""wyckoff_spring_score.py -- WSS composite scoring + tier classification.

Substitui gate binario BTC_VOL>=p60 por scoring 0-100 composito:
  - market_quality       (30%) — T1/T2/T3 from journal/wyckoff_market_quality.json
  - btc_vol_pct          (15%) — percentile vol_20d
  - btc_dd_zone          (15%) — -15 a -40% = sweet zone Wyckoff Spring
  - months_post_halving  (25%) — 12-26mo = bucket historico positivo
  - cluster_penalty      (15%) — -20 se >=3 markets disparam mesmo dia

Tier classification:
  WSS >= 70 = Tier S (paper-trade eligible)
  40 <= WSS < 70 = Tier A (observatory + TG alert)
  WSS < 40 = Tier B (log silent)
"""
from __future__ import annotations
import json, sys
from pathlib import Path
from collections import defaultdict
sys.path.insert(0, "backtest")
from regime_gate_alpha import (build_btc_regime_index, build_cross_corr_index,
                                load_candles, walk_signals,
                                CANDLES_DIR, EXT_DIR, WINDOW_BARS, COSTS_PCT)
from datetime import datetime, timezone

HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
HALVING_2020 = datetime(2020, 5, 11, tzinfo=timezone.utc)


def load_market_quality():
    p = Path("journal/wyckoff_market_quality.json")
    if not p.exists(): return {}
    return json.loads(p.read_text(encoding="utf-8"))


def months_post_halving(ts_iso):
    dt = datetime.fromisoformat(ts_iso.replace("Z","+00:00"))
    if dt >= HALVING_2024: return (dt - HALVING_2024).days / 30.5
    if dt >= HALVING_2020: return (dt - HALVING_2020).days / 30.5
    return -1


def score_market_quality(market, quality_table):
    q = quality_table.get(market)
    if not q: return 50  # unknown market = neutral
    return {"T1":100, "T2":60, "T3":20}.get(q["tier"], 50)


def score_btc_vol(vol_20d, vol_distribution):
    """Percentile rank of vol in distribution -> 0-100."""
    if vol_20d is None or not vol_distribution: return 50
    n = len(vol_distribution)
    below = sum(1 for v in vol_distribution if v < vol_20d)
    return int(below / n * 100)


def score_btc_dd_zone(dd):
    """Wyckoff Spring sweet zone: -15% to -40% drawdown from 90d high."""
    if dd is None: return 50
    if -40 <= dd <= -15: return 100
    if -50 <= dd <= -10: return 60
    if -55 <= dd <= -5:  return 30
    return 0


def score_months_post_halving(mph):
    """Bucket scoring from historical hit-rates:
       <12mo=50%, 12-18mo=90%, 18-22mo=61%, 22-26mo=81%, 26-30mo=100%."""
    if mph < 0: return 30
    if mph < 12: return 40
    if 12 <= mph < 18: return 95
    if 18 <= mph < 22: return 60
    if 22 <= mph < 26: return 85
    if 26 <= mph < 30: return 70  # n=1 only, less confident
    return 30


def cluster_penalty(cluster_size):
    """Penalty if >= 3 markets fire same day (correlated bet risk)."""
    if cluster_size <= 1: return 0
    if cluster_size == 2: return 5
    if cluster_size <= 4: return 15
    return 25  # very correlated = severe penalty


WEIGHTS = {"market":0.35, "vol":0.10, "dd":0.20, "mph":0.35, "cluster":1.0}

# Tier thresholds recalibrated to top-20% / middle-60% / bottom-20% of historical distribution.
# WSS = sum(weight*subscore) - cluster_penalty. Subscores 0-100, weights sum 1.0.
# Effective range pos: ~25 (worst) to ~95 (best).
TIER_S_MIN = 60.0
TIER_A_MIN = 45.0


def compute_wss(market, btc_dd, btc_vol, mph, cluster_size, vol_distribution, quality_table):
    """Returns dict {wss, market_q, vol_pct, dd_zone, mph_s, cluster_pen, tier}."""
    mq  = score_market_quality(market, quality_table)
    vp  = score_btc_vol(btc_vol, vol_distribution)
    ddz = score_btc_dd_zone(btc_dd)
    mphs= score_months_post_halving(mph)
    cp  = cluster_penalty(cluster_size)
    wss = (WEIGHTS["market"]*mq + WEIGHTS["vol"]*vp + WEIGHTS["dd"]*ddz
           + WEIGHTS["mph"]*mphs) - WEIGHTS["cluster"]*cp
    wss = max(0, min(100, wss))
    if wss >= TIER_S_MIN: tier = "S"
    elif wss >= TIER_A_MIN: tier = "A"
    else: tier = "B"
    return {"wss": round(wss,1), "tier":tier, "market_q":mq, "vol_pct":vp,
            "dd_zone":ddz, "mph_s":mphs, "cluster_pen":cp}


def main():
    btc_regime = build_btc_regime_index()
    cc = build_cross_corr_index()
    quality_table = load_market_quality()
    print(f"Market quality table: {len(quality_table)} markets")

    md = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300: md.append((f.stem.replace("_1day",""), d))
    for f in sorted(EXT_DIR.glob("*_BITSTAMP_1day.json")):
        market = f.stem.replace("_BITSTAMP_1day","")
        if market in ("BTCUSD","ETHUSD"): continue
        d = load_candles(market, src="bitstamp")
        if d and len(d) >= 1500: md.append((market, d))

    all_e = walk_signals(md, btc_regime, cc, window=WINDOW_BARS)
    sig = [e for e in all_e if e['signal']=='v' and e['phase'] in ('h20_p3_bear','h24_p3_bear')]

    # Vol distribution baseline (all events not just signals)
    vol_dist = sorted([e['btc_vol_20d'] for e in all_e if e['btc_vol_20d'] is not None])

    # Cluster size per day
    by_day = defaultdict(list)
    for e in sig: by_day[e['ts'][:10]].append(e)

    # Score each event
    scored = []
    for e in sig:
        cs = len(by_day[e['ts'][:10]])
        mph = months_post_halving(e['ts'])
        s = compute_wss(e['market'], e['btc_drawdown'], e['btc_vol_20d'],
                        mph, cs, vol_dist, quality_table)
        scored.append({**e, **s, "mph":round(mph,1), "cluster_size":cs})

    # Per-tier EV
    print("\n=== WSS Tier validation ===")
    print(f"{'tier':<5} {'n':>4} {'EV_net':>8} {'wins':>5} {'hit':>5} {'avg_win':>8} {'avg_loss':>9}")
    print("-"*55)
    for tier in ["S","A","B"]:
        evs = [e for e in scored if e['tier']==tier]
        if not evs: continue
        outs = [e['outcome']-COSTS_PCT for e in evs]
        wins = [o for o in outs if o > 0]
        losses = [o for o in outs if o <= 0]
        avg_w = sum(wins)/len(wins) if wins else 0
        avg_l = sum(losses)/len(losses) if losses else 0
        print(f"  {tier:<3} {len(evs):>4} {sum(outs)/len(outs):>+7.2f}% {len(wins):>5} {len(wins)/len(evs)*100:>4.0f}% {avg_w:>+7.2f}% {avg_l:>+8.2f}%")

    # OOS test
    print("\n=== OOS holdout test (last 20% by date, h24 only) ===")
    h24 = sorted([e for e in scored if e['phase']=='h24_p3_bear'], key=lambda e: e['ts'])
    split = int(len(h24)*0.80)
    if split >= 1 and split < len(h24):
        ho = h24[split:]
        print(f"  Total holdout: {len(ho)}")
        for tier in ["S","A","B"]:
            evs = [e for e in ho if e['tier']==tier]
            if not evs: continue
            outs = [e['outcome']-COSTS_PCT for e in evs]
            print(f"  Tier {tier}: n={len(evs)} EV_net={sum(outs)/len(outs):>+.2f}% hit={sum(1 for o in outs if o>0)/len(outs)*100:.0f}%")

    # Cross-cycle per tier
    print("\n=== Cross-cycle per tier ===")
    for cycle in ["h20_p3_bear","h24_p3_bear"]:
        print(f"  {cycle}:")
        for tier in ["S","A","B"]:
            evs = [e for e in scored if e['tier']==tier and e['phase']==cycle]
            if not evs: continue
            outs = [e['outcome']-COSTS_PCT for e in evs]
            print(f"    Tier {tier}: n={len(evs)} EV={sum(outs)/len(outs):>+.2f}%")

    # WSS distribution
    print("\n=== WSS distribution (all signals) ===")
    wss_buckets = defaultdict(int)
    for e in scored:
        bk = int(e['wss']//10)*10
        wss_buckets[bk] += 1
    for bk in sorted(wss_buckets):
        print(f"  WSS [{bk:>2}-{bk+10:>2}): {wss_buckets[bk]} events")

    # Current month-post-halving (May 2026)
    now_mph = (datetime.now(timezone.utc) - HALVING_2024).days / 30.5
    print(f"\nNow: {now_mph:.1f} months post-halving 2024 -> score_mph={score_months_post_halving(now_mph)}")

    # Top scored events
    print("\n=== TOP 10 WSS events (winners we'd identify) ===")
    scored.sort(key=lambda e: -e['wss'])
    for e in scored[:10]:
        out_net = e['outcome'] - COSTS_PCT
        print(f"  WSS={e['wss']:>5.1f} tier={e['tier']} {e['ts'][:10]} {e['market']:<12} out_net={out_net:+6.2f}% "
              f"[mkt={e['market_q']:>3} vol={e['vol_pct']:>3} dd={e['dd_zone']:>3} mph={e['mph_s']:>3} cl_pen={e['cluster_pen']}]")


if __name__ == "__main__":
    main()
