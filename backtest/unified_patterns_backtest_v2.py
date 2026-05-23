"""unified_patterns_backtest_v2.py -- Backtest RIGOROSO aplicando 7 sub-gates.

v1 (unified_patterns_backtest.py) media edge bruto sem custos, sem phase split,
sem walk-forward, sem Bonferroni. Resultado +8.6pp vol_climax podia ser
otimista 3-6pp.

v2 aplica gates 3.1-3.7 do protocolo pericia v2:
  3.1. Edge bruto >= +5pp
  3.2. Edge NET (apos custos 0.6% round-trip)
  3.3. Bonferroni-adjusted (N hipoteses testadas)
  3.4. Per-phase split (halving phases)
  3.5. Walk-forward expanding window
  3.6. N >= 30 por phase testada
  3.7. Outcome sensitivity grid (threshold x window)

Pure functions + asserts inline (TDD-driven). Roda offline em ~5min.
"""
from __future__ import annotations
import json, math, sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDLES_DIR = ROOT / "journal" / "candles_coinex"

# ═══════════════ Constants ═════════════════════════════════════════════════
LOOKBACK = 60
COSTS_ROUND_TRIP_PCT = 0.6   # 0.20% taker + 0.20% taker + 0.20% slippage
N_HYPOTHESES_TESTED = 10     # Tori_long, Tori_short, vol_climax_long, vol_climax_short, candle_long, candle_short, rsi_div_long, rsi_div_short, confluence_2+, confluence_3+

# Halving phases (BTC anchor)
HALVING_2024 = datetime(2024, 4, 19, tzinfo=timezone.utc)
PHASE_BOUNDARIES = {
    "phase_1_bull":     (HALVING_2024, HALVING_2024.replace(year=2024).replace(month=10).replace(day=19)),     # mes 0-6
    "phase_2_top":      (HALVING_2024.replace(year=2024).replace(month=10).replace(day=19), HALVING_2024.replace(year=2025).replace(month=4).replace(day=19)),  # mes 6-12
    "phase_3_bear":     (HALVING_2024.replace(year=2025).replace(month=4).replace(day=19), HALVING_2024.replace(year=2026).replace(month=10).replace(day=19)),  # mes 12-30
    "phase_4_recovery": (HALVING_2024.replace(year=2026).replace(month=10).replace(day=19), HALVING_2024.replace(year=2028).replace(month=4).replace(day=19)),  # mes 30+
}


# ═══════════════ TDD-style asserts (mini-tests inline) ═════════════════════

def assign_phase(ts_iso: str):
    """Retorna phase name dada timestamp ISO."""
    try:
        dt = datetime.fromisoformat(ts_iso.replace("Z", "+00:00"))
    except Exception:
        return "unknown"
    for name, (start, end) in PHASE_BOUNDARIES.items():
        if start <= dt < end:
            return name
    if dt < HALVING_2024:
        return "pre_halving_2024"
    return "future"


# Inline test
assert assign_phase("2024-05-01T00:00:00Z") == "phase_1_bull", "May 2024 should be phase_1_bull"
assert assign_phase("2025-01-01T00:00:00Z") == "phase_2_top", "Jan 2025 should be phase_2_top"
assert assign_phase("2025-06-01T00:00:00Z") == "phase_3_bear", "Jun 2025 should be phase_3_bear"
assert assign_phase("2023-01-01T00:00:00Z") == "pre_halving_2024", "2023 should be pre_halving"


def edge_net_pct(edge_gross_pct: float, outcome_threshold_pct: float, costs_pct: float = COSTS_ROUND_TRIP_PCT):
    """Calcula edge NET descontando custos do outcome threshold.

    Logic: se outcome bruto era +3% pra "hit", custos 0.6% comem 20% do outcome.
    Edge net efetivo = edge_gross * (1 - costs/outcome).
    """
    if outcome_threshold_pct <= 0:
        return 0.0
    cost_ratio = costs_pct / outcome_threshold_pct
    return edge_gross_pct * max(0.0, 1.0 - cost_ratio)


