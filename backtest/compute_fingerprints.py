"""
compute_fingerprints.py — Popula a tabela pump_fingerprints no Supabase.

Lê candles 1min da tabela `candles` para cada par seed (PEPE, WIF, BONK, SKYAI, AIDOGE),
calcula métricas de fingerprint na janela de pump inicial (primeiras 4h após spike),
e faz upsert na tabela pump_fingerprints.

Uso:
    python backtest/compute_fingerprints.py
    python backtest/compute_fingerprints.py --market SKYAIUSDT --window 240
    python backtest/compute_fingerprints.py --dry-run
"""
import os
import sys
import math
import json
import argparse
import statistics
from datetime import datetime, timezone
from typing import List, Dict, Optional

# resolve imports when run from project root or backtest/
sys.path.insert(0, os.path.dirname(__file__))
from db import Database


# ── Seed pairs com outcome conhecido ──────────────────────────────────────────

SEED_PAIRS = [
    {"market": "PEPEUSDT",   "outcome_pct": 320.0,  "spike_date": "2023-04-18"},
    {"market": "WIFUSDT",    "outcome_pct": 1800.0, "spike_date": "2023-12-01"},
    {"market": "BONKUSDT",   "outcome_pct": 850.0,  "spike_date": "2023-12-25"},
    {"market": "SKYAIUSDT",  "outcome_pct": 441.0,  "spike_date": None},
    {"market": "AIDOGEUSDT", "outcome_pct": -30.0,  "spike_date": None},
]


# ── Métricas de fingerprint ────────────────────────────────────────────────────

def _coefficient_of_variation(values: List[float]) -> float:
    """CV = std / mean; indicador de heterogeneidade de volume."""
    if len(values) < 2:
        return 0.0
    mean = statistics.mean(values)
    if mean == 0:
        return 0.0
    return statistics.stdev(values) / mean


def _green_ratio(candles: List[Dict]) -> float:
    """Fração de candles de alta (close > open)."""
    if not candles:
        return 0.0
    green = sum(1 for c in candles if float(c["close"]) > float(c["open"]))
    return green / len(candles)


def _body_ratio(candles: List[Dict]) -> float:
    """Razão média (corpo / range total) — candles longas = direcional."""
    if not candles:
        return 0.0
    ratios = []
    for c in candles:
        h, l = float(c["high"]), float(c["low"])
        total_range = h - l
        if total_range == 0:
            continue
        body = abs(float(c["close"]) - float(c["open"]))
        ratios.append(body / total_range)
    return statistics.mean(ratios) if ratios else 0.0


def _max_retraction(candles: List[Dict]) -> float:
    """
    Retração máxima do pico durante a janela.
    Quanto menor, mais forte o pump (menos realizações).
    """
    if len(candles) < 2:
        return 0.0
    closes = [float(c["close"]) for c in candles]
    peak = closes[0]
    max_ret = 0.0
    for price in closes:
        if price > peak:
            peak = price
        elif peak > 0:
            ret = (peak - price) / peak
            if ret > max_ret:
                max_ret = ret
    return max_ret


def _vol_accel(candles: List[Dict], split: int = 4) -> float:
    """
    Aceleração de volume: ratio entre 2ª metade e 1ª metade da janela.
    > 1.0 = aceleração (demand aumentando); < 1.0 = desaceleração.
    """
    if len(candles) < split * 2:
        return 1.0
    mid = len(candles) // 2
    first_half = [float(c["volume"]) for c in candles[:mid]]
    second_half = [float(c["volume"]) for c in candles[mid:]]
    avg_first = statistics.mean(first_half)
    avg_second = statistics.mean(second_half)
    if avg_first == 0:
        return 1.0
    return avg_second / avg_first


