"""branch_a_oos_validation.py -- WSS OOS validation com 3 metodologias side-by-side.

Per cycle (h20, h24, combined) compute:
  - M1 per-event (baseline atual, potentially infla n)
  - M2 dedup_alphabetical (matches scanner behavior)
  - M3 dedup_max_wss (potential scanner refactor)
  - Bootstrap 95% CI for each

Output: tabela honest lift+CI por (cycle x method).
"""
from __future__ import annotations
import sys
from collections import defaultdict
sys.path.insert(0, "backtest")
from lib_methodology import (dedup_alphabetical, dedup_max_wss,
                              cluster_portfolio_avg, effective_n,
                              bootstrap_ci_by_day)
from regime_gate_alpha import (build_btc_regime_index, build_cross_corr_index,
                                load_candles, walk_signals,
                                CANDLES_DIR, EXT_DIR, WINDOW_BARS, COSTS_PCT)
from wyckoff_spring_score import compute_wss, load_market_quality, months_post_halving


THR_NET = 1.0 + COSTS_PCT  # threshold=1% gross + 0.6% costs = 1.6%


def hit_rate(events):
    if not events: return None
    return sum(1 for e in events if e["outcome"] - COSTS_PCT >= 1.0) / len(events) * 100


def main():
    btc = build_btc_regime_index()
    cc  = build_cross_corr_index()
    qt  = load_market_quality()

    md = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300: md.append((f.stem.replace("_1day",""), d))
    for f in sorted(EXT_DIR.glob("*_BITSTAMP_1day.json")):
        market = f.stem.replace("_BITSTAMP_1day","")
        if market in ("BTCUSD","ETHUSD"): continue
        d = load_candles(market, src="bitstamp")
        if d and len(d) >= 1500: md.append((market, d))

    all_e = walk_signals(md, btc, cc, window=WINDOW_BARS)
    sig = [e for e in all_e if e["signal"]=="v" and e["phase"] in ("h20_p3_bear","h24_p3_bear")]
    base = [e for e in all_e if e["signal"]=="_" and e["phase"] in ("h20_p3_bear","h24_p3_bear")]
    vol_dist = sorted([e["btc_vol_20d"] for e in all_e if e["btc_vol_20d"] is not None])

    # Score WSS in all sig events
    by_day_sig = defaultdict(list)
    for e in sig: by_day_sig[e["ts"][:10]].append(e)
    scored = []
    for e in sig:
        cs = len(by_day_sig[e["ts"][:10]])
        mph = months_post_halving(e["ts"])
        s = compute_wss(e["market"], e["btc_drawdown"], e["btc_vol_20d"], mph, cs, vol_dist, qt)
        # Normalize outcome to "outcome" field (subtract costs once)
        scored.append({**e, **s, "outcome": e["outcome"]})

    # Also score baseline (so dedup_max_wss has fair comparison)
    by_day_base = defaultdict(list)
    for e in base: by_day_base[e["ts"][:10]].append(e)
    base_scored = []
    for e in base:
        cs = len(by_day_base[e["ts"][:10]])
        mph = months_post_halving(e["ts"])
        s = compute_wss(e["market"], e["btc_drawdown"], e["btc_vol_20d"], mph, cs, vol_dist, qt)
        base_scored.append({**e, **s, "outcome": e["outcome"]})

    # Filter Tier S only (the actionable signal class)
    tier_s_sig = [e for e in scored if e["tier"] == "S"]
    # Baseline ALL (not filtered by tier — baseline is universe of non-signals)

    print("=== BRANCH A — OOS validation com 3 metodologias ===")
    print()
    print(f"Total Tier S sig events: {len(tier_s_sig)}")
    print(f"Distinct days Tier S: {effective_n(tier_s_sig)}")
    print()

    for cycle_filter, cycle_name in [
        ({"h20_p3_bear"}, "h20_p3_bear"),
        ({"h24_p3_bear"}, "h24_p3_bear"),
        ({"h20_p3_bear","h24_p3_bear"}, "combined"),
    ]:
        cycle_sig = [e for e in tier_s_sig if e["phase"] in cycle_filter]
        cycle_base = [e for e in base_scored if e["phase"] in cycle_filter]
        if not cycle_sig:
            print(f"-- {cycle_name}: NO Tier S events")
            continue

        # OOS split: last 20% of sig events by date
        sig_sorted = sorted(cycle_sig, key=lambda e: e["ts"])
        split = int(len(sig_sorted) * 0.80)
        if split < 1 or split >= len(sig_sorted):
            print(f"-- {cycle_name}: insufficient for split")
            continue
        last_train_ts = sig_sorted[split-1]["ts"]
        ho_sig = sig_sorted[split:]
        ho_base = [e for e in cycle_base if e["ts"] > last_train_ts]

        print(f"== {cycle_name} ==")
        print(f"  OOS sig events: {len(ho_sig)} | OOS distinct days: {effective_n(ho_sig)}")
        print(f"  OOS base events: {len(ho_base)} | OOS distinct days base: {effective_n(ho_base)}")
        print()
        print(f"  {'method':<28} {'n_evs':>6} {'n_days':>7} {'sig_hit':>8} {'base_hit':>9} {'lift':>7} {'CI 95%':>16}")
        print(f"  {'-'*82}")

        # M1: per-event (no dedup)
        sr = hit_rate(ho_sig)
        br = hit_rate(ho_base)
        lift = (sr - br) if sr is not None and br is not None else 0
        print(f"  {'M1 per-event':<28} {len(ho_sig):>6} {effective_n(ho_sig):>7} {sr:>7.1f}% {br:>8.1f}% {lift:>+5.1f}pp {'N/A':>16}")

        # M2 alphabetical
        ho_sig_m2 = dedup_alphabetical(ho_sig)
        ho_base_m2 = dedup_alphabetical(ho_base)
        sr2 = hit_rate(ho_sig_m2)
        br2 = hit_rate(ho_base_m2)
        lift2 = (sr2 - br2) if sr2 is not None and br2 is not None else 0
        ci2 = bootstrap_ci_by_day(ho_sig, ho_base, n_iter=1000, seed=42)
        ci2_s = f"[{ci2['ci_low']:+.1f}, {ci2['ci_high']:+.1f}]" if ci2 else "insuf"
        print(f"  {'M2 alphabetical (scanner)':<28} {len(ho_sig_m2):>6} {effective_n(ho_sig_m2):>7} {sr2:>7.1f}% {br2:>8.1f}% {lift2:>+5.1f}pp {ci2_s:>16}")

        # M3 max-WSS
        ho_sig_m3 = dedup_max_wss(ho_sig)
        ho_base_m3 = dedup_max_wss(ho_base)
        sr3 = hit_rate(ho_sig_m3)
        br3 = hit_rate(ho_base_m3)
        lift3 = (sr3 - br3) if sr3 is not None and br3 is not None else 0
        print(f"  {'M3 max-WSS':<28} {len(ho_sig_m3):>6} {effective_n(ho_sig_m3):>7} {sr3:>7.1f}% {br3:>8.1f}% {lift3:>+5.1f}pp {'(CI same as M2)':>16}")

        # M4 cluster portfolio avg
        ho_sig_m4 = cluster_portfolio_avg(ho_sig)
        ho_base_m4 = cluster_portfolio_avg(ho_base)
        sr4 = hit_rate(ho_sig_m4)
        br4 = hit_rate(ho_base_m4)
        lift4 = (sr4 - br4) if sr4 is not None and br4 is not None else 0
        print(f"  {'M4 portfolio mean':<28} {len(ho_sig_m4):>6} {effective_n(ho_sig_m4):>7} {sr4:>7.1f}% {br4:>8.1f}% {lift4:>+5.1f}pp {'cluster-as-1':>16}")

        print()


if __name__ == "__main__":
    main()