# Inline tests
assert abs(edge_net_pct(8.6, 3.0, 0.6) - 6.88) < 0.01, "edge NET 8.6*0.8 = 6.88"
assert edge_net_pct(8.6, 0.5, 0.6) == 0, "outcome menor que custos = 0 edge"


def bonferroni_gate(base_gate: float, n_hypotheses: int):
    """Retorna gate ajustado por Bonferroni-like ln(N) factor."""
    if n_hypotheses <= 1:
        return base_gate
    return base_gate * math.log(n_hypotheses)


# Inline test
assert abs(bonferroni_gate(5.0, 10) - 11.51) < 0.1, "5pp * ln(10) = 11.51pp"
assert abs(bonferroni_gate(5.0, 2) - 3.47) < 0.1, "5pp * ln(2) = 3.47pp (smaller!)"


# ═══════════════ Math helpers (reused from v1) ═════════════════════════════

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
                "ts": c.get("ts"),
                "open": float(c["open"]), "high": float(c["high"]),
                "low": float(c["low"]), "close": float(c["close"]),
                "volume": float(c.get("volume", 0)),
            })
        except: pass
    return out


def backtest_walker(market, candles, outcome_threshold_pct=3.0, outcome_bars=5):
    """Walks bar-by-bar coletando events com phase + outcome.

    Returns: list dicts {ts, phase, signal, hit_gross, hit_net, outcome_pct}
    """
    if len(candles) < LOOKBACK + outcome_bars + 30: return []
    events = []
    end = len(candles) - outcome_bars
    for i in range(LOOKBACK, end):
        window = candles[i-LOOKBACK:i+1]
        highs   = [c["high"]   for c in window]
        lows    = [c["low"]    for c in window]
        closes  = [c["close"]  for c in window]
        volumes = [c["volume"] for c in window]
        bar_ts  = candles[i].get("ts", "")
        phase = assign_phase(str(bar_ts))

        outcome = candles[i+1:i+1+outcome_bars]
        if not outcome: continue
        entry = candles[i]["close"]
        max_close = max(c["close"] for c in outcome)
        min_close = min(c["close"] for c in outcome)
        long_move  = (max_close - entry) / entry * 100
        short_move = (entry - min_close) / entry * 100

        signals_long = []; signals_short = []
        if detect_volume_climax(closes, highs, lows, volumes, "LONG"):   signals_long.append("vol_climax")
        if detect_volume_climax(closes, highs, lows, volumes, "SHORT"):  signals_short.append("vol_climax")

        # Gross hit: outcome bruto >= threshold
        # Net hit: outcome - custos >= threshold (precisa mover +threshold+costs em bruto)
        net_threshold = outcome_threshold_pct + COSTS_ROUND_TRIP_PCT
        for sig in signals_long:
            events.append({
                "ts": bar_ts, "phase": phase, "side": "LONG", "signal": sig,
                "hit_gross": long_move >= outcome_threshold_pct,
                "hit_net":   long_move >= net_threshold,
                "outcome_pct": long_move,
            })
        for sig in signals_short:
            events.append({
                "ts": bar_ts, "phase": phase, "side": "SHORT", "signal": sig,
                "hit_gross": short_move >= outcome_threshold_pct,
                "hit_net":   short_move >= net_threshold,
                "outcome_pct": short_move,
            })

        # Baseline (todas as barras)
        events.append({"ts": bar_ts, "phase": phase, "side": "LONG", "signal": "_BASELINE",
                       "hit_gross": long_move >= outcome_threshold_pct,
                       "hit_net":   long_move >= net_threshold,
                       "outcome_pct": long_move})
        events.append({"ts": bar_ts, "phase": phase, "side": "SHORT", "signal": "_BASELINE",
                       "hit_gross": short_move >= outcome_threshold_pct,
                       "hit_net":   short_move >= net_threshold,
                       "outcome_pct": short_move})

    return events


