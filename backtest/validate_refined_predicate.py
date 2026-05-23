"""validate_refined_predicate.py -- Validacao profunda do predicate refinado.

Best config grid: mult=2.5, threshold=3%, close_rej=0.3, confluence=RSI<30
Edge phase_3_bear: +20.7pp (n=26)

Pergunta: edge sobrevive (a) per-cycle split, (b) walk-forward, (c) OOS, (d) outras phases?
"""
from __future__ import annotations
import json, math, sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

LOOKBACK = 60
COSTS_PCT = 0.6

HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
HALVING_2020 = datetime(2020, 5, 11, tzinfo=timezone.utc)

# REFINED predicate
MULT = 2.5
THRESHOLD = 3.0
CLOSE_REJ = 0.3
RSI_CONF = 30.0


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
    return "pre_h20"


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
        if d > 0: ag = (ag*(period-1) + d)/period; al = al*(period-1)/period
        else: ag = ag*(period-1)/period; al = (al*(period-1) + abs(d))/period
    if al == 0: return 100.0
    return 100 - (100/(1 + ag/al))


def refined_predicate(volumes, lows, highs, closes):
    """Refined: mult=2.5 + close_rej=0.3 + RSI<30."""
    n = len(volumes)
    lookback = 20
    if n < lookback: return False
    avg = sum(volumes[-lookback:-1]) / (lookback - 1)
    if avg <= 0 or volumes[-1] < MULT * avg: return False
    prior_lows = lows[-lookback:-1]
    new_low = lows[-1] < min(prior_lows)
    rng = highs[-1] - lows[-1]
    if rng <= 0: return False
    close_above = closes[-1] > lows[-1] + rng * CLOSE_REJ
    if not (new_low and close_above): return False
    rsi = calc_rsi(closes)
    return rsi < RSI_CONF


def load_candles(market):
    p = CANDLES_DIR / f"{market}_1day.json"
    if not p.exists(): return None
    try: data = json.loads(p.read_text(encoding="utf-8"))
    except: return None
    out = []
    for c in data:
        if not isinstance(c, dict): continue
        try:
            out.append({"ts": c.get("ts"), "open": float(c["open"]),
                        "high": float(c["high"]), "low": float(c["low"]),
                        "close": float(c["close"]), "volume": float(c.get("volume", 0))})
        except: pass
    return out


def walk_market(candles, outcome_bars=5):
    events = []
    if len(candles) < LOOKBACK + outcome_bars + 30: return events
    end = len(candles) - outcome_bars
    net_threshold = THRESHOLD + COSTS_PCT
    for i in range(LOOKBACK, end):
        win = candles[i-LOOKBACK:i+1]
        highs = [c["high"] for c in win]; lows = [c["low"] for c in win]
        closes = [c["close"] for c in win]; volumes = [c["volume"] for c in win]
        ts = candles[i].get("ts","")
        phase = assign_phase(str(ts))
        out = candles[i+1:i+1+outcome_bars]
        if not out: continue
        entry = candles[i]["close"]
        max_c = max(c["close"] for c in out)
        long_move = (max_c - entry) / entry * 100
        signal = refined_predicate(volumes, lows, highs, closes)
        events.append({"ts": ts, "phase": phase, "signal": "v" if signal else "_",
                       "hit_gross": long_move >= THRESHOLD,
                       "hit_net": long_move >= net_threshold,
                       "outcome_pct": long_move})
    return events


def stats(events, key="hit_net"):
    if not events: return None
    n = len(events); hits = sum(1 for e in events if e[key])
    return {"n": n, "hits": hits, "rate": hits/n*100}


def report_block(label, events):
    sig = [e for e in events if e["signal"] == "v"]
    base = [e for e in events if e["signal"] == "_"]
    if not sig or not base:
        print(f"  {label}: insufficient"); return None
    s = stats(sig); b = stats(base)
    sg = stats(sig, "hit_gross"); bg = stats(base, "hit_gross")
    en = s["rate"] - b["rate"]; eg = sg["rate"] - bg["rate"]
    print(f"  {label:<35} n={s['n']:>4}  edge_gross={eg:+5.1f}pp  edge_net={en:+5.1f}pp")
    return en


