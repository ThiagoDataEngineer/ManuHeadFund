"""
data_collector.py — Coleta candles históricos → Supabase
Fontes suportadas:
  coinex   — CoinEx Futures API (padrão). Paginação para trás via end_time.
  binance  — data.binance.vision (repositório público). ZIPs mensais de klines UM-perpetuals.
  bitstamp — Bitstamp REST API pública. BTCUSD desde 2011, dados USD (não USDT).
  auto     — tenta CoinEx primeiro; se retornar < MIN_AUTO_FALLBACK_CANDLES, usa Binance.

Uso:
    python data_collector.py --market BTCUSDT --period 1hour --years 2
    python data_collector.py --market BTCUSDT --period 1hour --source binance --start 2023-01-01 --end 2025-01-01
    python data_collector.py --market BTCUSD  --period 1hour --source bitstamp --start 2012-01-01 --end 2026-04-30
    python data_collector.py --market ETHUSDT --period 4hour --source auto --years 2
"""
import argparse
import io
import time
import zipfile
from datetime import datetime, timedelta, timezone
from typing import Dict, List

import requests

PERIOD_SECONDS = {
    "1sec": 1,    # Binance daily ZIPs only (data.binance.vision/daily/klines)
    "1min": 60, "3min": 180, "5min": 300, "15min": 900,
    "30min": 1800, "1hour": 3600, "2hour": 7200, "4hour": 14400,
    "6hour": 21600, "12hour": 43200, "1day": 86400,
    "3day": 259200, "1week": 604800,
}

COINEX_KLINE = "https://api.coinex.com/v2/futures/kline"
MAX_LIMIT = 1000
RATE_LIMIT_SLEEP = 0.4

# data.binance.vision — USDT-margined perpetuals (UM futures)
BINANCE_KLINES_BASE_MONTHLY = "https://data.binance.vision/data/futures/um/monthly/klines"
BINANCE_KLINES_BASE_DAILY   = "https://data.binance.vision/data/futures/um/daily/klines"
BINANCE_KLINES_BASE = BINANCE_KLINES_BASE_MONTHLY  # alias para compatibilidade

# Intervals que usam ZIPs diários (sub-minuto) em vez de mensais
BINANCE_DAILY_ONLY = frozenset({"1s"})

# Mapeamento CoinEx → Binance interval string
BINANCE_PERIOD_MAP = {
    "1sec": "1s",  # daily ZIPs; CoinEx não tem equivalente
    "1min":  "1m",  "3min":  "3m",  "5min":  "5m",  "15min": "15m",
    "30min": "30m", "1hour": "1h",  "2hour": "2h",  "4hour": "4h",
    "6hour": "6h",  "12hour":"12h", "1day":  "1d",  "3day":  "3d",
    "1week": "1w",
}

# Threshold para modo auto: se CoinEx retornar menos que este número de candles, usa Binance
MIN_AUTO_FALLBACK_CANDLES = 100

# Bitstamp OHLC API pública (sem auth) — histórico desde 2011 para BTCUSD
BITSTAMP_OHLC_URL = "https://www.bitstamp.net/api/v2/ohlc/{pair}/"
# step suportados pelo Bitstamp (em segundos)
BITSTAMP_STEPS = frozenset({60, 180, 300, 900, 1800, 3600, 7200, 14400, 21600, 43200, 86400, 259200})
BITSTAMP_MAX_LIMIT = 1000


# ── Parsers ───────────────────────────────────────────────────────────────────

def parse_candle(raw: Dict, market: str, period: str) -> Dict:
    """Converte candle da CoinEx API para o schema do Supabase."""
    ts_ms = raw["created_at"]
    ts_iso = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).isoformat()
    return {
        "market": market,
        "period": period,
        "ts": ts_iso,
        "open":   float(raw["open"]),
        "high":   float(raw["high"]),
        "low":    float(raw["low"]),
        "close":  float(raw["close"]),
        "volume": float(raw["volume"]),
    }


def parse_binance_candle(row: List, market: str, period: str) -> Dict:
    """Converte uma linha do CSV Binance para o schema do Supabase.

    Formato Binance: open_time, open, high, low, close, volume, close_time, ...
    Usa open_time (não close_time) para manter consistência com CoinEx.
    """
    ts_ms = int(row[0])
    ts_iso = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc).isoformat()
    return {
        "market": market,
        "period": period,
        "ts": ts_iso,
        "open":   float(row[1]),
        "high":   float(row[2]),
        "low":    float(row[3]),
        "close":  float(row[4]),
        "volume": float(row[5]),
    }