def compute_stats(events, use_net=False):
    """Returns dict por (side, signal): n, hits, rate%."""
    out = defaultdict(lambda: {"n":0, "hits":0})
    key_hit = "hit_net" if use_net else "hit_gross"
    for e in events:
        k = (e["side"], e["signal"])
        out[k]["n"] += 1
        if e[key_hit]: out[k]["hits"] += 1
    stats = {}
    for k, v in out.items():
        if v["n"] == 0: continue
        stats[k] = {"n": v["n"], "hits": v["hits"], "rate": v["hits"] / v["n"] * 100}
    return stats


def walk_forward_split(events, n_folds=4):
    """Expanding window: fold 0 = train [0..25%], test [25..50%]; fold 1 = train [0..50%], test [50..75%]; etc.
    Retorna lista de (train_events, test_events) tuples.
    """
    events_sorted = sorted([e for e in events if e.get("ts")], key=lambda e: e["ts"])
    n = len(events_sorted)
    if n < 100: return []
    folds = []
    for f in range(n_folds):
        train_end = int(n * (0.25 + f * 0.25 * 0.5))   # 25%, 37%, 50%, 62%
        test_start = train_end
        test_end = min(int(test_start + n * 0.20), n)  # 20% test window
        if test_end <= test_start: continue
        folds.append((events_sorted[:train_end], events_sorted[test_start:test_end]))
    return folds


def out_of_sample_split(events, holdout_pct=0.20):
    """Separa últimos holdout_pct% como out-of-sample puro."""
    events_sorted = sorted([e for e in events if e.get("ts")], key=lambda e: e["ts"])
    n = len(events_sorted)
    split = int(n * (1 - holdout_pct))
    return events_sorted[:split], events_sorted[split:]


# ═══════════════ Main analysis ═════════════════════════════════════════════

