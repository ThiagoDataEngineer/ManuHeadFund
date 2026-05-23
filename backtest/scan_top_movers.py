"""
scan_top_movers.py - Scan top gainers/losers 30d cruzado com filtros do projeto.

Fonte: CoinGecko free API (sem auth, rate-limited).

Critério LONG candidate (gainer):
  - 30d % positivo (top N)
  - market_cap >= MIN_MCAP
  - volume_24h >= MIN_VOLUME
  - não-stablecoin, não-wrapped
  - regime simples = BULL (preço > sma50 proxy via CoinGecko sparkline)

Critério SHORT candidate (loser):
  - 30d % negativo (top N piores)
  - mesmos filtros de liquidez
  - regime simples = BEAR (preço < sma50 proxy)

CLI:
    python backtest/scan_top_movers.py --top 10
"""
import argparse
import json
import os
import time
from datetime import datetime, timezone
from typing import Dict, List


COINGECKO_BASE = "https://api.coingecko.com/api/v3"

MIN_MCAP_DEFAULT   = 50_000_000        # $50M
MIN_VOLUME_DEFAULT = 10_000_000        # $10M

# Listas para filtrar stables e wrapped
STABLECOIN_SYMBOLS = frozenset({
    "usdt", "usdc", "busd", "dai", "tusd", "usdp", "frax", "lusd",
    "gusd", "usdd", "ust", "susd", "usde", "pyusd", "fdusd", "usdy",
    "usds", "usdb", "usdt0", "usd1", "usd0",
})

WRAPPED_OR_SYNTHETIC_PREFIXES = ("w", "st", "r", "sw", "wst", "rs")
WRAPPED_OR_SYNTHETIC_SYMBOLS = frozenset({
    "wbtc", "weth", "wsteth", "steth", "reth", "cbeth", "wbnb",
    "wmatic", "wpol", "savax", "stsol", "msol", "jitosol", "wsol",
    "tbtc", "renbtc", "sbtc", "hbtc", "btcb",
})

SIDEWAYS_BAND_PCT = 1.0  # +-1% de SMA50 = SIDEWAYS

COINEX_SPOT_MARKETS_URL    = "https://api.coinex.com/v2/spot/market"
COINEX_FUTURES_MARKETS_URL = "https://api.coinex.com/v2/futures/market"


# ----------------------------------------------------------------------------
# Filtros
# ----------------------------------------------------------------------------

def is_stablecoin(symbol: str) -> bool:
    return str(symbol).strip().lower() in STABLECOIN_SYMBOLS


def is_wrapped_or_synthetic(symbol: str) -> bool:
    return str(symbol).strip().lower() in WRAPPED_OR_SYNTHETIC_SYMBOLS


def filter_liquid_coins(
    coins: List[Dict],
    min_mcap: float = MIN_MCAP_DEFAULT,
    min_volume: float = MIN_VOLUME_DEFAULT,
) -> List[Dict]:
    out = []
    for c in coins:
        sym = c.get("symbol", "")
        if is_stablecoin(sym):       continue
        if is_wrapped_or_synthetic(sym): continue
        mcap = c.get("market_cap") or 0
        vol  = c.get("total_volume") or 0
        if mcap < min_mcap:   continue
        if vol  < min_volume: continue
        out.append(c)
    return out


# ----------------------------------------------------------------------------
# Ranking
# ----------------------------------------------------------------------------

def rank_top_gainers(coins: List[Dict], n: int = 10) -> List[Dict]:
    valid = [c for c in coins if (c.get("price_change_percentage_30d_in_currency") or 0) > 0]
    valid.sort(key=lambda c: c.get("price_change_percentage_30d_in_currency") or 0, reverse=True)
    return valid[:n]


def rank_top_losers(coins: List[Dict], n: int = 10) -> List[Dict]:
    valid = [c for c in coins if (c.get("price_change_percentage_30d_in_currency") or 0) < 0]
    valid.sort(key=lambda c: c.get("price_change_percentage_30d_in_currency") or 0)
    return valid[:n]


