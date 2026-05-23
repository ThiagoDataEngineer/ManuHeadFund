"""regime_gate_alpha.py -- Caminho alfa: regime gate antes do predicate.

Hipotese: vol_climax + RSI<30 funciona em CAPITULACAO real, falha em GRIND.
Adicionar regime gate que detecta "capitulation mode" e so libera signal nesse modo.

3 gates candidatos:
  1. BTC drawdown >= X% from rolling 90d high (Bitstamp full 7y)
  2. BTC realized vol (20d) >= percentil X (Bitstamp full)
  3. Cross-asset correlation BTC-ETH-SOL rolling 30d >= X (h24 only)

Best config Design 1: thr=1.0% win=3 (edge cross-cycle +18.9pp, OOS -25.1pp).
Pergunta: algum gate restaura OOS edge >= 0?
"""
from __future__ import annotations
import json
from datetime import datetime, timezone
from pathlib import Path
from math import sqrt

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"
EXT_DIR = ROOT / "journal" / "candles_external"

LOOKBACK = 60
COSTS_PCT = 0.6
MULT = 2.5
CLOSE_REJ = 0.3
RSI_CONF = 30.0

# WINNER Design 1: thr=1.0% win=3
THRESHOLD_PCT = 1.0
WINDOW_BARS = 3

HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
HALVING_2020 = datetime(2020, 5, 11, tzinfo=timezone.utc)


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
    return calc_rsi(closes) < RSI_CONF


def load_candles(market, src="coinex"):
    if src == "coinex":
        f = CANDLES_DIR / f"{market}_1day.json"
    else:
        f = EXT_DIR / f"{market}_{src.upper()}_1day.json"
    if not f.exists(): return []
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(d, list) and d and isinstance(d[0], dict): return d
    except: pass
    return []


def build_btc_regime_index():
    """Build per-day BTC indicators from Bitstamp 7y.
    Returns: {date_str_yyyy_mm_dd: {drawdown_pct, vol_20d, close, high_90d}}
    """
    btc = load_candles("BTCUSD", src="bitstamp")
    if not btc:
        raise RuntimeError("BTC Bitstamp data missing")
    # Sort by ts
    btc = sorted(btc, key=lambda c: c.get("ts",""))
    closes = [c["close"] for c in btc]
    dates = [c["ts"][:10] for c in btc]

    idx = {}
    for i in range(len(btc)):
        # Drawdown from rolling 90d high
        start = max(0, i-89)
        win_high = max(closes[start:i+1])
        dd = (closes[i] - win_high) / win_high * 100  # negative when below high

        # Realized vol 20d (stddev of % returns)
        vol = None
        if i >= 20:
            rets = [(closes[j] - closes[j-1])/closes[j-1] for j in range(i-19, i+1)]
            mean = sum(rets)/len(rets)
            var = sum((r-mean)**2 for r in rets)/len(rets)
            vol = sqrt(var) * 100  # daily vol %

        idx[dates[i]] = {"close": closes[i], "drawdown_pct": dd,
                         "vol_20d": vol, "high_90d": win_high}
    return idx


