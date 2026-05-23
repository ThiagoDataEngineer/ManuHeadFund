"""dow_universe_coinex.py — DoW effect em TODO o universo CoinEx USDT.

Fetch via /v2/spot/kline (1000 candles max = ~3 anos) por market.
Agrega: efeito Mon>Thu sustenta no universo geral? Eh mais forte em alts?
"""
import json
import math
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone
from typing import Dict, List

try: sys.stdout.reconfigure(encoding="utf-8")
except Exception: pass

from dotenv import load_dotenv
load_dotenv()

from calendar_effects_btc import t_test_two_groups

COINEX_TICKERS = "https://api.coinex.com/v2/spot/ticker"
COINEX_KLINE   = "https://api.coinex.com/v2/spot/kline"
MIN_DAYS = 200          # minimo de dias para estatistica valida
RATE_LIMIT_SEC = 0.10


def fetch_markets() -> List[str]:
    """Lista todos os markets USDT na CoinEx spot."""
    resp = urllib.request.urlopen(COINEX_TICKERS, timeout=15)
    data = json.loads(resp.read().decode())
    rows = data.get("data", [])
    markets = [r["market"] for r in rows
               if r["market"].endswith("USDT") and float(r.get("value", 0)) > 0]
    return sorted(markets)


def fetch_daily(market: str, limit: int = 1000) -> List[Dict]:
    """Fetch daily kline (max 1000)."""
    url = f"{COINEX_KLINE}?market={market}&period=1day&limit={limit}"
    try:
        resp = urllib.request.urlopen(url, timeout=10)
        data = json.loads(resp.read().decode())
    except Exception:
        return []
    rows = data.get("data", [])
    out = []
    for r in rows:
        try:
            ts_ms = int(r["created_at"])
            date = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).date().isoformat()
            close = float(r["close"])
            out.append({"date": date, "close": close})
        except (KeyError, ValueError, TypeError):
            continue
    return sorted(out, key=lambda c: c["date"])


def analyze_market(candles: List[Dict]) -> Dict:
    """Calcula DoW returns + Mon vs Thu test."""
    if len(candles) < MIN_DAYS:
        return None
    by_dow: Dict[int, List[float]] = {i: [] for i in range(7)}
    for i in range(1, len(candles)):
        prev = candles[i - 1]["close"]
        curr = candles[i]["close"]
        if prev > 0:
            r = math.log(curr / prev)
            dow = datetime.fromisoformat(candles[i]["date"]).weekday()
            by_dow[dow].append(r)
    if not by_dow[0] or not by_dow[3]:
        return None
    mon_mean = sum(by_dow[0]) / len(by_dow[0])
    thu_mean = sum(by_dow[3]) / len(by_dow[3])
    t, p = t_test_two_groups(by_dow[0], by_dow[3])
    return {
        "n_days":    sum(len(v) for v in by_dow.values()),
        "mon_mean":  mon_mean,
        "thu_mean":  thu_mean,
        "diff":      mon_mean - thu_mean,
        "t":         t,
        "p":         p,
        "by_dow_means": [sum(by_dow[i]) / len(by_dow[i]) if by_dow[i] else 0
                         for i in range(7)],
    }


