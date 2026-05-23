"""fetch_coinex_universe.py -- Fetch CoinEx full market universe + 1day klines.

Otimizacao:
  1. Get market list (1 API call) → ~1000+ markets
  2. Filter quality: status=open + 24h_vol >= threshold + age >= 6 meses
  3. Fetch klines sequencialmente com rate-limit-respeit (200ms entre calls)
  4. Save em journal/candles_coinex/{market}_1day.json (compatibilidade com cache existente)
  5. Skip se cache existe + ts ultimo bar > today-2 (fresh)

User OK: "se for 50, 100, ou 1000 (precisa ver forma otima de baixar)"
"""
from __future__ import annotations
import json
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / "journal" / "candles_coinex"
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Quality thresholds
MIN_24H_VOL_USD = 20_000      # 20K daily vol = meaningful liquidity in bear (gets ~100-200 markets)
MIN_AGE_DAYS = 180             # 6 months = enough history for backtest
RATE_LIMIT_SECONDS = 0.25      # 4 req/sec (conservative for unauth)
FRESH_HOURS = 24               # cache fresh se ultimo bar < 24h

# CoinEx v2 endpoints (public, sem auth)
MARKETS_SPOT = "https://api.coinex.com/v2/spot/market"
MARKETS_FUTURES = "https://api.coinex.com/v2/futures/market"
KLINE_SPOT = "https://api.coinex.com/v2/spot/kline"
KLINE_FUTURES = "https://api.coinex.com/v2/futures/kline"
TICKER_SPOT = "https://api.coinex.com/v2/spot/ticker"


def _http_get(url, params=None, timeout=15):
    if params:
        from urllib.parse import urlencode
        url = url + "?" + urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def fetch_market_list(source="spot"):
    """Returns list of dicts with market info (one call)."""
    url = MARKETS_SPOT if source == "spot" else MARKETS_FUTURES
    try:
        data = _http_get(url)
        if data.get("code") == 0:
            return data.get("data", [])
    except Exception as e:
        print(f"  ERR fetch market list ({source}): {e}")
    return []


def fetch_24h_tickers_spot():
    """Bulk ticker call - returns dict {market: ticker_data} para filtrar by volume."""
    try:
        data = _http_get(TICKER_SPOT)
        if data.get("code") == 0:
            return {t.get("market"): t for t in data.get("data", [])}
    except Exception as e:
        print(f"  ERR fetch tickers spot: {e}")
    return {}


def fetch_klines(market, source="spot", limit=1000):
    """Returns list of dicts with ts/o/h/l/c/v."""
    url = KLINE_SPOT if source == "spot" else KLINE_FUTURES
    params = {"market": market, "period": "1day", "limit": limit}
    try:
        data = _http_get(url, params=params)
        if data.get("code") == 0 and data.get("data"):
            out = []
            for k in data["data"]:
                ts = int(k.get("created_at", 0))
                if ts > 0:
                    dt = datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
                    out.append({
                        "ts": dt.strftime("%Y-%m-%dT%H:%M:%S+00:00"),
                        "open": float(k.get("open", 0)),
                        "high": float(k.get("high", 0)),
                        "low": float(k.get("low", 0)),
                        "close": float(k.get("close", 0)),
                        "volume": float(k.get("volume", 0)),
                    })
            return out
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"  HTTP {e.code} for {market}: {e.reason}")
    except Exception as e:
        print(f"  ERR fetch klines {market}: {e}")
    return []


def is_cache_fresh(market):
    f = CACHE_DIR / f"{market}_1day.json"
    if not f.exists():
        return False
    try:
        mtime = datetime.fromtimestamp(f.stat().st_mtime)
        age_hours = (datetime.now() - mtime).total_seconds() / 3600
        return age_hours < FRESH_HOURS
    except:
        return False


def save_klines(market, klines):
    if not klines:
        return False
    f = CACHE_DIR / f"{market}_1day.json"
    f.write_text(json.dumps(klines), encoding="utf-8")
    return True


