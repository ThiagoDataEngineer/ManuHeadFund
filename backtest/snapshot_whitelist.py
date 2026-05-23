"""
snapshot_whitelist.py — Snapshot paralelo current state Tier A+B.

Fetch CoinEx tickers + computa: preço, 24h%, ATR ratio, dist SMA200,
regime simplificado. Tudo em paralelo via ThreadPoolExecutor.
"""
from __future__ import annotations
import json, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError

ROOT = Path(__file__).resolve().parent.parent
WL = ROOT / "journal" / "per_asset_whitelist_2026_05_18_v3.json"

COINEX_BASE = "https://api.coinex.com/v2/spot"


def fetch_json(url, timeout=8):
    req = Request(url, headers={"User-Agent": "coinex-snapshot/1.0"})
    try:
        with urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except Exception as e:
        return {"_error": str(e)}


def fetch_ticker(market):
    data = fetch_json(f"{COINEX_BASE}/ticker?market={market}")
    if "_error" in data: return {"market": market, "error": data["_error"]}
    arr = data.get("data") or []
    if not arr: return {"market": market, "error": "no_data"}
    t = arr[0]
    return {
        "market": market,
        "last": float(t.get("last", 0)),
        "open": float(t.get("open", 0)),
        "high": float(t.get("high", 0)),
        "low": float(t.get("low", 0)),
        "volume": float(t.get("volume", 0)),
        "value": float(t.get("value", 0)),
    }


def fetch_kline_daily(market, n=210):
    """1day klines pra SMA200 + regime."""
    data = fetch_json(f"{COINEX_BASE}/kline?market={market}&period=1day&limit={n}")
    if "_error" in data: return None
    arr = data.get("data") or []
    return arr if arr else None


def regime(closes, highs, lows):
    """Classificação simplificada baseada em SMA200 + momentum recent."""
    if len(closes) < 200:
        return {"label": "NO_DATA", "dist_sma200": None, "mom_20d": None}
    sma200 = sum(closes[-200:]) / 200
    cur = closes[-1]
    dist = (cur - sma200) / sma200
    mom_20d = (closes[-1] - closes[-20]) / closes[-20] if closes[-20] > 0 else 0
    if dist > 0.15 and mom_20d > 0.05:
        label = "BULL_STRONG"
    elif dist > 0 and mom_20d > 0:
        label = "BULL_WEAK"
    elif dist > -0.05 and mom_20d > -0.05:
        label = "SIDEWAYS"
    elif dist < -0.15 and mom_20d < -0.05:
        label = "BEAR_STRONG"
    elif dist < 0:
        label = "BEAR_WEAK"
    else:
        label = "TRANSITION"
    return {"label": label, "dist_sma200": round(dist, 3), "mom_20d": round(mom_20d, 3)}


def evaluate(market):
    t = fetch_ticker(market)
    if "error" in t: return {**t, "tier": "?", "regime": "ERR"}
    kl = fetch_kline_daily(market)
    if not kl:
        return {**t, "regime": "NO_KLINE"}
    closes = [float(k["close"]) for k in kl]
    highs  = [float(k["high"])  for k in kl]
    lows   = [float(k["low"])   for k in kl]
    r = regime(closes, highs, lows)
    pct24 = ((t["last"] - t["open"]) / t["open"] * 100) if t["open"] > 0 else 0
    return {
        "market": market,
        "price": t["last"],
        "pct24h": round(pct24, 2),
        "vol_usdt": round(t["value"], 0),
        **r,
    }


def main():
    with open(WL, "r", encoding="utf-8") as f:
        wl = json.load(f)
    tier_a = [e["market"] for e in wl["TIER_A_LIVE"] if "BITSTAMP" not in e["market"]]
    tier_b = [e["market"] for e in wl["TIER_B_PAPER"] if "BITSTAMP" not in e["market"]]
    tier_b = [m for m in tier_b if m not in tier_a]

    markets = tier_a + tier_b
    print(f"Snapshot {len(markets)} markets em paralelo...\n")

    t0 = time.time()
    results = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futures = {ex.submit(evaluate, m): m for m in markets}
        for fut in as_completed(futures):
            m = futures[fut]
            results[m] = fut.result()
    elapsed = time.time() - t0

    print(f"{'MARKET':<12} {'TIER':<5} {'PRICE':>12} {'24H%':>7} {'VOL$':>14} {'DIST SMA200':>12} {'MOM 20D':>8} {'REGIME':<12}")
    print("─" * 95)
    for m in markets:
        r = results.get(m, {})
        if "error" in r:
            print(f"{m:<12} ERR   {r.get('error','?')}")
            continue
        tier = "A" if m in tier_a else "B"
        dist = r.get("dist_sma200")
        mom = r.get("mom_20d")
        dist_s = f"{dist:+.1%}" if dist is not None else "?"
        mom_s = f"{mom:+.1%}" if mom is not None else "?"
        print(f"{m:<12} {tier:<5} {r['price']:>12.4f} {r['pct24h']:>+6.2f}% "
              f"{r.get('vol_usdt',0):>14,.0f} {dist_s:>12} {mom_s:>8} {r['label']:<12}")

    print(f"\n[done] {elapsed:.1f}s | {len(markets)} markets")


if __name__ == "__main__":
    main()