def report_for_side_signal(events, side, signal, label, n_hyp=N_HYPOTHESES_TESTED, outcome_pct=3.0):
    """Reporta 7 sub-gates pra (side, signal)."""
    # Filter
    sig_events  = [e for e in events if e["side"] == side and e["signal"] == signal]
    base_events = [e for e in events if e["side"] == side and e["signal"] == "_BASELINE"]
    if not sig_events:
        print(f"  {label}: N=0 events")
        return

    n = len(sig_events)
    hit_gross = sum(1 for e in sig_events if e["hit_gross"])
    hit_net   = sum(1 for e in sig_events if e["hit_net"])
    rate_gross = hit_gross / n * 100
    rate_net   = hit_net   / n * 100
    n_base = len(base_events)
    base_gross = sum(1 for e in base_events if e["hit_gross"]) / max(n_base, 1) * 100
    base_net   = sum(1 for e in base_events if e["hit_net"])   / max(n_base, 1) * 100
    edge_gross = rate_gross - base_gross
    edge_net   = rate_net   - base_net
    bonf_gate  = bonferroni_gate(5.0, n_hyp)

    # Per-phase split
    phase_stats = defaultdict(lambda: {"n":0, "hits_g":0, "hits_n":0, "base_n":0, "base_hits_g":0, "base_hits_n":0})
    for e in sig_events:
        ps = phase_stats[e["phase"]]
        ps["n"] += 1
        if e["hit_gross"]: ps["hits_g"] += 1
        if e["hit_net"]:   ps["hits_n"] += 1
    for e in base_events:
        ps = phase_stats[e["phase"]]
        ps["base_n"] += 1
        if e["hit_gross"]: ps["base_hits_g"] += 1
        if e["hit_net"]:   ps["base_hits_n"] += 1

    print(f"\n  {label}")
    print(f"    n={n}  baseline_n={n_base}")
    print(f"    hit_rate_gross={rate_gross:.1f}% vs base {base_gross:.1f}% = edge_gross {edge_gross:+.1f}pp")
    print(f"    hit_rate_net  ={rate_net:.1f}% vs base {base_net:.1f}% = edge_net   {edge_net:+.1f}pp  (custos {COSTS_ROUND_TRIP_PCT}%)")
    print(f"    Bonferroni gate (N={n_hyp} hyp): {bonf_gate:.2f}pp")
    print(f"    Per-phase split:")
    for ph, ps in sorted(phase_stats.items()):
        if ps["n"] == 0: continue
        rg = ps["hits_g"] / ps["n"] * 100
        rn = ps["hits_n"] / ps["n"] * 100
        bg = ps["base_hits_g"] / max(ps["base_n"], 1) * 100
        bn = ps["base_hits_n"] / max(ps["base_n"], 1) * 100
        eg = rg - bg; en = rn - bn
        print(f"      {ph:<22} n={ps['n']:>3} edge_gross={eg:+5.1f}pp edge_net={en:+5.1f}pp  baseline {bg:.1f}%/{bn:.1f}%")

    # 7 sub-gates check
    print(f"    GATES CHECK:")
    g_3_1 = edge_gross >= 5.0 and n >= 30
    g_3_2 = edge_net >= 5.0
    g_3_3 = edge_gross >= bonf_gate

    # 3.4 per-phase: edge gross >= +3pp em pelo menos 2 phases
    phases_with_edge = sum(1 for ph, ps in phase_stats.items()
                          if ps["n"] >= 20 and ((ps["hits_g"]/ps["n"]*100) - (ps["base_hits_g"]/max(ps["base_n"],1)*100)) >= 3.0)
    g_3_4 = phases_with_edge >= 2

    # 3.6 N >= 30 por phase
    phases_with_n = sum(1 for ph, ps in phase_stats.items() if ps["n"] >= 30)
    g_3_6 = phases_with_n >= 2

    print(f"      3.1 edge bruto >=+5pp & n>=30:  {'✓' if g_3_1 else '✗'}  ({edge_gross:+.1f}pp, n={n})")
    print(f"      3.2 edge NET   >=+5pp:           {'✓' if g_3_2 else '✗'}  ({edge_net:+.1f}pp)")
    print(f"      3.3 Bonferroni adjusted:         {'✓' if g_3_3 else '✗'}  ({edge_gross:+.1f}pp vs gate {bonf_gate:.1f}pp)")
    print(f"      3.4 per-phase >=+3pp in 2+ ph:   {'✓' if g_3_4 else '✗'}  ({phases_with_edge} phases qualified)")
    print(f"      3.6 n>=30 in 2+ phases:          {'✓' if g_3_6 else '✗'}  ({phases_with_n} phases qualified)")


def walk_forward_check(events, side, signal):
    folds = walk_forward_split(events)
    if not folds:
        print(f"      3.5 walk-forward: SKIP (n<100)")
        return
    print(f"      3.5 walk-forward ({len(folds)} folds):")
    for i, (train, test) in enumerate(folds):
        for label, fold_events in [("train", train), ("test", test)]:
            sig_e = [e for e in fold_events if e["side"] == side and e["signal"] == signal]
            base_e = [e for e in fold_events if e["side"] == side and e["signal"] == "_BASELINE"]
            if not sig_e or not base_e: continue
            r = sum(1 for e in sig_e if e["hit_gross"]) / len(sig_e) * 100
            br = sum(1 for e in base_e if e["hit_gross"]) / len(base_e) * 100
            edge = r - br
            print(f"        fold {i} {label}: n={len(sig_e):>3} edge_gross={edge:+5.1f}pp")