# ----------------------------------------------------------------------------
# Regime simples
# ----------------------------------------------------------------------------

def classify_simple_regime(coin: Dict) -> str:
    """BULL se preço > sma50_proxy +1%, BEAR se < -1%, senão SIDEWAYS."""
    price = float(coin.get("current_price") or 0)
    sma   = float(coin.get("sma50_proxy") or 0)
    if sma <= 0 or price <= 0:
        return "UNKNOWN"
    dist_pct = (price - sma) / sma * 100.0
    if dist_pct > SIDEWAYS_BAND_PCT:  return "BULL"
    if dist_pct < -SIDEWAYS_BAND_PCT: return "BEAR"
    return "SIDEWAYS"


def _verdict(coin: Dict, side: str) -> str:
    """side: 'gainer' ou 'loser'.
    LONG_CANDIDATE: gainer + regime BULL
    SHORT_CANDIDATE: loser + regime BEAR
    AVOID: senão (regime conflitante com a direção sugerida)"""
    regime = classify_simple_regime(coin)
    if side == "gainer":
        return "LONG_CANDIDATE" if regime == "BULL" else "AVOID"
    if side == "loser":
        return "SHORT_CANDIDATE" if regime == "BEAR" else "AVOID"
    return "AVOID"


# ----------------------------------------------------------------------------
# CoinEx availability
# ----------------------------------------------------------------------------

def fetch_coinex_pairs() -> Dict[str, set]:
    """Retorna {'spot': set('BTCUSDT', ...), 'futures': set(...)} via CoinEx API publica."""
    import requests
    out = {"spot": set(), "futures": set()}
    try:
        r = requests.get(COINEX_SPOT_MARKETS_URL, timeout=15)
        if r.status_code == 200:
            data = r.json().get("data", []) or []
            for m in data:
                name = (m.get("market") or "").upper()
                if name.endswith("USDT"):
                    out["spot"].add(name)
    except Exception as e:
        print(f"  erro fetch spot CoinEx: {e}")
    try:
        r = requests.get(COINEX_FUTURES_MARKETS_URL, timeout=15)
        if r.status_code == 200:
            data = r.json().get("data", []) or []
            for m in data:
                name = (m.get("market") or "").upper()
                if name.endswith("USDT"):
                    out["futures"].add(name)
    except Exception as e:
        print(f"  erro fetch futures CoinEx: {e}")
    return out


def annotate_coinex_availability(coins: List[Dict], coinex_pairs: Dict[str, set]) -> List[Dict]:
    """Adiciona coinex_spot/coinex_futures/coinex_availability a cada coin."""
    spot_set    = coinex_pairs.get("spot", set())
    futures_set = coinex_pairs.get("futures", set())
    out = []
    for c in coins:
        sym = str(c.get("symbol", "")).upper()
        pair = f"{sym}USDT"
        on_spot    = pair in spot_set
        on_futures = pair in futures_set
        if on_spot and on_futures:
            avail = "BOTH"
        elif on_spot:
            avail = "SPOT_ONLY"
        elif on_futures:
            avail = "FUTURES_ONLY"
        else:
            avail = "NOT_AVAILABLE"
        nc = dict(c)
        nc["coinex_spot"]         = on_spot
        nc["coinex_futures"]      = on_futures
        nc["coinex_availability"] = avail
        out.append(nc)
    return out


def filter_tradeable_on_coinex(coins: List[Dict]) -> List[Dict]:
    """Mantem apenas coins com coinex_availability != NOT_AVAILABLE."""
    return [c for c in coins if c.get("coinex_availability") != "NOT_AVAILABLE"]


# ----------------------------------------------------------------------------
# Build report
# ----------------------------------------------------------------------------

