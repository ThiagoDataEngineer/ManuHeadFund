"""test_coingecko_enrichment.py -- TDD pra enrichment de coin_registry via CoinGecko.

Testa pure functions (sem hit API real):
  - map_market_to_coingecko_id: BTCUSDT -> "bitcoin"
  - derive_registry_fields: response CoinGecko -> campos FQS (age, supply, etc)
  - merge_into_registry: aplica campos derivados ao registry preservando manual fields
"""
from __future__ import annotations
import os, sys, json, tempfile
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from coingecko_enrichment import (
    map_market_to_coingecko_id,
    derive_registry_fields,
    merge_into_registry,
    find_markets_needing_full_enrichment,
)


class TestMapping:
    def test_btc_usdt_maps_to_bitcoin(self):
        assert map_market_to_coingecko_id("BTCUSDT") == "bitcoin"
    def test_eth_usdt_maps_to_ethereum(self):
        assert map_market_to_coingecko_id("ETHUSDT") == "ethereum"
    def test_inj_usdt_maps_to_injective(self):
        assert map_market_to_coingecko_id("INJUSDT") == "injective-protocol"
    def test_unknown_returns_none(self):
        assert map_market_to_coingecko_id("UNKNOWNUSDT") is None
    def test_lowercase_normalized(self):
        assert map_market_to_coingecko_id("btcusdt") == "bitcoin"


class TestDeriveFields:
    def test_basic_supply_capped(self):
        response = {
            "genesis_date": "2009-01-03",
            "market_data": {
                "max_supply": 21000000,
                "circulating_supply": 19500000,
                "ath_date": {"usd": "2021-11-10T00:00:00Z"},
                "current_price": {"usd": 77000},
                "ath": {"usd": 69000},
            }
        }
        derived = derive_registry_fields(response, as_of_year=2026)
        assert derived["supply_capped"] is True
        assert derived["age_years"] >= 16
        # current 77000 vs ath 69000 = recovered
        assert derived["recovered_2021_ath"] is True

    def test_uncapped_supply(self):
        response = {
            "genesis_date": "2020-01-01",
            "market_data": {
                "max_supply": None,
                "circulating_supply": 100_000_000,
                "current_price": {"usd": 50},
                "ath": {"usd": 100},
                "ath_date": {"usd": "2021-05-10T00:00:00Z"},
            }
        }
        derived = derive_registry_fields(response, as_of_year=2026)
        assert derived["supply_capped"] is False
        assert derived["recovered_2021_ath"] is False  # current 50 < ath 100

    def test_old_no_ath_date_skipped(self):
        response = {
            "genesis_date": "2018-06-01",
            "market_data": {
                "max_supply": None,
                "circulating_supply": 1_000_000,
            }
        }
        derived = derive_registry_fields(response, as_of_year=2026)
        # Sem price/ath data -> recovered None ou False
        assert "age_years" in derived
        assert derived["age_years"] >= 7

    def test_missing_market_data_safe(self):
        derived = derive_registry_fields({"genesis_date": "2020-01-01"}, as_of_year=2026)
        assert derived["age_years"] >= 5
        # Sem market_data -> defaults safe (False)
        assert derived["supply_capped"] is False


class TestFindMarketsNeedingFullEnrichment:
    def test_market_missing_age_years_needs_enrich(self):
        # NEAR ja mapeado em MARKET_TO_CG; BTC nao precisa
        registry = {
            "BTCUSDT": {"age_years": 16, "supply_capped": True},
            "NEARUSDT": {"supply_capped": True},  # SEM age_years
        }
        result = find_markets_needing_full_enrichment(registry)
        assert "NEARUSDT" in result
        assert "BTCUSDT" not in result

    def test_market_age_zero_or_null_needs_enrich(self):
        # Markets mapeados: ETH, INJ, SOL
        registry = {
            "ETHUSDT": {"age_years": 0},
            "INJUSDT": {"age_years": None},
            "SOLUSDT": {"age_years": 5},
        }
        result = find_markets_needing_full_enrichment(registry)
        assert "ETHUSDT" in result
        assert "INJUSDT" in result
        assert "SOLUSDT" not in result

    def test_meta_field_skipped(self):
        registry = {
            "_meta": {"version": "1.0"},
            "BTCUSDT": {"age_years": 16},
        }
        result = find_markets_needing_full_enrichment(registry)
        assert "_meta" not in result
        assert "BTCUSDT" not in result

    def test_unmapped_market_skipped(self):
        # Market sem mapping CoinGecko nao pode ser enriquecido -> skip
        registry = {
            "WEIRDOUSDT": {"supply_capped": False},  # nao ta em MARKET_TO_CG
        }
        result = find_markets_needing_full_enrichment(registry)
        assert "WEIRDOUSDT" not in result

    def test_empty_registry(self):
        assert find_markets_needing_full_enrichment({}) == []


class TestMerge:
    def test_preserves_manual_burn_active(self):
        # User curou burn_active=true manualmente; merge nao deve sobrescrever
        registry = {
            "BTCUSDT": {
                "age_years": 16,
                "supply_capped": True,
                "burn_active": False,  # manual
                "utility_score": 1.0,
            }
        }
        derived = {
            "age_years": 17,
            "supply_capped": True,
            # CoinGecko nao sabe burn -> nao retorna
        }
        merged = merge_into_registry(registry, "BTCUSDT", derived)
        assert merged["BTCUSDT"]["burn_active"] is False  # preservado
        assert merged["BTCUSDT"]["age_years"] == 17  # atualizado
        assert merged["BTCUSDT"]["utility_score"] == 1.0  # preservado

    def test_new_market_added(self):
        registry = {}
        derived = {"age_years": 5, "supply_capped": True}
        merged = merge_into_registry(registry, "NEWUSDT", derived)
        assert "NEWUSDT" in merged
        assert merged["NEWUSDT"]["age_years"] == 5

    def test_only_derived_fields_overwrite(self):
        registry = {
            "X": {
                "age_years": 3,  # antigo, derived deve atualizar
                "burn_active": True,  # manual, preservar
                "utility_score": 0.5,  # manual
            }
        }
        derived = {"age_years": 4}  # so atualiza age
        merged = merge_into_registry(registry, "X", derived)
        assert merged["X"]["age_years"] == 4
        assert merged["X"]["burn_active"] is True
        assert merged["X"]["utility_score"] == 0.5
