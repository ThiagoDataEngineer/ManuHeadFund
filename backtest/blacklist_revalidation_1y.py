"""blacklist_revalidation_1y.py -- Re-validar blacklist BULL_WEAK+LONG em 365+ dias.

Hipotese: blacklist criada em 2025 phase_2_top com -0.37R. Em phase_3_bear
(mes 18-30 post-halving 2024) pode ter EV diferente. 9 markets blacklisted
hoje sao TIER A premium (score=100), bloqueados injustamente?

Methodology:
  1. 9 markets blacklisted real (per decisions.csv)
  2. Walk last 365+ bars (1+ year)
  3. Filter: bars em regime BULL_WEAK proxy (broader definition)
  4. Para cada bar BULL_WEAK: simular LONG entry (vol/score nao filtered —
     replica o que sistema faria SEM blacklist)
  5. Measure outcome 3-bar (matches WSS) E 5-bar E 10-bar windows
  6. Aggregate
"""
from __future__ import annotations
import json
import numpy as np
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
COSTS_PCT = 0.6
LOOKBACK = 60
DAYS_WINDOW = 400  # >365 days

BLOCKED_MARKETS = ["BCHUSDT", "BTCUSDT", "CFGUSDT", "INJUSDT", "PENDLEUSDT",
                   "RENDERUSDT", "SKYUSDT", "XMRUSDT", "XRPUSDT"]


def load_candles(market):
    f = CANDLES_DIR / f"{market}_1day.json"
    if not f.exists(): return []
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(d, list): return d
    except: pass
    return []


def is_bull_weak_proxy_v2(closes, i):
    """Broader BULL_WEAK proxy:
       - price > SMA50 (uptrend exists)
       - change_30d in [-10%, +20%] (modest momentum, not strong rally)
       - NOT in capitulation (change_7d > -10%)
    """
    if i < 50: return False
    price = closes[i]
    sma_50 = closes[i-50:i].mean()
    if price <= sma_50: return False  # not uptrend
    if i < 30: return False
    ch_30d = (price - closes[i-30]) / closes[i-30] * 100
    if not (-10.0 <= ch_30d <= 20.0): return False
    if i < 7: return False
    ch_7d = (price - closes[i-7]) / closes[i-7] * 100
    if ch_7d < -10.0: return False  # exclude capitulation
    return True


def walk_market(market, candles, days_window):
    """Walk candles, identify BULL_WEAK bars, simulate LONG entries.
    Outcomes: 3-bar (WSS) AND 5-bar AND 10-bar windows."""
    n = len(candles)
    if n < LOOKBACK + 10 + 30: return []
    closes = np.array([c["close"] for c in candles])
    ts_list = [c.get("ts","")[:10] for c in candles]

    start = max(LOOKBACK, n - days_window - 10)
    end = n - 10  # need 10-bar window outcome
    entries = []
    for i in range(start, end):
        if not is_bull_weak_proxy_v2(closes, i): continue
        # LONG entry simulation at close[i]
        entry = closes[i]
        out_3 = (closes[i+1:i+1+3].max() - entry) / entry * 100 - COSTS_PCT
        out_5 = (closes[i+1:i+1+5].max() - entry) / entry * 100 - COSTS_PCT
        out_10 = (closes[i+1:i+1+10].max() - entry) / entry * 100 - COSTS_PCT
        # Also negative: max drawdown over windows
        dd_3 = (closes[i+1:i+1+3].min() - entry) / entry * 100 - COSTS_PCT
        dd_5 = (closes[i+1:i+1+5].min() - entry) / entry * 100 - COSTS_PCT
        entries.append({
            "market": market, "ts": ts_list[i],
            "out_3": out_3, "out_5": out_5, "out_10": out_10,
            "dd_3": dd_3, "dd_5": dd_5
        })
    return entries


