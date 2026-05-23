"""
coinex_collector.py — Coleta top N pares CoinEx por volume + candles 1day.

CoinEx API v2 endpoints públicos (sem auth):
  GET /v2/futures/ticker          — todos tickers + 24h volume
  GET /v2/futures/kline?market=X&period=1day&limit=1000

Salva em journal/candles_coinex/<MARKET>_1day.json para reuso por backtest stack.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Dict, List

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
CANDLES_DIR = ROOT_DIR / "journal" / "candles_coinex"
CANDLES_DIR.mkdir(parents=True, exist_ok=True)

COINEX_BASE = "https://api.coinex.com"


def fetch_all_tickers() -> List[Dict]:
    """Busca todos tickers futures com volume 24h."""
    r = requests.get(f"{COINEX_BASE}/v2/futures/ticker", timeout=15)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 0:
        raise RuntimeError(f"CoinEx error: {d.get('message')}")
    return d.get("data", [])


def top_pairs_by_volume(n: int = 20, quote: str = "USDT",
                         exclude: tuple = ("USDC", "DAI", "TUSD", "FDUSD")) -> List[Dict]:
    """Top N pares por volume USD 24h."""
    tickers = fetch_all_tickers()
    valid = []
    for t in tickers:
        m = t.get("market", "")
        if not m.endswith(quote):
            continue
        # Excluir stables-on-stables
        base = m.replace(quote, "")
        if base in exclude:
            continue
        # Volume em USD = value (já em USDT)
        try:
            vol_usd = float(t.get("value", 0) or 0)
        except Exception:
            vol_usd = 0
        valid.append({"market": m, "vol_usd_24h": vol_usd,
                       "last": float(t.get("last", 0) or 0)})
    valid.sort(key=lambda x: x["vol_usd_24h"], reverse=True)
    return valid[:n]


def fetch_candles(market: str, period: str = "1day", limit: int = 1000) -> List[Dict]:
    """Baixa candles. CoinEx limit max=1000 por chamada."""
    url = f"{COINEX_BASE}/v2/futures/kline?market={market}&period={period}&limit={limit}"
    r = requests.get(url, timeout=15)
    r.raise_for_status()
    d = r.json()
    if d.get("code") != 0:
        raise RuntimeError(f"kline error {market}: {d.get('message')}")
    out = []
    for c in d.get("data", []):
        out.append({
            "ts": _ts_to_iso(c.get("created_at", 0)),
            "open":   float(c.get("open", 0)),
            "high":   float(c.get("high", 0)),
            "low":    float(c.get("low", 0)),
            "close":  float(c.get("close", 0)),
            "volume": float(c.get("volume", 0)),
        })
    return out


def _ts_to_iso(ts_ms: int) -> str:
    """CoinEx created_at é ms. Converte para ISO 8601 UTC."""
    from datetime import datetime, timezone
    if ts_ms > 1e12:   # ms
        secs = ts_ms / 1000.0
    else:              # seconds
        secs = ts_ms
    return datetime.fromtimestamp(secs, tz=timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%S+00:00")


def collect_top_n(n: int = 20, period: str = "1day",
                   sleep_ms: int = 100) -> Dict:
    """Coleta + salva top N pares."""
    print(f"[coinex] Buscando top {n} pares por volume...")
    pairs = top_pairs_by_volume(n=n)
    print(f"[coinex] Top {len(pairs)} encontrados:")
    for i, p in enumerate(pairs, 1):
        print(f"  {i:2d}. {p['market']:15s} vol_24h=${p['vol_usd_24h']:>15,.0f}")

    out = {"period": period, "n": len(pairs), "pairs": []}
    for p in pairs:
        m = p["market"]
        try:
            candles = fetch_candles(m, period=period, limit=1000)
        except Exception as e:
            print(f"  [skip {m}] {e}")
            continue
        if not candles:
            continue
        path = CANDLES_DIR / f"{m}_{period}.json"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(candles, f)
        out["pairs"].append({
            "market": m, "vol_usd_24h": p["vol_usd_24h"],
            "n_candles": len(candles),
            "first_ts": candles[0]["ts"], "last_ts": candles[-1]["ts"],
            "path": str(path.relative_to(ROOT_DIR)).replace("\\", "/"),
        })
        print(f"  [ok] {m}: {len(candles)} candles {candles[0]['ts']} → {candles[-1]['ts']}")
        time.sleep(sleep_ms / 1000.0)

    summary_path = CANDLES_DIR / f"summary_{period}.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {summary_path}")
    return out


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    period = sys.argv[2] if len(sys.argv) > 2 else "1day"
    collect_top_n(n=n, period=period)