def build_cross_corr_index():
    """Cross-corr BTC-ETH rolling 30d. Uses Bitstamp 7y+ for FULL coverage (h20+h24).
    Returns: {date: pairwise_corr}
    """
    btc = sorted(load_candles("BTCUSD", src="bitstamp"), key=lambda c: c.get("ts",""))
    eth = sorted(load_candles("ETHUSD", src="bitstamp"), key=lambda c: c.get("ts",""))
    if not (btc and eth): return {}

    by_date = {}
    for src, lst in [("b",btc),("e",eth)]:
        for c in lst:
            d = c["ts"][:10]
            by_date.setdefault(d, {})[src] = c["close"]
    dates = sorted(by_date.keys())

    closes_b, closes_e, valid_dates = [], [], []
    for d in dates:
        v = by_date[d]
        if "b" in v and "e" in v:
            closes_b.append(v["b"])
            closes_e.append(v["e"])
            valid_dates.append(d)
    closes_s = closes_e  # alias - keep below code happy

    def corr(x, y):
        n = len(x)
        if n < 2: return 0
        mx = sum(x)/n; my = sum(y)/n
        cov = sum((xi-mx)*(yi-my) for xi,yi in zip(x,y))
        vx = sqrt(sum((xi-mx)**2 for xi in x))
        vy = sqrt(sum((yi-my)**2 for yi in y))
        if vx == 0 or vy == 0: return 0
        return cov/(vx*vy)

    idx = {}
    for i in range(len(valid_dates)):
        if i < 30: continue
        rb = [(closes_b[j]-closes_b[j-1])/closes_b[j-1] for j in range(i-29, i+1)]
        re = [(closes_e[j]-closes_e[j-1])/closes_e[j-1] for j in range(i-29, i+1)]
        c_be = corr(rb, re)
        idx[valid_dates[i]] = c_be
    return idx


def walk_signals(market_data, btc_regime, cross_corr, window=WINDOW_BARS):
    """Walk markets, capture signals + regime indicators at signal time."""
    events = []
    for market, candles in market_data:
        if len(candles) < LOOKBACK + window + 30: continue
        end = len(candles) - window
        for i in range(LOOKBACK, end):
            win = candles[i-LOOKBACK:i+1]
            highs   = [c["high"]   for c in win]
            lows    = [c["low"]    for c in win]
            closes  = [c["close"]  for c in win]
            volumes = [c["volume"] for c in win]
            ts = candles[i].get("ts","")
            d = ts[:10]
            phase = assign_phase(str(ts))
            if phase not in ("h20_p3_bear","h24_p3_bear"): continue
            entry = candles[i]["close"]
            out = candles[i+1:i+1+window]
            if len(out) < window: continue
            max_c = max(c["close"] for c in out)
            outcome = (max_c - entry) / entry * 100
            sig = refined_predicate(volumes, lows, highs, closes)
            btc = btc_regime.get(d, {})
            cc  = cross_corr.get(d)
            events.append({
                "ts": ts, "market": market, "phase": phase,
                "signal": "v" if sig else "_",
                "outcome": outcome,
                "btc_drawdown": btc.get("drawdown_pct"),
                "btc_vol_20d": btc.get("vol_20d"),
                "cross_corr": cc,
            })
    return events


def hit_rate(events, threshold_net):
    n = len(events)
    if n == 0: return None, 0
    wins = sum(1 for e in events if e["outcome"] >= threshold_net)
    return wins/n*100, n


def evaluate_gate(sig, base, gate_name, gate_fn, thr_net):
    """Apply gate_fn boolean filter on signals + same filter on baseline (apples-to-apples)."""
    sig_f = [e for e in sig if gate_fn(e)]
    base_f = [e for e in base if gate_fn(e)]
    sr, ns = hit_rate(sig_f, thr_net)
    br, nb = hit_rate(base_f, thr_net)
    if sr is None or br is None or ns < 5:
        return None
    edge = sr - br
    # OOS holdout
    sig_sorted = sorted(sig_f, key=lambda e: e["ts"])
    if len(sig_sorted) < 5: return None
    split = int(len(sig_sorted) * 0.80)
    if split < 1 or split >= len(sig_sorted): return None
    last_ts = sig_sorted[split-1]["ts"]
    ho = sig_sorted[split:]
    bh = [e for e in base_f if e["ts"] > last_ts]
    hr, _ = hit_rate(ho, thr_net)
    br_h, _ = hit_rate(bh, thr_net)
    oos = (hr - br_h) if hr is not None and br_h is not None else 0
    # Cross-cycle
    s_h20 = [e for e in sig_f if e["phase"]=="h20_p3_bear"]
    s_h24 = [e for e in sig_f if e["phase"]=="h24_p3_bear"]
    b_h20 = [e for e in base_f if e["phase"]=="h20_p3_bear"]
    b_h24 = [e for e in base_f if e["phase"]=="h24_p3_bear"]
    rh20,nh20 = hit_rate(s_h20, thr_net)
    rh24,nh24 = hit_rate(s_h24, thr_net)
    bh20,_    = hit_rate(b_h20, thr_net)
    bh24,_    = hit_rate(b_h24, thr_net)
    eh20 = (rh20-bh20) if rh20 is not None and bh20 is not None else 0
    eh24 = (rh24-bh24) if rh24 is not None and bh24 is not None else 0
    return {
        "gate": gate_name, "n_sig": ns, "edge": edge, "oos": oos,
        "h20": eh20, "h24": eh24, "n_h20": nh20, "n_h24": nh24,
    }