def out_of_sample_check(events, side, signal):
    train, holdout = out_of_sample_split(events, 0.20)
    sig_t = [e for e in train   if e["side"] == side and e["signal"] == signal]
    sig_h = [e for e in holdout if e["side"] == side and e["signal"] == signal]
    base_t = [e for e in train   if e["side"] == side and e["signal"] == "_BASELINE"]
    base_h = [e for e in holdout if e["side"] == side and e["signal"] == "_BASELINE"]
    if not sig_t or not sig_h or not base_t or not base_h:
        print(f"      OOS: SKIP (insuficient sample)")
        return
    edge_t = sum(1 for e in sig_t if e["hit_gross"])/len(sig_t)*100 - sum(1 for e in base_t if e["hit_gross"])/len(base_t)*100
    edge_h = sum(1 for e in sig_h if e["hit_gross"])/len(sig_h)*100 - sum(1 for e in base_h if e["hit_gross"])/len(base_h)*100
    ratio = edge_h / edge_t * 100 if edge_t != 0 else 0
    print(f"      OOS (last 20% holdout):  train_edge={edge_t:+.1f}pp  test_edge={edge_h:+.1f}pp  persistence={ratio:.0f}%")


def outcome_sensitivity_check(events, side, signal):
    """3.7. Testar threshold 2/3/5% x window 3/5/10d -- aqui simplificado pra threshold only
    pois window foi fixado outcome_bars=5 no walker. Reportar gross edge variando threshold."""
    print(f"      3.7 outcome sensitivity (threshold variation):")
    sig_e = [e for e in events if e["side"] == side and e["signal"] == signal]
    base_e = [e for e in events if e["side"] == side and e["signal"] == "_BASELINE"]
    if not sig_e: print("        SKIP no events"); return
    for thresh in [2.0, 3.0, 5.0]:
        hits = sum(1 for e in sig_e if e["outcome_pct"] >= thresh)
        rate = hits / len(sig_e) * 100
        bhits = sum(1 for e in base_e if e["outcome_pct"] >= thresh)
        brate = bhits / max(len(base_e),1) * 100
        edge = rate - brate
        print(f"        threshold +{thresh}%:  edge={edge:+5.1f}pp  (sig={rate:.1f}%, base={brate:.1f}%)")


def main():
    print(f"=== Unified Patterns Backtest v2 (gates 3.1-3.7) ===")
    print(f"Lookback={LOOKBACK}d outcome=5d Costs={COSTS_ROUND_TRIP_PCT}% N_hyp={N_HYPOTHESES_TESTED}\n")

    candle_files = sorted(CANDLES_DIR.glob("*_1day.json"))
    all_events = []
    n_markets = 0
    for f in candle_files:
        mkt = f.stem.replace("_1day", "")
        candles = load_candles(mkt)
        if not candles: continue
        evs = backtest_walker(mkt, candles)
        if evs:
            for e in evs: e["market"] = mkt
            all_events.extend(evs)
            n_markets += 1
    print(f"Markets processed: {n_markets}\nTotal events: {len(all_events)}\n")

    # Focus on the signal that passed gate 3.1 in v1
    print("─" * 80)
    print("VOL_CLIMAX LONG (passou gate 3.1 em v1 com +8.6pp bruto):")
    report_for_side_signal(all_events, "LONG", "vol_climax", "vol_climax LONG")
    walk_forward_check(all_events, "LONG", "vol_climax")
    out_of_sample_check(all_events, "LONG", "vol_climax")
    outcome_sensitivity_check(all_events, "LONG", "vol_climax")

    print("\n" + "─" * 80)
    print("VOL_CLIMAX SHORT (controle):")
    report_for_side_signal(all_events, "SHORT", "vol_climax", "vol_climax SHORT")

    print("\n" + "=" * 80)
    print("VEREDICTO FINAL gates 3.1-3.7 para vol_climax LONG:")
    print("  Cron continua rodando (zero risco capital)")
    print("  Decisao ativacao trade: depende de quantos gates passaram acima")


if __name__ == "__main__":
    print("Inline asserts: PASS")
    sys.exit(main())
