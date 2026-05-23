"""
binance_funding_collector.py -- Coleta funding rate history da Binance Futures.

Endpoint publico (sem auth): /fapi/v1/fundingRate
Limit 1000 por call, 8h por rate, ~3 rates/dia. Para 2020+: ~5500 dias * 3 = ~16500 rates
=> ~17 calls por symbol. Rate limit 1200/min, super tranquilo.

CLI:
    python binance_funding_collector.py BTCUSDT
    python binance_funding_collector.py BTCUSDT --since 2020-01-01
    python binance_funding_collector.py --symbols BTCUSDT,ETHUSDT,INJUSDT --since 2024-01-01

Output: journal/funding_history/<SYMBOL>.jsonl (1 linha = 1 funding event).

Schema linha:
{"symbol":"BTCUSDT","funding_time":1577836800000,"funding_rate":"0.0001","mark_price":"7195.50"}
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Optional

import urllib.request
import urllib.parse
import urllib.error

ROOT = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "journal" / "funding_history"
BINANCE_FAPI = "https://fapi.binance.com/fapi/v1/fundingRate"
CALL_LIMIT = 1000
SLEEP_BETWEEN_CALLS = 0.25


def _http_get(url: str, timeout: int = 15) -> list:
    req = urllib.request.Request(url, headers={"User-Agent": "coinex-ai-funding-collector/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_funding_chunk(symbol: str, start_ms: int, end_ms: Optional[int] = None) -> list:
    params = {"symbol": symbol, "limit": CALL_LIMIT, "startTime": start_ms}
    if end_ms is not None:
        params["endTime"] = end_ms
    url = BINANCE_FAPI + "?" + urllib.parse.urlencode(params)
    try:
        return _http_get(url)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            time.sleep(5)
            return _http_get(url)
        raise


def collect_symbol(symbol: str, since_ms: int, out_path: Path) -> int:
    """Coleta funding history desde since_ms ate agora. Retorna n linhas escritas."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    written = 0
    cursor = since_ms
    last_ts = None
    with out_path.open("w", encoding="utf-8") as f:
        while True:
            chunk = fetch_funding_chunk(symbol, cursor)
            if not chunk:
                break
            for row in chunk:
                line = {
                    "symbol": row.get("symbol", symbol),
                    "funding_time": int(row["fundingTime"]),
                    "funding_rate": row["fundingRate"],
                    "mark_price": row.get("markPrice", ""),
                }
                f.write(json.dumps(line) + "\n")
                written += 1
                last_ts = int(row["fundingTime"])
            if len(chunk) < CALL_LIMIT:
                break
            # advance cursor para evitar loop infinito (Binance retorna fundingTime asc)
            cursor = last_ts + 1
            time.sleep(SLEEP_BETWEEN_CALLS)
    return written


def parse_since(arg: str) -> int:
    dt = datetime.strptime(arg, "%Y-%m-%d").replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Binance funding history collector.")
    p.add_argument("symbol", nargs="?", help="Symbol unico (ex: BTCUSDT). Use --symbols pra multiplos.")
    p.add_argument("--symbols", help="Lista comma-separated (ex: BTCUSDT,ETHUSDT)")
    p.add_argument("--since", default="2020-01-01", help="Data inicio YYYY-MM-DD (default 2020-01-01)")
    p.add_argument("--out-dir", default=str(OUTPUT_DIR), help="Dir saida (default journal/funding_history)")
    args = p.parse_args(argv)

    if args.symbols:
        symbols = [s.strip().upper() for s in args.symbols.split(",") if s.strip()]
    elif args.symbol:
        symbols = [args.symbol.upper()]
    else:
        p.error("Forneca symbol ou --symbols")
        return 2

    since_ms = parse_since(args.since)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[binance_funding] symbols={symbols} since={args.since} out={out_dir}", flush=True)
    total = 0
    for sym in symbols:
        out_path = out_dir / f"{sym}.jsonl"
        try:
            n = collect_symbol(sym, since_ms, out_path)
            total += n
            print(f"[binance_funding] {sym}: {n} rates -> {out_path.name}", flush=True)
        except Exception as e:
            print(f"[binance_funding] {sym}: ERRO {e}", flush=True)
    print(f"[binance_funding] TOTAL {total} rates", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
