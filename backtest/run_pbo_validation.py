"""run_pbo_validation.py — Aplica PBO/CSCV em grids existentes.

XRP hourly grid + BTC daily grid são os principais candidatos a edge.
Gate científico final: PBO > 0.5 = overfit. PBO < 0.5 = robusto.
"""
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from pbo_cscv import pbo_score, build_period_matrix
from simulate_from_entries import simulate_from_entries
from constants import TB_MAX_BARS, TB_FEE_TAKER_PCT, TB_SLIPPAGE_PCT, RISK_PCT_PER_TRADE

JOURNAL_DIR = ROOT_DIR / "journal"


def run_pbo_for_asset(asset_label: str, entries_cache_path: Path,
                      all_dicts_path: Path,
                      grid_stops: list, grid_targets: list,
                      max_bars: int = TB_MAX_BARS, n_periods: int = 6) -> dict:
    print(f"\n{'='*68}\nPBO/CSCV — {asset_label}\n{'='*68}")

    with open(entries_cache_path, "r", encoding="utf-8") as f:
        entries = json.load(f)
    with open(all_dicts_path, "r", encoding="utf-8") as f:
        all_dicts = json.load(f)
    print(f"[load] {len(entries)} entries, simulando {len(grid_stops)}x{len(grid_targets)} configs")

    trades_per_config = {}
    for s in grid_stops:
        for t in grid_targets:
            label = f"s{s}_t{t}"
            trades = simulate_from_entries(
                entries, all_dicts, stop_atr=s, target_atr=t,
                max_bars=max_bars, fee_pct=TB_FEE_TAKER_PCT,
                slippage_pct=TB_SLIPPAGE_PCT,
            )
            if len(trades) >= 30:
                trades_per_config[label] = trades

    print(f"[sim] {len(trades_per_config)} configs válidos (>=30 trades cada)")

    pm = build_period_matrix(trades_per_config, n_periods=n_periods,
                              risk_pct=RISK_PCT_PER_TRADE)
    if not pm.get("valid"):
        print(f"[ERRO] {pm}")
        return {"valid": False}

    print(f"[matrix] {pm['n_configs']} configs × {pm['n_periods']} períodos")
    print(f"[periods]")
    for i, (s, e) in enumerate(pm["periods"]):
        print(f"  P{i}: {s} → {e}")

    pbo = pbo_score(pm["matrix"])
    print(f"\n[PBO] {pbo['verdict']}")
    print(f"  pbo={pbo['pbo']} | combinacoes={pbo['n_combinations']} | "
          f"mean_lambda={pbo['mean_lambda']}")

    # IS vs OOS scatter (cada config)
    print(f"\n[per-config Sharpes por período]")
    for c_idx, label in enumerate(pm["labels"]):
        row = pm["matrix"][c_idx]
        avg = sum(row) / len(row) if row else 0
        print(f"  {label:15s} avg={avg:>6.3f}  " +
              " ".join(f"P{i}:{v:>+5.2f}" for i, v in enumerate(row)))

    return {
        "asset": asset_label,
        "n_configs": pm["n_configs"],
        "n_periods": pm["n_periods"],
        "periods": pm["periods"],
        "labels": pm["labels"],
        "matrix": pm["matrix"],
        "pbo": pbo,
    }


def main():
    results = {}

    # XRP hourly grid (já cached entries)
    xrp_e = JOURNAL_DIR / "entries_cache_xrp_2026_05_17.json"
    xrp_a = JOURNAL_DIR / "all_dicts_xrp_2026_05_17.json"
    if xrp_e.exists() and xrp_a.exists():
        results["xrp_hourly"] = run_pbo_for_asset(
            "XRP hourly", xrp_e, xrp_a,
            grid_stops=[0.5, 1.0, 1.5, 2.0],
            grid_targets=[1.0, 2.0, 3.0, 5.0],
            max_bars=168,
        )

    # BTC daily grid
    btc_e = JOURNAL_DIR / "entries_btc_daily_2026_05_17.json"
    btc_a = JOURNAL_DIR / "all_dicts_btc_daily_2026_05_17.json"
    if btc_e.exists() and btc_a.exists():
        results["btc_daily"] = run_pbo_for_asset(
            "BTC daily", btc_e, btc_a,
            grid_stops=[1.0, 1.5, 2.0, 3.0],
            grid_targets=[2.0, 3.0, 5.0, 7.0],
            max_bars=14,
        )

    out_path = JOURNAL_DIR / "pbo_validation_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")

    print(f"\n{'='*68}\nSUMÁRIO PBO/CSCV\n{'='*68}")
    for label, r in results.items():
        if r.get("pbo"):
            p = r["pbo"]
            print(f"{label:15s}: {p['verdict']}  (PBO={p['pbo']}, n={r['n_configs']}c×{r['n_periods']}p)")


if __name__ == "__main__":
    main()
