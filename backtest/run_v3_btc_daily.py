"""run_v3_btc_daily.py — Whitelist v3 (LONG+SHORT) em BTC DAILY timeframe.

Combinação não testada ainda. Verifica:
- SHORT em daily salva os bear/sideways periods?
- v3 daily supera v2 daily (LONG-only)?
"""
import json
import sys
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
MAX_BARS_DAILY = 14


def evaluate(trades):
    if not trades or len(trades) < 30: return {"valid": False, "n": len(trades)}
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
    long_n = sum(1 for t in trades if t["direction"] == "LONG")
    short_n = len(trades) - long_n
    return {
        "valid": True,
        "n_trades": len(trades), "n_long": long_n, "n_short": short_n,
        "n_days": len(eq), "sharpe": round(sharpe, 4),
        "psr": round(psr, 4), "dsr": round(dsr, 4),
        "mean_r": round(mean_r, 4), "win_rate_pct": round(win, 2),
        "final_equity": round(eq[dates[-1]], 6),
        "decision": ("PASS" if (sharpe > 0 and dsr >= DSR_THRESHOLD and
                                  psr >= PSR_THRESHOLD) else "FAIL"),
    }


def main():
    cache_e = JOURNAL_DIR / "entries_v3_btc_daily_2026_05_17.json"
    cache_ad = JOURNAL_DIR / "all_dicts_btc_daily_2026_05_17.json"
    if cache_e.exists() and cache_ad.exists():
        with open(cache_e, "r", encoding="utf-8") as f: entries = json.load(f)
        with open(cache_ad, "r", encoding="utf-8") as f: all_dicts = json.load(f)
        print(f"[load] {len(entries)} v3 BTC daily entries cached")
    else:
        from db import Database
        candles = Database().get_candles("BTCUSD", "1day",
                                          "2014-01-01T00:00:00", "2026-05-01T00:00:00")
        print(f"[load] {len(candles)} BTC daily candles")
        entries, all_dicts = detect_entries(
            candles, bars_per_day=1, label="btc_daily_v3",
            whitelist_mode="strict_v3", test_signals=("COMPRA", "VENDA"),
        )
        with open(cache_e, "w", encoding="utf-8") as f: json.dump(entries, f)
        with open(cache_ad, "w", encoding="utf-8") as f: json.dump(all_dicts, f)

    n_long = sum(1 for e in entries if e["direction"] == "LONG")
    n_short = sum(1 for e in entries if e["direction"] == "SHORT")
    print(f"[entries] LONG={n_long} SHORT={n_short} total={len(entries)}")
    if n_short > 0:
        regime_short = {}
        for e in entries:
            if e["direction"] == "SHORT":
                regime_short[e["regime"]] = regime_short.get(e["regime"], 0) + 1
        print(f"[short_regimes] {regime_short}")

    # Grid 4×4 + extras
    STOPS = [1.0, 1.5, 2.0, 3.0]
    TARGETS = [2.0, 3.0, 5.0, 7.0]
    results = []
    for s in STOPS:
        for t in TARGETS:
            trades = simulate_from_entries(
                entries, all_dicts, stop_atr=s, target_atr=t,
                max_bars=MAX_BARS_DAILY,
                fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
            )
            m = evaluate(trades)
            if m.get("valid"):
                tag = m["decision"]
                print(f"  s={s:.1f} t={t:.1f}  Sharpe={m['sharpe']:>7.3f} "
                      f"DSR={m['dsr']:.3f} win%={m['win_rate_pct']:>5.1f} "
                      f"meanR={m['mean_r']:>+6.3f} eq={m['final_equity']:>10.3f}x "
                      f"L={m['n_long']:>4} S={m['n_short']:>4} [{tag}]")
                results.append({"stop_atr": s, "target_atr": t, **m})

    passing = [r for r in results if r["decision"] == "PASS"]
    if passing:
        best = max(passing, key=lambda r: r["sharpe"])
        print(f"\n{len(passing)}/16 PASS. Best: stop={best['stop_atr']} target={best['target_atr']}")
        print(f"  Sharpe={best['sharpe']} DSR={best['dsr']} mean_r={best['mean_r']} eq={best['final_equity']}")

        # Walk-forward + PBO
        trades_best = simulate_from_entries(
            entries, all_dicts, stop_atr=best["stop_atr"], target_atr=best["target_atr"],
            max_bars=MAX_BARS_DAILY, fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
        )
        wf = walk_forward_evaluate(trades_best, k=5, embargo_days=14,
                                     risk_pct=RISK_PCT_PER_TRADE)
        print(f"\nWF: {wf['verdict']} mean OOS={wf['oos_summary']['mean_test_sharpe']} "
              f"positive={wf['oos_summary']['positive_sharpe_folds']}/{wf['oos_summary']['total_folds']}")

        # PBO sobre todos os configs válidos do grid
        trades_per_config = {}
        for s in STOPS:
            for t in TARGETS:
                trs = simulate_from_entries(
                    entries, all_dicts, stop_atr=s, target_atr=t,
                    max_bars=MAX_BARS_DAILY, fee_pct=TB_FEE_TAKER_PCT,
                    slippage_pct=TB_SLIPPAGE_PCT,
                )
                if len(trs) >= 30:
                    trades_per_config[f"s{s}_t{t}"] = trs
        pm = build_period_matrix(trades_per_config, n_periods=6,
                                   risk_pct=RISK_PCT_PER_TRADE)
        if pm.get("valid"):
            pbo = pbo_score(pm["matrix"])
            print(f"PBO: {pbo['verdict']} (pbo={pbo['pbo']})")
        else:
            pbo = None
    else:
        print(f"\n0/16 PASS no v3 daily")
        wf = None
        pbo = None

    out = {
        "asset": "BTCUSD", "timeframe": "1day", "whitelist": "v3_long_short",
        "n_long": n_long, "n_short": n_short, "results": results,
        "best": (max(passing, key=lambda r: r["sharpe"]) if passing else None),
        "walk_forward": wf, "pbo": pbo,
        "verdict": "PASS" if passing else "FAIL",
    }
    out_path = JOURNAL_DIR / "v3_btc_daily_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
