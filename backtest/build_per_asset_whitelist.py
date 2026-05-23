"""
build_per_asset_whitelist.py — Extrai best params por ativo + filtra por gate completo.

Lê cross_asset_matrix_2026_05_17.json e produz:
  journal/per_asset_whitelist_2026_05_17.json

Estrutura output:
  {
    "TIER_A_LIVE":  [{market, stop_atr, target_atr, ...}, ...],   # passa todos gates
    "TIER_B_PAPER": [{...}, ...],                                  # PASS Sharpe+DSR mas frágil
    "TIER_C_SKIP":  [{...}, ...],                                  # FAIL
  }
"""
import json
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
JOURNAL_DIR = ROOT_DIR / "journal"


def tier_of(r: dict) -> str:
    b = r.get("best")
    if not b: return "C"
    sharpe = b.get("sharpe", 0)
    dsr = b.get("dsr", 0)
    psr = b.get("psr", 0)
    pbo = (r.get("pbo") or {}).get("pbo")
    wf = r.get("walk_forward")
    wf_pos = 0
    wf_total = 0
    if wf:
        wf_pos = wf["oos_summary"].get("positive_sharpe_folds", 0)
        wf_total = wf["oos_summary"].get("total_folds", 0)

    # TIER A: passa Sharpe+DSR+PSR + PBO<0.3 + WF>=3/5
    if (sharpe > 0 and dsr >= 0.95 and psr >= 0.95 and
        pbo is not None and pbo < 0.3 and
        wf_total > 0 and wf_pos >= 3):
        return "A"
    # TIER B: PASS no Sharpe/DSR mas frágil em PBO ou WF
    if sharpe > 0 and dsr >= 0.95 and psr >= 0.95:
        return "B"
    return "C"


def main():
    src = JOURNAL_DIR / "cross_asset_matrix_2026_05_17.json"
    if not src.exists():
        print(f"[ERRO] {src} nao encontrado")
        sys.exit(1)
    with open(src, "r", encoding="utf-8") as f:
        data = json.load(f)

    tier_a, tier_b, tier_c = [], [], []
    for r in data["results"]:
        if r.get("skipped") or r.get("error") or not r.get("best"):
            continue
        b = r["best"]
        entry = {
            "market": r["market"],
            "stop_atr": b["stop_atr"], "target_atr": b["target_atr"],
            "rr": round(b["target_atr"] / b["stop_atr"], 2),
            "sharpe": b["sharpe"], "dsr": b["dsr"], "psr": b["psr"],
            "win_rate_pct": b["win_rate_pct"], "mean_r": b["mean_r"],
            "final_equity": b["final_equity"],
            "n_trades": b["n_trades"],
            "pbo": (r.get("pbo") or {}).get("pbo"),
            "wf_positive_folds": (r.get("walk_forward") or {}).get("oos_summary", {}).get("positive_sharpe_folds"),
            "wf_total_folds": (r.get("walk_forward") or {}).get("oos_summary", {}).get("total_folds"),
        }
        t = tier_of(r)
        entry["tier"] = t
        if   t == "A": tier_a.append(entry)
        elif t == "B": tier_b.append(entry)
        else:          tier_c.append(entry)

    tier_a.sort(key=lambda x: x["sharpe"], reverse=True)
    tier_b.sort(key=lambda x: x["sharpe"], reverse=True)
    tier_c.sort(key=lambda x: x["sharpe"], reverse=True)

    out = {
        "as_of": "2026-05-17",
        "source": "cross_asset_matrix_2026_05_17.json",
        "criteria": {
            "TIER_A_LIVE":  "Sharpe>0 & DSR>=0.95 & PSR>=0.95 & PBO<0.3 & WF>=3/5",
            "TIER_B_PAPER": "Sharpe>0 & DSR>=0.95 & PSR>=0.95 (mas PBO/WF frágil)",
            "TIER_C_SKIP":  "Falha em qualquer gate",
        },
        "TIER_A_LIVE":  tier_a,
        "TIER_B_PAPER": tier_b,
        "TIER_C_SKIP":  tier_c,
    }
    out_path = JOURNAL_DIR / "per_asset_whitelist_2026_05_17.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*72}\nPER-ASSET WHITELIST 2026-05-17\n{'='*72}")
    print(f"\nTIER A (LIVE — passa todos gates): {len(tier_a)} ativo(s)")
    for e in tier_a:
        print(f"  {e['market']:10s}  stop={e['stop_atr']} target={e['target_atr']} R:R={e['rr']:.1f}  "
              f"Sharpe={e['sharpe']:.2f} PBO={e['pbo']:.2f} WF={e['wf_positive_folds']}/{e['wf_total_folds']}")
    print(f"\nTIER B (PAPER — robust mas frágil): {len(tier_b)} ativo(s)")
    for e in tier_b:
        pbo = e['pbo'] if e['pbo'] is not None else 0
        wf_p = e['wf_positive_folds'] if e['wf_positive_folds'] is not None else 0
        wf_t = e['wf_total_folds'] if e['wf_total_folds'] is not None else 0
        print(f"  {e['market']:10s}  stop={e['stop_atr']} target={e['target_atr']} R:R={e['rr']:.1f}  "
              f"Sharpe={e['sharpe']:.2f} PBO={pbo:.2f} WF={wf_p}/{wf_t}")
    print(f"\nTIER C (SKIP — sem edge): {len(tier_c)} ativo(s)")
    for e in tier_c:
        print(f"  {e['market']:10s}  Sharpe={e['sharpe']:>+6.2f}")

    print(f"\n[save] {out_path.name}")
    return out


if __name__ == "__main__":
    main()