def _entry(coin: Dict, side: str) -> Dict:
    return {
        "symbol":           str(coin.get("symbol", "")).upper(),
        "name":             coin.get("name", ""),
        "price":            round(float(coin.get("current_price") or 0), 6),
        "change_30d_pct":   round(float(coin.get("price_change_percentage_30d_in_currency") or 0), 2),
        "change_24h_pct":   round(float(coin.get("price_change_percentage_24h") or 0), 2),
        "market_cap":       coin.get("market_cap"),
        "volume_24h":       coin.get("total_volume"),
        "sma50_proxy":      round(float(coin.get("sma50_proxy") or 0), 6),
        "regime_simple":    classify_simple_regime(coin),
        "coinex_spot":      coin.get("coinex_spot", False),
        "coinex_futures":   coin.get("coinex_futures", False),
        "coinex_availability": coin.get("coinex_availability", "UNKNOWN"),
        "long_long_or_short_long": _verdict(coin, side),
    }


def build_movers_report(
    coins: List[Dict],
    top_n: int = 10,
    min_mcap: float = MIN_MCAP_DEFAULT,
    min_volume: float = MIN_VOLUME_DEFAULT,
    coinex_pairs: Dict[str, set] = None,
    require_coinex: bool = True,
) -> Dict:
    liquid = filter_liquid_coins(coins, min_mcap=min_mcap, min_volume=min_volume)

    # Cruza com pares CoinEx
    if coinex_pairs is not None:
        annotated = annotate_coinex_availability(liquid, coinex_pairs)
        if require_coinex:
            tradeable = filter_tradeable_on_coinex(annotated)
        else:
            tradeable = annotated
    else:
        tradeable = liquid
        require_coinex = False

    gainers = rank_top_gainers(tradeable, n=top_n)
    losers  = rank_top_losers(tradeable,  n=top_n)

    return {
        "timestamp_utc": datetime.now(tz=timezone.utc).isoformat(),
        "criteria": {
            "min_marketcap_usd": min_mcap,
            "min_volume_24h_usd": min_volume,
            "top_n": top_n,
            "excluded": "stablecoins, wrapped/synthetic tokens",
            "require_coinex_listing": require_coinex,
        },
        "top_gainers": [_entry(c, "gainer") for c in gainers],
        "top_losers":  [_entry(c, "loser")  for c in losers],
        "summary": {
            "total_screened":         len(coins),
            "liquid_after_filter":    len(liquid),
            "tradeable_on_coinex":    len(tradeable),
            "long_candidates":        sum(1 for c in gainers if _verdict(c, "gainer") == "LONG_CANDIDATE"),
            "short_candidates":       sum(1 for c in losers  if _verdict(c, "loser")  == "SHORT_CANDIDATE"),
        },
    }


# ----------------------------------------------------------------------------
# Fetcher (CoinGecko)
# ----------------------------------------------------------------------------