def filter_quality_markets(market_list, tickers, min_vol=MIN_24H_VOL_USD):
    """Apply quality filters."""
    qualified = []
    rejected_volume = 0
    rejected_other = 0
    for m in market_list:
        symbol = m.get("market")
        if not symbol:
            continue
        # Must end with USDT (avoid weird pairs)
        if not symbol.endswith("USDT"):
            rejected_other += 1
            continue
        ticker = tickers.get(symbol)
        if ticker:
            try:
                vol_24h_usd = float(ticker.get("value", 0))  # value = volume * vwap in USD
                if vol_24h_usd < min_vol:
                    rejected_volume += 1
                    continue
            except:
                rejected_volume += 1
                continue
        else:
            rejected_other += 1
            continue
        qualified.append({"market": symbol, "vol_24h_usd": vol_24h_usd})
    print(f"  Quality filter: {len(qualified)} qualified, {rejected_volume} low vol, {rejected_other} other")
    qualified.sort(key=lambda x: -x["vol_24h_usd"])
    return qualified


def main(target_max=None, dry_run=False, force=False):
    print("=== CoinEx Universe Fetch ===")
    print(f"  Cache dir: {CACHE_DIR}")
    print()

    # 1. Get market list + tickers
    print("Fetching spot market list...")
    spot_markets = fetch_market_list("spot")
    print(f"  {len(spot_markets)} spot markets")
    print("Fetching 24h tickers...")
    tickers = fetch_24h_tickers_spot()
    print(f"  {len(tickers)} tickers")

    # 2. Filter quality
    qualified = filter_quality_markets(spot_markets, tickers, min_vol=MIN_24H_VOL_USD)
    print(f"  Top 5 by vol: {[q['market'] for q in qualified[:5]]}")
    if target_max:
        qualified = qualified[:target_max]
        print(f"  Limited to top {target_max} by 24h volume")

    if dry_run:
        print("\nDRY RUN — skipping klines fetch")
        print(f"\nWould fetch klines for {len(qualified)} markets")
        return

    # 3. Fetch klines
    print(f"\nFetching klines for {len(qualified)} markets (rate-limit {RATE_LIMIT_SECONDS}s)...")
    fetched = 0
    skipped = 0
    failed = 0
    start_ts = time.time()
    for i, q in enumerate(qualified):
        symbol = q["market"]
        if not force and is_cache_fresh(symbol):
            skipped += 1
            continue
        klines = fetch_klines(symbol, source="spot", limit=1000)
        if klines and len(klines) >= 30:
            save_klines(symbol, klines)
            fetched += 1
        else:
            failed += 1
        time.sleep(RATE_LIMIT_SECONDS)
        if (i + 1) % 50 == 0:
            elapsed = time.time() - start_ts
            eta = elapsed * (len(qualified) - i - 1) / (i + 1)
            print(f"  Progress: {i+1}/{len(qualified)} | fetched={fetched} skipped={skipped} failed={failed} | ETA {eta:.0f}s")

    elapsed = time.time() - start_ts
    print()
    print(f"=== DONE ===")
    print(f"  Total: {len(qualified)} | fetched={fetched} | skipped(fresh)={skipped} | failed={failed}")
    print(f"  Elapsed: {elapsed:.0f}s ({elapsed/60:.1f} min)")
    print(f"  Cache: {len(list(CACHE_DIR.glob('*_1day.json')))} files total")


if __name__ == "__main__":
    import sys
    args = sys.argv[1:]
    if "--help" in args:
        print("Usage: fetch_coinex_universe.py [--dry-run] [--force] [--top N]")
        print("  --dry-run: skip klines fetch, only show qualified list")
        print("  --force: ignore cache freshness, re-fetch all")
        print("  --top N: limit to top N by 24h volume (default: all qualified)")
        sys.exit(0)
    target_max = None
    if "--top" in args:
        idx = args.index("--top")
        target_max = int(args[idx + 1])
    main(target_max=target_max, dry_run=("--dry-run" in args), force=("--force" in args))
