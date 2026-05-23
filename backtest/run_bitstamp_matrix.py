"""run_bitstamp_matrix.py — Matrix triple barrier nos 4 pares Bitstamp histórico longo."""
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
from metrics_pct_returns import sharpe_from_daily_returns, psr_from_daily_returns, dsr_from_daily_returns
from walk_forward_purged import walk_forward_evaluate
from pbo_cscv import build_period_matrix, pbo_score
from constants import (
    RISK_PCT_PER_TRADE, SIMONS_N_TRIALS_DEFAULT, SIMONS_SAMPLE_VAR,
    DSR_THRESHOLD, PSR_THRESHOLD, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT,
)

JOURNAL_DIR = ROOT_DIR / "journal"
MAX_BARS_DAILY = 14
STOPS = [1.0, 1.5, 2.0, 3.0]
TARGETS = [2.0, 3.0, 5.0, 7.0]

PAIRS = {
    "BTCUSD-BITSTAMP": "btcusd_bitstamp_1day.json",
    "XRPUSD-BITSTAMP": "xrpusd_bitstamp_1day.json",
    "ETHUSD-BITSTAMP": "ethusd_bitstamp_1day.json",
    "LTCUSD-BITSTAMP": "ltcusd_bitstamp_1day.json",
}


def evaluate(trades):
    if not trades or len(trades) < 30: return {"valid": False, "n": len(trades)}
    eq = build_equity_curve(trades, risk_pct=RISK_PCT_PER_TRADE)
    rets = daily_returns_from_equity(eq)
    if len(rets) < 30: return {"valid": False}
    s = sharpe_from_daily_returns(rets)
    p = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
    d = dsr_from_daily_returns(rets, n_trials=SIMONS_N_TRIALS_DEFAULT,
                                sharpe_benchmark=0.0, sample_variance_sharpes=SIMONS_SAMPLE_VAR)
    mean_r = sum(t["result_r"] for t in trades) / len(trades)
    win = sum(1 for t in trades if t["result_r"] > 0) / len(trades) * 100
    dates = sorted(eq.keys())
    return {
        "valid": True, "n_trades": len(trades), "sharpe": round(s, 4),
        "psr": round(p, 4), "dsr": round(d, 4),
        "mean_r": round(mean_r, 4), "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (s > 0 and d >= DSR_THRESHOLD and p >= PSR_THRESHOLD) else "FAIL"),
    }


def process(market: str, candles_file: str) -> dict:
    print(f"\n=== {market} ===")
    path = SCRIPT_DIR / candles_file
    if not path.exists():
        print(f"  [skip] {path} not found")
        return {"market": market, "skipped": True}
    with open(path, "r", encoding="utf-8") as f:
        candles = json.load(f)
    print(f"  {len(candles)} candles")

    e_cache = JOURNAL_DIR / f"entries_bitstamp_{market.lower().replace('-', '_')}.json"
    a_cache = JOURNAL_DIR / f"alldicts_bitstamp_{market.lower().replace('-', '_')}.json"
    if e_cache.exists() and a_cache.exists():
        with open(e_cache, "r", encoding="utf-8") as f: entries = json.load(f)
        with open(a_cache, "r", encoding="utf-8") as f: all_dicts = json.load(f)
    else:
        entries, all_dicts = detect_entries(candles, bars_per_day=1,
                                              label=market, whitelist_mode="strict_v2",
                                              test_signals=("COMPRA",),
                                              progress_every_pct=25.0)
        with open(e_cache, "w", encoding="utf-8") as f: json.dump(entries, f)
        with open(a_cache, "w", encoding="utf-8") as f: json.dump(all_dicts, f)

    if len(entries) < 30:
        print(f"  [skip] {len(entries)} entries (<30)")
        return {"market": market, "skipped": True, "n_entries": len(entries)}

    print(f"  [entries] {len(entries)}")
    results = []
    trades_per_config = {}
    for s in STOPS:
        for t in TARGETS:
            trs = simulate_from_entries(entries, all_dicts, stop_atr=s, target_atr=t,
                                          max_bars=MAX_BARS_DAILY,
                                          fee_pct=TB_FEE_TAKER_PCT,
                                          slippage_pct=TB_SLIPPAGE_PCT)
            m = evaluate(trs)
            if m.get("valid"):
                results.append({"stop_atr": s, "target_atr": t, **m})
                trades_per_config[f"s{s}_t{t}"] = trs
    if not results:
        return {"market": market, "no_valid_configs": True}

    passing = [r for r in results if r["decision"] == "PASS"]
    best = max(results, key=lambda r: r["sharpe"])
    print(f"  best stop={best['stop_atr']} t={best['target_atr']} "
          f"Sharpe={best['sharpe']} DSR={best['dsr']} win={best['win_rate_pct']}% "
          f"eq={best['final_equity']:.2f}x [{best['decision']}]  PASS:{len(passing)}/{len(results)}")

    pbo = None
    if len(trades_per_config) >= 2:
        pm = build_period_matrix(trades_per_config, n_periods=6,
                                   risk_pct=RISK_PCT_PER_TRADE)
        if pm.get("valid"):
            pbo = pbo_score(pm["matrix"])
            print(f"  PBO: {pbo['verdict']} (pbo={pbo['pbo']})")

    wf = None
    if best["decision"] == "PASS":
        trs_best = simulate_from_entries(entries, all_dicts,
                                           stop_atr=best["stop_atr"],
                                           target_atr=best["target_atr"],
                                           max_bars=MAX_BARS_DAILY,
                                           fee_pct=TB_FEE_TAKER_PCT,
                                           slippage_pct=TB_SLIPPAGE_PCT)
        wf = walk_forward_evaluate(trs_best, k=5, embargo_days=14,
                                     risk_pct=RISK_PCT_PER_TRADE)
        oos = wf["oos_summary"]
        print(f"  WF: {wf['verdict']} OOS mean={oos['mean_test_sharpe']} +{oos['positive_sharpe_folds']}/{oos['total_folds']}")

    return {"market": market, "n_candles": len(candles), "n_entries": len(entries),
             "n_pass": len(passing), "n_configs": len(results),
             "best": best, "results": results, "pbo": pbo, "walk_forward": wf}


def main():
    all_results = []
    for m, f in PAIRS.items():
        r = process(m, f)
        all_results.append(r)

    print(f"\n{'='*78}\nBITSTAMP LONG HISTORY MATRIX\n{'='*78}")
    print(f"{'Market':22s} {'Best (s/t)':12s} {'Sharpe':>8s} {'DSR':>6s} "
          f"{'Win%':>6s} {'eq':>12s} {'PASS/N':>8s} {'PBO':>6s} {'WF+':>6s}")
    for r in all_results:
        if r.get("best"):
            b = r["best"]
            pbo_str = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
            wf_str = "-"
            if r.get("walk_forward"):
                oos = r["walk_forward"]["oos_summary"]
                wf_str = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
            print(f"{r['market']:22s} s{b['stop_atr']}/t{b['target_atr']:<5}  "
                  f"{b['sharpe']:>+7.2f} {b['dsr']:>6.2f} {b['win_rate_pct']:>5.1f}% "
                  f"{b['final_equity']:>10.2f}x {r['n_pass']:>2}/{r['n_configs']:>2} "
                  f"{pbo_str:>6s} {wf_str:>6s}")

    out = JOURNAL_DIR / "bitstamp_matrix_2026_05_17.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "results": all_results}, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out.name}")


if __name__ == "__main__":
    main()