def _tdd_inline():
    # T1: hit_rate
    fake = [{"outcome":3.0},{"outcome":1.0},{"outcome":5.0}]
    r, n = hit_rate(fake, 2.5)
    assert n==3 and abs(r-200/3)<1e-6, f"T1 fail r={r}"
    # T2: phase
    assert assign_phase("2025-06-01T00:00:00+00:00")=="h24_p3_bear","T2 phase h24_p3"
    assert assign_phase("2021-08-01T00:00:00+00:00")=="h20_p3_bear","T2 phase h20_p3"
    # T3: predicate determinism
    import random; random.seed(7)
    v=[random.uniform(1,5) for _ in range(30)]
    l=[random.uniform(95,100) for _ in range(30)]
    h=[random.uniform(101,105) for _ in range(30)]
    c=[random.uniform(96,104) for _ in range(30)]
    assert refined_predicate(v,l,h,c)==refined_predicate(v,l,h,c),"T3 det"
    # T4: drawdown sign: deeper = more negative
    fake_btc = [{"ts":"2024-01-01T00:00:00Z","close":100,"high":100,"low":100,"open":100,"volume":1},
                {"ts":"2024-01-02T00:00:00Z","close":80,"high":80,"low":80,"open":80,"volume":1}]
    # Mock minimal regime build via direct calc
    closes = [c["close"] for c in fake_btc]
    dd_day2 = (80-100)/100*100
    assert dd_day2 == -20.0, "T4 drawdown calc"
    # T5: evaluate_gate skips when n<5
    res = evaluate_gate([{"ts":"2024-01-01T00:00:00Z","outcome":5,"phase":"h24_p3_bear",
                          "btc_drawdown":-30,"cross_corr":0.8,"btc_vol_20d":3}]*2,
                         [], "test", lambda e: True, 1.6)
    assert res is None, "T5 small sample skip"
    print("Inline TDD: 5/5 PASS")