# ── Paginação (legado, mantido para compatibilidade) ──────────────────────────

def paginate_candles(start: str, end: str, period: str, limit: int = MAX_LIMIT):
    """Gera janelas para paginação — mantido para compatibilidade com testes."""
    period_sec = PERIOD_SECONDS.get(period, 3600)
    window_ms = period_sec * limit * 1000

    start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
    end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)

    start_ms = int(start_dt.timestamp() * 1000)
    end_ms = int(end_dt.timestamp() * 1000)

    cursor = start_ms
    while cursor < end_ms:
        window_end = min(cursor + window_ms, end_ms)
        yield {"start_ts": cursor, "end_ts": window_end}
        cursor = window_end


# ── CoinExCollector ───────────────────────────────────────────────────────────

class CoinExCollector:
    def __init__(self, db):
        self.db = db

    def _fetch_batch(self, market: str, period: str, end_time_ms: int) -> List[Dict]:
        params = {
            "market": market,
            "period": period,
            "limit": MAX_LIMIT,
            "end_time": end_time_ms,
        }
        resp = requests.get(COINEX_KLINE, params=params, timeout=15)
        if resp.status_code != 200:
            raise Exception(f"CoinEx API erro {resp.status_code}: {resp.text[:200]}")
        data = resp.json()
        if isinstance(data, dict) and data.get("code", 0) not in (0, 200):
            raise Exception(f"CoinEx API código {data.get('code')}: {data.get('message')}")
        return data.get("data", [])

    def fetch_and_store(self, market: str, period: str, start: str, end: str) -> int:
        start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
        end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)

        total = 0
        cursor_ms = end_ms
        batch_num = 0

        while cursor_ms > start_ms:
            raw_candles = self._fetch_batch(market, period, cursor_ms)

            if not raw_candles:
                break

            in_range = [c for c in raw_candles if c["created_at"] >= start_ms]

            if in_range:
                parsed = [parse_candle(c, market, period) for c in in_range]
                self.db.upsert_candles(parsed)
                total += len(parsed)

            batch_num += 1
            oldest_ms = raw_candles[0]["created_at"]
            print(f"  {market} {period} batch {batch_num} — {len(in_range)} candles | "
                  f"oldest: {datetime.fromtimestamp(oldest_ms/1000, tz=timezone.utc).strftime('%Y-%m-%d')} "
                  f"| total: {total}")

            cursor_ms = oldest_ms - 1

            if oldest_ms <= start_ms:
                break

            time.sleep(RATE_LIMIT_SLEEP)

        return total


# ── BinanceCollector ──────────────────────────────────────────────────────────

