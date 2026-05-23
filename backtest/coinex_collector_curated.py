"""
coinex_collector_curated.py — Coletor para lista CURADA de candidatos.

Diferenças vs coinex_collector.py (genérico top-N por vol):
1. Lista pré-curada (curated_candidates.py)
2. Liquidity haircut Makarov/Schoar (vol × 0.7)
3. Reusa cache existente em journal/candles_coinex/

Pra cada candidato:
  - Se já cached: skip (reusa)
  - Senão: GET /v2/futures/kline?limit=1000
  - Salva em journal/candles_coinex/<MARKET>_1day.json
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
CANDLES_DIR = ROOT_DIR / "journal" / "candles_coinex"
CANDLES_DIR.mkdir(parents=True, exist_ok=True)

sys.path.insert(0, str(SCRIPT_DIR))
from curated_candidates import flatten_curated, LIQUIDITY_HAIRCUT, MIN_VOL_USD_REAL  # noqa
from coinex_collector import fetch_candles, _ts_to_iso  # noqa

COINEX_BASE = "https://api.coinex.com"


def fetch_ticker(market: str) -> Optional[Dict]:
    """Busca ticker de 1 market específico."""
    try:
        r = requests.get(f"{COINEX_BASE}/v2/futures/ticker?market={market}",
                          timeout=10)
        r.raise_for_status()
        d = r.json()
        if d.get("code") != 0:
            return None
        data = d.get("data", [])
        if not data:
            return None
        return data[0]
    except Exception:
        return None


def liquidity_passes(market: str) -> tuple[bool, float]:
    """
    Retorna (passa?, vol_real_usd).
    vol_real = vol_reportado × LIQUIDITY_HAIRCUT (Makarov/Schoar)
    """
    t = fetch_ticker(market)
    if not t:
        return (False, 0.0)
    try:
        vol_reported = float(t.get("value", 0) or 0)
    except Exception:
        vol_reported = 0.0
    vol_real = vol_reported * LIQUIDITY_HAIRCUT
    return (vol_real >= MIN_VOL_USD_REAL, vol_real)


def collect(skip_cached: bool = True) -> Dict:
    candidates = flatten_curated()
    print(f"[curated] {len(candidates)} candidatos para processar")
    print(f"[liquidity] gate: vol_real >= ${MIN_VOL_USD_REAL:,} "
          f"(haircut {(1-LIQUIDITY_HAIRCUT)*100:.0f}%)")

    out = {"period": "1day", "n_total": len(candidates), "pairs": [],
           "skipped_low_vol": [], "errors": []}

    for i, m in enumerate(candidates, 1):
        path = CANDLES_DIR / f"{m}_1day.json"
        if skip_cached and path.exists():
            try:
                with open(path, "r", encoding="utf-8") as f:
                    candles = json.load(f)
                out["pairs"].append({
                    "market": m, "cached": True, "n_candles": len(candles),
                    "first_ts": candles[0]["ts"] if candles else None,
                    "last_ts": candles[-1]["ts"] if candles else None,
                    "vol_real_usd": None,
                })
                print(f"  [{i:2d}] {m:14s} CACHED ({len(candles)} candles)")
                continue
            except Exception:
                pass

        passes, vol_real = liquidity_passes(m)
        if not passes:
            print(f"  [{i:2d}] {m:14s} SKIP liquidez (vol_real=${vol_real:,.0f})")
            out["skipped_low_vol"].append({"market": m, "vol_real_usd": vol_real})
            continue

        try:
            candles = fetch_candles(m, period="1day", limit=1000)
            if not candles:
                out["errors"].append({"market": m, "reason": "empty"})
                continue
            with open(path, "w", encoding="utf-8") as f:
                json.dump(candles, f)
            print(f"  [{i:2d}] {m:14s} OK  {len(candles)} candles  "
                  f"vol_real=${vol_real:,.0f}")
            out["pairs"].append({
                "market": m, "cached": False, "n_candles": len(candles),
                "first_ts": candles[0]["ts"], "last_ts": candles[-1]["ts"],
                "vol_real_usd": vol_real,
            })
            time.sleep(0.15)   # rate limit
        except Exception as e:
            out["errors"].append({"market": m, "reason": str(e)})
            print(f"  [{i:2d}] {m:14s} ERROR {e}")

    summary_path = CANDLES_DIR / "summary_curated_1day.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n[save] {summary_path}")
    print(f"\nResumo: {len(out['pairs'])} coletados, "
          f"{len(out['skipped_low_vol'])} skip liquidez, "
          f"{len(out['errors'])} erros")
    return out


if __name__ == "__main__":
    collect()
