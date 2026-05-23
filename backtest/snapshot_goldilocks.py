"""
snapshot_goldilocks.py -- Caca entries A+ no universo TODO CoinEx.

NAO procura BULL_STRONG (geralmente tardio). Procura:
- EARLY BULL: cruzou SMA200 nas ultimas N semanas, mom positivo mas nao parabolico
- PULLBACK in BULL: regime bull mas drawdown 5-15% (entry timing)
- TRANSITION UP: ainda abaixo SMA200 mas momentum forte positivo (about-to-bull)
- BREAKOUT: testando SMA200 com vol spike
"""
from __future__ import annotations
import json, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import Request, urlopen

COINEX = "https://api.coinex.com/v2/spot"
MIN_VOL_USDT = 100_000   # threshold relaxado pra escanear mais
WORKERS = 32


def fetch(url, timeout=10):
    try:
        with urlopen(Request(url, headers={"User-Agent":"s/1"}), timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def get_all_tickers():
    d = fetch(f"{COINEX}/ticker")
    return d.get("data") or []


def get_kline(market, n=210, period="1day"):
    d = fetch(f"{COINEX}/kline?market={market}&period={period}&limit={n}")
    return d.get("data") or []


def deep_analyze(t):
    m = t["market"]
    last = float(t.get("last", 0))
    op   = float(t.get("open", 0))
    val  = float(t.get("value", 0))
    pct24 = ((last - op) / op * 100) if op > 0 else 0

    kl = get_kline(m, n=210)
    if len(kl) < 200:
        return None

    closes = [float(k["close"]) for k in kl]
    highs  = [float(k["high"])  for k in kl]
    lows   = [float(k["low"])   for k in kl]

    sma200 = sum(closes[-200:]) / 200
    sma50  = sum(closes[-50:])  / 50
    cur = closes[-1]
    dist200 = (cur - sma200) / sma200
    dist50  = (cur - sma50)  / sma50
    mom_20d = (cur - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
    mom_5d  = (cur - closes[-5])  / closes[-5]  if closes[-5]  > 0 else 0

    # SMA200 cross detection: foi negativo nas ultimas 30 candles e agora positivo?
    cross_recent = False
    cross_days_ago = None
    for i in range(1, min(40, len(closes) - 200)):
        idx = len(closes) - 1 - i
        sma200_then = sum(closes[idx-199:idx+1]) / 200
        ratio_then = (closes[idx] - sma200_then) / sma200_then
        if ratio_then < 0 and dist200 > 0:
            cross_recent = True
            cross_days_ago = i
            break

    # Pullback detection: dist dropping from recent peak
    recent_peak = max(closes[-30:])
    pullback_from_peak = (cur - recent_peak) / recent_peak  # negative if dropped

    # Volatility (high/low range pct)
    range_pct = (max(highs[-20:]) - min(lows[-20:])) / cur * 100

    # Categorize
    cat = None
    if dist200 > 0 and dist200 < 0.15 and mom_20d > 0.02 and mom_20d < 0.30:
        cat = "EARLY_BULL"
    elif dist200 > 0 and pullback_from_peak < -0.05 and pullback_from_peak > -0.15 and mom_5d > 0:
        cat = "PULLBACK_BULL"
    elif cross_recent and cross_days_ago and cross_days_ago <= 14:
        cat = "FRESH_CROSS"
    elif dist200 > -0.05 and dist200 < 0.05 and mom_20d > 0.05:
        cat = "BREAKOUT_TEST"
    elif dist200 < 0 and dist200 > -0.15 and mom_20d > 0.10:
        cat = "TRANSITION_UP"

    return {
        "market": m,
        "price": last,
        "pct24": pct24,
        "vol": val,
        "dist200": dist200,
        "dist50": dist50,
        "mom_20d": mom_20d,
        "mom_5d": mom_5d,
        "cross_recent": cross_recent,
        "cross_days_ago": cross_days_ago,
        "pullback_peak": pullback_from_peak,
        "range_pct": range_pct,
        "category": cat,
    }


def main():
    t0 = time.time()
    print("[1/3] fetching all tickers...")
    tickers = get_all_tickers()
    print(f"      {len(tickers)} total")

    usdt = [t for t in tickers if t["market"].endswith("USDT")
            and float(t.get("value", 0)) >= MIN_VOL_USDT]
    usdt.sort(key=lambda x: float(x["value"]), reverse=True)
    print(f"[2/3] {len(usdt)} markets USDT vol >= ${MIN_VOL_USDT:,.0f}; deep-analyzing all...")

    results = []
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(deep_analyze, t): t["market"] for t in usdt}
        for f in as_completed(futs):
            try:
                r = f.result()
                if r: results.append(r)
            except: pass

    elapsed = time.time() - t0
    print(f"[3/3] {len(results)} analisados em {elapsed:.1f}s\n")

    # Group by category
    cats = {
        "EARLY_BULL":     "[A+] Cruzou SMA200, momento bom (nao tardio)",
        "PULLBACK_BULL":  "[A]  Bull com pullback -5 a -15% (entry timing)",
        "FRESH_CROSS":    "[A]  Cruzou SMA200 ULTIMOS 14 dias",
        "BREAKOUT_TEST":  "[B]  Testando SMA200 com momentum",
        "TRANSITION_UP":  "[C]  Bear-weak mas momentum >10% (about-to-bull)",
    }

    def fmt(r):
        return (f"  {r['market']:<14} ${r['price']:>10.4f} 24h={r['pct24']:>+5.1f}% "
                f"vol=${r['vol']/1e6:>5.1f}M dist200={r['dist200']:>+6.1%} "
                f"mom20={r['mom_20d']:>+5.1%} mom5={r['mom_5d']:>+5.1%}")

    found_total = 0
    for cat_key, cat_desc in cats.items():
        matching = [r for r in results if r["category"] == cat_key]
        if not matching: continue
        # Sort by vol within category
        matching.sort(key=lambda x: -x["vol"])
        print(f"\n=== {cat_desc} ({len(matching)}) ===")
        for r in matching[:10]:
            extra = ""
            if r["cross_days_ago"]:
                extra = f" [cross {r['cross_days_ago']}d ago]"
            print(fmt(r) + extra)
        found_total += len(matching)

    print(f"\n[total candidatos] {found_total} de {len(results)} analisados")
    print("\nNenhuma categoria = sem entrada A+ agora. Bear continua dominando.")


if __name__ == "__main__":
    main()
