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
    build_supabase_row,
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

    def test_expansion_2026_08_19_top_liquid_markets_mapped(self):
        # Achado real: Invoke-FqsLazyEnrich (gem_executor.ps1) ja chama este
        # mapping automaticamente a cada candidato novo, mas so cobria 53
        # tickers -- travando LINK/ADA/AVAX/BNB/UNI/etc em FQS=AVOID por
        # ausencia de mapeamento (nao qualidade real). Expandido pra cobrir
        # a maioria dos top ~100 mercados FUTURES liquidos da CoinEx.
        expected = {
            "LINKUSDT": "chainlink", "ADAUSDT": "cardano", "AVAXUSDT": "avalanche-2",
            "BNBUSDT": "binancecoin", "UNIUSDT": "uniswap", "CROUSDT": "crypto-com-chain",
            "XAUTUSDT": "tether-gold", "AAVEUSDT": "aave",
        }
        for market, cg_id in expected.items():
            assert map_market_to_coingecko_id(market) == cg_id, f"{market} deveria mapear para {cg_id}"

    def test_gram_usdt_maps_to_same_id_as_legacy_ton(self):
        # Rebrand TON->GRAM 2026-06-15 na CoinEx (mesmo ativo, par TONUSDT
        # descontinuado) -- GRAMUSDT precisa resolver pro MESMO CoinGecko ID
        # que TONUSDT ja usava, nao um ID novo/errado.
        assert map_market_to_coingecko_id("GRAMUSDT") == map_market_to_coingecko_id("TONUSDT")
        assert map_market_to_coingecko_id("GRAMUSDT") == "the-open-network"

    def test_no_duplicate_keys_in_market_to_cg(self):
        # TDD real: duplicata de chave em dict literal Python nao lanca erro
        # (a segunda silenciosamente sobrescreve a primeira) -- valida via
        # AST que o arquivo fonte nao tem chaves repetidas no bloco
        # MARKET_TO_CG, garantia que nao regride ao expandir no futuro.
        import ast
        src_path = os.path.join(os.path.dirname(__file__), "..", "coingecko_enrichment.py")
        with open(src_path, encoding="utf-8") as f:
            tree = ast.parse(f.read())
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == "MARKET_TO_CG" for t in node.targets
            ):
                keys = [k.value for k in node.value.keys]
                dupes = [k for k in set(keys) if keys.count(k) > 1]
                assert dupes == [], f"chaves duplicadas em MARKET_TO_CG: {dupes}"
                return
        assert False, "MARKET_TO_CG nao encontrado no arquivo fonte"


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


class TestBuildSupabaseRow:
    # 2026-08-19: coin_registry.json (curadoria manual, git) fica cada vez
    # mais dificil de escalar pra ~100 moedas -- pivotou pra Supabase como
    # destino do job periodico (persistencia central, sem git commit-back).
    # build_supabase_row so deve levar campos DERIVADOS (CoinGecko), nunca
    # burn_active/utility_score/concentration_top10 (esses continuam so no
    # registry estatico curado manualmente -- CoinGecko nao tem esse dado).
    def test_only_derived_fields_included(self):
        derived = {
            "age_years": 16, "supply_capped": True, "recovered_2021_ath": True,
            "current_price_usd": 77000.0, "ath_all_time_usd": 69000.0,
            "max_supply": 21000000.0, "circulating_supply": 19500000.0,
        }
        row = build_supabase_row("BTCUSDT", "bitcoin", derived)
        assert row["market"] == "BTCUSDT"
        assert row["coingecko_id"] == "bitcoin"
        assert row["source"] == "coingecko_enrichment_auto"
        assert row["age_years"] == 16
        assert row["supply_capped"] is True
        assert "burn_active" not in row
        assert "utility_score" not in row
        assert "concentration_top10" not in row

    def test_partial_derived_fields_ok(self):
        # Nem toda resposta CoinGecko tem todos os campos (ex: sem price/ath) --
        # row deve conter so o que veio, sem KeyError.
        derived = {"age_years": 5}
        row = build_supabase_row("NEWUSDT", "new-coin", derived)
        assert row["age_years"] == 5
        assert "current_price_usd" not in row
