"""
run_grid_search.py — Grid search stop_atr x target_atr no triple barrier.

Otimizacao: detect_entries roda UMA vez (caro), simulate_from_entries roda
GRID_SIZE vezes (barato). Speedup ~16x vs run_pct_returns_realistic.

Output: tabela de (stop_atr, target_atr) -> (Sharpe, DSR, mean_r, win%, final_eq)
       + identifica best params per Sharpe ajustado por DSR.

Uso:
    python backtest/run_grid_search.py xrp
    python backtest/run_grid_search.py btc
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

from entries_cache import detect_entries  # noqa: E402
from simulate_from_entries import simulate_from_entries  # noqa: E402
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity  # noqa: E402
from metrics_pct_returns import (  # noqa: E402
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
)
from constants import (  # noqa: E402
    RISK_PCT_PER_TRADE, SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD,
    TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

JOURNAL_DIR = ROOT_DIR / "journal"

# Grid: 4 stops x 4 targets = 16 combinacoes
STOP_GRID    = [0.5, 1.0, 1.5, 2.0]
TARGET_GRID  = [1.0, 2.0, 3.0, 5.0]


def load_candles(asset: str) -> List[Dict]:
    if asset.lower() == "xrp":
        from run_simons_gate_xrp import load_xrp_candles
        return load_xrp_candles()
    if asset.lower() == "btc":
        from db import Database
        db = Database()
        return db.get_candles("BTCUSD", "1hour",
                               "2014-01-01T00:00:00", "2025-05-01T00:00:00")
    raise ValueError(f"asset desconhecido: {asset}")


def evaluate_params(entries, all_dicts, stop_atr, target_atr) -> Dict:
    trades = simulate_from_entries(
        entries=entries, all_dicts=all_dicts,
        stop_atr=stop_atr, target_atr=target_atr,
        max_bars=TB_MAX_BARS, fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
    )
    n_trades = len(trades)
    if n_trades < 30:
        return {"valid": False, "n_trades": n_trades}

    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30:
        return {"valid": False, "n_returns": len(rets)}

    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                  sharpe_benchmark=0.0,
                                  sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / n_trades
    win_rate = sum(1 for t in trades if t["result_r"] > 0) / n_trades * 100
    dates = sorted(eq.keys())
    final_eq = eq[dates[-1]]

    return {
        "valid": True,
        "stop_atr": stop_atr,
        "target_atr": target_atr,
        "rr": round(target_atr / stop_atr, 2),
        "n_trades": n_trades,
        "n_days": len(eq),
        "sharpe": round(sharpe, 4),
        "psr": round(psr, 4),
        "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4),
        "win_rate_pct": round(win_rate, 2),
        "final_equity": round(final_eq, 6),
        "pass": (sharpe > 0 and dsr >= DSR_THRESHOLD and psr >= PSR_THRESHOLD),
    }


def main(asset: str):
    print("=" * 72)
    print(f"GRID SEARCH {asset.upper()} — stop x target ATR multipliers")
    print("=" * 72)

    # Cache entries em disco — pula re-deteccao se ja existe
    cache = JOURNAL_DIR / f"entries_cache_{asset.lower()}_2026_05_17.json"
    all_dicts_cache = JOURNAL_DIR / f"all_dicts_{asset.lower()}_2026_05_17.json"
    if cache.exists() and all_dicts_cache.exists():
        print(f"[load] {cache.name} cache encontrado")
        with open(cache, "r", encoding="utf-8") as f:
            entries = json.load(f)
        with open(all_dicts_cache, "r", encoding="utf-8") as f:
            all_dicts = json.load(f)
    else:
        candles = load_candles(asset)
        print(f"[load] {len(candles)} candles")
        entries, all_dicts = detect_entries(candles, bars_per_day=24,
                                             label=asset.lower())
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(entries, f)
        with open(all_dicts_cache, "w", encoding="utf-8") as f:
            json.dump(all_dicts, f)
        print(f"[save] {cache.name}")

    print(f"[entries] {len(entries)} entries cached\n")

    # Grid sweep
    results = []
    for s in STOP_GRID:
        for t in TARGET_GRID:
            r = evaluate_params(entries, all_dicts, s, t)
            if r.get("valid"):
                tag = "PASS" if r["pass"] else "fail"
                print(f"  stop={s:.1f} target={t:.1f} R:R={r['rr']:.1f}  "
                      f"Sharpe={r['sharpe']:>7.3f}  DSR={r['dsr']:.3f}  "
                      f"PSR={r['psr']:.3f}  win%={r['win_rate_pct']:>5.1f}  "
                      f"meanR={r['mean_r']:>6.3f}  eq={r['final_equity']:>11.3f}x  "
                      f"n={r['n_trades']:>4}  [{tag}]")
                results.append(r)
            else:
                print(f"  stop={s:.1f} target={t:.1f}  INVALID ({r})")

    # Best params: maior Sharpe entre PASS, fallback maior Sharpe positivo
    pass_results = [r for r in results if r["pass"]]
    if pass_results:
        best = max(pass_results, key=lambda x: x["sharpe"])
        verdict = "PASS"
    else:
        positives = [r for r in results if r["sharpe"] > 0]
        if positives:
            best = max(positives, key=lambda x: x["sharpe"])
            verdict = "MARGINAL (Sharpe>0 mas DSR<0.95 ou PSR<0.95)"
        else:
            best = max(results, key=lambda x: x["sharpe"]) if results else None
            verdict = "FAIL (nenhum Sharpe positivo)"

    out = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": asset.upper(),
        "methodology": "grid_search_triple_barrier_pct_returns_with_fees",
        "grid": {"stop_atr": STOP_GRID, "target_atr": TARGET_GRID},
        "fixed_params": {"max_bars": TB_MAX_BARS,
                         "fee_pct": TB_FEE_TAKER_PCT,
                         "slippage_pct": TB_SLIPPAGE_PCT,
                         "risk_pct": RISK_PCT_PER_TRADE},
        "n_entries_cached": len(entries),
        "results": results,
        "best_params": best,
        "verdict": verdict,
    }

    out_json = JOURNAL_DIR / f"grid_search_{asset.lower()}_2026_05_17.json"
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_json.name}")

    print("\n" + "=" * 72)
    print(f"VERDICT {asset.upper()}: {verdict}")
    if best:
        print(f"  Best: stop={best['stop_atr']} target={best['target_atr']} "
              f"R:R={best['rr']}")
        print(f"  Sharpe={best['sharpe']} DSR={best['dsr']} PSR={best['psr']}")
        print(f"  win%={best['win_rate_pct']} meanR={best['mean_r']} "
              f"eq={best['final_equity']:.3f}x n={best['n_trades']}")
    print("=" * 72)


if __name__ == "__main__":
    asset = sys.argv[1] if len(sys.argv) > 1 else "xrp"
    main(asset)
