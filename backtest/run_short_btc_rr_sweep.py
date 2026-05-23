"""
run_short_btc_rr_sweep.py — Sweep R:R em rule_a (única marginal).

Testa 2 configs:
  #1a stop=2.0×ATR / target=3.0×ATR (R:R 1:1.5 agressivo)
  #1b stop=2.5×ATR / target=2.5×ATR (R:R 1:1 conservador)

Mantém max_bars=14, fees, etc. Foco: ver se R:R melhor leva DSR/PSR pra cima.
"""
from __future__ import annotations
import json, sys
from pathlib import Path
SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from short_features import compute_features
from short_rules import rule_a_sma200_break
from triple_barrier_simulator import simulate_trade
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
from metrics_pct_returns import (
    sharpe_from_daily_returns, psr_from_daily_returns, dsr_from_daily_returns,
)
from walk_forward_purged import walk_forward_evaluate
from constants import (
    RISK_PCT_PER_TRADE, SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

MAX_BARS = 14
CONFIGS = [
    {"name": "baseline_3.0_1.5", "stop": 3.0, "target": 1.5},
    {"name": "#1a_2.0_3.0",       "stop": 2.0, "target": 3.0},
    {"name": "#1b_2.5_2.5",       "stop": 2.5, "target": 2.5},
]


def load():
    with open(SCRIPT_DIR / "btcusd_bitstamp_1day.json", "r", encoding="utf-8") as f:
        return json.load(f)


def detect(candles):
    entries = []
    for i in range(200, len(candles) - 1):
        feats = compute_features(candles, i)
        if not feats: continue
        if rule_a_sma200_break(feats):
            entries.append({"idx": i, "ts": candles[i]["ts"],
                            "price": candles[i]["close"], "features": feats})
    return entries


def simulate(entries, candles, stop, target):
    trades = []
    for e in entries:
        atr = e["features"].get("atr")
        if not atr or atr <= 0: continue
        sim = simulate_trade(
            entry_idx=e["idx"], candles=candles, direction="SHORT",
            atr_value=atr, stop_atr=stop, target_atr=target,
            max_bars=MAX_BARS, fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
        )
        if sim["exit_reason"] == "invalid": continue
        trades.append({
            "entry_ts": e["ts"], "direction": "SHORT",
            "result_r": round(sim["result_r"], 4),
            "exit_reason": sim["exit_reason"], "holding_bars": sim["holding_bars"],
            "entry_price": round(e["price"], 2), "atr_at_entry": round(atr, 4),
        })
    return trades


def evaluate(trades):
    if len(trades) < 30: return {"valid": False}
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
        "valid": True, "n": len(trades),
        "sharpe": round(sharpe, 3), "psr": round(psr, 3), "dsr": round(dsr, 3),
        "mean_r": round(mean_r, 3), "win_pct": round(win, 1),
        "final_eq": round(eq[dates[-1]], 3),
        "pass_gate": (sharpe > 0 and dsr >= DSR_THRESHOLD and psr >= PSR_THRESHOLD),
    }


def main():
    print("=" * 72)
    print("SHORT BTC rule_a -- R:R sweep")
    print("=" * 72)
    candles = load()
    entries = detect(candles)
    print(f"[load] {len(candles)} candles | {len(entries)} entries rule_a\n")

    results = {}
    for cfg in CONFIGS:
        trades = simulate(entries, candles, cfg["stop"], cfg["target"])
        m = evaluate(trades)
        if m["valid"]:
            wf = walk_forward_evaluate(trades, k=5, embargo_days=14, risk_pct=RISK_PCT_PER_TRADE)
            m["wf_verdict"] = wf["verdict"]
            m["wf_pos"] = wf["oos_summary"]["positive_sharpe_folds"]
            m["wf_total"] = wf["oos_summary"]["total_folds"]
            m["wf_mean"] = wf["oos_summary"]["mean_test_sharpe"]
        results[cfg["name"]] = m
        gate = "PASS" if m.get("pass_gate") else "FAIL"
        print(f"{cfg['name']:25s} | n={m.get('n','?'):>3} Sharpe={m.get('sharpe','?'):>6} "
              f"DSR={m.get('dsr','?'):>5} PSR={m.get('psr','?'):>5} "
              f"meanR={m.get('mean_r','?'):>6} win={m.get('win_pct','?'):>5}% "
              f"eq={m.get('final_eq','?'):>6}x "
              f"WF={m.get('wf_pos','?')}/{m.get('wf_total','?')} {gate}")

    out_path = ROOT_DIR / "journal" / "short_btc_rr_sweep_2026_05_18.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")
    return results


if __name__ == "__main__":
    main()
