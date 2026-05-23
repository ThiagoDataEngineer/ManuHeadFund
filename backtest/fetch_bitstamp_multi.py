"""
fetch_bitstamp_multi.py — Coleta histórico longo BTC/XRP/ETH/LTC daily Bitstamp.

Endpoints públicos sem auth. Bitstamp tem histórico desde:
- BTCUSD: 2011-08-18
- XRPUSD: 2017-08
- ETHUSD: 2017-08-17
- LTCUSD: 2017-05-02

Daily step=86400, limit=1000 por request, paginação manual.
Saída: backtest/<PAIR>_bitstamp_1day.json (~3000+ candles cada par)
"""
from __future__ import annotations

import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

import requests

SCRIPT_DIR = Path(__file__).resolve().parent

PAIRS = {
    "btcusd": "BTC",
    "xrpusd": "XRP",
    "ethusd": "ETH",
    "ltcusd": "LTC",
}

BITSTAMP_STEP = 86400   # 1 day in seconds
BITSTAMP_LIMIT = 1000
SLEEP_BETWEEN = 0.5
MAX_RETRIES = 3

# Período alvo: começo até hoje
END_TS = int(datetime(2026, 5, 15, 23, 59, 59, tzinfo=timezone.utc).timestamp())
START_TS_DEFAULT = int(datetime(2011, 1, 1, tzinfo=timezone.utc).timestamp())


def fetch_page(pair: str, start: int, end: int) -> Optional[List[Dict]]:
    url = f"https://www.bitstamp.net/api/v2/ohlc/{pair}/"
    params = {"step": BITSTAMP_STEP, "limit": BITSTAMP_LIMIT,
              "start": start, "end": end}
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, params=params, timeout=15)
            if r.status_code == 200:
                d = r.json()
                ohlc = d.get("data", {}).get("ohlc", [])
                return ohlc
            else:
                print(f"  [HTTP {r.status_code}] attempt {attempt+1}")
        except Exception as e:
            print(f"  [ERRO] {e}")
        time.sleep(1.0 * (attempt + 1))
    return None


def fetch_all(pair: str, start_ts: int = START_TS_DEFAULT,
              end_ts: int = END_TS) -> List[Dict]:
    """Pagina daily candles do start_ts até end_ts."""
    all_candles = []
    cursor = start_ts
    print(f"[{pair}] {datetime.fromtimestamp(start_ts, tz=timezone.utc).date()} → "
          f"{datetime.fromtimestamp(end_ts, tz=timezone.utc).date()}")
    page_n = 0
    while cursor < end_ts:
        page_n += 1
        end_chunk = min(cursor + BITSTAMP_STEP * BITSTAMP_LIMIT, end_ts)
        page = fetch_page(pair, cursor, end_chunk)
        if not page:
            print(f"  [page {page_n}] vazia ou erro, cursor avança 1000 candles")
            cursor = end_chunk + 1
            continue
        # Normaliza
        rows = []
        for c in page:
            ts = int(c.get("timestamp", 0))
            if ts < cursor or ts > end_ts:
                continue
            rows.append({
                "ts": datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00"),
                "open":   float(c.get("open", 0)),
                "high":   float(c.get("high", 0)),
                "low":    float(c.get("low", 0)),
                "close":  float(c.get("close", 0)),
                "volume": float(c.get("volume", 0)),
            })
        if not rows:
            print(f"  [page {page_n}] 0 valid rows; cursor avança")
            cursor = end_chunk + 1
            continue
        all_candles.extend(rows)
        last_ts = int(page[-1].get("timestamp", end_chunk))
        cursor = last_ts + BITSTAMP_STEP
        print(f"  [page {page_n}] +{len(rows)} candles, last={datetime.fromtimestamp(last_ts, tz=timezone.utc).date()}, total={len(all_candles)}")
        time.sleep(SLEEP_BETWEEN)

    # Dedup
    seen = set()
    out = []
    for c in all_candles:
        if c["ts"] not in seen:
            seen.add(c["ts"])
            out.append(c)
    out.sort(key=lambda x: x["ts"])
    return out


def main():
    summary = {"timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "pairs": []}
    for pair, label in PAIRS.items():
        cache = SCRIPT_DIR / f"{pair}_bitstamp_1day.json"
        if cache.exists():
            with open(cache, "r", encoding="utf-8") as f:
                cached = json.load(f)
            if cached and len(cached) > 500:
                print(f"[{pair}] cache existe ({len(cached)} candles). Skip.")
                summary["pairs"].append({
                    "pair": pair, "label": label, "cached": True,
                    "n_candles": len(cached),
                    "first": cached[0]["ts"], "last": cached[-1]["ts"],
                    "path": str(cache.name),
                })
                continue

        candles = fetch_all(pair)
        if not candles:
            print(f"[{pair}] sem dados.")
            continue
        with open(cache, "w", encoding="utf-8") as f:
            json.dump(candles, f)
        print(f"[{pair}] {len(candles)} candles {candles[0]['ts']} → {candles[-1]['ts']}")
        summary["pairs"].append({
            "pair": pair, "label": label, "cached": False,
            "n_candles": len(candles),
            "first": candles[0]["ts"], "last": candles[-1]["ts"],
            "path": str(cache.name),
        })

    out_path = SCRIPT_DIR.parent / "journal" / "bitstamp_long_history_summary.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {out_path}")


if __name__ == "__main__":
    main()
