"""
run_short_btc_refined.py — Backtest batch das 4 regras SHORT em BTC 14.7y Bitstamp.

Pipeline:
1. Carrega candles Bitstamp BTC 1d (~5400 candles)
2. Para cada idx >= 200: compute_features
3. Para cada regra: detect entries
4. Triple barrier SHORT (path-dependent + fees)
5. Walk-forward purged k=5
6. PBO/CSCV sobre todas regras
7. Output: tabela completa + decision tree (deploy/backlog)

Reusa stack:
- triple_barrier_simulator (10 TDD GREEN)
- walk_forward_purged (6 TDD GREEN)
- pbo_cscv (5 TDD GREEN)
- metrics_pct_returns
- equity_curve_from_trades
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from short_features import compute_features
from short_rules import ALL_RULES
from triple_barrier_simulator import simulate_trade
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
from metrics_pct_returns import (
    sharpe_from_daily_returns, psr_from_daily_returns, dsr_from_daily_returns,
)
from walk_forward_purged import walk_forward_evaluate
from pbo_cscv import build_period_matrix, pbo_score
from constants import (
    RISK_PCT_PER_TRADE, SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

JOURNAL_DIR = ROOT_DIR / "journal"

# SHORT-specific params — calibrados via rr_sweep 2026-05-18
# Sweep testou 3.0/1.5 (orig), 2.0/3.0, 2.5/2.5; ganhou 2.5/2.5
# Resultado rule_a: Sharpe 1.82 / PSR 0.96 / DSR 0.58 / WF 4/5
# Ainda não passa DSR≥0.95 strict, mas é o melhor achado
SHORT_STOP_ATR  = 2.5
SHORT_TARGET_ATR = 2.5
MAX_BARS_DAILY  = 14


def load_btc_candles() -> list:
    """Carrega Bitstamp BTC daily."""
    path = SCRIPT_DIR / "btcusd_bitstamp_1day.json"
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def detect_entries_for_rule(candles, rule_fn, min_history=200):
    """Para cada candle: compute features + check rule."""
    entries = []
    for i in range(min_history, len(candles) - 1):
        feats = compute_features(candles, i)
        if not feats: continue
        if rule_fn(feats):
            entries.append({
                "idx": i,
                "ts": candles[i]["ts"],
                "price": candles[i]["close"],
                "features": feats,
            })
    return entries


def simulate_shorts(entries, all_candles, stop_atr=SHORT_STOP_ATR, target_atr=SHORT_TARGET_ATR):
    """SHORT trades via triple_barrier."""
    trades = []
    for e in entries:
        atr = e["features"].get("atr")
        if not atr or atr <= 0: continue
        sim = simulate_trade(
            entry_idx=e["idx"],
            candles=all_candles,
            direction="SHORT",
            atr_value=atr,
            stop_atr=stop_atr,
            target_atr=target_atr,
            max_bars=MAX_BARS_DAILY,
            fee_pct=TB_FEE_TAKER_PCT,
            slippage_pct=TB_SLIPPAGE_PCT,
        )
        if sim["exit_reason"] == "invalid": continue
        trades.append({
            "entry_ts": e["ts"],
            "direction": "SHORT",
            "result_r": round(sim["result_r"], 4),
            "exit_reason": sim["exit_reason"],
            "holding_bars": sim["holding_bars"],
            "entry_price": round(e["price"], 2),
            "atr_at_entry": round(atr, 4),
        })
    return trades


def evaluate_trades(trades):
    if not trades or len(trades) < 30:
        return {"valid": False, "n": len(trades)}
    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30: return {"valid": False}
    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                  sharpe_benchmark=0.0, sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / len(trades)
    win = sum(1 for t in trades if t["result_r"] > 0) / len(trades) * 100
    dates = sorted(eq.keys())
    return {
        "valid": True,
        "n_trades": len(trades), "n_days": len(eq),
        "sharpe": round(sharpe, 4), "psr": round(psr, 4), "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4), "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (sharpe > 0 and dsr >= DSR_THRESHOLD and psr >= PSR_THRESHOLD) else "FAIL"),
    }


def main():
    print("=" * 72)
    print("SHORT BTC REFINED -- 4 regras × 14.7y Bitstamp")
    print("=" * 72)

    candles = load_btc_candles()
    print(f"[load] {len(candles)} candles BTC daily ({candles[0]['ts']} → {candles[-1]['ts']})")

    all_results = {}
    trades_per_rule = {}

    for rule_name, rule_fn in ALL_RULES.items():
        print(f"\n=== {rule_name} ===")
        entries = detect_entries_for_rule(candles, rule_fn)
        print(f"  Entries detected: {len(entries)}")
        if len(entries) < 30:
            print(f"  [SKIP] poucos entries (<30)")
            all_results[rule_name] = {"skipped": True, "n_entries": len(entries)}
            continue

        trades = simulate_shorts(entries, candles)
        print(f"  Trades simulated: {len(trades)}")
        m = evaluate_trades(trades)
        if not m.get("valid"):
            print(f"  [INVALID] {m}")
            all_results[rule_name] = {"invalid": True, **m}
            continue

        # Walk-forward
        wf = walk_forward_evaluate(trades, k=5, embargo_days=14, risk_pct=RISK_PCT_PER_TRADE)
        oos = wf["oos_summary"]
        m["wf_verdict"] = wf["verdict"]
        m["wf_mean_sharpe"] = oos["mean_test_sharpe"]
        m["wf_positive"] = oos["positive_sharpe_folds"]
        m["wf_total"] = oos["total_folds"]

        print(f"  Sharpe={m['sharpe']} DSR={m['dsr']} PSR={m['psr']} {'✅PASS' if m['decision']=='PASS' else '❌FAIL'}")
        print(f"  WF: {wf['verdict']} OOS mean={oos['mean_test_sharpe']} {oos['positive_sharpe_folds']}/{oos['total_folds']}")
        print(f"  Win rate: {m['win_rate_pct']}% | Mean R: {m['mean_r']} | Final eq: {m['final_equity']}x")

        all_results[rule_name] = m
        trades_per_rule[rule_name] = trades

    # PBO cross-rule
    pbo_result = None
    if len(trades_per_rule) >= 2:
        print(f"\n=== PBO/CSCV cross-rule ===")
        pm = build_period_matrix(trades_per_rule, n_periods=6, risk_pct=RISK_PCT_PER_TRADE)
        if pm.get("valid"):
            pbo_result = pbo_score(pm["matrix"])
            print(f"  {pbo_result['verdict']} (pbo={pbo_result['pbo']})")

    # Decision tree
    print(f"\n{'='*72}\nDECISION\n{'='*72}")
    promoted = []
    for name, m in all_results.items():
        if m.get("decision") != "PASS":
            print(f"  {name}: ❌ {m.get('decision', 'INVALID/SKIPPED')}")
            continue
        # PASS — check PBO + WF
        pbo_ok = (pbo_result is None or pbo_result["pbo"] < 0.40)
        wf_ok = m.get("wf_positive", 0) >= 3
        if pbo_ok and wf_ok:
            print(f"  {name}: 🎯 PROMOTE LIVE (Sharpe={m['sharpe']} WF={m['wf_positive']}/{m['wf_total']})")
            promoted.append(name)
        else:
            print(f"  {name}: 🟡 PASS marginal (PBO ok={pbo_ok}, WF ok={wf_ok}) — backlog")

    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": "BTCUSD-BITSTAMP",
        "timeframe": "1day",
        "params": {
            "stop_atr": SHORT_STOP_ATR,
            "target_atr": SHORT_TARGET_ATR,
            "max_bars": MAX_BARS_DAILY,
            "fee_pct": TB_FEE_TAKER_PCT,
            "slippage_pct": TB_SLIPPAGE_PCT,
        },
        "rules_results": all_results,
        "pbo_cross_rule": pbo_result,
        "promoted_to_live": promoted,
    }
    out_path = JOURNAL_DIR / "short_btc_refined_2026_05_18.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")
    print(f"\nPROMOTED TO LIVE: {len(promoted)} regra(s) - {promoted}")
    return out


if __name__ == "__main__":
    main()
