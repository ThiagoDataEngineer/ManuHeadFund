"""branch_a_v2_expanded.py -- WSS Branch A re-run com universe expandido + fast lib.

Comparativo: v1 (49 markets, ~50 signals p3_bear) vs v2 (135 markets, expected ~150+ signals).

Uses lib_methodology_fast.py (NumPy vectorized) — should run in ~30s vs ~5min v1.
"""
from __future__ import annotations
import sys, time
sys.path.insert(0, "backtest")
from collections import defaultdict
from lib_methodology import (dedup_alphabetical, dedup_max_wss,
                              cluster_portfolio_avg, effective_n,
                              bootstrap_ci_by_day)
from lib_methodology_fast import (build_btc_regime_index_fast, walk_signals_fast,
                                   load_universe, COSTS_PCT)
from wyckoff_spring_score import compute_wss, load_market_quality, months_post_halving

THR_NET = 1.0 + COSTS_PCT  # threshold=1% gross + 0.6% costs


def hit_rate(events):
    if not events: return None
    return sum(1 for e in events if e["outcome"] - COSTS_PCT >= 1.0) / len(events) * 100


def main():
    t0 = time.time()
    print("=== Branch A v2 — Expanded Universe (NumPy fast) ===\n")

    print("Loading universe...")
    md = load_universe(min_bars=300, include_external=True)
    print(f"  Markets: {len(md)}")

    print("Building BTC regime (Bitstamp 7y vectorized)...")
    btc = build_btc_regime_index_fast()
    print(f"  Days indexed: {len(btc)} | took {time.time()-t0:.1f}s")

    print("Walking signals (vectorized RSI + early term)...")
    t1 = time.time()
    all_e = walk_signals_fast(md, btc, window=3)
    print(f"  Events: {len(all_e)} | took {time.time()-t1:.1f}s")

    sig = [e for e in all_e if e["signal"] == "v" and e["phase"] in ("h20_p3_bear", "h24_p3_bear")]
    base = [e for e in all_e if e["signal"] == "_" and e["phase"] in ("h20_p3_bear", "h24_p3_bear")]
    print(f"  Sig p3_bear: {len(sig)} | Base p3_bear: {len(base)}")
    print(f"  Distinct days sig: {effective_n(sig)}")

    # Score WSS — APENAS sig events (baseline nao precisa scoring, sao todos baseline natural)
    # Otimizacao: pular 58k iteracoes do baseline. Baseline eh "what random day looks like".
    qt = load_market_quality()
    vol_dist = sorted([e["btc_vol_20d"] for e in all_e if e["btc_vol_20d"] is not None])
    by_day_sig = defaultdict(list)
    for e in sig: by_day_sig[e["ts"][:10]].append(e)
    t2 = time.time()
    scored = []
    for e in sig:
        cs = len(by_day_sig[e["ts"][:10]])
        mph = months_post_halving(e["ts"])
        s = compute_wss(e["market"], e["btc_drawdown"], e["btc_vol_20d"], mph, cs, vol_dist, qt)
        scored.append({**e, **s})
    print(f"  WSS sig scoring: {len(scored)} events | took {time.time()-t2:.1f}s")
    # Baseline: pass-through (no WSS needed)
    base_scored = base  # same structure, just no wss/tier fields

    tier_s_sig = [e for e in scored if e["tier"] == "S"]
    print(f"\n  Tier S events: {len(tier_s_sig)} | Distinct days: {effective_n(tier_s_sig)}")

    # OOS by cycle
    for cycle_filter, cycle_name in [
        ({"h20_p3_bear"}, "h20_p3_bear"),
        ({"h24_p3_bear"}, "h24_p3_bear"),
        ({"h20_p3_bear","h24_p3_bear"}, "combined"),
    ]:
        cycle_sig = [e for e in tier_s_sig if e["phase"] in cycle_filter]
        cycle_base = [e for e in base_scored if e["phase"] in cycle_filter]
        if len(cycle_sig) < 3:
            print(f"\n-- {cycle_name}: insufficient ({len(cycle_sig)})")
            continue
        sig_sorted = sorted(cycle_sig, key=lambda e: e["ts"])
        split = int(len(sig_sorted) * 0.80)
        if split < 1 or split >= len(sig_sorted):
            continue
        last_train_ts = sig_sorted[split-1]["ts"]
        ho_sig = sig_sorted[split:]
        ho_base = [e for e in cycle_base if e["ts"] > last_train_ts]

        print(f"\n== {cycle_name} ==")
        print(f"  Train: {len(sig_sorted[:split])} events ({effective_n(sig_sorted[:split])} days)")
        print(f"  OOS:   {len(ho_sig)} events ({effective_n(ho_sig)} days) | OOS base days: {effective_n(ho_base)}")

        print(f"  {'method':<28} {'n_evs':>6} {'n_days':>7} {'sig%':>7} {'base%':>7} {'lift':>7} {'CI 95%':>18}")
        print(f"  {'-'*82}")

        for name, fn in [("M1 per-event", lambda e: e), ("M2 alphabetical", dedup_alphabetical), ("M3 max-WSS", dedup_max_wss)]:
            if callable(fn) and fn != (lambda e: e):
                ho_s = fn(ho_sig); ho_b = fn(ho_base)
            else:
                ho_s = ho_sig; ho_b = ho_base
            sr = hit_rate(ho_s); br = hit_rate(ho_b)
            lift = (sr - br) if sr is not None and br is not None else 0
            ci_str = "N/A"
            if name == "M2 alphabetical":
                ci = bootstrap_ci_by_day(ho_sig, ho_base, n_iter=500, seed=42)
                if ci: ci_str = f"[{ci['ci_low']:+.1f}, {ci['ci_high']:+.1f}]"
            print(f"  {name:<28} {len(ho_s):>6} {effective_n(ho_s):>7} {sr:>6.1f}% {br:>6.1f}% {lift:>+5.1f}pp {ci_str:>18}")

    print(f"\nTotal time: {time.time()-t0:.1f}s")
    
    # Save results for Branch C
    import json
    from pathlib import Path
    from datetime import datetime
    
    output = {
        "timestamp": datetime.now().isoformat(),
        "n_markets": len(md),
        "n_total_events": len(all_e),
        "n_sig_events": len(sig),
        "n_tier_s_events": len(tier_s_sig),
        "all_sig_events": scored,  # All scored sig events with WSS
        "execution_time_seconds": time.time() - t0
    }
    
    output_file = Path(__file__).parent.parent / "journal" / "branch_a_v2_expanded_results.json"
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Results saved: {output_file.name}")


if __name__ == "__main__":
    main()
