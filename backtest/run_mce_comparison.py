"""
run_mce_comparison.py -- Compara performance trades com vs sem MCE filter.

Para cada Tier A LIVE market:
1. Re-detecta entries via cross_asset_matrix
2. Simulate trades
3. Apply MCE filter retroativo (threshold 0.5)
4. Compute Sharpe/DSR before/after
5. Show comparison + delta

Output: journal/mce_comparison_<DATE>.json
"""
import json, sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent
ROOT = SCRIPT.parent
sys.path.insert(0, str(SCRIPT))

from mce_filter import apply_context_filter, compare_metrics, context_score
from equity_curve_from_trades import build_equity_curve, daily_returns_from_equity
from metrics_pct_returns import sharpe_from_daily_returns, psr_from_daily_returns
from constants import RISK_PCT_PER_TRADE

CANDLES_DIR = ROOT / "journal" / "candles_coinex"
ENTRIES_DIR = ROOT / "journal" / "entries_coinex"


def load_trades_for_market(market):
    """Loads trade dicts produced by simulate_from_entries cached output if available.
       Falls back: re-runs simulation."""
    from run_cross_asset_matrix import process_pair
    cp = CANDLES_DIR / f"{market}_1day.json"
    if not cp.exists(): return None
    r = process_pair(market, cp)
    if not r or not r.get("best"):
        return None
    return r


def compute_metrics_with_filter(trades, regime_default="BULL_WEAK"):
    """Aplica MCE filter + compute Sharpe/PSR before/after."""
    kept, filtered = apply_context_filter(trades, threshold=0.50, regime_default=regime_default)

    def equity_stats(tr):
        if not tr or len(tr) < 30: return None
        try:
            eq = build_equity_curve(tr, risk_pct=RISK_PCT_PER_TRADE)
            rets = daily_returns_from_equity(eq)
            if len(rets) < 30: return None
            sharpe = sharpe_from_daily_returns(rets)
            psr = psr_from_daily_returns(rets, sharpe_benchmark=0.0)
            dates = sorted(eq.keys())
            return {"n": len(tr), "sharpe": round(sharpe,3), "psr": round(psr,3),
                    "final_eq": round(eq[dates[-1]], 3),
                    "win_pct": round(sum(1 for t in tr if t["result_r"]>0)/len(tr)*100, 1)}
        except Exception as e:
            return {"error": str(e), "n": len(tr)}

    return {
        "before": equity_stats(trades),
        "after_filter": equity_stats(kept),
        "filtered_out_count": len(filtered),
        "kept_count": len(kept),
        "threshold": 0.50,
    }


def main():
    print("=" * 78)
    print("MCE Comparison: trades antes vs depois context filter")
    print("=" * 78)

    # Carrega whitelist Tier A LIVE
    files = sorted((ROOT/"journal").glob("per_asset_whitelist_*.json"),
                    key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        print("[err] sem whitelist"); return
    with open(files[0], "r", encoding="utf-8") as f: wl = json.load(f)

    targets = []
    for e in wl.get("TIER_A_LIVE", []):
        m = e.get("market")
        if m and "BITSTAMP" not in m: targets.append(m)
    print(f"Tier A LIVE markets: {targets}\n")

    all_results = []
    for market in targets:
        print(f"\n--- {market} ---")
        result = load_trades_for_market(market)
        if not result:
            print(f"  [skip] sem dados")
            continue
        # Pega trades do best config
        best = result.get("best")
        if not best: continue
        # entries detectados sao salvos; reconstruimos trades via simulate
        from entries_cache import detect_entries
        from simulate_from_entries import simulate_from_entries
        from constants import TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT
        candles_path = CANDLES_DIR / f"{market}_1day.json"
        entries_path = ENTRIES_DIR / f"entries_{market}.json"
        all_dicts_path = ENTRIES_DIR / f"alldicts_{market}.json"
        if not entries_path.exists() or not all_dicts_path.exists():
            print(f"  [skip] entries cache nao existe"); continue
        with open(entries_path, "r", encoding="utf-8") as f: entries = json.load(f)
        with open(all_dicts_path, "r", encoding="utf-8") as f: all_dicts = json.load(f)
        trades = simulate_from_entries(
            entries=entries, all_dicts=all_dicts,
            stop_atr=float(best["stop_atr"]), target_atr=float(best["target_atr"]),
            max_bars=14, fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
        )
        # Adiciona regime placeholder se nao tem (assumimos BULL_WEAK como default)
        for t in trades:
            if "regime" not in t: t["regime"] = "BULL_WEAK"
        print(f"  trades simulados: {len(trades)}")

        comp = compute_metrics_with_filter(trades)
        all_results.append({"market": market, "comparison": comp})

        b = comp.get("before"); a = comp.get("after_filter")
        if b and a:
            sh_delta = (a["sharpe"] - b["sharpe"])
            eq_delta_pct = ((a["final_eq"] - b["final_eq"]) / b["final_eq"] * 100) if b["final_eq"] > 0 else 0
            print(f"  BEFORE: n={b['n']:>4} sharpe={b['sharpe']:>+6.2f} win={b['win_pct']:>5.1f}% eq={b['final_eq']:>6.2f}x")
            print(f"  AFTER : n={a['n']:>4} sharpe={a['sharpe']:>+6.2f} win={a['win_pct']:>5.1f}% eq={a['final_eq']:>6.2f}x  (sharpe {sh_delta:+.2f}, eq {eq_delta_pct:+.1f}%)")
            print(f"  filtered: {comp['filtered_out_count']} trades (score<{comp['threshold']})")

    print(f"\n{'='*78}\nSUMARIO\n{'='*78}")
    for r in all_results:
        b = r["comparison"]["before"]; a = r["comparison"]["after_filter"]
        if not b or not a or "error" in str(b) or "error" in str(a): continue
        delta = round(a["sharpe"] - b["sharpe"], 2)
        verdict = "MELHOR" if delta > 0.1 else ("PIOR" if delta < -0.1 else "neutro")
        print(f"  {r['market']:<14} sharpe {b['sharpe']:+.2f} -> {a['sharpe']:+.2f}  delta={delta:+.2f}  ({verdict})")

    out_path = ROOT / "journal" / f"mce_comparison_{datetime.now().strftime('%Y_%m_%d')}.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"timestamp": datetime.now(timezone.utc).isoformat(),
                    "results": all_results}, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