def main():
    print("  Fetching CoinEx USDT spot markets...", flush=True)
    markets = fetch_markets()
    print(f"  {len(markets)} markets USDT encontrados")

    if "--limit" in sys.argv:
        idx = sys.argv.index("--limit")
        markets = markets[: int(sys.argv[idx + 1])]
        print(f"  (limitado a {len(markets)} para teste rapido)")

    results = []
    skipped = 0
    print(f"\n  Coletando daily klines + analyzing (~{len(markets) * RATE_LIMIT_SEC / 60:.1f} min)...")
    for i, m in enumerate(markets):
        candles = fetch_daily(m, limit=1000)
        r = analyze_market(candles)
        if r is None:
            skipped += 1
        else:
            r["market"] = m
            results.append(r)
        if (i + 1) % 50 == 0:
            print(f"    [{i+1}/{len(markets)}]  valid={len(results)} skip={skipped}",
                  flush=True)
        time.sleep(RATE_LIMIT_SEC)

    print(f"\n  Analise concluida: {len(results)} markets com >= {MIN_DAYS} dias, "
          f"{skipped} skipped por baixa historico\n")

    if not results:
        print("  Nenhum market com dados suficientes.")
        return

    # Agregacao geral
    n_mon_gt_thu = sum(1 for r in results if r["diff"] > 0)
    n_sig = sum(1 for r in results if r["p"] < 0.05)
    n_sig_mon = sum(1 for r in results if r["p"] < 0.05 and r["diff"] > 0)
    avg_diff = sum(r["diff"] for r in results) / len(results)
    avg_mon = sum(r["mon_mean"] for r in results) / len(results)
    avg_thu = sum(r["thu_mean"] for r in results) / len(results)

    sep = "=" * 80
    print(sep)
    print(f"  AGREGADO UNIVERSO COINEX ({len(results)} markets USDT)")
    print(sep)
    print(f"  Mon > Thu em:                {n_mon_gt_thu}/{len(results)} markets "
          f"({n_mon_gt_thu/len(results)*100:.1f}%)")
    print(f"  Significativo (p<0.05):      {n_sig}/{len(results)} markets")
    print(f"  Significativo E Mon > Thu:   {n_sig_mon}/{len(results)} markets")
    print(f"  Media Mon:                   {avg_mon*100:+.4f}%/dia")
    print(f"  Media Thu:                   {avg_thu*100:+.4f}%/dia")
    print(f"  Media diff (Mon - Thu):      {avg_diff*100:+.4f}pp/dia")

    # Top performers (maior diff Mon-Thu)
    print(f"\n  TOP 15 MARKETS por (Mon - Thu) diff:")
    sorted_diff = sorted(results, key=lambda r: -r["diff"])[:15]
    print(f"  {'Market':<14} {'Days':>5} {'Mon%':>9} {'Thu%':>9} {'Diff':>8} {'p':>7}")
    for r in sorted_diff:
        sig = "SIG" if r["p"] < 0.05 else ""
        print(f"  {r['market']:<14} {r['n_days']:>5} "
              f"{r['mon_mean']*100:>+8.3f}% {r['thu_mean']*100:>+8.3f}% "
              f"{r['diff']*100:>+7.3f}pp {r['p']:>6.3f} {sig}")

    # Bottom (menor diff = Thu > Mon)
    print(f"\n  BOTTOM 15 (Thu > Mon):")
    sorted_diff_asc = sorted(results, key=lambda r: r["diff"])[:15]
    print(f"  {'Market':<14} {'Days':>5} {'Mon%':>9} {'Thu%':>9} {'Diff':>8} {'p':>7}")
    for r in sorted_diff_asc:
        sig = "SIG" if r["p"] < 0.05 else ""
        print(f"  {r['market']:<14} {r['n_days']:>5} "
              f"{r['mon_mean']*100:>+8.3f}% {r['thu_mean']*100:>+8.3f}% "
              f"{r['diff']*100:>+7.3f}pp {r['p']:>6.3f} {sig}")

    # DoW agregado (media de medias)
    print(f"\n  DoW MEAN AGREGADO (media das medias de cada market):")
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i in range(7):
        means_i = [r["by_dow_means"][i] for r in results]
        avg = sum(means_i) / len(means_i)
        n_pos = sum(1 for m in means_i if m > 0)
        print(f"  {days[i]:<5} avg={avg*100:>+7.4f}%  "
              f"markets_positive={n_pos}/{len(results)} ({n_pos/len(results)*100:.0f}%)")

    # Veredito
    pct_mon_gt_thu = n_mon_gt_thu / len(results) * 100
    print(f"\n{sep}")
    print(f"  VEREDITO")
    print(sep)
    if pct_mon_gt_thu >= 65:
        print(f"  -> EFEITO UNIVERSAL: {pct_mon_gt_thu:.0f}% dos markets confirmam Mon > Thu")
        print(f"     Calibracao DoW do lib_seasonality.ps1 e VALIDA para todo o universo CoinEx")
    elif pct_mon_gt_thu >= 55:
        print(f"  -> EFEITO MAJORITARIO: {pct_mon_gt_thu:.0f}% dos markets confirmam")
        print(f"     Calibracao funciona em media, mas exceptions notaveis nos bottom")
    else:
        print(f"  -> EFEITO HETEROGENEO: {pct_mon_gt_thu:.0f}% confirmam")
        print(f"     Calibracao pode nao se aplicar uniformemente; ver per-market analysis")
    print(sep)


if __name__ == "__main__":
    main()