def fetch_coingecko_markets(pages: int = 2, per_page: int = 250) -> List[Dict]:
    """Busca top N coins por mcap com 30d performance via CoinGecko free API."""
    import requests
    out: List[Dict] = []
    for page in range(1, pages + 1):
        url = (f"{COINGECKO_BASE}/coins/markets"
               f"?vs_currency=usd&order=market_cap_desc"
               f"&per_page={per_page}&page={page}"
               f"&sparkline=true&price_change_percentage=24h,30d")
        for attempt in range(3):
            try:
                r = requests.get(url, timeout=20)
                if r.status_code == 200:
                    out.extend(r.json())
                    break
                if r.status_code == 429:
                    time.sleep(15)  # rate limit
                    continue
                print(f"  CoinGecko {r.status_code} page {page}: {r.text[:120]}")
                break
            except Exception as e:
                print(f"  erro tentativa {attempt + 1}: {e}")
                time.sleep(3)
        time.sleep(2)

    # SMA50 proxy: media dos ultimos 50 valores do sparkline (7d hourly => ~168 pontos)
    # Aproximacao: ultimos 50 pontos da sparkline
    for c in out:
        sp = (c.get("sparkline_in_7d") or {}).get("price") or []
        if sp:
            tail = sp[-50:] if len(sp) >= 50 else sp
            c["sma50_proxy"] = sum(tail) / len(tail) if tail else c.get("current_price")
        else:
            c["sma50_proxy"] = c.get("current_price")
    return out


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Scan top movers 30d (gainers/losers) + regime filter")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--min-mcap", type=float, default=MIN_MCAP_DEFAULT)
    parser.add_argument("--min-vol",  type=float, default=MIN_VOLUME_DEFAULT)
    parser.add_argument("--pages", type=int, default=2)
    parser.add_argument("--output", default=None)
    args = parser.parse_args()

    print(f"Buscando CoinGecko top {args.pages*250} coins por mcap (30d perf)...")
    coins = fetch_coingecko_markets(pages=args.pages, per_page=250)
    print(f"  -> {len(coins)} coins retornados")

    print("Buscando pares listados na CoinEx...")
    coinex_pairs = fetch_coinex_pairs()
    print(f"  -> CoinEx Spot: {len(coinex_pairs['spot'])} pares USDT | Futures: {len(coinex_pairs['futures'])} pares USDT")

    report = build_movers_report(
        coins, top_n=args.top, min_mcap=args.min_mcap, min_volume=args.min_vol,
        coinex_pairs=coinex_pairs, require_coinex=True,
    )

    out_path = args.output
    if out_path is None:
        here = os.path.dirname(os.path.abspath(__file__))
        journal = os.path.abspath(os.path.join(here, "..", "journal"))
        os.makedirs(journal, exist_ok=True)
        out_path = os.path.join(journal, "scan_top_movers.json")

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    print()
    print("=" * 90)
    print(f"TOP {args.top} GAINERS 30d (candidatos LONG):")
    print("=" * 90)
    print(f"{'#':<3}{'SYMBOL':<10}{'30d %':>9}{'24h %':>9}{'PRICE':>12}{'VOL($M)':>10}{'REGIME':>10}{'CoinEx':>13}  VERDICT")
    print("-" * 110)
    for i, e in enumerate(report["top_gainers"], 1):
        flag = "*" if e["long_long_or_short_long"] == "LONG_CANDIDATE" else " "
        vol_m = (e["volume_24h"] or 0) / 1e6
        print(f"{i:<3}{e['symbol']:<10}{e['change_30d_pct']:>+8.1f}%{e['change_24h_pct']:>+8.1f}%"
              f"{e['price']:>12.4f}{vol_m:>9.0f}M{e['regime_simple']:>10}{e['coinex_availability']:>13}  {flag}{e['long_long_or_short_long']}")

    print()
    print("=" * 90)
    print(f"TOP {args.top} LOSERS 30d (candidatos SHORT):")
    print("=" * 90)
    print(f"{'#':<3}{'SYMBOL':<10}{'30d %':>9}{'24h %':>9}{'PRICE':>12}{'VOL($M)':>10}{'REGIME':>10}{'CoinEx':>13}  VERDICT")
    print("-" * 110)
    for i, e in enumerate(report["top_losers"], 1):
        flag = "*" if e["long_long_or_short_long"] == "SHORT_CANDIDATE" else " "
        vol_m = (e["volume_24h"] or 0) / 1e6
        print(f"{i:<3}{e['symbol']:<10}{e['change_30d_pct']:>+8.1f}%{e['change_24h_pct']:>+8.1f}%"
              f"{e['price']:>12.4f}{vol_m:>9.0f}M{e['regime_simple']:>10}{e['coinex_availability']:>13}  {flag}{e['long_long_or_short_long']}")

    s = report["summary"]
    print()
    print(f"Resumo: {s['total_screened']} screened | {s['liquid_after_filter']} líquidos | "
          f"{s['long_candidates']} LONG / {s['short_candidates']} SHORT candidates marcados (*)")
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
