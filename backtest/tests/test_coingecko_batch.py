"""test_coingecko_batch.py -- TDD pra batch endpoint /coins/markets.

Funcoes puras testadas:
  - derive_from_batch_row: 1 row /coins/markets -> derived FQS fields
  - merge_batch_into_registry: aplica multi-rows respeitando manual fields
  - chunk_ids: split lista em chunks (CoinGecko limita ~250/call)
"""
from __future__ import annotations
import os, sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from coingecko_batch import (
    derive_from_batch_row,
    merge_batch_into_registry,
    chunk_ids,
    map_batch_response_to_markets,
)


class TestDeriveFromBatchRow:
    def test_supply_capped_true(self):
        row = {
            "id": "bitcoin", "symbol": "btc",
            "max_supply": 21000000, "circulating_supply": 19500000,
            "current_price": 77000, "ath": 108000, "ath_date": "2025-01-15T00:00:00Z",
        }
        d = derive_from_batch_row(row)
        assert d["supply_capped"] is True
        assert d["recovered_2021_ath"] is False  # 77000 < 108000

    def test_supply_capped_false_null_max(self):
        row = {
            "id": "ethereum", "symbol": "eth",
            "max_supply": None, "circulating_supply": 120_000_000,
            "current_price": 2100, "ath": 4800, "ath_date": "2021-11-10T00:00:00Z",
        }
        d = derive_from_batch_row(row)
        assert d["supply_capped"] is False
        assert d["recovered_2021_ath"] is False

    def test_recovered_above_ath(self):
        row = {
            "id": "solana", "symbol": "sol",
            "max_supply": None, "circulating_supply": 500_000_000,
            "current_price": 280, "ath": 260, "ath_date": "2024-03-15T00:00:00Z",
        }
        d = derive_from_batch_row(row)
        assert d["recovered_2021_ath"] is True

    def test_missing_fields_safe(self):
        row = {"id": "x", "symbol": "x"}
        d = derive_from_batch_row(row)
        assert d["supply_capped"] is False
        assert d["recovered_2021_ath"] is False


class TestChunkIds:
    def test_small_list_single_chunk(self):
        ids = ["a", "b", "c"]
        chunks = chunk_ids(ids, size=250)
        assert len(chunks) == 1
        assert chunks[0] == ids

    def test_split_into_chunks(self):
        ids = [f"id_{i}" for i in range(300)]
        chunks = chunk_ids(ids, size=100)
        assert len(chunks) == 3
        assert len(chunks[0]) == 100
        assert len(chunks[-1]) == 100

    def test_uneven_last_chunk(self):
        ids = [f"id_{i}" for i in range(7)]
        chunks = chunk_ids(ids, size=3)
        assert len(chunks) == 3
        assert len(chunks[-1]) == 1


class TestMapBatchResponseToMarkets:
    def test_maps_coingecko_ids_back_to_market_symbols(self):
        batch_response = [
            {"id": "bitcoin", "max_supply": 21000000, "current_price": 77000, "ath": 108000},
            {"id": "ethereum", "max_supply": None, "current_price": 2100, "ath": 4800},
        ]
        id_to_market = {"bitcoin": "BTCUSDT", "ethereum": "ETHUSDT"}
        result = map_batch_response_to_markets(batch_response, id_to_market)
        assert "BTCUSDT" in result
        assert "ETHUSDT" in result
        assert result["BTCUSDT"]["supply_capped"] is True
        assert result["ETHUSDT"]["supply_capped"] is False

    def test_unknown_id_skipped(self):
        batch_response = [
            {"id": "bitcoin", "max_supply": 21000000, "current_price": 77000, "ath": 108000},
            {"id": "unknown_coin", "max_supply": None},
        ]
        id_to_market = {"bitcoin": "BTCUSDT"}
        result = map_batch_response_to_markets(batch_response, id_to_market)
        assert "BTCUSDT" in result
        assert len(result) == 1  # unknown_coin skipped


class TestMergeBatchIntoRegistry:
    def test_preserves_manual_burn_active(self):
        registry = {
            "BTCUSDT": {"age_years": 16, "burn_active": False, "utility_score": 1.0}
        }
        derived = {"BTCUSDT": {"supply_capped": True, "recovered_2021_ath": False}}
        merged = merge_batch_into_registry(registry, derived)
        assert merged["BTCUSDT"]["burn_active"] is False  # preservado
        assert merged["BTCUSDT"]["utility_score"] == 1.0
        assert merged["BTCUSDT"]["supply_capped"] is True  # atualizado
        assert merged["BTCUSDT"]["age_years"] == 16  # preservado (nao no batch)

    def test_new_markets_added(self):
        registry = {}
        derived = {"NEWUSDT": {"supply_capped": True, "recovered_2021_ath": False}}
        merged = merge_batch_into_registry(registry, derived)
        assert "NEWUSDT" in merged
        assert merged["NEWUSDT"]["supply_capped"] is True

    def test_multiple_markets_independent_merge(self):
        registry = {
            "A": {"burn_active": True}, "B": {"burn_active": False}
        }
        derived = {
            "A": {"supply_capped": True},
            "B": {"supply_capped": False},
        }
        merged = merge_batch_into_registry(registry, derived)
        assert merged["A"]["burn_active"] is True
        assert merged["B"]["burn_active"] is False
        assert merged["A"]["supply_capped"] is True
        assert merged["B"]["supply_capped"] is False
