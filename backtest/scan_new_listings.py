"""
scan_new_listings.py -- Detecta ultimos N new listings CoinEx + matrix.

Logica:
1. Fetch all tickers
2. Para cada USDT com vol >= MIN_VOL: pega kline depth
3. New listing = kline count entre MIN_DAYS (50) e MAX_DAYS (250) -- jovem mas com sample
4. Ordena por mais recente (menor kline count)
5. Pega top N e roda cross_asset_matrix
6. Outputs: tier verdict per market
"""
import json, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen
from concurrent.futures import ThreadPoolExecutor, as_completed

SCRIPT = Path(__file__).resolve().parent
ROOT = SCRIPT.parent
sys.path.insert(0, str(SCRIPT))

CANDLES_DIR = ROOT / "journal" / "candles_coinex"
CANDLES_DIR.mkdir(parents=True, exist_ok=True)

MIN_VOL = 30_000          # listing tem que ter algum vol pra ser tradeavel
MIN_DAYS = 50             # min sample pra ter pelo menos chance de 30 trades
MAX_DAYS = 250            # acima disso nao e "new listing"
TOP_N = 10                # quantos testar


def fetch(url, timeout=15):
    try:
        with urlopen(Request(url, headers={"User-Agent":"nl/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def get_klines_count(market):
    """Conta kline daily disponivel. New listing = pouca historia."""
    d = fetch(f"https://api.coinex.com/v2/spot/kline?market={market}&period=1day&limit=1000")
    data = d.get("data") or []
    return len(data), data


def collect_and_save(market, data):
    if not data: return False
    candles = [{"ts": k.get("created_at"), "open":float(k["open"]),"high":float(k["high"]),"low":float(k["low"]),"close":float(k["close"]),"volume":float(k.get("volume",0))} for k in data]
    candles.sort(key=lambda x: x["ts"])
    for c in candles:
        if isinstance(c["ts"], (int,float)):
            c["ts"] = datetime.fromtimestamp(int(c["ts"])/1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    path = CANDLES_DIR / f"{market}_1day.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(candles, f, ensure_ascii=False)
    return True


def main():
    print("=" * 70)
    print("Scan New Listings + Matrix")
    print("=" * 70)
    t0 = time.time()

    print("[1] Fetching all tickers...")
    d = fetch("https://api.coinex.com/v2/spot/ticker")
    tickers = d.get("data") or []
    usdt = [t for t in tickers if t["market"].endswith("USDT") and float(t.get("value",0)) >= MIN_VOL]
    print(f"    {len(usdt)} USDT vol >= ${MIN_VOL:,.0f}")

    print(f"[2] Checking kline depth (parallel)...")
    candidates = []  # (market, days_count, vol)
    with ThreadPoolExecutor(max_workers=24) as ex:
        futs = {ex.submit(get_klines_count, t["market"]): (t["market"], float(t.get("value",0))) for t in usdt}
        for f in as_completed(futs):
            mkt, vol = futs[f]
            try:
                cnt, _ = f.result()
                if MIN_DAYS <= cnt <= MAX_DAYS:
                    candidates.append((mkt, cnt, vol))
            except Exception as e:
                pass

    candidates.sort(key=lambda x: x[1])  # menor count primeiro (mais novo)
    new_listings = candidates[:TOP_N]
    print(f"    {len(candidates)} new-listing candidates encontrados, testando top {len(new_listings)}:")
    for m, d, v in new_listings:
        print(f"      {m:<14} kline={d:>4}d  vol=${v/1e3:.0f}K")

    print(f"\n[3] Collect candles + run matrix...")
    from run_cross_asset_matrix import process_pair

    results = []
    for m, days, vol in new_listings:
        print(f"\n--- {m} ({days}d) ---")
        # Re-fetch + save
        _, raw = get_klines_count(m)
        collect_and_save(m, raw)
        try:
            r = process_pair(m, CANDLES_DIR / f"{m}_1day.json")
            r["listing_days"] = days
            r["vol_24h"] = vol
            results.append(r)
        except Exception as e:
            print(f"  err: {e}")
            results.append({"market": m, "error": str(e), "listing_days": days})

    elapsed = time.time() - t0
    print(f"\n[done] {elapsed:.1f}s | {len(results)} markets testados")

    print(f"\n{'='*70}\nRANKING NEW LISTINGS\n{'='*70}")
    ranked = [r for r in results if r.get("best")]
    ranked.sort(key=lambda r: r["best"]["sharpe"], reverse=True)
    for r in ranked:
        b = r["best"]
        pbo = (f"{r['pbo']['pbo']:.2f}" if r.get("pbo") and r["pbo"].get("pbo") is not None else "-")
        wf = "-"
        if r.get("walk_forward"):
            oos = r["walk_forward"]["oos_summary"]
            wf = f"{oos['positive_sharpe_folds']}/{oos['total_folds']}"
        print(f"  {r['market']:<14} kline={r.get('listing_days','?'):>4}d  Sharpe={b['sharpe']:>+6.2f} DSR={b['dsr']:>5.2f} PBO={pbo:>5s} WF={wf:>4s} eq={b['final_equity']:>6.2f}x")

    print(f"\n=== VEREDICTO ===")
    tier_buckets = {"A":[], "B":[], "C":[]}
    for r in ranked:
        b = r["best"]; sh = b["sharpe"]; dsr = b["dsr"]; psr = b["psr"]
        pbo = r["pbo"]["pbo"] if r.get("pbo") and r["pbo"].get("pbo") is not None else 1.0
        wf_pos = 0; wf_tot = 0
        if r.get("walk_forward"):
            oos = r["walk_forward"]["oos_summary"]; wf_pos = oos["positive_sharpe_folds"]; wf_tot = oos["total_folds"]
        if sh >= 1.5 and dsr >= 0.95 and psr >= 0.95 and pbo < 0.30 and (wf_pos >= 3 if wf_tot > 0 else False):
            tier_buckets["A"].append(r["market"])
        elif sh >= 2.0 and dsr >= 0.65 and pbo < 0.4:
            tier_buckets["B"].append(r["market"])
        else:
            tier_buckets["C"].append(r["market"])
    for t in ("A","B","C"):
        if tier_buckets[t]:
            print(f"  TIER {t}: {tier_buckets[t]}")

    out_path = ROOT / "journal" / f"new_listings_scan_{datetime.now().strftime('%Y_%m_%d')}.json"
    out = {"timestamp": datetime.now(timezone.utc).isoformat(),
            "candidates_tested": [m for m,_,_ in new_listings],
            "results": results, "tier_a": tier_buckets["A"], "tier_b": tier_buckets["B"], "tier_c": tier_buckets["C"]}
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path.name}")


if __name__ == "__main__":
    main()