def main():
    print(f"=== Validation refined predicate ===")
    print(f"  mult={MULT}  threshold={THRESHOLD}%  close_rej={CLOSE_REJ}  RSI<{RSI_CONF}")
    print()

    # OPCAO B: usar TODOS markets do cache (>=300 bars pra ter LOOKBACK + outcome OK).
    # Antes filtravamos >=1500 bars (4y) -- restringia a 12 markets.
    # Agora aceita 300+ bars (~10 meses) -- captura mais signals em h24_p3_bear.
    target_markets = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300:
            target_markets.append((f.stem.replace("_1day",""), d))

    # Aggregate all events
    all_events = []
    per_market = {}
    for mkt, candles in target_markets:
        evs = walk_market(candles)
        if evs:
            for e in evs: e["market"] = mkt
            all_events.extend(evs)
            per_market[mkt] = evs

    # 1. Per-phase
    print("=== 1. Per-phase split (all markets) ===")
    phase_groups = defaultdict(list)
    for e in all_events: phase_groups[e["phase"]].append(e)
    for ph in sorted(phase_groups.keys()):
        report_block(ph, phase_groups[ph])

    # 2. Per-cycle (h20 vs h24 p3_bear)
    print("\n=== 2. Cross-cycle validation (p3_bear) ===")
    h20_events = [e for e in all_events if e["phase"] == "h20_p3_bear"]
    h24_events = [e for e in all_events if e["phase"] == "h24_p3_bear"]
    e_h20 = report_block("h20_p3_bear (2021-22)", h20_events)
    e_h24 = report_block("h24_p3_bear (2025-26)", h24_events)
    if e_h20 is not None and e_h24 is not None:
        print(f"  Cross-cycle consistency: {'STABLE' if (e_h20 > 0 and e_h24 > 0) else 'UNSTABLE'}")

    # 3. Walk-forward p3_bear
    print("\n=== 3. Walk-forward em p3_bear combined ===")
    p3_events = h20_events + h24_events
    sig_sorted = sorted([e for e in p3_events if e["signal"] == "v"], key=lambda e: e["ts"])
    base_sorted = sorted([e for e in p3_events if e["signal"] == "_"], key=lambda e: e["ts"])
    n_sig = len(sig_sorted)
    if n_sig >= 16:
        for f_idx in range(4):
            train_end = int(n_sig * (0.25 + f_idx*0.125))
            test_start = train_end
            test_end = min(test_start + n_sig // 5, n_sig)
            tr = sig_sorted[:train_end]; te = sig_sorted[test_start:test_end]
            if not tr or not te: continue
            tr_last = tr[-1]["ts"]; te_first = te[0]["ts"]; te_last = te[-1]["ts"]
            base_tr = [e for e in base_sorted if e["ts"] <= tr_last]
            base_te = [e for e in base_sorted if te_first <= e["ts"] <= te_last]
            if base_tr and base_te:
                e_tr = stats(tr,"hit_net")["rate"] - stats(base_tr,"hit_net")["rate"]
                e_te = stats(te,"hit_net")["rate"] - stats(base_te,"hit_net")["rate"]
                print(f"  fold {f_idx}: train n={len(tr)} edge={e_tr:+5.1f}pp | test n={len(te)} edge={e_te:+5.1f}pp")

    # 4. OOS holdout 20% in p3_bear
    print("\n=== 4. OOS holdout (last 20%) p3_bear ===")
    if n_sig >= 20:
        split = int(n_sig * 0.80)
        tr_oos = sig_sorted[:split]; te_oos = sig_sorted[split:]
        if tr_oos and te_oos:
            tr_last = tr_oos[-1]["ts"]
            base_tr = [e for e in base_sorted if e["ts"] <= tr_last]
            base_te = [e for e in base_sorted if e["ts"] > tr_last]
            if base_tr and base_te:
                e_tr = stats(tr_oos,"hit_net")["rate"] - stats(base_tr,"hit_net")["rate"]
                e_te = stats(te_oos,"hit_net")["rate"] - stats(base_te,"hit_net")["rate"]
                ratio = e_te/e_tr*100 if e_tr != 0 else 0
                print(f"  train n={len(tr_oos)} edge={e_tr:+5.1f}pp | holdout n={len(te_oos)} edge={e_te:+5.1f}pp | persistence={ratio:.0f}%")

    # 5. Per-market breakdown em p3_bear (anti-overfit single asset)
    print("\n=== 5. Per-market events em p3_bear ===")
    per_mkt_count = defaultdict(lambda: {"sig":0, "base":0, "hit_n":0})
    for e in p3_events:
        if e["signal"] == "v":
            per_mkt_count[e["market"]]["sig"] += 1
            if e["hit_net"]: per_mkt_count[e["market"]]["hit_n"] += 1
        else:
            per_mkt_count[e["market"]]["base"] += 1
    markets_with_signal = sorted([(m, d) for m, d in per_mkt_count.items() if d["sig"] > 0],
                                  key=lambda x: -x[1]["sig"])
    for mkt, d in markets_with_signal:
        rate = d["hit_n"] / d["sig"] * 100 if d["sig"] > 0 else 0
        print(f"  {mkt:<14} sig_events={d['sig']:>3}  hits_net={d['hit_n']}  rate={rate:.1f}%")

    print(f"\n=== Verdict ===")
    p3_sig_total = sum(d["sig"] for d in per_mkt_count.values())
    p3_total = len(p3_events)
    print(f"  Total signal events em phase_3_bear: {p3_sig_total}")
    print(f"  Total bars phase_3_bear: {p3_total}")
    print(f"  Frequency: {p3_sig_total/p3_total*100:.2f}% (sparse = expected for selective predicate)")
    markets_diverse = len([m for m, d in per_mkt_count.items() if d["sig"] >= 2])
    print(f"  Markets with >=2 signals: {markets_diverse}  (anti-overfit single asset: {'OK' if markets_diverse >= 5 else 'CONCERN'})")


if __name__ == "__main__":
    sys.exit(main())
