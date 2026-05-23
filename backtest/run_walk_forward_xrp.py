"""run_walk_forward_xrp.py — walk-forward purged CV nos best XRP configs."""
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from simulate_from_entries import simulate_from_entries  # noqa: E402
from walk_forward_purged import walk_forward_evaluate  # noqa: E402
from constants import RISK_PCT_PER_TRADE, TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT  # noqa: E402

JOURNAL_DIR = ROOT_DIR / "journal"

CONFIGS = [
    ("stop1.0_target5.0_default", 1.0, 5.0),
    ("stop1.5_target5.0", 1.5, 5.0),
    ("stop2.0_target3.0", 2.0, 3.0),
    ("stop2.0_target5.0_grid_best", 2.0, 5.0),
]


def main():
    cache = JOURNAL_DIR / "entries_cache_xrp_2026_05_17.json"
    ad = JOURNAL_DIR / "all_dicts_xrp_2026_05_17.json"
    with open(cache, "r", encoding="utf-8") as f:
        entries = json.load(f)
    with open(ad, "r", encoding="utf-8") as f:
        all_dicts = json.load(f)
    print(f"[load] {len(entries)} entries XRP")

    out_all = []
    for label, s, t in CONFIGS:
        print(f"\n=== {label} (stop={s}, target={t}) ===")
        trades = simulate_from_entries(entries, all_dicts,
                                        stop_atr=s, target_atr=t,
                                        max_bars=TB_MAX_BARS,
                                        fee_pct=TB_FEE_TAKER_PCT,
                                        slippage_pct=TB_SLIPPAGE_PCT)
        wf = walk_forward_evaluate(trades, k=5, embargo_days=7,
                                    risk_pct=RISK_PCT_PER_TRADE)
        print(f"  verdict: {wf['verdict']}")
        for fl in wf["flags"]:
            print(f"    flag: {fl}")
        is_m = wf["in_sample"]
        oos = wf["oos_summary"]
        print(f"  IS Sharpe={is_m.get('sharpe')} DSR={is_m.get('dsr')}")
        print(f"  OOS folds: mean Sharpe={oos['mean_test_sharpe']} "
              f"min={oos['min_test_sharpe']} max={oos['max_test_sharpe']}")
        print(f"  OOS positive: {oos['positive_sharpe_folds']}/{oos['total_folds']} folds")
        print(f"  per-fold:")
        for fr in wf["fold_results"]:
            tm = fr["test_metrics"]
            if tm.get("valid"):
                print(f"    fold {fr['fold_idx']}: test {fr['test_period'][0]}→{fr['test_period'][1]} "
                      f"n_test={fr['n_test']} Sharpe={tm['sharpe']} mean_r={tm['mean_r']} "
                      f"eq={tm['final_equity']:.3f}x")
            else:
                print(f"    fold {fr['fold_idx']}: INVALID n_test={fr['n_test']}")

        out_all.append({"label": label, "stop_atr": s, "target_atr": t,
                         "walk_forward": wf})

    out_path = JOURNAL_DIR / "xrp_walk_forward_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out_all, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
