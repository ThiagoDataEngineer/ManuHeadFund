"""run_btc_daily.py — Caminho 5: BTC em timeframe DAILY (não hourly).

Hipótese: hourly tem stop hunts. Daily reduz noise → maybe edge survives.

Adapta:
- bars_per_day=1 (não 24)
- TB_MAX_BARS=14 days (em vez de 168h)
- ATR window mantida em 14 bars
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from entries_cache import detect_entries  # noqa: E402
from simulate_from_entries import simulate_from_entries  # noqa: E402
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity  # noqa: E402
from metrics_pct_returns import (  # noqa: E402
    sharpe_from_daily_returns,
    psr_from_daily_returns,
    dsr_from_daily_returns,
)
from walk_forward_purged import walk_forward_evaluate  # noqa: E402
from constants import (  # noqa: E402
    RISK_PCT_PER_TRADE, SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD,
    TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

JOURNAL_DIR = ROOT_DIR / "journal"

MAX_BARS_DAILY = 14  # 14 dias de timeout vs 168h (7d) hourly
STOP_GRID = [1.0, 1.5, 2.0, 3.0]
TARGET_GRID = [2.0, 3.0, 5.0, 7.0]


def evaluate(trades) -> dict:
    if not trades or len(trades) < 30:
        return {"valid": False, "n_trades": len(trades)}
    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30:
        return {"valid": False, "n_returns": len(rets)}
    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                  sharpe_benchmark=0.0,
                                  sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / len(trades)
    win = sum(1 for t in trades if t["result_r"] > 0) / len(trades) * 100
    dates = sorted(eq.keys())
    return {
        "valid": True,
        "n_trades": len(trades),
        "n_days": len(eq),
        "sharpe": round(sharpe, 4),
        "psr": round(psr, 4),
        "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4),
        "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (sharpe > 0 and dsr >= DSR_THRESHOLD and
                                  psr >= PSR_THRESHOLD) else "FAIL"),
    }


def main():
    cache_e = JOURNAL_DIR / "entries_btc_daily_2026_05_17.json"
    cache_ad = JOURNAL_DIR / "all_dicts_btc_daily_2026_05_17.json"
    print("=" * 72)
    print("BTC DAILY TIMEFRAME — Caminho 5")
    print("=" * 72)

    if cache_e.exists() and cache_ad.exists():
        with open(cache_e, "r", encoding="utf-8") as f:
            entries = json.load(f)
        with open(cache_ad, "r", encoding="utf-8") as f:
            all_dicts = json.load(f)
        print(f"[load] {len(entries)} BTC daily entries cached")
    else:
        from db import Database
        db = Database()
        candles = db.get_candles("BTCUSD", "1day",
                                  "2014-01-01T00:00:00", "2026-05-01T00:00:00")
        print(f"[load] {len(candles)} BTC daily candles")
        entries, all_dicts = detect_entries(
            candles, bars_per_day=1, label="btc_daily",
            whitelist_mode="strict_v2", test_signals=("COMPRA",),
        )
        with open(cache_e, "w", encoding="utf-8") as f:
            json.dump(entries, f)
        with open(cache_ad, "w", encoding="utf-8") as f:
            json.dump(all_dicts, f)
        print(f"[save] {cache_e.name}")

    print(f"[entries] {len(entries)} entries\n")

    if len(entries) < 30:
        print(f"[ERRO] {len(entries)} entries < 30. Insuficiente.")
        sys.exit(1)

    # Grid search
    results = []
    for s in STOP_GRID:
        for t in TARGET_GRID:
            trades = simulate_from_entries(
                entries, all_dicts, stop_atr=s, target_atr=t,
                max_bars=MAX_BARS_DAILY,
                fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
            )
            m = evaluate(trades)
            if m.get("valid"):
                tag = m["decision"]
                print(f"  stop={s:.1f} target={t:.1f}  Sharpe={m['sharpe']:>7.3f} "
                      f"DSR={m['dsr']:.3f} PSR={m['psr']:.3f} win%={m['win_rate_pct']:>5.1f} "
                      f"meanR={m['mean_r']:>6.3f} eq={m['final_equity']:>12.4f}x "
                      f"n={m['n_trades']:>4} [{tag}]")
                results.append({"stop_atr": s, "target_atr": t, **m})
            else:
                print(f"  stop={s:.1f} target={t:.1f}  INVALID {m}")

    # Best params
    valid = [r for r in results if r.get("valid")]
    best = max(valid, key=lambda r: r["sharpe"]) if valid else None
    passing = [r for r in valid if r["decision"] == "PASS"]

    print("\n" + "=" * 72)
    if passing:
        print(f"PASS count: {len(passing)}/16")
        best = max(passing, key=lambda r: r["sharpe"])
        print(f"Best PASS: stop={best['stop_atr']} target={best['target_atr']}")
        print(f"  Sharpe={best['sharpe']} DSR={best['dsr']} PSR={best['psr']}")
        print(f"  win%={best['win_rate_pct']} meanR={best['mean_r']} "
              f"eq={best['final_equity']}x n={best['n_trades']}")

        # Walk-forward no best
        print(f"\n[WF] Walk-forward purged k=5 best params...")
        trades_best = simulate_from_entries(
            entries, all_dicts,
            stop_atr=best["stop_atr"], target_atr=best["target_atr"],
            max_bars=MAX_BARS_DAILY,
            fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
        )
        wf = walk_forward_evaluate(trades_best, k=5, embargo_days=14,
                                    risk_pct=RISK_PCT_PER_TRADE)
        print(f"WF verdict: {wf['verdict']}")
        oos = wf["oos_summary"]
        print(f"OOS: mean Sharpe={oos['mean_test_sharpe']} "
              f"positive folds={oos['positive_sharpe_folds']}/{oos['total_folds']}")
        for fr in wf["fold_results"]:
            tm = fr["test_metrics"]
            if tm.get("valid"):
                print(f"  fold {fr['fold_idx']}: {fr['test_period'][0]}→{fr['test_period'][1]} "
                      f"Sharpe={tm['sharpe']} mean_r={tm['mean_r']} eq={tm['final_equity']:.3f}x")
    else:
        print(f"FAIL: 0/16 PASS no daily timeframe")
        if best:
            print(f"Best Sharpe (fail): stop={best['stop_atr']} target={best['target_atr']} "
                  f"Sharpe={best['sharpe']} win%={best['win_rate_pct']} meanR={best['mean_r']}")
        wf = None

    out_obj = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "asset": "BTCUSD",
        "timeframe": "1day",
        "n_entries": len(entries),
        "results": results,
        "best": best,
        "walk_forward": wf,
        "verdict": "PASS" if passing else "FAIL",
    }
    out_path = JOURNAL_DIR / "btc_daily_grid_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_obj, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