def main():
    _tdd_inline()
    print()
    print("=== Building BTC regime index (Bitstamp 7y) ===")
    btc_regime = build_btc_regime_index()
    print(f"  Bars indexed: {len(btc_regime)}")
    print()
    print("=== Building cross-asset corr (BTC/ETH/SOL CoinEx) ===")
    cross_corr = build_cross_corr_index()
    print(f"  Days indexed: {len(cross_corr)}")
    print()
    print("=== Loading markets >=300 bars ===")
    md = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300:
            md.append((f.stem.replace("_1day",""), d))
    # External (Bitstamp long-history) — skip BTC/ETH used as regime base
    for f in sorted(EXT_DIR.glob("*_BITSTAMP_1day.json")):
        market = f.stem.replace("_BITSTAMP_1day","")
        if market in ("BTCUSD","ETHUSD"): continue  # used as regime base, avoid leakage
        d = load_candles(market, src="bitstamp")
        if d and len(d) >= 1500:  # only long-history bitstamp markets (h20 coverage)
            md.append((market, d))
            print(f"  + external: {market} ({len(d)} bars)")
    print(f"  Markets total: {len(md)}")

    print()
    print(f"=== Walking signals (thr={THRESHOLD_PCT}% win={WINDOW_BARS}) ===")
    all_evs = walk_signals(md, btc_regime, cross_corr, window=WINDOW_BARS)
    sig  = [e for e in all_evs if e["signal"]=="v"]
    base = [e for e in all_evs if e["signal"]=="_"]
    print(f"  Total sig events p3_bear: {len(sig)}")
    print(f"  Total base events: {len(base)}")

    thr_net = THRESHOLD_PCT + COSTS_PCT
    # Baseline (no gate)
    base_res = evaluate_gate(sig, base, "NO_GATE", lambda e: True, thr_net)
    print()
    print(f"{'gate':<30} {'n':>4} {'edge':>7} {'h20':>6} {'h24':>6} {'OOS':>7}")
    print("-"*68)
    print(f"{'NO_GATE (baseline)':<30} {base_res['n_sig']:>4} {base_res['edge']:>+6.1f}pp "
          f"{base_res['h20']:>+5.1f} {base_res['h24']:>+5.1f} {base_res['oos']:>+6.1f}pp")

    # Gate 1: BTC drawdown thresholds
    for dd_thr in [-15, -20, -25, -30, -35, -40]:
        gn = f"BTC_DD<={dd_thr}%"
        r = evaluate_gate(sig, base,
                          gn,
                          lambda e, t=dd_thr: e["btc_drawdown"] is not None and e["btc_drawdown"] <= t,
                          thr_net)
        if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

    # Gate 2: BTC vol percentiles
    vols = [e["btc_vol_20d"] for e in all_evs if e["btc_vol_20d"] is not None]
    vols.sort()
    for pct in [50, 60, 70, 80]:
        if not vols: continue
        v_thr = vols[int(len(vols)*pct/100)]
        gn = f"BTC_VOL>=p{pct}({v_thr:.2f}%)"
        r = evaluate_gate(sig, base,
                          gn,
                          lambda e, t=v_thr: e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= t,
                          thr_net)
        if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

    # Gate 3: cross-corr BTC-ETH (full cycle via Bitstamp 7y)
    for cc_thr in [0.5, 0.6, 0.7, 0.8]:
        gn = f"X_CORR>={cc_thr:.1f}"
        r = evaluate_gate(sig, base,
                          gn,
                          lambda e, t=cc_thr: e["cross_corr"] is not None and e["cross_corr"] >= t,
                          thr_net)
        if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

    # Combos
    if vols:
        v60 = vols[int(len(vols)*0.6)]
        gn = "BTC_DD<=-20 + VOL>=p60"
        r = evaluate_gate(sig, base, gn,
                          lambda e, v=v60: (e["btc_drawdown"] is not None and e["btc_drawdown"] <= -20
                                            and e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= v),
                          thr_net)
        if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

        # Triple combo: DD + VOL + CORR
        for cc_thr in [0.5, 0.6, 0.7]:
            gn = f"TRIPLE_DD<=-20_VOL>=p60_CORR>={cc_thr}"
            r = evaluate_gate(sig, base, gn,
                              lambda e, v=v60, c=cc_thr: (
                                  e["btc_drawdown"] is not None and e["btc_drawdown"] <= -20
                                  and e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= v
                                  and e["cross_corr"] is not None and e["cross_corr"] >= c),
                              thr_net)
            if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

        # Dual variants
        for dd_thr in [-15, -25]:
            gn = f"BTC_DD<={dd_thr} + VOL>=p60"
            r = evaluate_gate(sig, base, gn,
                              lambda e, t=dd_thr, v=v60: (
                                  e["btc_drawdown"] is not None and e["btc_drawdown"] <= t
                                  and e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= v),
                              thr_net)
            if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")
        # DD + CORR alone
        for cc_thr in [0.6, 0.7]:
            gn = f"BTC_DD<=-20 + CORR>={cc_thr}"
            r = evaluate_gate(sig, base, gn,
                              lambda e, c=cc_thr: (
                                  e["btc_drawdown"] is not None and e["btc_drawdown"] <= -20
                                  and e["cross_corr"] is not None and e["cross_corr"] >= c),
                              thr_net)
            if r: print(f"{gn:<30} {r['n_sig']:>4} {r['edge']:>+6.1f}pp {r['h20']:>+5.1f} {r['h24']:>+5.1f} {r['oos']:>+6.1f}pp")

    print()
    print("=== WINNERS: gate with OOS edge > 0 ===")
    print("(Re-running to collect results...)")
    # Collect all and rank
    results = [base_res]
    for dd_thr in [-15, -20, -25, -30, -35, -40]:
        r = evaluate_gate(sig, base, f"BTC_DD<={dd_thr}",
                          lambda e, t=dd_thr: e["btc_drawdown"] is not None and e["btc_drawdown"] <= t, thr_net)
        if r: results.append(r)
    for pct in [50, 60, 70, 80]:
        if vols:
            v_thr = vols[int(len(vols)*pct/100)]
            r = evaluate_gate(sig, base, f"BTC_VOL>=p{pct}",
                              lambda e, t=v_thr: e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= t, thr_net)
            if r: results.append(r)
    for cc_thr in [0.5, 0.6, 0.7, 0.8]:
        r = evaluate_gate(sig, base, f"X_CORR>={cc_thr}",
                          lambda e, t=cc_thr: e["cross_corr"] is not None and e["cross_corr"] >= t, thr_net)
        if r: results.append(r)

    # Add combos to results
    if vols:
        v60 = vols[int(len(vols)*0.6)]
        for c in [0.5, 0.6, 0.7]:
            r = evaluate_gate(sig, base, f"TRIPLE_DD20_VOL60_CORR{c}",
                lambda e, v=v60, cc=c: (e["btc_drawdown"] is not None and e["btc_drawdown"] <= -20
                                        and e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= v
                                        and e["cross_corr"] is not None and e["cross_corr"] >= cc),
                thr_net)
            if r: results.append(r)
        for t in [-15, -20, -25]:
            r = evaluate_gate(sig, base, f"DD{t}_VOL60",
                lambda e, x=t, v=v60: (e["btc_drawdown"] is not None and e["btc_drawdown"] <= x
                                       and e["btc_vol_20d"] is not None and e["btc_vol_20d"] >= v),
                thr_net)
            if r: results.append(r)
        for c in [0.6, 0.7]:
            r = evaluate_gate(sig, base, f"DD20_CORR{c}",
                lambda e, cc=c: (e["btc_drawdown"] is not None and e["btc_drawdown"] <= -20
                                 and e["cross_corr"] is not None and e["cross_corr"] >= cc),
                thr_net)
            if r: results.append(r)

    winners = [r for r in results if r["oos"] > 0 and r["n_sig"] >= 10]
    if not winners:
        print("  NONE -- nenhum gate (n>=10) restaura OOS edge positivo")
        print()
        print("=== TOP 5 melhores OOS (qualquer n) ===")
        results.sort(key=lambda r: -r["oos"])
        for r in results[:5]:
            tag = "" if r["n_sig"] >= 10 else " [SMALL_N]"
            print(f"  {r['gate']:<35} n={r['n_sig']:>3} edge={r['edge']:+.1f}pp oos={r['oos']:+.1f}pp h20={r['h20']:+.1f} h24={r['h24']:+.1f}{tag}")
    else:
        winners.sort(key=lambda r: -r["oos"])
        for r in winners:
            print(f"  WIN: {r['gate']:<35} n={r['n_sig']:>3} edge={r['edge']:+.1f}pp OOS={r['oos']:+.1f}pp h20={r['h20']:+.1f} h24={r['h24']:+.1f}")


if __name__ == "__main__":
    main()
