"""
run_cross_asset_matrix.py — Cross-asset backtest matrix.

Para cada par coletado:
1. detect_entries (whitelist strict_v2)
2. Grid 4x4 stop_atr × target_atr com triple barrier
3. Sharpe/PSR/DSR + best config
4. PBO/CSCV

Output: matriz pair × config + best per pair + ranking.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from entries_cache import detect_entries
from simulate_from_entries import simulate_from_entries
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
CANDLES_DIR = JOURNAL_DIR / "candles_coinex"
ENTRIES_DIR = JOURNAL_DIR / "entries_coinex"
ENTRIES_DIR.mkdir(exist_ok=True)
MAX_BARS_DAILY = 14
MIN_CANDLES = 250        # min para detect_entries (min_history=210 + folga)
MIN_TRADES_VALID = 30
STOPS  = [1.0, 1.5, 2.0, 3.0]
TARGETS = [2.0, 3.0, 5.0, 7.0]


def evaluate(trades):
    if not trades or len(trades) < MIN_TRADES_VALID: return {"valid": False, "n": len(trades)}
    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30: return {"valid": False, "n_rets": len(rets)}
    sharpe = sharpe_from_daily_returns(rets)
    psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    dsr = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                  sharpe_benchmark=0.0, sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / len(trades)
    win = sum(1 for t in trades if t["result_r"] > 0) / len(trades) * 100
    dates = sorted(eq.keys())
    return {
        "valid": True, "n_trades": len(trades), "n_days": len(eq),
        "sharpe": round(sharpe, 4), "psr": round(psr, 4), "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4), "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (sharpe > 0 and dsr >= DSR_THRESHOLD and
                                  psr >= PSR_THRESHOLD) else "FAIL"),
    }


def process_pair(market: str, candles_path: Path) -> dict:
    print(f"\n=== {market} ===")
    with open(candles_path, "r", encoding="utf-8") as f:
        candles = json.load(f)
    if len(candles) < MIN_CANDLES:
        print(f"  [skip] apenas {len(candles)} candles (<{MIN_CANDLES})")
        return {"market": market, "skipped": "few_candles", "n_candles": len(candles)}

    # Cache entries por pair
    entries_path = ENTRIES_DIR / f"entries_{market}.json"
    all_dicts_path = ENTRIES_DIR / f"alldicts_{market}.json"
    if entries_path.exists() and all_dicts_path.exists():
        with open(entries_path, "r", encoding="utf-8") as f: entries = json.load(f)
        with open(all_dicts_path, "r", encoding="utf-8") as f: all_dicts = json.load(f)
        print(f"  [load] {len(entries)} entries cached")
    else:
        entries, all_dicts = detect_entries(
            candles, bars_per_day=1, label=market,
            whitelist_mode="strict_v2", test_signals=("COMPRA",),
            progress_every_pct=25.0,
        )
        with open(entries_path, "w", encoding="utf-8") as f: json.dump(entries, f)
        with open(all_dicts_path, "w", encoding="utf-8") as f: json.dump(all_dicts, f)

    if len(entries) < MIN_TRADES_VALID:
        print(f"  [skip] {len(entries)} entries (<{MIN_TRADES_VALID})")
        return {"market": market, "skipped": "few_entries", "n_entries": len(entries)}

    # Grid
    results = []
    trades_per_config = {}
    for s in STOPS:
        for t in TARGETS:
            trades = simulate_from_entries(
                entries, all_dicts, stop_atr=s, target_atr=t,
                max_bars=MAX_BARS_DAILY,
                fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
            )
            m = evaluate(trades)
            if m.get("valid"):
                m_full = {"stop_atr": s, "target_atr": t, **m}
                results.append(m_full)
                trades_per_config[f"s{s}_t{t}"] = trades

    if not results:
        return {"market": market, "skipped": "no_valid_configs", "n_entries": len(entries)}

    passing = [r for r in results if r["decision"] == "PASS"]
    best = max(results, key=lambda r: r["sharpe"])
    print(f"  Best: stop={best['stop_atr']} target={best['target_atr']} "
          f"Sharpe={best['sharpe']} DSR={best['dsr']} win={best['win_rate_pct']}% "
          f"eq={best['final_equity']:.2f}x [{best['decision']}]")
    print(f"  PASS: {len(passing)}/{len(results)}")

    # PBO se temos >=2 configs validos e >=4 periods de dados
    pbo = None
    if len(trades_per_config) >= 2:
        n_periods = 4 if len(entries) < 100 else 6
        pm = build_period_matrix(trades_per_config, n_periods=n_periods,
                                   risk_pct=RISK_PCT_PER_TRADE)
        if pm.get("valid"):
            pbo = pbo_score(pm["matrix"])
            print(f"  PBO: {pbo['verdict']} (pbo={pbo['pbo']})")

    # WF apenas no best (se passa)
    wf = None
    if best.get("decision") == "PASS":
        trades_best = simulate_from_entries(
            entries, all_dicts, stop_atr=best["stop_atr"], target_atr=best["target_atr"],
            max_bars=MAX_BARS_DAILY, fee_pct=TB_FEE_TAKER_PCT,
            slippage_pct=TB_SLIPPAGE_PCT,
        )
        wf = walk_forward_evaluate(trades_best, k=5, embargo_days=14,
                                    risk_pct=RISK_PCT_PER_TRADE)
        oos = wf["oos_summary"]
        print(f"  WF: {wf['verdict']} mean OOS={oos['mean_test_sharpe']} "
              f"+{oos['positive_sharpe_folds']}/{oos['total_folds']}")

    return {
        "market": market, "n_candles": len(candles), "n_entries": len(entries),
        "n_pass": len(passing), "n_configs": len(results),
        "best": best, "results": results,
        "pbo": pbo, "walk_forward": wf,
    }


def main():
    summary_path = CANDLES_DIR / "summary_1day.json"
    if not summary_path.exists():
        print(f"[ERRO] {summary_path} nao encontrado — rode coinex_collector.py primeiro")
        sys.exit(1)
    with open(summary_path, "r", encoding="utf-8") as f:
        summary = json.load(f)
    pairs = summary.get("pairs", [])
    print(f"[load] {len(pairs)} pares para processar")

    all_results = []
    for p in pairs:
        market = p["market"]
        candles_path = ROOT_DIR / p["path"]
        try:
            r = process_pair(market, candles_path)
            all_results.append(r)
        except Exception as e:
            print(f"[ERRO] {market}: {e}")
            all_results.append({"market": market, "error": str(e)})

    # Ranking
    print(f"\n{'='*72}\nRANKING CROSS-ASSET (por best Sharpe)\n{'='*72}")
    ranked = [r for r in all_results if r.get("best")]
    ranked.sort(key=lambda r: r["best"]["sharpe"], reverse=True)
    print(f"{'Market':12s} {'Best (s/t)':12s} {'Sharpe':>8s} {'DSR':>6s} {'PSR':>6s} "
          f"{'Win%':>6s} {'mR':>7s} {'eq':>10s} {'PASS/N':>8s} {'PBO':>6s} {'WF+':>6s}")
    for r in ranked:
        b = r["best"]
        pbo_str = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
        wf_str = "-"
        if r.get("walk_forward"):
            oos = r["walk_forward"]["oos_summary"]
            wf_str = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
        print(f"{r['market']:12s} s{b['stop_atr']}/t{b['target_atr']:<5}  "
              f"{b['sharpe']:>+7.2f} {b['dsr']:>6.2f} {b['psr']:>6.2f} "
              f"{b['win_rate_pct']:>5.1f}% {b['mean_r']:>+6.2f} {b['final_equity']:>9.2f}x "
              f"{r['n_pass']:>2}/{r['n_configs']:>2}  {pbo_str:>6s} {wf_str:>6s}")

    out_path = JOURNAL_DIR / "cross_asset_matrix_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "results": all_results}, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
