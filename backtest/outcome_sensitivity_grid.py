"""outcome_sensitivity_grid.py -- Design 1 A/B test.

Mesma predicate refinada (mult=2.5 + RSI<30 + close_rej=0.3).
Varia outcome: threshold (1/2/3/4%) x window (3/5/7/10 bars) = 16 configs.

Para cada config mede:
  - n p3_bear (h20+h24 combined)
  - edge_net = hit_rate(signal) - hit_rate(baseline) considerando custos
  - cross-cycle: edge_h20 vs edge_h24 (gap pequeno = STABLE)
  - OOS holdout (last 20% sig events) edge
  - Bonferroni gate: +2*sqrt(p*(1-p)/n_sig) com z ajustado pra 16 hipoteses

Output: tabela ranked + recommendation.
"""
from __future__ import annotations
import json, sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from math import sqrt, log

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

LOOKBACK = 60
COSTS_PCT = 0.6
MULT = 2.5
PRED_THRESHOLD = 3.0  # used in predicate (close_above check)
CLOSE_REJ = 0.3
RSI_CONF = 30.0

HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
HALVING_2020 = datetime(2020, 5, 11, tzinfo=timezone.utc)

# Grid axes
THRESHOLDS = [1.0, 2.0, 3.0, 4.0]      # outcome target % (gross, before costs)
WINDOWS    = [3, 5, 7, 10]              # outcome bars


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


def load_candles(market):
    f = CANDLES_DIR / f"{market}_1day.json"
    if not f.exists(): return []
    try:
        d = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(d, list) and d and isinstance(d[0], dict): return d
    except: pass
    return []


def walk_capture_outcomes(candles, market, max_window=10):
    """Walk once, capture outcomes for ALL windows simultaneously."""
    events = []
    if len(candles) < LOOKBACK + max_window + 30: return events
    end = len(candles) - max_window
    for i in range(LOOKBACK, end):
        win = candles[i-LOOKBACK:i+1]
        highs   = [c["high"]   for c in win]
        lows    = [c["low"]    for c in win]
        closes  = [c["close"]  for c in win]
        volumes = [c["volume"] for c in win]
        ts = candles[i].get("ts","")
        phase = assign_phase(str(ts))
        entry = candles[i]["close"]
        sig = refined_predicate(volumes, lows, highs, closes)
        outcomes = {}
        for w in WINDOWS:
            slc = candles[i+1:i+1+w]
            if len(slc) < w:
                outcomes[w] = None
            else:
                max_c = max(c["close"] for c in slc)
                outcomes[w] = (max_c - entry) / entry * 100
        events.append({"ts":ts, "phase":phase, "market":market,
                       "signal": "v" if sig else "_",
                       "outcomes": outcomes})
    return events


def hit_rate(events, window, threshold_net):
    n = sum(1 for e in events if e["outcomes"][window] is not None)
    if n == 0: return None, 0
    wins = sum(1 for e in events if e["outcomes"][window] is not None
               and e["outcomes"][window] >= threshold_net)
    return wins / n * 100, n


