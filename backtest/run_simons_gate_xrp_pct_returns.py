"""
run_simons_gate_xrp_pct_returns.py — Fase D: XRP Simons Gate em DAILY RETURNS (%).

Reusa generate_xrp_trades + load_xrp_candles de run_simons_gate_xrp.py (whitelist v2
strict_v2), depois aplica a nova metodologia % returns daily Bailey-LdP 2014.

Compara contra:
  - XRP R-multiples baseline (Wave 1: DSR 1.0 / Sharpe 41.60 inflado por hourly)
  - BTC pct_returns Fase C (DSR 0.50)
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(ROOT_DIR))

from run_simons_gate_xrp import load_xrp_candles, generate_xrp_trades  # noqa: E402
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity  # noqa: E402
from metrics_pct_returns import (  # noqa: E402
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
    annualizer_crypto,
)

RISK_PCT = 0.01
N_TRIALS_PRIMARY = 50
SAMPLE_VAR = 0.5
DSR_THRESH = 0.95
PSR_THRESH = 0.95
SENSITIVITY_N_TRIALS = [20, 50, 100, 200, 500]

JOURNAL_DIR = ROOT_DIR / "journal"
TRADES_DUMP = JOURNAL_DIR / "xrp_trades_dump_2026_05_16.json"

# Baselines
XRP_R_MULTIPLES_BASELINE = {
    "dsr": 1.0,
    "psr": 1.0,
    "sharpe": 41.598,
    "decision": "PASS",
    "annualizer_note": "sqrt(365*8) hourly R-mult",
}
BTC_PCT_RETURNS_REF = {
    "sharpe": 1.603,
    "psr": 0.950,
    "dsr": 0.497,
    "decision": "FAIL",
}


def compute_metrics(returns: List[float], n_trials: int) -> Dict:
    return {
        "sharpe": sharpe_from_daily_returns(returns),
        "psr": psr_from_daily_returns(returns, sharpe_benchmark=0.0),
        "dsr": dsr_from_daily_returns(
            returns,
            n_trials=n_trials,
            sharpe_benchmark=0.0,
            sample_variance_sharpes=SAMPLE_VAR,
        ),
    }


def decide(m: Dict) -> tuple[str, List[str]]:
    reasons = []
    if m["dsr"] < DSR_THRESH:
        reasons.append(f"DSR {m['dsr']:.4f} < {DSR_THRESH}")
    if m["psr"] < PSR_THRESH:
        reasons.append(f"PSR {m['psr']:.4f} < {PSR_THRESH}")
    if m["sharpe"] <= 0:
        reasons.append(f"Sharpe {m['sharpe']:.4f} <= 0")
    return ("PASS" if not reasons else "FAIL", reasons)


def main():
    print("=" * 60)
    print("Simons Gate XRP — % Returns DAILY (Fase D)")
    print("=" * 60)

    # 1. Tenta usar trades dump se existir; senão gera
    if TRADES_DUMP.exists():
        print(f"[load] {TRADES_DUMP.name} encontrado — reusando")
        with open(TRADES_DUMP, "r", encoding="utf-8") as f:
            trades = json.load(f)
    else:
        print("[gen] Carregando candles + gerando trades (pode demorar)")
        candles = load_xrp_candles()
        trades = generate_xrp_trades(candles)
        with open(TRADES_DUMP, "w", encoding="utf-8") as f:
            json.dump(trades, f, indent=2)
        print(f"[gen] Trades dump salvo: {TRADES_DUMP.name}")

    n_trades = len(trades)
    print(f"[load] {n_trades} trades XRP")

    if n_trades < 30:
        print(f"[ERRO] Apenas {n_trades} trades. Insuficiente.")
        sys.exit(1)

    # 2. Equity curve + daily returns
    equity = build_equity_curve(trades, risk_pct=RISK_PCT)
    n_days = len(equity)
    returns = daily_returns_from_equity(equity)
    n_returns = len(returns)
    print(f"[build] {n_days} dias / {n_returns} daily returns")

    if n_returns < 30:
        print(f"[ERRO] Apenas {n_returns} daily returns.")
        sys.exit(1)

    dates = sorted(equity.keys())
    period_str = f"{dates[0]} -> {dates[-1]}"
    final_equity = equity[dates[-1]]
    print(f"[build] Período {period_str} | Final equity {final_equity:.4f}x")

    # 3. Primary metrics
    primary = compute_metrics(returns, n_trials=N_TRIALS_PRIMARY)
    decision, reasons = decide(primary)
    print(f"\n[primary] Sharpe={primary['sharpe']:.4f} PSR={primary['psr']:.4f} "
          f"DSR={primary['dsr']:.4f} -> {decision}")

    # 4. Sensitivity
    print(f"\n[sensitivity] n_trials sweep")
    sensitivity = []
    for n in SENSITIVITY_N_TRIALS:
        m = compute_metrics(returns, n_trials=n)
        d, _ = decide(m)
        sensitivity.append({
            "n_trials": n,
            "sharpe": round(m["sharpe"], 6),
            "psr": round(m["psr"], 6),
            "dsr": round(m["dsr"], 6),
            "decision": d,
        })
        print(f"  n_trials={n:4d}: Sharpe={m['sharpe']:.4f} PSR={m['psr']:.4f} "
              f"DSR={m['dsr']:.4f} -> {d}")

    # 5. Save
    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": "XRPUSD",
        "methodology": "pct_returns_daily_bailey_lopez_de_prado_2014",
        "dataset": {
            "n_trades": n_trades,
            "n_days": n_days,
            "n_returns": n_returns,
            "period": period_str,
            "final_equity": round(final_equity, 6),
            "risk_pct": RISK_PCT,
            "annualizer": f"sqrt(365)={round(annualizer_crypto(), 4)}",
        },
        "params": {
            "n_trials": N_TRIALS_PRIMARY,
            "sample_variance_sharpes": SAMPLE_VAR,
            "dsr_threshold": DSR_THRESH,
            "psr_threshold": PSR_THRESH,
        },
        "metrics": {
            "sharpe": round(primary["sharpe"], 6),
            "psr": round(primary["psr"], 6),
            "dsr": round(primary["dsr"], 6),
        },
        "decision": decision,
        "reasons": reasons,
        "sensitivity": sensitivity,
        "baselines": {
            "xrp_r_multiples": XRP_R_MULTIPLES_BASELINE,
            "btc_pct_returns": BTC_PCT_RETURNS_REF,
        },
    }

    out_json = JOURNAL_DIR / "simons_gate_pct_returns_xrp_2026_05_16.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_json.name}")

    print("\n" + "=" * 60)
    print(f"XRP DECISION: {decision}")
    print(f"  Sharpe   : {primary['sharpe']:.4f} (vs R-mult {XRP_R_MULTIPLES_BASELINE['sharpe']:.2f})")
    print(f"  PSR      : {primary['psr']:.4f} (vs R-mult {XRP_R_MULTIPLES_BASELINE['psr']:.4f})")
    print(f"  DSR      : {primary['dsr']:.4f} (vs R-mult {XRP_R_MULTIPLES_BASELINE['dsr']:.4f})")
    print(f"  N_days   : {n_days}")
    print(f"  Final eq : {final_equity:.4f}x")
    print(f"  BTC ref  : Sharpe {BTC_PCT_RETURNS_REF['sharpe']} / "
          f"DSR {BTC_PCT_RETURNS_REF['dsr']} -> {BTC_PCT_RETURNS_REF['decision']}")
    print("=" * 60)


if __name__ == "__main__":
    main()
