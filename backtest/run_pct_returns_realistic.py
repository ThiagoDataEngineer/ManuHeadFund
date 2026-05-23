"""
run_pct_returns_realistic.py — Fase D-v2: Simons Gate pct_returns com
simulação realista (triple barrier path-dependent + fees CoinEx).

Corrige bug de equity 10^28 da Fase D v1 (simulação binária +5R/-1R).

Uso:
    python backtest/run_pct_returns_realistic.py xrp
    python backtest/run_pct_returns_realistic.py btc
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

from generate_trades_realistic import generate_trades_realistic  # noqa: E402
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity  # noqa: E402
from metrics_pct_returns import (  # noqa: E402
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
    annualizer_crypto,
)
from constants import (  # noqa: E402
    RISK_PCT_PER_TRADE,
    SIMONS_N_TRIALS_DEFAULT,
    SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD,
    PSR_THRESHOLD,
)

JOURNAL_DIR = ROOT_DIR / "journal"
SENSITIVITY_N_TRIALS = [20, 50, 100, 200, 500]


def load_candles(asset: str) -> List[Dict]:
    if asset.lower() == "xrp":
        from run_simons_gate_xrp import load_xrp_candles
        return load_xrp_candles()
    if asset.lower() == "btc":
        # BTC vem do Supabase via db.Database (similar a run_simons_gate_real)
        from db import Database
        # Período conservador: 2014-2025 (mesmo do BTC pct_returns fase C)
        db = Database()
        candles = db.get_candles("BTCUSD", "1hour",
                                  "2014-01-01T00:00:00", "2025-05-01T00:00:00")
        return candles
    raise ValueError(f"Asset desconhecido: {asset}")


def compute_metrics(returns: List[float], n_trials: int) -> Dict:
    return {
        "sharpe": sharpe_from_daily_returns(returns),
        "psr": psr_from_daily_returns(returns, sharpe_benchmark=0.0),
        "dsr": dsr_from_daily_returns(returns, n_trials=n_trials,
                                       sharpe_benchmark=0.0,
                                       sample_variance_sharpes=SIMONS_SAMPLE_VAR),
    }


def decide(m: Dict) -> tuple[str, List[str]]:
    reasons = []
    if m["dsr"] < DSR_THRESHOLD:
        reasons.append(f"DSR {m['dsr']:.4f} < {DSR_THRESHOLD}")
    if m["psr"] < PSR_THRESHOLD:
        reasons.append(f"PSR {m['psr']:.4f} < {PSR_THRESHOLD}")
    if m["sharpe"] <= 0:
        reasons.append(f"Sharpe {m['sharpe']:.4f} <= 0")
    return ("PASS" if not reasons else "FAIL", reasons)


def run(asset: str):
    print("=" * 60)
    print(f"Simons Gate {asset.upper()} — Realistic (triple barrier + fees)")
    print("=" * 60)

    trades_dump = JOURNAL_DIR / f"{asset.lower()}_trades_realistic_2026_05_16.json"

    if trades_dump.exists():
        print(f"[load] {trades_dump.name} cache encontrado")
        with open(trades_dump, "r", encoding="utf-8") as f:
            trades = json.load(f)
    else:
        candles = load_candles(asset)
        print(f"[load] {len(candles)} candles {asset}")
        trades = generate_trades_realistic(candles, label=asset.lower())
        with open(trades_dump, "w", encoding="utf-8") as f:
            json.dump(trades, f, indent=2)
        print(f"[save] {trades_dump.name}")

    n_trades = len(trades)
    print(f"[load] {n_trades} trades")
    if n_trades < 30:
        print(f"[ERRO] Apenas {n_trades} trades. Insuficiente.")
        sys.exit(1)

    # Distribuição exit_reason
    reasons_count = {}
    for t in trades:
        er = t.get("exit_reason", "unknown")
        reasons_count[er] = reasons_count.get(er, 0) + 1
    print(f"[stats] exit_reasons: {reasons_count}")
    mean_r = sum(t.get("result_r", 0) for t in trades) / n_trades
    win_rate = sum(1 for t in trades if t.get("result_r", 0) > 0) / n_trades * 100
    print(f"[stats] mean_r={mean_r:.4f} win_rate={win_rate:.1f}%")

    # Equity curve + daily returns
    equity = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    n_days = len(equity)
    returns = daily_returns_from_equity(equity)
    n_returns = len(returns)
    dates = sorted(equity.keys())
    final_eq = equity[dates[-1]]
    print(f"[build] {n_days}d / {n_returns} returns | "
          f"Período {dates[0]} → {dates[-1]} | Final eq {final_eq:.4f}x")

    if n_returns < 30:
        print(f"[ERRO] Apenas {n_returns} daily returns. Insuficiente.")
        sys.exit(1)

    # Métricas
    primary = compute_metrics(returns, n_trials=SIMONS_N_TRIALS_DEFAULT)
    decision, reasons = decide(primary)
    print(f"\n[primary] Sharpe={primary['sharpe']:.4f} PSR={primary['psr']:.4f} "
          f"DSR={primary['dsr']:.4f} → {decision}")

    # Sensitivity
    sensitivity = []
    for n in SENSITIVITY_N_TRIALS:
        m = compute_metrics(returns, n_trials=n)
        d, _ = decide(m)
        sensitivity.append({"n_trials": n, "sharpe": round(m["sharpe"], 6),
                             "psr": round(m["psr"], 6), "dsr": round(m["dsr"], 6),
                             "decision": d})
        print(f"  n_trials={n:4d}: Sharpe={m['sharpe']:.4f} PSR={m['psr']:.4f} "
              f"DSR={m['dsr']:.4f} → {d}")

    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": asset.upper(),
        "methodology": "pct_returns_daily + triple_barrier_path_dependent + CoinEx_fees",
        "simulation": {
            "stop_atr": "1.0 * ATR(14)",
            "target_atr": "5.0 * ATR(14)",
            "max_bars": 168,
            "fee_pct": 0.0005,
            "slippage_pct": 0.0005,
        },
        "dataset": {
            "n_trades": n_trades,
            "n_days": n_days,
            "n_returns": n_returns,
            "period": f"{dates[0]} → {dates[-1]}",
            "final_equity": round(final_eq, 6),
            "mean_r": round(mean_r, 4),
            "win_rate_pct": round(win_rate, 2),
            "exit_reasons": reasons_count,
            "risk_pct": RISK_PCT_PER_TRADE,
            "annualizer": f"sqrt(365)={round(annualizer_crypto(), 4)}",
        },
        "metrics": {
            "sharpe": round(primary["sharpe"], 6),
            "psr": round(primary["psr"], 6),
            "dsr": round(primary["dsr"], 6),
        },
        "decision": decision,
        "reasons": reasons,
        "sensitivity": sensitivity,
    }

    out_json = JOURNAL_DIR / f"simons_gate_realistic_{asset.lower()}_2026_05_16.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_json.name}")

    print("\n" + "=" * 60)
    print(f"{asset.upper()} REALISTIC DECISION: {decision}")
    print(f"  Sharpe   : {primary['sharpe']:.4f}")
    print(f"  PSR      : {primary['psr']:.4f}")
    print(f"  DSR      : {primary['dsr']:.4f}")
    print(f"  Mean R   : {mean_r:.4f}")
    print(f"  Win rate : {win_rate:.1f}%")
    print(f"  Final eq : {final_eq:.4f}x")
    print("=" * 60)


if __name__ == "__main__":
    asset = sys.argv[1] if len(sys.argv) > 1 else "xrp"
    run(asset)
