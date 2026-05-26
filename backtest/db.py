"""
db.py — Abstração do banco de dados via Supabase REST API (PostgREST)
Usa requests diretamente — sem dependência da supabase-py que trava em alguns ambientes.
Trocar banco = trocar apenas este arquivo.

Schema-aware (Etapa 5, 2026-05-26):
  Tabelas candles/backtest_* movidas para schema 'manuheadfund'.
  Cliente envia Accept-Profile (GET) e Content-Profile (POST/DELETE) headers.
  Fallback para 'public' via env SUPABASE_SCHEMA=public (rollback).
"""
import os
import json
import requests
from typing import List, Dict, Optional


# Tabelas do ManuHeadFund que vivem no schema dedicado
MANUHEADFUND_TABLES = {
    "candles", "backtest_runs", "backtest_signals", "backtest_trades",
    "trailing_positions", "capital_context", "validation_snapshots",
    "mentor_reviews", "trade_outcomes", "state_smoke",
}


class Database:
    def __init__(self, url: Optional[str] = None, key: Optional[str] = None,
                 schema: Optional[str] = None):
        self.url = (url or os.environ["SUPABASE_URL"]).rstrip("/")
        self.key = key or os.environ.get("SUPABASE_SERVICE_KEY") or os.environ["SUPABASE_ANON_KEY"]
        # Schema padrao 'manuheadfund' para tabelas listadas em MANUHEADFUND_TABLES.
        # Override via env SUPABASE_SCHEMA (e.g., "public" para rollback).
        self.schema = schema or os.environ.get("SUPABASE_SCHEMA", "manuheadfund")
        self.headers = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }
        # Alias para compatibilidade com testes que verificam self.client
        self.client = self

    def _table_headers(self, table: str, method: str) -> Dict[str, str]:
        """Build per-request headers, adding Accept-Profile/Content-Profile when
        accessing manuheadfund tables in non-public schema."""
        headers = dict(self.headers)
        # Strip table_name leading 'rest/v1/' if caller already adds prefix
        bare = table.split("/")[-1].split("?")[0]
        if bare in MANUHEADFUND_TABLES and self.schema and self.schema != "public":
            if method.upper() in ("GET", "HEAD"):
                headers["Accept-Profile"] = self.schema
            else:
                headers["Content-Profile"] = self.schema
        return headers

    def _get(self, table: str, params: str = "") -> List[Dict]:
        h = self._table_headers(table, "GET")
        r = requests.get(f"{self.url}/rest/v1/{table}?{params}", headers=h, timeout=15)
        r.raise_for_status()
        return r.json()

    def _post(self, table: str, data: List[Dict], on_conflict: Optional[str] = None) -> List[Dict]:
        url = f"{self.url}/rest/v1/{table}"
        if on_conflict:
            url += f"?on_conflict={on_conflict}"
        h = self._table_headers(table, "POST")
        h["Prefer"] = "return=representation,resolution=merge-duplicates"
        r = requests.post(url, headers=h, data=json.dumps(data), timeout=30)
        r.raise_for_status()
        return r.json() if r.text else []

    # ── Candles ───────────────────────────────────────────────────────────────

    def upsert_candles(self, candles: List[Dict]) -> None:
        if not candles:
            return
        # enviar em lotes de 500 para evitar payload muito grande
        for i in range(0, len(candles), 500):
            batch = candles[i:i + 500]
            self._post("candles", batch, on_conflict="market,period,ts")

    def get_candles(self, market: str, period: str, date_from: str, date_to: str) -> List[Dict]:
        # Pagina em lotes de 1000 para contornar o limite padrão do PostgREST
        all_rows: List[Dict] = []
        offset = 0
        page_size = 1000
        while True:
            params = (
                f"select=*"
                f"&market=eq.{market}"
                f"&period=eq.{period}"
                f"&ts=gte.{date_from}"
                f"&ts=lte.{date_to}"
                f"&order=ts.asc"
                f"&limit={page_size}&offset={offset}"
            )
            rows = self._get("candles", params)
            all_rows.extend(rows)
            if len(rows) < page_size:
                break
            offset += page_size
        return all_rows

    # ── Signals ───────────────────────────────────────────────────────────────

    def insert_signal(self, signal: Dict) -> int:
        result = self._post("backtest_signals", [signal])
        return result[0]["id"] if result else 0

    def insert_signals_bulk(self, signals: List[Dict], batch_size: int = 500) -> int:
        total = 0
        for i in range(0, len(signals), batch_size):
            self._post("backtest_signals", signals[i:i + batch_size])
            total += len(signals[i:i + batch_size])
        return total

    def get_signals(self, market: str, period: str, date_from: str, date_to: str) -> List[Dict]:
        all_rows: List[Dict] = []
        offset = 0
        page_size = 1000
        while True:
            params = (
                f"select=*"
                f"&market=eq.{market}"
                f"&period=eq.{period}"
                f"&bar_ts=gte.{date_from}"
                f"&bar_ts=lte.{date_to}"
                f"&order=bar_ts.asc"
                f"&limit={page_size}&offset={offset}"
            )
            rows = self._get("backtest_signals", params)
            all_rows.extend(rows)
            if len(rows) < page_size:
                break
            offset += page_size
        return all_rows

    def clear_signals(self, market: str, period: str) -> None:
        # trades primeiro (FK), depois signals
        self.clear_trades(market, period)
        url = f"{self.url}/rest/v1/backtest_signals?market=eq.{market}&period=eq.{period}"
        h = self._table_headers("backtest_signals", "DELETE")
        requests.delete(url, headers=h, timeout=30).raise_for_status()

    def clear_trades(self, market: str, period: str = "") -> None:
        url = f"{self.url}/rest/v1/backtest_trades?market=eq.{market}"
        h = self._table_headers("backtest_trades", "DELETE")
        requests.delete(url, headers=h, timeout=30).raise_for_status()

    # ── Trades ────────────────────────────────────────────────────────────────

    def insert_trade(self, trade: Dict) -> int:
        result = self._post("backtest_trades", [trade])
        return result[0]["id"] if result else 0

    def insert_trades_bulk(self, trades: List[Dict], batch_size: int = 500) -> int:
        total = 0
        for i in range(0, len(trades), batch_size):
            self._post("backtest_trades", trades[i:i + batch_size])
            total += len(trades[i:i + batch_size])
        return total

    # ── Backtest Runs ─────────────────────────────────────────────────────────

    def insert_run(self, run: Dict) -> int:
        result = self._post("backtest_runs", [run])
        return result[0]["id"] if result else 0

    def get_runs(self) -> List[Dict]:
        return self._get("backtest_runs", "select=*&order=created_at.desc")

    # ── Compat: table().select().eq()... (para testes mock) ──────────────────

    def table(self, name: str):
        return _TableRef(self, name)


class _TableRef:
    """Stub mínimo para compatibilidade com testes que mockam supabase-py."""
    def __init__(self, db, name):
        self._db = db
        self._name = name

    def select(self, *a, **kw): return self
    def eq(self, *a, **kw): return self
    def gte(self, *a, **kw): return self
    def lte(self, *a, **kw): return self
    def order(self, *a, **kw): return self
    def insert(self, data): return _ExecRef(self._db, self._name, data)
    def upsert(self, data, **kw): return _ExecRef(self._db, self._name, data)

    def execute(self):
        class R:
            data = []
        return R()


class _ExecRef:
    def __init__(self, db, name, data):
        self._db = db
        self._name = name
        self._data = data

    def execute(self):
        class R:
            data = []
        return R()