class BinanceCollector:
    """Coleta klines de USDT-margined perpetuals do repositório público data.binance.vision.

    Binance e CoinEx têm preços praticamente idênticos para BTC/ETH/SOL via arbitragem.
    Ideal como fallback quando CoinEx não tem histórico suficiente.
    URL pattern: {BINANCE_KLINES_BASE}/{symbol}/{interval}/{symbol}-{interval}-{YYYY}-{MM}.zip
    """

    def __init__(self, db):
        self.db = db

    def _parse_zip(self, content: bytes) -> List[List]:
        """Extrai rows de dados de um ZIP Binance. Descarta header e linhas incompletas."""
        with zipfile.ZipFile(io.BytesIO(content)) as z:
            with z.open(z.namelist()[0]) as f:
                lines = f.read().decode("utf-8").strip().split("\n")
        rows = []
        for line in lines:
            if not line:
                continue
            parts = line.strip().split(",")
            if len(parts) < 6:
                continue
            if not parts[0].isdigit():
                continue
            rows.append(parts)
        return rows

    def _fetch_month(self, symbol: str, interval: str, year: int, month: int) -> List[List]:
        """Baixa ZIP mensal de klines (>= 1m). Retorna lista de rows."""
        url = f"{BINANCE_KLINES_BASE_MONTHLY}/{symbol}/{interval}/{symbol}-{interval}-{year}-{month:02d}.zip"
        resp = requests.get(url, timeout=30)
        if resp.status_code == 404:
            return []
        if resp.status_code != 200:
            raise Exception(f"Binance data {resp.status_code}: {url}")
        return self._parse_zip(resp.content)

    def _fetch_daily(self, symbol: str, interval: str, date: datetime) -> List[List]:
        """Baixa ZIP diário de klines sub-minuto (ex: 1s). Retorna lista de rows."""
        url = (f"{BINANCE_KLINES_BASE_DAILY}/{symbol}/{interval}/"
               f"{symbol}-{interval}-{date.strftime('%Y-%m-%d')}.zip")
        resp = requests.get(url, timeout=30)
        if resp.status_code == 404:
            return []
        if resp.status_code != 200:
            raise Exception(f"Binance daily data {resp.status_code}: {url}")
        return self._parse_zip(resp.content)

    def fetch_and_store(self, market: str, period: str, start: str, end: str) -> int:
        interval = BINANCE_PERIOD_MAP.get(period)
        if not interval:
            raise ValueError(f"Period '{period}' not supported by Binance source")

        start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
        end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
        start_ms = int(start_dt.timestamp() * 1000)
        end_ms = int(end_dt.timestamp() * 1000)

        total = 0

        if interval in BINANCE_DAILY_ONLY:
            # ZIPs diários: 1 arquivo por dia (usado para 1s e outros sub-minuto)
            current = start_dt.replace(hour=0, minute=0, second=0, microsecond=0)
            while current <= end_dt:
                raw_rows = self._fetch_daily(market, interval, current)
                in_range = [r for r in raw_rows if start_ms <= int(r[0]) <= end_ms]
                if in_range:
                    parsed = [parse_binance_candle(r, market, period) for r in in_range]
                    self.db.upsert_candles(parsed)
                    total += len(in_range)
                    print(f"  {market} {period} {current.strftime('%Y-%m-%d')} "
                          f"[Binance daily] — {len(in_range)} candles | total: {total}")
                current = current + timedelta(days=1)
                time.sleep(RATE_LIMIT_SLEEP)
        else:
            # ZIPs mensais: 1 arquivo por mês (>= 1m)
            current = start_dt.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
            while current <= end_dt:
                raw_rows = self._fetch_month(market, interval, current.year, current.month)
                in_range = [r for r in raw_rows if start_ms <= int(r[0]) <= end_ms]
                if in_range:
                    parsed = [parse_binance_candle(r, market, period) for r in in_range]
                    self.db.upsert_candles(parsed)
                    total += len(in_range)
                    print(f"  {market} {period} {current.year}-{current.month:02d} "
                          f"[Binance] — {len(in_range)} candles | total: {total}")
                if current.month == 12:
                    current = current.replace(year=current.year + 1, month=1)
                else:
                    current = current.replace(month=current.month + 1)
                time.sleep(RATE_LIMIT_SLEEP)

        return total


# ── BitstampCollector ─────────────────────────────────────────────────────────

