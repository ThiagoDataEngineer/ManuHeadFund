"""fetch_btc_bitstamp_7y.py -- Fetch BTCUSD Bitstamp daily 2019-2026.

Bitstamp API v2 OHLC:
  GET /api/v2/ohlc/btcusd/?step=86400&limit=1000&start=TIMESTAMP_UNIX
  step=86400 (1 day), limit max 1000.
  7 anos = 2555 days -> precisa 3 paginas.

Output: journal/candles_external/BTCUSD_BITSTAMP_1day.json
"""
from __future__ import annotations
import json, sys, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "journal" / "candles_external"
OUT_DIR.mkdir(parents=True, exist_ok=True)

START = datetime(2019, 1, 1, tzinfo=timezone.utc)
END   = datetime(2026, 5, 22, tzinfo=timezone.utc)


def fetch_page(start_ts_unix: int, limit=1000):
    url = f"https://www.bitstamp.net/api/v2/ohlc/btcusd/?step=86400&limit={limit}&start={start_ts_unix}"
    req = urllib.request.Request(url, headers={"User-Agent": "coinex-ai-7y-fetch/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data.get("data", {}).get("ohlc", [])
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.reason}")
        return []
    except Exception as e:
        print(f"ERR: {e}")
        return []


def main():
    all_candles = {}   # ts_unix -> candle
    cursor = int(START.timestamp())
    end_ts = int(END.timestamp())
    pages = 0
    while cursor < end_ts and pages < 5:
        print(f"  Page {pages+1}: start={datetime.fromtimestamp(cursor, timezone.utc).date()}", flush=True)
        page = fetch_page(cursor)
        if not page:
            print("  empty page, breaking")
            break
        for c in page:
            try:
                ts = int(c["timestamp"])
                all_candles[ts] = {
                    "ts": datetime.fromtimestamp(ts, timezone.utc).isoformat(),
                    "open":  float(c["open"]),
                    "high":  float(c["high"]),
                    "low":   float(c["low"]),
                    "close": float(c["close"]),
                    "volume": float(c.get("volume", 0)),
                }
            except (KeyError, ValueError, TypeError):
                continue
        # Advance cursor to last ts + 1 day
        max_ts = max((int(c["timestamp"]) for c in page), default=cursor)
        if max_ts <= cursor:
            break
        cursor = max_ts + 86400
        pages += 1

    sorted_candles = sorted(all_candles.values(), key=lambda c: c["ts"])
    if not sorted_candles:
        print("ZERO candles fetched"); return 1

    out_path = OUT_DIR / "BTCUSD_BITSTAMP_1day.json"
    out_path.write_text(json.dumps(sorted_candles, separators=(",", ":")), encoding="utf-8")

    first = sorted_candles[0]["ts"][:10]
    last  = sorted_candles[-1]["ts"][:10]
    print(f"\nDone: {len(sorted_candles)} candles  range={first} -> {last}")
    print(f"Output: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
