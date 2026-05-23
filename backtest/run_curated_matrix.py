"""run_curated_matrix.py — Matrix triple barrier nos 21 markets curados (Tier 3 expansion)."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from run_cross_asset_matrix import process_pair

JOURNAL_DIR = ROOT_DIR / "journal"
CANDLES_DIR = JOURNAL_DIR / "candles_coinex"


def main():
    summary = JOURNAL_DIR / "candles_coinex" / "summary_curated_1day.json"
    with open(summary, "r", encoding="utf-8") as f:
        data = json.load(f)

    pairs = data.get("pairs", [])
    print(f"[load] {len(pairs)} pares para matrix")

    all_results = []
    for p in pairs:
        market = p["market"]
        candles_path = CANDLES_DIR / f"{market}_1day.json"
        try:
            r = process_pair(market, candles_path)
            all_results.append(r)
        except Exception as e:
            print(f"[ERRO] {market}: {e}")
            all_results.append({"market": market, "error": str(e)})

    # Ranking
    print(f"\n{'='*88}\nRANKING CURATED MATRIX (TIER 3) — por best Sharpe\n{'='*88}")
    ranked = [r for r in all_results if r.get("best")]
    ranked.sort(key=lambda r: r["best"]["sharpe"], reverse=True)
    print(f"{'Market':14s} {'Best (s/t)':14s} {'Sharpe':>8s} {'DSR':>6s} {'PSR':>6s} "
          f"{'Win%':>6s} {'mR':>7s} {'eq':>10s} {'PASS/N':>8s} {'PBO':>6s} {'WF+':>6s}")
    for r in ranked:
        b = r["best"]
        pbo_str = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
        wf_str = "-"
        if r.get("walk_forward"):
            oos = r["walk_forward"]["oos_summary"]
            wf_str = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
        print(f"{r['market']:14s} s{b['stop_atr']}/t{b['target_atr']:<7}  "
              f"{b['sharpe']:>+7.2f} {b['dsr']:>6.2f} {b['psr']:>6.2f} "
              f"{b['win_rate_pct']:>5.1f}% {b['mean_r']:>+6.2f} {b['final_equity']:>9.2f}x "
              f"{r['n_pass']:>2}/{r['n_configs']:>2}  {pbo_str:>6s} {wf_str:>6s}")

    out_path = JOURNAL_DIR / "curated_matrix_2026_05_18.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "results": all_results}, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
