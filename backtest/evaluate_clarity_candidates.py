"""Avalia ONDO/CFG/DYDX/BERA via collect + cross_asset_matrix."""
import json, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

SCRIPT = Path(__file__).resolve().parent
ROOT = SCRIPT.parent
sys.path.insert(0, str(SCRIPT))

CANDLES_DIR = ROOT / "journal" / "candles_coinex"

def fetch(url, timeout=15):
    with urlopen(Request(url, headers={"User-Agent":"e/1"}), timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def collect(market):
    path = CANDLES_DIR / f"{market}_1day.json"
    if path.exists():
        with open(path,"r",encoding="utf-8") as f:
            existing = json.load(f)
        if len(existing) >= 250: return existing
    all_c = []
    end_ts = None
    for p in range(5):
        url = f"https://api.coinex.com/v2/spot/kline?market={market}&period=1day&limit=1000"
        if end_ts: url += f"&end_time={end_ts}"
        try:
            d = fetch(url)
            data = d.get("data") or []
            if not data: break
            for k in data:
                all_c.append({"ts":k.get("created_at"),"open":float(k["open"]),"high":float(k["high"]),"low":float(k["low"]),"close":float(k["close"]),"volume":float(k.get("volume",0))})
            if len(data)<1000: break
            end_ts = data[0].get("created_at")
            time.sleep(0.3)
        except Exception as e:
            print(f"  err: {e}"); break
    seen=set(); dedup=[]
    for c in all_c:
        if c["ts"] not in seen:
            seen.add(c["ts"]); dedup.append(c)
    dedup.sort(key=lambda x:x["ts"])
    for c in dedup:
        if isinstance(c["ts"],(int,float)):
            c["ts"] = datetime.fromtimestamp(int(c["ts"])/1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    with open(path,"w",encoding="utf-8") as f:
        json.dump(dedup, f, ensure_ascii=False)
    return dedup


MARKETS = ["ONDOUSDT","CFGUSDT","DYDXUSDT","BERAUSDT"]

print("=" * 70)
print("Avaliacao CLARITY Act candidates")
print("=" * 70)

for m in MARKETS:
    print(f"\n--- {m} ---")
    cs = collect(m)
    print(f"  candles: {len(cs)}")

from run_cross_asset_matrix import process_pair

results = []
for m in MARKETS:
    cp = CANDLES_DIR / f"{m}_1day.json"
    if not cp.exists():
        print(f"\n[skip] {m} sem candles")
        continue
    try:
        r = process_pair(m, cp)
        results.append(r)
    except Exception as e:
        print(f"  err matrix: {e}")
        results.append({"market":m,"error":str(e)})

print(f"\n{'='*70}\nRANKING\n{'='*70}")
ranked=[r for r in results if r.get("best")]
ranked.sort(key=lambda r:r["best"]["sharpe"], reverse=True)
for r in ranked:
    b=r["best"]
    pbo = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
    wf = "-"
    if r.get("walk_forward"):
        oos = r["walk_forward"]["oos_summary"]
        wf = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
    print(f"  {r['market']:10s} Sharpe={b['sharpe']:>+6.2f} DSR={b['dsr']:>5.2f} PSR={b['psr']:>5.2f} PBO={pbo:>5s} WF={wf:>5s} eq={b['final_equity']:>7.2f}x s{b['stop_atr']}/t{b['target_atr']}")

print(f"\n=== VEREDICTO ===")
for r in ranked:
    b=r["best"]; sh=b["sharpe"]; dsr=b["dsr"]; psr=b["psr"]
    pbo=r["pbo"]["pbo"] if r.get("pbo") and r["pbo"].get("pbo") is not None else 1.0
    wf_pos=0; wf_tot=0
    if r.get("walk_forward"):
        oos=r["walk_forward"]["oos_summary"]; wf_pos=oos["positive_sharpe_folds"]; wf_tot=oos["total_folds"]
    if sh>=1.5 and dsr>=0.95 and psr>=0.95 and pbo<0.30 and (wf_pos>=3 if wf_tot>0 else False):
        v="TIER A LIVE"
    elif sh>=2.0 and dsr>=0.65 and pbo<0.4:
        v="TIER B PAPER"
    else:
        v="TIER C SKIP"
    print(f"  {r['market']:10s} -> {v}")
