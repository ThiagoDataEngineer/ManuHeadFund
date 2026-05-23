"""blacklist_bull_weak_counterfactual.py -- Re-validar blacklist BULL_WEAK+LONG.

Hipotese: blacklist baseada em 2025 phase_2_top data (-0.4R avg). Agora estamos
em phase_3_bear (mes 25 post-halving). Regime mudou — pode estar custando lift.

Counterfactual direto:
  1. Le decisions.csv: SKIPs com regime=BULL_WEAK e reason matching blacklist
  2. Para cada SKIP: timestamp + market
  3. Pull candles (cache existente CoinEx)
  4. Compute outcome 3-bar window after SKIP timestamp
  5. Aggregate: total realized PnL se SKIPped trades tivessem executado
  6. Verdict: keep blacklist OR relax

Output: docs/backtest/BLACKLIST_BULL_WEAK_REVALIDATION.md
"""
from __future__ import annotations
import csv, json
import numpy as np
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
COSTS_PCT = 0.6  # round-trip
WINDOW_BARS = 3  # outcome window matches WSS predicate

def load_candles(market):
    f = CANDLES_DIR / f"{market}_1day.json"
    if not f.exists(): return []
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(d, list): return d
    except: pass
    return []

def find_bar_at_or_after(candles, ts_iso):
    """Find bar index where ts >= ts_iso. Returns -1 if not found."""
    target = ts_iso[:10]  # YYYY-MM-DD only
    for i, c in enumerate(candles):
        if c.get("ts", "")[:10] >= target:
            return i
    return -1


def main():
    # 1. Load SKIPs BULL_WEAK+LONG from decisions.csv
    skips = []
    with open(ROOT / "journal/decisions.csv", "r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if (row.get("decision") == "SKIP" and
                row.get("regime") == "BULL_WEAK" and
                "BULL_WEAK" in row.get("reason", "") and
                "live blacklist" in row.get("reason", "")):
                skips.append({
                    "ts": row.get("timestamp", ""),
                    "market": row.get("market", ""),
                    "reason": row.get("reason", "")[:80]
                })

    print(f"=== Counterfactual: BULL_WEAK+LONG blacklist re-validation ===\n")
    print(f"SKIPs BULL_WEAK+LONG total: {len(skips)}")
    if not skips:
        print("No SKIPs found. Exiting.")
        return

    # Date range
    sorted_skips = sorted(skips, key=lambda x: x["ts"])
    print(f"Date range: {sorted_skips[0]['ts'][:10]} -> {sorted_skips[-1]['ts'][:10]}\n")

    # 2. Per market, compute outcome
    markets_in_skips = set(s["market"] for s in skips)
    print(f"Markets blocked: {len(markets_in_skips)}")
    for m in sorted(markets_in_skips): print(f"  {m}")
    print()

    # Counterfactual: for each SKIP, find bar at that timestamp + measure max-close in 3 bars
    results = []
    not_found = []
    for skip in skips:
        market = skip["market"]
        candles = load_candles(market)
        if not candles:
            not_found.append(market)
            continue
        idx = find_bar_at_or_after(candles, skip["ts"])
        if idx < 0 or idx + WINDOW_BARS >= len(candles):
            continue
        entry = candles[idx]["close"]
        future = candles[idx+1:idx+1+WINDOW_BARS]
        max_close = max(c["close"] for c in future)
        outcome_pct = (max_close - entry) / entry * 100
        net = outcome_pct - COSTS_PCT
        results.append({
            "ts": skip["ts"], "market": market,
            "entry": entry, "max_close": max_close,
            "outcome_pct": outcome_pct, "net_pct": net,
            "win": net >= 1.0  # 1% net threshold (matches WSS)
        })

    if not_found:
        print(f"WARNING: candles missing for {len(set(not_found))} markets")

    print(f"\n=== Counterfactual results ({len(results)} skips analyzed) ===")
    if not results:
        print("No results to analyze.")
        return

    nets = [r["net_pct"] for r in results]
    wins = sum(1 for r in results if r["win"])
    mean_ev = np.mean(nets)
    median_ev = np.median(nets)
    hit_rate = wins / len(results) * 100

    print(f"  Mean EV (net):     {mean_ev:+.2f}%")
    print(f"  Median EV (net):   {median_ev:+.2f}%")
    print(f"  Hit rate (>=+1%):  {hit_rate:.0f}% ({wins}/{len(results)})")
    print(f"  Best outcome:      {max(nets):+.2f}%")
    print(f"  Worst outcome:     {min(nets):+.2f}%")
    print(f"  Stddev:            {np.std(nets):.2f}%")

    # Per-market breakdown
    print(f"\n=== Per-market breakdown ===")
    by_mkt = defaultdict(list)
    for r in results: by_mkt[r["market"]].append(r)
    print(f"  {'Market':<14} {'n':>3} {'mean':>8} {'hit%':>6} {'best':>7} {'worst':>7}")
    print(f"  {'-'*50}")
    for mkt in sorted(by_mkt.keys()):
        evs = [r["net_pct"] for r in by_mkt[mkt]]
        ws = sum(1 for r in by_mkt[mkt] if r["win"])
        print(f"  {mkt:<14} {len(evs):>3} {np.mean(evs):>+7.2f}% {ws/len(evs)*100:>5.0f}% {max(evs):>+6.2f}% {min(evs):>+6.2f}%")

    # Verdict
    print(f"\n=== VERDICT ===")
    print(f"  Blacklist baseline (2025): -0.37R = ~-0.55pp net (assuming 1.5% risk)")
    print(f"  Counterfactual EV now:     {mean_ev:+.2f}%")
    print()
    if mean_ev > 1.0:
        print(f"  -> RELAX BLACKLIST: counterfactual STRONGLY POSITIVE ({mean_ev:+.2f}pp)")
        print(f"     Action: remove blanket SKIP, allow with cap (e.g., paper-only OR 0.5% sizing)")
    elif mean_ev > 0:
        print(f"  -> RELAX WITH CAUTION: counterfactual mildly positive ({mean_ev:+.2f}pp)")
        print(f"     Action: convert SKIP -> PAPER tier (no live execution but tracked)")
    elif mean_ev > -0.5:
        print(f"  -> KEEP BUT MONITOR: counterfactual neutral ({mean_ev:+.2f}pp)")
        print(f"     Action: keep blacklist, re-test every 30d")
    else:
        print(f"  -> BLACKLIST JUSTIFIED: counterfactual negative ({mean_ev:+.2f}pp)")
        print(f"     Action: keep blacklist hard SKIP")

    # Save results
    out_path = ROOT / "journal/blacklist_bull_weak_revalidation.json"
    out_path.write_text(json.dumps({
        "audit_ts": datetime.now(timezone.utc).isoformat(),
        "n_skips_analyzed": len(results),
        "mean_ev_net_pct": round(mean_ev, 2),
        "median_ev_net_pct": round(median_ev, 2),
        "hit_rate_pct": round(hit_rate, 1),
        "best": round(max(nets), 2),
        "worst": round(min(nets), 2),
        "stddev": round(np.std(nets), 2),
        "per_market": {m: {"n": len(by_mkt[m]), "mean_ev": round(np.mean([r["net_pct"] for r in by_mkt[m]]), 2),
                           "hit_pct": round(sum(1 for r in by_mkt[m] if r["win"])/len(by_mkt[m])*100, 1)}
                       for m in sorted(by_mkt.keys())},
        "verdict": "RELAX" if mean_ev > 0 else "KEEP"
    }, indent=2), encoding="utf-8")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
