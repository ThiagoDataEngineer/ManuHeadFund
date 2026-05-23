"""
snapshot_all_coinex.py — Snapshot universo CoinEx inteiro.

1. Pega todos tickers de uma vez (/spot/tickers)
2. Filtra por volume USDT > MIN_VOL pra cortar dust
3. Em paralelo busca klines daily pros top N por volume
4. Computa regime + momentum
5. Ranking por interesse: top movers (24h), top regimes BULL_STRONG, BEAR colapsando
"""
from __future__ import annotations
import json, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import Request, urlopen

COINEX = "https://api.coinex.com/v2/spot"
MIN_VOL_USDT = 50_000    # cortar dust < $50k volume 24h
KLINE_TOP_N = 200        # top N por volume pra fetch kline
WORKERS = 24


def fetch(url, timeout=10):
    try:
        with urlopen(Request(url, headers={"User-Agent":"snap/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def get_all_tickers():
    d = fetch(f"{COINEX}/ticker")
    return d.get("data") or []


def get_kline_daily(market, n=210):
    d = fetch(f"{COINEX}/kline?market={market}&period=1day&limit={n}")
    return d.get("data") or []


def regime(closes):
    if len(closes) < 200: return ("NO_HIST", None, None)
    sma200 = sum(closes[-200:]) / 200
    cur = closes[-1]
    dist = (cur - sma200) / sma200
    mom20 = (closes[-1] - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
    if dist > 0.20 and mom20 > 0.10:   label = "BULL_STRONG"
    elif dist > 0 and mom20 > 0:         label = "BULL_WEAK"
    elif dist < -0.20 and mom20 < -0.10: label = "BEAR_STRONG"
    elif dist < 0 and mom20 < 0:         label = "BEAR_WEAK"
    elif abs(dist) < 0.05:               label = "SIDEWAYS"
    else:                                  label = "TRANSITION"
    return (label, dist, mom20)


def analyze(t):
    m = t["market"]
    last = float(t.get("last", 0))
    op   = float(t.get("open", 0))
    val  = float(t.get("value", 0))
    pct24 = ((last - op) / op * 100) if op > 0 else 0
    kl = get_kline_daily(m)
    closes = [float(k["close"]) for k in kl]
    label, dist, mom20 = regime(closes)
    return {"market": m, "price": last, "pct24": pct24, "vol": val,
            "regime": label, "dist": dist, "mom20": mom20, "hist": len(closes)}


def main():
    t0 = time.time()
    print("[1/3] fetching all CoinEx tickers...")
    tickers = get_all_tickers()
    print(f"      {len(tickers)} markets total\n")

    # Filtrar por volume + apenas USDT (universo trabalhavel)
    usdt = [t for t in tickers if t["market"].endswith("USDT")
            and float(t.get("value", 0)) >= MIN_VOL_USDT]
    usdt.sort(key=lambda x: float(x["value"]), reverse=True)
    top = usdt[:KLINE_TOP_N]
    print(f"[2/3] {len(usdt)} markets USDT vol>${MIN_VOL_USDT:,.0f}; analisando top {len(top)} em paralelo...\n")

    results = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(analyze, t): t["market"] for t in top}
        for f in as_completed(futs):
            try: results.append(f.result())
            except Exception as e: print(f"  err {futs[f]}: {e}")

    elapsed = time.time() - t0
    print(f"[3/3] done {elapsed:.1f}s | {len(results)} analisados\n")

    # Buckets
    bull_strong = [r for r in results if r["regime"] == "BULL_STRONG"]
    bear_strong = [r for r in results if r["regime"] == "BEAR_STRONG"]
    big_pump    = [r for r in results if r["pct24"] >= 3]
    big_dump    = [r for r in results if r["pct24"] <= -3]
    no_hist     = [r for r in results if r["regime"] == "NO_HIST"]

    def fmt(r):
        dist = f"{r['dist']:+.1%}" if r['dist'] is not None else "?"
        mom = f"{r['mom20']:+.1%}" if r['mom20'] is not None else "?"
        return f"  {r['market']:<14} ${r['price']:>11.4f} 24h={r['pct24']:>+6.2f}% vol=${r['vol']/1e6:>6.1f}M SMA200={dist:>7} M20={mom:>7}"

    print(f"═══ BULL_STRONG ({len(bull_strong)}) — preço alto + momentum forte ═══")
    for r in sorted(bull_strong, key=lambda x: -(x['dist'] or 0))[:15]:
        print(fmt(r))

    print(f"\n═══ TOP PUMP 24h ({len(big_pump)} com ≥5%) ═══")
    for r in sorted(big_pump, key=lambda x: -x['pct24'])[:10]:
        print(fmt(r) + f" [{r['regime']}]")

    print(f"\n═══ BEAR_STRONG ({len(bear_strong)}) — colapso estrutural ═══")
    for r in sorted(bear_strong, key=lambda x: (x['dist'] or 0))[:10]:
        print(fmt(r))

    print(f"\n═══ TOP DUMP 24h ({len(big_dump)} com ≤-5%) ═══")
    for r in sorted(big_dump, key=lambda x: x['pct24'])[:10]:
        print(fmt(r) + f" [{r['regime']}]")

    print(f"\n═══ Sample distribution ═══")
    from collections import Counter
    c = Counter(r["regime"] for r in results)
    for k in ["BULL_STRONG","BULL_WEAK","SIDEWAYS","TRANSITION","BEAR_WEAK","BEAR_STRONG","NO_HIST"]:
        print(f"  {k:<12} {c.get(k,0):>3}")

    print(f"\n[total] tickers={len(tickers)} usdt_liquid={len(usdt)} analisados={len(results)} elapsed={elapsed:.1f}s")


if __name__ == "__main__":
    main()