def main():
    print("=== Blacklist BULL_WEAK+LONG re-validation (365+ days) ===\n")
    all_entries = []
    per_market = defaultdict(list)

    for m in BLOCKED_MARKETS:
        c = load_candles(m)
        if len(c) < LOOKBACK + 10 + 30:
            print(f"  {m:<14} INSUFFICIENT candles ({len(c)})")
            continue
        entries = walk_market(m, c, DAYS_WINDOW)
        if entries:
            print(f"  {m:<14} {len(entries)} BULL_WEAK bars")
            all_entries.extend(entries)
            per_market[m].extend(entries)

    if not all_entries:
        print("\nNo BULL_WEAK bars found em 1y. Proxy may need refinement.")
        return

    print(f"\n=== Aggregate (n={len(all_entries)} BULL_WEAK signals across {DAYS_WINDOW}d) ===")

    for window_key, label in [("out_3", "3-bar (WSS)"), ("out_5", "5-bar"), ("out_10", "10-bar")]:
        outs = [e[window_key] for e in all_entries]
        wins = sum(1 for o in outs if o >= 1.0)
        print(f"\n  {label}:")
        print(f"    Mean EV (net):  {np.mean(outs):+.2f}%")
        print(f"    Median EV:      {np.median(outs):+.2f}%")
        print(f"    Hit rate >=1%:  {wins/len(outs)*100:.0f}%  ({wins}/{len(outs)})")
        print(f"    Best:           {max(outs):+.2f}%")
        print(f"    Worst:          {min(outs):+.2f}%")
        print(f"    Stddev:         {np.std(outs):.2f}%")

    # Risk: max drawdown analysis
    dds_3 = [e["dd_3"] for e in all_entries]
    dds_5 = [e["dd_5"] for e in all_entries]
    print(f"\n  Drawdown analysis:")
    print(f"    Mean 3-bar DD:  {np.mean(dds_3):+.2f}%")
    print(f"    Mean 5-bar DD:  {np.mean(dds_5):+.2f}%")
    print(f"    Worst 5-bar DD: {min(dds_5):+.2f}%")

    print(f"\n=== Per market (3-bar window) ===")
    print(f"  {'Market':<14} {'n':>4} {'mean':>8} {'hit%':>6} {'worst':>8}")
    for m in sorted(per_market.keys()):
        sigs = per_market[m]
        evs = [s["out_3"] for s in sigs]
        ws = sum(1 for s in sigs if s["out_3"] >= 1.0)
        print(f"  {m:<14} {len(sigs):>4} {np.mean(evs):>+7.2f}% {ws/len(sigs)*100:>5.0f}% {min(evs):>+7.2f}%")

    print(f"\n=== VERDICT ===")
    main_ev = np.mean([e["out_3"] for e in all_entries])
    main_hit = sum(1 for e in all_entries if e["out_3"] >= 1.0) / len(all_entries) * 100
    main_dd = np.mean([e["dd_5"] for e in all_entries])

    print(f"  Blacklist baseline (2025 phase_2_top): -0.4R avg = ~-0.6pp net")
    print(f"  Counterfactual EV (1y BULL_WEAK 3-bar): {main_ev:+.2f}pp")
    print(f"  Counterfactual hit rate:                {main_hit:.0f}%")
    print(f"  Mean 5-bar drawdown (risk):             {main_dd:+.2f}pp")
    print()

    if main_ev > 1.5 and main_hit > 50:
        print(f"  >> RELAX BLACKLIST STRONGLY <<")
        print(f"     EV +{main_ev:.2f}pp e hit {main_hit:.0f}% justifica relaxar pra Tier B PAPER")
        print(f"     Action recommended: convert SKIP -> PAPER tier no lib_operational_whitelist")
    elif main_ev > 0.5:
        print(f"  >> RELAX WITH CAP <<")
        print(f"     Lift positivo {main_ev:.2f}pp mas moderado. Convert SKIP -> OBSERVE.")
    elif main_ev > -0.5:
        print(f"  >> KEEP MONITORING <<")
        print(f"     Borderline neutro {main_ev:+.2f}pp. Re-test mensalmente.")
    else:
        print(f"  >> BLACKLIST JUSTIFIED <<")
        print(f"     Negative {main_ev:.2f}pp confirms blacklist still valid.")

    # Save
    out = ROOT / "journal/blacklist_revalidation_1y.json"
    out.write_text(json.dumps({
        "audit_ts": str(np.datetime64('now')),
        "markets_analyzed": BLOCKED_MARKETS,
        "days_window": DAYS_WINDOW,
        "n_bull_weak_signals": len(all_entries),
        "out_3_bar": {"mean_ev": round(main_ev, 2), "hit_pct": round(main_hit, 1)},
        "verdict": "RELAX" if main_ev > 0.5 else ("MONITOR" if main_ev > -0.5 else "KEEP")
    }, indent=2), encoding="utf-8")
    print(f"\nSaved: {out}")


if __name__ == "__main__":
    main()
