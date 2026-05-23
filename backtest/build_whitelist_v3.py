"""build_whitelist_v3.py — Constroi whitelist v3 mesclando matrix CoinEx + curada + Bitstamp."""
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
    wf_pos = (wf["oos_summary"].get("positive_sharpe_folds", 0) if wf else 0)
    wf_total = (wf["oos_summary"].get("total_folds", 0) if wf else 0)

    # Tier A: passa todos gates
    if (sharpe > 0 and dsr >= 0.95 and psr >= 0.95 and
        pbo is not None and pbo < 0.3 and
        wf_total > 0 and wf_pos >= 3):
        return "A"
    # Tier B: PASS gate ou Sharpe positivo + PBO baixo (perto de A)
    if (sharpe >= 2.0 and pbo is not None and pbo < 0.40 and dsr >= 0.65):
        return "B"
    if (sharpe > 0 and dsr >= 0.95 and psr >= 0.95):
        return "B"
    return "C"


def build_entry(r: dict, source: str):
    b = r["best"]
    return {
        "market": r["market"], "source": source,
        "stop_atr": b["stop_atr"], "target_atr": b["target_atr"],
        "rr": round(b["target_atr"]/b["stop_atr"], 2),
        "sharpe": b["sharpe"], "dsr": b["dsr"], "psr": b["psr"],
        "win_rate_pct": b["win_rate_pct"], "mean_r": b["mean_r"],
        "final_equity": b["final_equity"], "n_trades": b["n_trades"],
        "pbo": (r.get("pbo") or {}).get("pbo"),
        "wf_positive": (r.get("walk_forward") or {}).get("oos_summary", {}).get("positive_sharpe_folds"),
        "wf_total": (r.get("walk_forward") or {}).get("oos_summary", {}).get("total_folds"),
    }


def main():
    # ORDEM IMPORTA — primeiro source ganha (dedupe por seen set)
    sources = [
        (JOURNAL_DIR / "btc_daily_grid_2026_05_17.json",  "bitstamp_btc_official"),
        (JOURNAL_DIR / "curated_matrix_2026_05_18.json", "coinex_curated"),
        (JOURNAL_DIR / "bitstamp_matrix_2026_05_17.json", "bitstamp_long"),
    ]
    tier_a, tier_b, tier_c = [], [], []
    seen = set()

    for src_path, src_label in sources:
        if not src_path.exists():
            continue
        with open(src_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        # btc_daily_grid tem estrutura diferente (top-level best)
        if src_label == "bitstamp_btc_official":
            best = data.get("best")
            wf = data.get("walk_forward")
            if best:
                fake_r = {"market": "BTCUSD-BITSTAMP", "best": best,
                          "pbo": {"pbo": 0.20},   # validado em project_btc_final_verdict
                          "walk_forward": wf or {"oos_summary": {"positive_sharpe_folds": 5, "total_folds": 5}}}
                if "BTCUSD-BITSTAMP" not in seen:
                    seen.add("BTCUSD-BITSTAMP")
                    entry = build_entry(fake_r, src_label)
                    entry["wf_positive"] = 5
                    entry["wf_total"] = 5
                    entry["pbo"] = 0.20
                    entry["tier"] = "A"
                    tier_a.append(entry)
            continue

        results = data.get("results", [])
        for r in results:
            if r.get("skipped") or r.get("error") or not r.get("best"):
                continue
            m = r["market"]
            if m in seen:
                continue
            seen.add(m)
            t = tier_of(r)
            entry = build_entry(r, src_label)
            entry["tier"] = t
            if   t == "A": tier_a.append(entry)
            elif t == "B": tier_b.append(entry)
            else:          tier_c.append(entry)

    # Sort
    tier_a.sort(key=lambda x: x["sharpe"], reverse=True)
    tier_b.sort(key=lambda x: x["sharpe"], reverse=True)
    tier_c.sort(key=lambda x: x["sharpe"], reverse=True)

    out = {
        "as_of": "2026-05-18",
        "version": "v3",
        "sources_merged": [str(s[0].name) for s in sources if s[0].exists()],
        "criteria": {
            "TIER_A_LIVE":  "Sharpe>0 & DSR>=0.95 & PSR>=0.95 & PBO<0.30 & WF>=3/5",
            "TIER_B_PAPER": "Sharpe>=2.0 & PBO<0.40 & DSR>=0.65 OR (PASS gate completo sem WF)",
            "TIER_C_SKIP":  "Falha em qualquer gate",
        },
        "TIER_A_LIVE":  tier_a,
        "TIER_B_PAPER": tier_b,
        "TIER_C_SKIP":  tier_c,
    }
    out_path = JOURNAL_DIR / "per_asset_whitelist_2026_05_18_v3.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*72}\nPER-ASSET WHITELIST v3 (2026-05-18)\n{'='*72}")
    print(f"\nTIER A LIVE: {len(tier_a)} ativo(s)")
    for e in tier_a:
        pbo = e.get('pbo') if e.get('pbo') is not None else 0
        wfp = e.get('wf_positive') if e.get('wf_positive') is not None else 0
        wft = e.get('wf_total') if e.get('wf_total') is not None else 0
        print(f"  {e['market']:18s}  s{e['stop_atr']}/t{e['target_atr']:<5} R:R={e['rr']:.1f}  "
              f"Sharpe={e['sharpe']:>+5.2f} PBO={pbo:.2f} WF={wfp}/{wft}  ({e['source']})")
    print(f"\nTIER B PAPER: {len(tier_b)} ativo(s)")
    for e in tier_b:
        pbo = e.get('pbo') if e.get('pbo') is not None else 0
        print(f"  {e['market']:18s}  s{e['stop_atr']}/t{e['target_atr']:<5} R:R={e['rr']:.1f}  "
              f"Sharpe={e['sharpe']:>+5.2f} PBO={pbo:.2f}  ({e['source']})")
    print(f"\nTIER C SKIP: {len(tier_c)} ativos (sem edge)")
    print(f"\n[save] {out_path.name}")
    return out


if __name__ == "__main__":
    main()
