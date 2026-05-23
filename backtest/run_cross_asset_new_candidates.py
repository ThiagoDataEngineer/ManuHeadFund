"""
run_cross_asset_new_candidates.py -- Matrix focada nos 6 novos candidatos.
NEAR, INJ, DASH, TAO, ATOM, TIA -- avaliar se passam Sharpe >= 1.5 + DSR/PSR.
"""
import json, sys
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

from run_cross_asset_matrix import process_pair

CANDLES_DIR = ROOT_DIR / "journal" / "candles_coinex"
MARKETS = ["NEARUSDT","INJUSDT","DASHUSDT","TAOUSDT","ATOMUSDT","TIAUSDT"]

results = []
for m in MARKETS:
    candles_path = CANDLES_DIR / f"{m}_1day.json"
    if not candles_path.exists():
        print(f"[skip] {m} sem candles_path")
        continue
    try:
        r = process_pair(m, candles_path)
        results.append(r)
    except Exception as e:
        print(f"[err] {m}: {e}")
        results.append({"market": m, "error": str(e)})

print(f"\n{'='*78}\nRANKING NOVOS CANDIDATOS\n{'='*78}")
ranked = [r for r in results if r.get("best")]
ranked.sort(key=lambda r: r["best"]["sharpe"], reverse=True)
print(f"{'Market':12s} {'s/t':10s} {'Sharpe':>8s} {'DSR':>6s} {'PSR':>6s} {'Win%':>6s} {'mR':>7s} {'eq':>10s} {'PASS/N':>8s} {'PBO':>6s} {'WF+':>6s}")
for r in ranked:
    b = r["best"]
    pbo_str = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
    wf_str = "-"
    if r.get("walk_forward"):
        oos = r["walk_forward"]["oos_summary"]
        wf_str = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
    print(f"{r['market']:12s} s{b['stop_atr']}/t{b['target_atr']:<6}  "
          f"{b['sharpe']:>+7.2f} {b['dsr']:>6.2f} {b['psr']:>6.2f} "
          f"{b['win_rate_pct']:>5.1f}% {b['mean_r']:>+6.2f} {b['final_equity']:>9.2f}x "
          f"{r['n_pass']:>2}/{r['n_configs']:>2}  {pbo_str:>6s} {wf_str:>6s}")

# Tier categorization
print(f"\n{'='*78}\nVEREDICTO TIER\n{'='*78}")
for r in ranked:
    b = r["best"]
    sharpe = b["sharpe"]; dsr = b["dsr"]; psr = b["psr"]
    pbo = r["pbo"]["pbo"] if r.get("pbo") and r["pbo"].get("pbo") is not None else 1.0
    wf_pos = 0; wf_total = 0
    if r.get("walk_forward"):
        oos = r["walk_forward"]["oos_summary"]
        wf_pos = oos["positive_sharpe_folds"]; wf_total = oos["total_folds"]
    if sharpe >= 1.5 and dsr >= 0.95 and psr >= 0.95 and pbo < 0.4 and (wf_pos >= 3 if wf_total > 0 else True):
        verdict = "TIER A LIVE"
    elif sharpe >= 1.0 and pbo < 0.5:
        verdict = "TIER B PAPER"
    else:
        verdict = "TIER C SKIP"
    print(f"  {r['market']:12s} -> {verdict}  (sharpe={sharpe:.2f} dsr={dsr:.2f} psr={psr:.2f} pbo={pbo:.2f} wf={wf_pos}/{wf_total})")

out_path = ROOT_DIR / "journal" / "new_candidates_matrix_2026_05_18.json"
with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "results": results}, f, indent=2, ensure_ascii=False)
print(f"\n[save] {out_path.name}")
