"""
fetch_xrp_bitstamp.py -- Baixa candles XRPUSD 1h da Bitstamp (2017-08 -> 2026-05).

Bitstamp OHLC endpoint:
  GET https://www.bitstamp.net/api/v2/ohlc/{currency_pair}/
  ?step=3600&limit=1000&start=<unix>&end=<unix>

Pagina automaticamente para cobrir 8+ anos (N ~70.000 candles esperado).
Salva em: backtest/xrp_bitstamp_1h.json (cache para não re-baixar)

Uso:
    python fetch_xrp_bitstamp.py              # baixa tudo
    python fetch_xrp_bitstamp.py --verify     # só verifica o cache existente
"""
from __future__ import annotations

import json
import time
import sys
import argparse
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Dict, Optional

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
CACHE_FILE = SCRIPT_DIR / "xrp_bitstamp_1h.json"

# Período alvo
START_TS = int(datetime(2017, 8, 1, tzinfo=timezone.utc).timestamp())
END_TS   = int(datetime(2026, 5, 15, 23, 59, 59, tzinfo=timezone.utc).timestamp())

BITSTAMP_STEP = 3600   # 1 hora em segundos
BITSTAMP_LIMIT = 1000  # máximo por request
PAIR = "xrpusd"

MAX_RETRIES = 3
SLEEP_BETWEEN = 0.5    # segundos entre requests (rate limit)


def fetch_page(start: int, end: int) -> Optional[List[Dict]]:
    """Busca uma página de candles Bitstamp. Retorna lista ou None em erro."""
    url = f"https://www.bitstamp.net/api/v2/ohlc/{PAIR}/"
    params = {
        "step": BITSTAMP_STEP,
        "limit": BITSTAMP_LIMIT,
        "start": start,
        "end": end,
    }
    for attempt in range(MAX_RETRIES):
        try:
            r = requests.get(url, params=params, timeout=30)
            r.raise_for_status()
            data = r.json()
            ohlc_list = data.get("data", {}).get("ohlc", [])
            return ohlc_list
        except requests.exceptions.RequestException as e:
            print(f"  [WARN] Tentativa {attempt+1}/{MAX_RETRIES} falhou: {e}")
            if attempt < MAX_RETRIES - 1:
                time.sleep(2 ** attempt)
    return None


def normalize_candle(raw: Dict) -> Dict:
    """Normaliza candle Bitstamp para schema padrão {ts, open, high, low, close, volume}."""
    ts_unix = int(raw["timestamp"])
    dt = datetime.fromtimestamp(ts_unix, tz=timezone.utc)
    return {
        "ts": dt.strftime("%Y-%m-%dT%H:%M:%S"),
        "ts_unix": ts_unix,
        "open": float(raw["open"]),
        "high": float(raw["high"]),
        "low": float(raw["low"]),
        "close": float(raw["close"]),
        "volume": float(raw["volume"]),
        "market": "XRPUSD",
        "period": "1hour",
    }


def fetch_all_xrp(start_ts: int = START_TS, end_ts: int = END_TS) -> List[Dict]:
    """
    Pagina toda a série 2017-08 -> 2026-05 em blocos de 1000 candles (1h cada).
    Um bloco de 1000 candles cobre 1000h = ~41.7 dias.
    8 anos ≈ 70.080h → ~71 páginas.
    """
    candles: List[Dict] = []
    seen_ts = set()

    current_start = start_ts
    page = 0
    total_requests = 0
    max_pages = 200  # safety limit

    print(f"[fetch_all_xrp] Iniciando: {datetime.fromtimestamp(start_ts, tz=timezone.utc).date()} -> "
          f"{datetime.fromtimestamp(end_ts, tz=timezone.utc).date()}")

    while current_start < end_ts and page < max_pages:
        page += 1
        current_end = min(current_start + BITSTAMP_STEP * BITSTAMP_LIMIT, end_ts)
        total_requests += 1

        print(f"  Page {page:3d}: {datetime.fromtimestamp(current_start, tz=timezone.utc).date()} "
              f"-> {datetime.fromtimestamp(current_end, tz=timezone.utc).date()} ...", end="", flush=True)

        raw_candles = fetch_page(current_start, current_end)

        if raw_candles is None:
            print(f" ERRO (pulando bloco)")
            current_start = current_end + BITSTAMP_STEP
            continue

        new_count = 0
        for raw in raw_candles:
            ts_unix = int(raw.get("timestamp", 0))
            if ts_unix in seen_ts or ts_unix < start_ts or ts_unix > end_ts:
                continue
            seen_ts.add(ts_unix)
            candles.append(normalize_candle(raw))
            new_count += 1

        print(f" {new_count} novos (total: {len(candles)})")

        if len(raw_candles) == 0:
            # Sem dados neste bloco (possível gap ou fim)
            current_start = current_end + BITSTAMP_STEP
        else:
            # Avança para a próxima janela após o último candle recebido
            last_ts = max(int(c["timestamp"]) for c in raw_candles)
            current_start = last_ts + BITSTAMP_STEP

        time.sleep(SLEEP_BETWEEN)

    # Ordena por timestamp
    candles.sort(key=lambda c: c["ts_unix"])
    print(f"\n[fetch_all_xrp] Total: {len(candles)} candles em {total_requests} requests")
    return candles