def main():
    target = []
    for f in sorted(CANDLES_DIR.glob("*_1day.json")):
        d = load_candles(f.stem.replace("_1day",""))
        if d and len(d) >= 300:
            target.append((f.stem.replace("_1day",""), d))

    all_e = []
    for m, c in target: all_e.extend(walk_capture_outcomes(c, m))

    p3 = [e for e in all_e if e["phase"] in ("h20_p3_bear","h24_p3_bear")]
    sig_all  = sorted([e for e in p3 if e["signal"]=="v"], key=lambda e: e["ts"])
    base_all = sorted([e for e in p3 if e["signal"]=="_"], key=lambda e: e["ts"])

    print(f"Universe: {len(target)} markets, p3_bear signals total: {len(sig_all)}")
    print()

    # Bonferroni: 16 configs, conf 95% -> z_adj = qnorm(1 - 0.05/16/2) ~ 2.74
    # gate threshold = z * sqrt(p*(1-p)/n)
    Z_BONF = 2.74  # ~95% conf adjusted Bonferroni 16 hyp
    print(f"Bonferroni z (16 hyp, 95% conf): {Z_BONF}")
    print()

    results = []
    for thr in THRESHOLDS:
        for w in WINDOWS:
            thr_net = thr + COSTS_PCT
            sig_valid = [e for e in sig_all if e["outcomes"][w] is not None]
            base_valid = [e for e in base_all if e["outcomes"][w] is not None]
            sig_rate, n_sig  = hit_rate(sig_valid, w, thr_net)
            base_rate, n_base = hit_rate(base_valid, w, thr_net)
            if sig_rate is None or base_rate is None or n_sig < 5: continue

            edge = sig_rate - base_rate
            # Bonferroni gate (one-tailed via 2-side z=2.74, conservative)
            p = sig_rate / 100.0
            se = sqrt(p*(1-p)/n_sig) * 100
            bonf_gate = Z_BONF * se

            # Cross-cycle h20 vs h24
            sv_h20 = [e for e in sig_valid if e["phase"]=="h20_p3_bear"]
            sv_h24 = [e for e in sig_valid if e["phase"]=="h24_p3_bear"]
            bv_h20 = [e for e in base_valid if e["phase"]=="h20_p3_bear"]
            bv_h24 = [e for e in base_valid if e["phase"]=="h24_p3_bear"]
            r_h20, n_h20 = hit_rate(sv_h20, w, thr_net)
            r_h24, n_h24 = hit_rate(sv_h24, w, thr_net)
            b_h20, _    = hit_rate(bv_h20, w, thr_net)
            b_h24, _    = hit_rate(bv_h24, w, thr_net)
            edge_h20 = (r_h20 - b_h20) if r_h20 and b_h20 else 0
            edge_h24 = (r_h24 - b_h24) if r_h24 and b_h24 else 0

            # OOS holdout (last 20% of sig events chronologically)
            split = int(len(sig_valid) * 0.80)
            if split < 1 or split >= len(sig_valid): continue
            tr = sig_valid[:split]; ho = sig_valid[split:]
            last_train_ts = tr[-1]["ts"]
            bh = [e for e in base_valid if e["ts"] > last_train_ts]
            ho_rate, _ = hit_rate(ho, w, thr_net)
            bh_rate, _ = hit_rate(bh, w, thr_net)
            edge_oos = (ho_rate - bh_rate) if ho_rate is not None and bh_rate is not None else 0

            results.append({
                "thr": thr, "thr_net": thr_net, "win": w,
                "n_sig": n_sig, "edge": edge, "bonf": bonf_gate,
                "passes_bonf": edge > bonf_gate,
                "edge_h20": edge_h20, "edge_h24": edge_h24,
                "stable": abs(edge_h20 - edge_h24) < 15,
                "edge_oos": edge_oos, "n_h20": n_h20, "n_h24": n_h24,
                "n_ho": len(ho)
            })

    results.sort(key=lambda r: -r["edge"])

    print(f"{'thr%':>5} {'win':>4} {'n':>4} {'edge':>7} {'bonf':>6} {'pass':>5} "
          f"{'h20':>6} {'h24':>6} {'stab':>5} {'oos':>7} {'n_h20':>6} {'n_h24':>6}")
    print("-"*92)
    for r in results:
        flag_b = "PASS" if r["passes_bonf"] else "fail"
        flag_s = "yes" if r["stable"] else "NO"
        print(f"{r['thr']:>5.1f} {r['win']:>4} {r['n_sig']:>4} "
              f"{r['edge']:>+6.1f}pp {r['bonf']:>5.1f} {flag_b:>5} "
              f"{r['edge_h20']:>+5.1f} {r['edge_h24']:>+5.1f} {flag_s:>5} "
              f"{r['edge_oos']:>+6.1f} {r['n_h20']:>6} {r['n_h24']:>6}")

    # Top candidates: Bonferroni PASS + stable + edge_oos > 0
    print()
    print("=== TOP CANDIDATES (Bonferroni PASS + cross-cycle stable + OOS edge>0) ===")
    top = [r for r in results if r["passes_bonf"] and r["stable"] and r["edge_oos"] > 0]
    if not top:
        print("  NONE -- nenhuma config sobrevive todos 3 filtros simultaneamente")
        print()
        print("=== TOP CANDIDATES (Bonferroni PASS + cross-cycle stable, OOS qualquer) ===")
        top = [r for r in results if r["passes_bonf"] and r["stable"]]
        if not top:
            print("  NONE -- nenhuma config passa Bonferroni + cross-cycle")
        else:
            for r in top[:5]:
                print(f"  thr={r['thr']:.1f}% win={r['win']} n={r['n_sig']} edge=+{r['edge']:.1f}pp "
                      f"(h20{r['edge_h20']:+.1f}/h24{r['edge_h24']:+.1f}) oos={r['edge_oos']:+.1f}pp")
    else:
        for r in top:
            print(f"  thr={r['thr']:.1f}% win={r['win']} n={r['n_sig']} edge=+{r['edge']:.1f}pp "
                  f"(h20{r['edge_h20']:+.1f}/h24{r['edge_h24']:+.1f}) oos={r['edge_oos']:+.1f}pp ")