def compute_fingerprint(candles: List[Dict], window_minutes: int = 240) -> Dict:
    """
    Computa todas as métricas para a janela de pump inicial.
    candles: list de dicts com keys open/high/low/close/volume (strings ou floats)
    """
    window = candles[:window_minutes]  # primeiros N candles 1min = primeiras N min
    volumes = [float(c["volume"]) for c in window]

    return {
        "cv_volume":      round(_coefficient_of_variation(volumes), 4),
        "green_ratio":    round(_green_ratio(window), 4),
        "body_ratio":     round(_body_ratio(window), 4),
        "max_retraction": round(_max_retraction(window), 4),
        "vol_accel":      round(_vol_accel(window), 4),
    }


# ── Upsert helpers ────────────────────────────────────────────────────────────

def upsert_fingerprints(db: Database, records: List[Dict]) -> None:
    """Upsert em lotes via db._post com on_conflict=market."""
    if not records:
        return
    for i in range(0, len(records), 100):
        batch = records[i:i + 100]
        db._post("pump_fingerprints", batch, on_conflict="market")
    print(f"  -> upserted {len(records)} fingerprint(s)")


# ── Fetch candles ──────────────────────────────────────────────────────────────

def fetch_candles_for_market(db: Database, market: str,
                              spike_date: Optional[str]) -> List[Dict]:
    """
    Busca candles 1min para a janela de pump inicial.
    Se spike_date for None, usa os 240 candles mais recentes disponíveis.
    """
    if spike_date:
        date_from = spike_date + "T00:00:00Z"
        date_to   = spike_date + "T04:00:00Z"
        candles = db.get_candles(market, "1min", date_from, date_to)
    else:
        # fallback: 240 registros mais recentes
        params = (
            f"select=*"
            f"&market=eq.{market}"
            f"&period=eq.1min"
            f"&order=ts.desc"
            f"&limit=240"
        )
        candles = db._get("pump_fingerprints_candles_fallback", params)
        # se a tabela não existir, tenta candles genérica
        if not candles:
            params2 = (
                f"select=*"
                f"&market=eq.{market}"
                f"&period=eq.1min"
                f"&order=ts.desc"
                f"&limit=240"
            )
            candles = db._get("candles", params2)
        candles = list(reversed(candles))  # ascending order
    return candles


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Compute pump fingerprints and upsert to Supabase")
    parser.add_argument("--market",  help="Single market to compute (default: all seeds)")
    parser.add_argument("--window",  type=int, default=240, help="Minutes window (default: 240)")
    parser.add_argument("--dry-run", action="store_true", help="Compute but do not upsert")
    args = parser.parse_args()

    db = Database()

    pairs = SEED_PAIRS
    if args.market:
        pairs = [p for p in SEED_PAIRS if p["market"] == args.market]
        if not pairs:
            # allow arbitrary market with --market flag even if not in seeds
            pairs = [{"market": args.market, "outcome_pct": 0.0, "spike_date": None}]

    records = []
    for seed in pairs:
        market = seed["market"]
        print(f"[{market}] fetching candles...")
        try:
            candles = fetch_candles_for_market(db, market, seed.get("spike_date"))
        except Exception as e:
            print(f"  WARN: could not fetch candles — {e}")
            candles = []

        if len(candles) < 10:
            print(f"  SKIP: only {len(candles)} candles found (need >= 10)")
            continue

        metrics = compute_fingerprint(candles, window_minutes=args.window)
        record = {
            "market":      market,
            "outcome_pct": seed["outcome_pct"],
            **metrics,
            "notes": f"seed pair — spike_date={seed.get('spike_date')} window={args.window}min",
        }
        records.append(record)
        print(f"  cv={metrics['cv_volume']:.3f}  green={metrics['green_ratio']:.2f}"
              f"  body={metrics['body_ratio']:.2f}  retraction={metrics['max_retraction']:.2f}"
              f"  accel={metrics['vol_accel']:.2f}  outcome={seed['outcome_pct']:+.0f}%")

    if not records:
        print("Nothing to upsert.")
        return

    if args.dry_run:
        print("\n-- DRY RUN --")
        print(json.dumps(records, indent=2))
        return

    upsert_fingerprints(db, records)
    print(f"\nDone. {len(records)} pair(s) upserted to pump_fingerprints.")


if __name__ == "__main__":
    main()