def analyze_gaps(candles: List[Dict]) -> Dict:
    """Analisa gaps maiores que 24h na série."""
    if len(candles) < 2:
        return {"n_gaps_24h": 0, "max_gap_hours": 0, "gaps": []}

    gaps = []
    for i in range(1, len(candles)):
        delta_h = (candles[i]["ts_unix"] - candles[i-1]["ts_unix"]) / 3600
        if delta_h > 24:
            gaps.append({
                "start": candles[i-1]["ts"],
                "end": candles[i]["ts"],
                "gap_hours": round(delta_h, 1),
            })

    max_gap = max((g["gap_hours"] for g in gaps), default=0)
    return {
        "n_gaps_24h": len(gaps),
        "max_gap_hours": max_gap,
        "gaps": gaps[:20],  # primeiros 20
    }


def verify_coverage(candles: List[Dict]) -> Dict:
    """Verifica cobertura das 3 janelas SEC."""
    SEC_START_TS = int(datetime(2020, 12, 22, tzinfo=timezone.utc).timestamp())
    SEC_END_TS   = int(datetime(2023, 7, 13, tzinfo=timezone.utc).timestamp())

    pre_sec   = [c for c in candles if c["ts_unix"] < SEC_START_TS]
    during    = [c for c in candles if SEC_START_TS <= c["ts_unix"] < SEC_END_TS]
    post_sec  = [c for c in candles if c["ts_unix"] >= SEC_END_TS]

    return {
        "pre_sec":    {"n": len(pre_sec),   "start": pre_sec[0]["ts"]   if pre_sec   else None, "end": pre_sec[-1]["ts"]   if pre_sec   else None},
        "during_sec": {"n": len(during),    "start": during[0]["ts"]    if during    else None, "end": during[-1]["ts"]    if during    else None},
        "post_sec":   {"n": len(post_sec),  "start": post_sec[0]["ts"]  if post_sec  else None, "end": post_sec[-1]["ts"]  if post_sec  else None},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true", help="Só verifica cache existente")
    parser.add_argument("--force", action="store_true", help="Força re-download ignorando cache")
    args = parser.parse_args()

    if args.verify and not CACHE_FILE.exists():
        print(f"[ERRO] Cache não encontrado: {CACHE_FILE}")
        sys.exit(1)

    if CACHE_FILE.exists() and not args.force:
        print(f"[fetch] Cache encontrado: {CACHE_FILE}")
        with open(CACHE_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        candles = data.get("candles", [])
        print(f"[fetch] {len(candles)} candles carregados do cache")
    else:
        print("[fetch] Baixando da Bitstamp ...")
        candles = fetch_all_xrp()

        if len(candles) < 10000:
            print(f"[ERRO CRÍTICO] Apenas {len(candles)} candles — muito pouco. Abortar.")
            sys.exit(1)

        # Salva cache
        gap_analysis = analyze_gaps(candles)
        coverage = verify_coverage(candles)
        cache_data = {
            "downloaded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "source": "bitstamp_api_v2",
            "pair": PAIR,
            "step_seconds": BITSTAMP_STEP,
            "period": "1hour",
            "n_candles": len(candles),
            "date_range": {
                "start": candles[0]["ts"] if candles else None,
                "end": candles[-1]["ts"] if candles else None,
            },
            "gap_analysis": gap_analysis,
            "coverage": coverage,
            "candles": candles,
        }

        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache_data, f, ensure_ascii=False, separators=(",", ":"))
        print(f"[fetch] Cache salvo: {CACHE_FILE} ({CACHE_FILE.stat().st_size // 1024}KB)")

    # Report final
    gap_analysis = analyze_gaps(candles)
    coverage = verify_coverage(candles)

    print(f"\n=== Verificação XRP Data ===")
    print(f"  N candles total: {len(candles)}")
    if candles:
        print(f"  Período: {candles[0]['ts']} -> {candles[-1]['ts']}")
    print(f"  Gaps >24h: {gap_analysis['n_gaps_24h']} (max: {gap_analysis['max_gap_hours']:.1f}h)")
    print(f"  Pre-SEC: {coverage['pre_sec']['n']} candles")
    print(f"  Durante-SEC: {coverage['during_sec']['n']} candles")
    print(f"  Pós-SEC: {coverage['post_sec']['n']} candles")

    if len(candles) < 40000:
        print(f"\n[WARN] N candles ({len(candles)}) abaixo do esperado (40k mínimo)")
    else:
        print(f"\n[OK] Cobertura suficiente para Simons Gate XRP")

    return candles


if __name__ == "__main__":
    main()
