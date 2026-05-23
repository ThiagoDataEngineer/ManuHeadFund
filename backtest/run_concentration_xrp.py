"""run_concentration_xrp.py — análise de concentração XRP best params."""
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from entries_cache import detect_entries  # noqa: E402
from simulate_from_entries import simulate_from_entries  # noqa: E402
from trade_concentration import analyze_concentration  # noqa: E402
from constants import RISK_PCT_PER_TRADE, TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT  # noqa: E402

JOURNAL_DIR = ROOT_DIR / "journal"

# Best params XRP do grid search
BEST_CONFIGS = [
    ("stop1.0_target5.0_default", 1.0, 5.0),
    ("stop1.5_target3.0", 1.5, 3.0),
    ("stop1.5_target5.0", 1.5, 5.0),
    ("stop2.0_target3.0", 2.0, 3.0),
    ("stop2.0_target5.0_best", 2.0, 5.0),
]


def main():
    cache_path = JOURNAL_DIR / "entries_cache_xrp_2026_05_17.json"
    all_dicts_path = JOURNAL_DIR / "all_dicts_xrp_2026_05_17.json"
    if not cache_path.exists():
        print(f"[ERRO] Cache não encontrado: {cache_path}")
        sys.exit(1)
    with open(cache_path, "r", encoding="utf-8") as f:
        entries = json.load(f)
    with open(all_dicts_path, "r", encoding="utf-8") as f:
        all_dicts = json.load(f)
    print(f"[load] {len(entries)} entries XRP")

    results = []
    for label, stop_atr, target_atr in BEST_CONFIGS:
        print(f"\n=== {label} (stop={stop_atr}, target={target_atr}) ===")
        trades = simulate_from_entries(
            entries, all_dicts,
            stop_atr=stop_atr, target_atr=target_atr,
            max_bars=TB_MAX_BARS,
            fee_pct=TB_FEE_TAKER_PCT, slippage_pct=TB_SLIPPAGE_PCT,
        )
        an = analyze_concentration(trades, risk_pct=RISK_PCT_PER_TRADE)
        print(f"  verdict: {an['verdict']}")
        for f in an["concentration_flags"]:
            print(f"    flag: {f}")
        print(f"  gini: {an['gini_pnl']}")
        print(f"  top 1% trades = {an['top_1pct']['top_pct_of_total_log']}% do equity log")
        print(f"  top 5% trades = {an['top_5pct']['top_pct_of_total_log']}% do equity log")
        print(f"  top 10% trades = {an['top_10pct']['top_pct_of_total_log']}% do equity log")
        print(f"  max year contribution = {an['max_year_pct']}%")
        print(f"  total equity x = {an['top_1pct']['total_equity_x']}")
        years = an["annual_breakdown"]
        # Show top 3 years by contribution
        top_years = sorted(years, key=lambda y: y["pct_of_total"] or 0, reverse=True)[:5]
        print(f"  top 5 anos:")
        for y in top_years:
            print(f"    {y['year']}: {y['pct_of_total']}% ({y['n_trades']} trades, "
                  f"eq {y['equity_x']:.3f}x)")
        results.append({"label": label, "stop_atr": stop_atr, "target_atr": target_atr,
                         "analysis": an})

    out_path = JOURNAL_DIR / "xrp_concentration_analysis_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