class BitstampCollector:
    """Coleta OHLCV da API pública Bitstamp.

    Endpoint: GET /api/v2/ohlc/{pair}/?step=<sec>&limit=1000&start=<unix>&end=<unix>
    Paginação para frente: incrementa start após cada batch.
    Mercado deve ser no formato Bitstamp: BTCUSD → 'btcusd', ETHUSD → 'ethusd'.
    """

    def __init__(self, db):
        self.db = db

    def _period_to_step(self, period: str) -> int:
        step = PERIOD_SECONDS.get(period)
        if step is None:
            raise ValueError(f"Period '{period}' desconhecido")
        if step not in BITSTAMP_STEPS:
            supported = sorted(BITSTAMP_STEPS)
            raise ValueError(
                f"Bitstamp não suporta step={step}s (period='{period}'). "
                f"Suportados (segundos): {supported}"
            )
        return step

    def _fetch_batch(self, pair: str, step: int, start_ts: int, end_ts: int) -> List[Dict]:
        url = BITSTAMP_OHLC_URL.format(pair=pair.lower())
        params = {"step": step, "limit": BITSTAMP_MAX_LIMIT, "start": start_ts, "end": end_ts}
        resp = requests.get(url, params=params, timeout=15)
        if resp.status_code != 200:
            raise Exception(f"Bitstamp API erro {resp.status_code}: {resp.text[:200]}")
        payload = resp.json()
        return payload.get("data", {}).get("ohlc", [])

    def fetch_and_store(self, market: str, period: str, start: str, end: str) -> int:
        step = self._period_to_step(period)
        start_dt = datetime.fromisoformat(start).replace(tzinfo=timezone.utc)
        end_dt = datetime.fromisoformat(end).replace(tzinfo=timezone.utc)
        start_ts = int(start_dt.timestamp())
        end_ts = int(end_dt.timestamp())

        total = 0
        # Pagina para trás: começa do end e recua até start (igual ao CoinExCollector)
        cursor_end = end_ts
        batch_num = 0

        while cursor_end > start_ts:
            # Bitstamp: limit candles terminando em cursor_end
            raw = self._fetch_batch(market, step, start_ts, cursor_end)
            if not raw:
                break

            in_range = [c for c in raw if start_ts <= int(c["timestamp"]) <= cursor_end]
            if not in_range:
                break

            parsed = []
            for c in in_range:
                ts = int(c["timestamp"])
                ts_iso = datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()
                parsed.append({
                    "market": market,
                    "period": period,
                    "ts":     ts_iso,
                    "open":   float(c["open"]),
                    "high":   float(c["high"]),
                    "low":    float(c["low"]),
                    "close":  float(c["close"]),
                    "volume": float(c["volume"]),
                })

            if parsed:
                self.db.upsert_candles(parsed)
                total += len(parsed)

            batch_num += 1
            oldest_ts = int(in_range[0]["timestamp"])
            print(f"  {market} {period} batch {batch_num} — {len(parsed)} candles | "
                  f"oldest: {datetime.fromtimestamp(oldest_ts, tz=timezone.utc).strftime('%Y-%m-%d')} "
                  f"| total: {total}")

            # Se batch retornou < limit, chegamos ao início do histórico
            if len(raw) < BITSTAMP_MAX_LIMIT or oldest_ts <= start_ts:
                break

            cursor_end = oldest_ts - step
            time.sleep(RATE_LIMIT_SLEEP)

        return total


# ── CLI ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Coleta candles históricos → Supabase")
    parser.add_argument("--market", default="BTCUSDT")
    parser.add_argument("--period", default="1hour", choices=sorted(PERIOD_SECONDS.keys()))
    parser.add_argument("--years", type=int, default=2)
    parser.add_argument("--start", default=None)
    parser.add_argument("--end", default=None)
    parser.add_argument("--source", default="coinex", choices=["coinex", "binance", "bitstamp", "auto"],
                        help="coinex (padrão) | binance (data.binance.vision) | "
                             "bitstamp (API pública, BTCUSD desde 2011) | "
                             "auto (tenta CoinEx, usa Binance se insuficiente)")
    args = parser.parse_args()

    end_dt = datetime.now(tz=timezone.utc)
    start_dt = datetime(end_dt.year - args.years, end_dt.month, end_dt.day, tzinfo=timezone.utc)

    start = args.start or start_dt.strftime("%Y-%m-%d")
    end   = args.end   or end_dt.strftime("%Y-%m-%d")

    import os
    from db import Database
    key = os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
    db = Database(url=os.environ["SUPABASE_URL"], key=key)

    print(f"\nColetando {args.market} {args.period} de {start} até {end} [fonte: {args.source}]...")

    if args.source == "coinex":
        collector = CoinExCollector(db=db)
        total = collector.fetch_and_store(args.market, args.period, start, end)

    elif args.source == "binance":
        collector = BinanceCollector(db=db)
        total = collector.fetch_and_store(args.market, args.period, start, end)

    elif args.source == "bitstamp":
        collector = BitstampCollector(db=db)
        total = collector.fetch_and_store(args.market, args.period, start, end)

    else:  # auto
        coinex = CoinExCollector(db=db)
        total = coinex.fetch_and_store(args.market, args.period, start, end)
        if total < MIN_AUTO_FALLBACK_CANDLES:
            print(f"\nCoinEx retornou apenas {total} candles (< {MIN_AUTO_FALLBACK_CANDLES}). "
                  f"Tentando Binance como fallback...")
            binance = BinanceCollector(db=db)
            total += binance.fetch_and_store(args.market, args.period, start, end)

    print(f"\nConcluído. {total} candles armazenados no Supabase.")


if __name__ == "__main__":
    main()