def _tdd_inline():
    """Invariantes auto-validadas. Falha = abort antes de produzir resultados enganosos."""
    # T1: hit_rate basico
    fake = [{"outcomes":{5: 3.0}}, {"outcomes":{5: 1.0}}, {"outcomes":{5: 5.0}}]
    r, n = hit_rate(fake, 5, 2.5)
    assert n == 3 and abs(r - 200/3) < 1e-6, f"T1 fail: r={r} n={n}"
    # T2: outcomes None nao contam
    fake2 = [{"outcomes":{5: None}}, {"outcomes":{5: 5.0}}]
    r, n = hit_rate(fake2, 5, 2.0)
    assert n == 1 and abs(r - 100.0) < 1e-6, f"T2 fail: r={r} n={n}"
    # T3: walk_capture_outcomes captura window>=3 (needs LOOKBACK+max_window+30 = 100 bars)
    closes = [100.0]*120
    cs = [{"open":c,"high":c+1,"low":c-1,"close":c,"volume":100,"ts":f"2026-{((i//28)%12)+1:02d}-{(i%28)+1:02d}T00:00:00Z"} for i,c in enumerate(closes)]
    evs = walk_capture_outcomes(cs, "TESTUSDT")
    assert len(evs) > 0, "T3 fail: zero events"
    for e in evs:
        assert set(e["outcomes"].keys()) == set(WINDOWS), f"T3 fail: outcomes keys {e['outcomes'].keys()}"
    # T4: phase assignment
    assert assign_phase("2024-12-01T00:00:00+00:00") == "h24_p2_top", "T4 fail h24_p2"
    assert assign_phase("2025-06-01T00:00:00+00:00") == "h24_p3_bear", "T4 fail h24_p3 (2025-06 = month 13)"
    assert assign_phase("2021-08-01T00:00:00+00:00") == "h20_p3_bear", "T4 fail h20_p3"
    # T5: predicate determinismo
    import random
    random.seed(42)
    v = [random.uniform(1,5) for _ in range(30)]
    l = [random.uniform(95,100) for _ in range(30)]
    h = [random.uniform(101,105) for _ in range(30)]
    c = [random.uniform(96,104) for _ in range(30)]
    r1 = refined_predicate(v, l, h, c)
    r2 = refined_predicate(v, l, h, c)
    assert r1 == r2, "T5 fail: predicate not deterministic"
    print("Inline TDD: 5/5 PASS")


if __name__ == "__main__":
    _tdd_inline()
    main()
