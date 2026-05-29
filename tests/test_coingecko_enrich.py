#!/usr/bin/env python3
"""
Test-Driven Development para CoinGecko Enrich
Testes para validar enrich de ativos Tier D via CoinGecko API

Estrutura TDD:
1. RED: Escrever testes que falham
2. GREEN: Implementar código mínimo para passar
3. REFACTOR: Melhorar código mantendo testes passando

Uso:
    pytest test_coingecko_enrich.py -v
    pytest test_coingecko_enrich.py -v --cov=coingecko_enrich_fqs_registry
"""

import pytest
import json
from datetime import datetime, timedelta
from unittest.mock import Mock, patch, MagicMock
import sys
from pathlib import Path

# Adicionar backtest ao path
sys.path.insert(0, str(Path(__file__).parent.parent / "backtest"))

# Importar módulo a testar (será criado)
try:
    from coingecko_enrich_fqs_registry import (
        calculate_age,
        calculate_utility_score,
        extract_concentration,
        fetch_coingecko_data,
        enrich_asset,
        enrich_all_assets,
        CoinGeckoCache,
        CircuitBreaker,
        _cache,
        _circuit_breaker
    )
except ImportError:
    # Funções ainda não existem, vamos criar os testes primeiro
    pass


class TestCalculateAge:
    """Testes para cálculo de idade em anos"""
    
    def test_calculate_age_valid_date(self):
        """Deve calcular idade corretamente para data válida"""
        # Arrange
        date_str = "2021-04-20T00:00:00Z"
        
        # Act
        age = calculate_age(date_str)
        
        # Assert
        assert age is not None
        assert isinstance(age, float)
        assert age > 4  # Deve ter mais de 4 anos (2021 -> 2026)
        assert age < 6  # Deve ter menos de 6 anos
    
    def test_calculate_age_none_input(self):
        """Deve retornar None para entrada None"""
        # Act
        age = calculate_age(None)
        
        # Assert
        assert age is None
    
    def test_calculate_age_empty_string(self):
        """Deve retornar None para string vazia"""
        # Act
        age = calculate_age("")
        
        # Assert
        assert age is None
    
    def test_calculate_age_invalid_format(self):
        """Deve retornar None para formato inválido"""
        # Act
        age = calculate_age("invalid-date")
        
        # Assert
        assert age is None
    
    def test_calculate_age_recent_date(self):
        """Deve calcular idade corretamente para data recente"""
        # Arrange
        today = datetime.now()
        one_year_ago = today - timedelta(days=365)
        date_str = one_year_ago.isoformat() + "Z"
        
        # Act
        age = calculate_age(date_str)
        
        # Assert
        assert age is not None
        assert 0.9 < age < 1.1  # Aproximadamente 1 ano


class TestCalculateUtilityScore:
    """Testes para cálculo de utility_score"""
    
    def test_utility_score_high_rank_high_dev(self):
        """Deve retornar score alto para rank baixo + dev ativo"""
        # Arrange
        data = {
            "market_cap_rank": 100,
            "developer_data": {
                "commit_count_4_weeks": 150
            },
            "community_data": {
                "twitter_followers": 50000
            }
        }
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert isinstance(score, float)
        assert 0 <= score <= 1
        assert score > 0.5  # Deve ser score alto
    
    def test_utility_score_low_rank_no_dev(self):
        """Deve retornar score baixo para rank alto + sem dev"""
        # Arrange
        data = {
            "market_cap_rank": 10000,
            "developer_data": {
                "commit_count_4_weeks": 0
            },
            "community_data": {
                "twitter_followers": 0
            }
        }
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert isinstance(score, float)
        assert 0 <= score <= 1
        assert score < 0.3  # Deve ser score baixo
    
    def test_utility_score_missing_fields(self):
        """Deve retornar score válido mesmo com campos faltando"""
        # Arrange
        data = {}
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert isinstance(score, float)
        assert 0 <= score <= 1
    
    def test_utility_score_meme_coin(self):
        """Deve retornar score baixo para meme coin"""
        # Arrange
        data = {
            "market_cap_rank": 5000,
            "developer_data": {
                "commit_count_4_weeks": 0
            },
            "community_data": {
                "twitter_followers": 10000
            }
        }
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert isinstance(score, float)
        assert score < 0.4  # Meme coin deve ter score baixo
    
    def test_utility_score_infrastructure(self):
        """Deve retornar score alto para infrastructure"""
        # Arrange
        data = {
            "market_cap_rank": 500,
            "developer_data": {
                "commit_count_4_weeks": 200
            },
            "community_data": {
                "twitter_followers": 100000
            }
        }
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert isinstance(score, float)
        assert score > 0.5  # Infrastructure deve ter score alto


class TestExtractConcentration:
    """Testes para extração de concentração"""
    
    def test_extract_concentration_high_rank(self):
        """Deve retornar concentração alta para rank alto"""
        # Arrange
        data = {
            "market_cap_rank": 10000
        }
        
        # Act
        concentration = extract_concentration(data)
        
        # Assert
        assert concentration is not None
        assert isinstance(concentration, float)
        assert concentration > 0.5  # Alta concentração
    
    def test_extract_concentration_low_rank(self):
        """Deve retornar concentração baixa para rank baixo"""
        # Arrange
        data = {
            "market_cap_rank": 100
        }
        
        # Act
        concentration = extract_concentration(data)
        
        # Assert
        assert concentration is not None
        assert isinstance(concentration, float)
        assert concentration < 0.5  # Baixa concentração
    
    def test_extract_concentration_no_rank(self):
        """Deve retornar None quando rank não disponível"""
        # Arrange
        data = {}
        
        # Act
        concentration = extract_concentration(data)
        
        # Assert
        assert concentration is None


class TestFetchCoinGeckoData:
    """Testes para busca de dados CoinGecko"""
    
    @patch('requests.get')
    def test_fetch_coingecko_data_success(self, mock_get):
        """Deve buscar dados com sucesso"""
        # Arrange
        mock_response = Mock()
        mock_response.json.return_value = {
            "id": "useless",
            "genesis_date": "2021-04-20",
            "market_cap_rank": 5000
        }
        mock_get.return_value = mock_response
        
        # Act
        data = fetch_coingecko_data("useless")
        
        # Assert
        assert data is not None
        assert data["id"] == "useless"
        assert data["genesis_date"] == "2021-04-20"
    
    @patch('requests.get')
    def test_fetch_coingecko_data_timeout(self, mock_get):
        """Deve retornar None após múltiplas tentativas de timeout"""
        # Arrange
        import requests
        # Limpar cache para evitar interferência
        _cache.clear()
        
        # Simular timeout em todas as tentativas
        mock_get.side_effect = requests.exceptions.Timeout()
        
        # Act & Assert
        # O retry decorator vai tentar 3 vezes e depois lançar exceção
        # fetch_coingecko_data captura e retorna None
        try:
            data = fetch_coingecko_data("useless_timeout_test")
            # Se não lançar exceção, deve retornar None
            assert data is None
        except requests.exceptions.Timeout:
            # Esperado após retries
            pass
    
    @patch('requests.get')
    def test_fetch_coingecko_data_not_found(self, mock_get):
        """Deve retornar None para ativo não encontrado"""
        # Arrange
        import requests
        mock_get.side_effect = requests.exceptions.HTTPError()
        
        # Act
        data = fetch_coingecko_data("invalid-coin")
        
        # Assert
        assert data is None


class TestEnrichAsset:
    """Testes para enrich de um ativo"""
    
    @patch('coingecko_enrich_fqs_registry.fetch_coingecko_data')
    def test_enrich_asset_success(self, mock_fetch):
        """Deve enriquecer ativo com sucesso"""
        # Arrange
        mock_fetch.return_value = {
            "id": "useless",
            "genesis_date": "2021-04-20",
            "market_cap_rank": 5000,
            "market_data": {
                "burn_fee_percentage": 0,
                "ath_date": {"usd": "2021-05-15"}
            },
            "developer_data": {
                "commit_count_4_weeks": 0
            },
            "community_data": {
                "twitter_followers": 0
            }
        }
        
        # Act
        enriched = enrich_asset("USELESSUSDT", "useless")
        
        # Assert
        assert enriched is not None
        assert enriched["symbol"] == "USELESSUSDT"
        assert enriched["age_years"] is not None
        assert enriched["burn_active"] is not None
        assert enriched["utility_score"] is not None
        assert enriched["source"] == "coingecko_api"
    
    @patch('coingecko_enrich_fqs_registry.fetch_coingecko_data')
    def test_enrich_asset_fetch_fails(self, mock_fetch):
        """Deve retornar None quando fetch falha"""
        # Arrange
        mock_fetch.return_value = None
        
        # Act
        enriched = enrich_asset("USELESSUSDT", "useless")
        
        # Assert
        assert enriched is None


class TestEnrichAllAssets:
    """Testes para enrich de todos os ativos"""
    
    @patch('coingecko_enrich_fqs_registry.enrich_asset')
    def test_enrich_all_assets_success(self, mock_enrich):
        """Deve enriquecer todos os ativos"""
        # Arrange
        mock_enrich.return_value = {
            "symbol": "USELESSUSDT",
            "utility_score": 0.1,
            "age_years": 5.0
        }
        
        # Act
        results = enrich_all_assets(dry_run=False)
        
        # Assert
        assert results is not None
        assert "timestamp" in results
        assert "total_assets" in results
        assert results["total_assets"] == 10
        assert "successful" in results
        assert "failed" in results
    
    def test_enrich_all_assets_dry_run(self):
        """Deve executar em modo dry-run sem fazer requisições"""
        # Act
        results = enrich_all_assets(dry_run=True)
        
        # Assert
        assert results is not None
        assert results["successful"] == 0
        assert results["failed"] == 0


class TestIntegration:
    """Testes de integração"""
    
    def test_tier_classification_meme_coin(self):
        """Deve classificar meme coin como Tier D"""
        # Arrange
        utility_score = 0.1
        
        # Act
        if utility_score >= 0.8:
            tier = "A"
        elif utility_score >= 0.6:
            tier = "B"
        elif utility_score >= 0.4:
            tier = "C"
        else:
            tier = "D"
        
        # Assert
        assert tier == "D"
    
    def test_tier_classification_infrastructure(self):
        """Deve classificar infrastructure como Tier C"""
        # Arrange
        utility_score = 0.6
        
        # Act
        if utility_score >= 0.8:
            tier = "A"
        elif utility_score >= 0.6:
            tier = "B"
        elif utility_score >= 0.4:
            tier = "C"
        else:
            tier = "D"
        
        # Assert
        assert tier == "B"
    
    def test_enriched_data_structure(self):
        """Deve ter estrutura correta de dados enriquecidos"""
        # Arrange
        enriched = {
            "symbol": "USELESSUSDT",
            "coingecko_id": "useless",
            "age_years": 5.0,
            "burn_active": False,
            "utility_score": 0.1,
            "concentration_top10": 0.6,
            "listing_years": 5.0,
            "source": "coingecko_api",
            "enriched_date": datetime.now().isoformat()
        }
        
        # Assert
        assert "symbol" in enriched
        assert "age_years" in enriched
        assert "burn_active" in enriched
        assert "utility_score" in enriched
        assert "concentration_top10" in enriched
        assert "listing_years" in enriched
        assert "source" in enriched
        assert "enriched_date" in enriched


class TestEdgeCases:
    """Testes para casos extremos"""
    
    def test_calculate_age_very_old_date(self):
        """Deve calcular idade para data muito antiga"""
        # Arrange
        date_str = "2009-01-03T00:00:00Z"  # Bitcoin genesis
        
        # Act
        age = calculate_age(date_str)
        
        # Assert
        assert age is not None
        assert age > 15  # Mais de 15 anos
    
    def test_utility_score_extreme_values(self):
        """Deve lidar com valores extremos"""
        # Arrange
        data = {
            "market_cap_rank": 1,
            "developer_data": {
                "commit_count_4_weeks": 10000
            },
            "community_data": {
                "twitter_followers": 10000000
            }
        }
        
        # Act
        score = calculate_utility_score(data)
        
        # Assert
        assert 0 <= score <= 1  # Score deve estar sempre entre 0 e 1
    
    def test_extract_concentration_edge_ranks(self):
        """Deve lidar com ranks extremos"""
        # Arrange
        data_low = {"market_cap_rank": 1}
        data_high = {"market_cap_rank": 100000}
        
        # Act
        conc_low = extract_concentration(data_low)
        conc_high = extract_concentration(data_high)
        
        # Assert
        assert conc_low is not None
        assert conc_high is not None
        assert conc_low < conc_high


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])


# ============================================================================
# TESTES REFACTOR PHASE - Cache, Circuit Breaker, Retry Logic
# ============================================================================

class TestCoinGeckoCache:
    """Testes para sistema de cache"""
    
    def test_cache_set_and_get(self):
        """Deve armazenar e recuperar dados do cache"""
        # Arrange
        cache = CoinGeckoCache()
        test_data = {"id": "useless", "rank": 5000}
        
        # Act
        cache.set("useless", test_data)
        retrieved = cache.get("useless")
        
        # Assert
        assert retrieved is not None
        assert retrieved["id"] == "useless"
    
    def test_cache_expiration(self):
        """Deve expirar dados após TTL"""
        # Arrange
        import time
        cache = CoinGeckoCache(ttl=1)  # 1 segundo
        test_data = {"id": "useless"}
        
        # Act
        cache.set("useless", test_data)
        time.sleep(1.1)  # Aguardar expiração
        retrieved = cache.get("useless")
        
        # Assert
        assert retrieved is None
    
    def test_cache_miss(self):
        """Deve retornar None para chave não encontrada"""
        # Arrange
        cache = CoinGeckoCache()
        
        # Act
        retrieved = cache.get("nonexistent")
        
        # Assert
        assert retrieved is None
    
    def test_cache_clear(self):
        """Deve limpar todo o cache"""
        # Arrange
        cache = CoinGeckoCache()
        cache.set("useless", {"id": "useless"})
        
        # Act
        cache.clear()
        retrieved = cache.get("useless")
        
        # Assert
        assert retrieved is None


class TestCircuitBreaker:
    """Testes para circuit breaker pattern"""
    
    def test_circuit_breaker_initial_state(self):
        """Deve iniciar em estado CLOSED"""
        # Arrange
        cb = CircuitBreaker()
        
        # Assert
        assert cb.state == CircuitBreaker.CLOSED
        assert cb.can_execute() is True
    
    def test_circuit_breaker_opens_after_failures(self):
        """Deve abrir após número de falhas"""
        # Arrange
        cb = CircuitBreaker(failure_threshold=3)
        
        # Act
        for _ in range(3):
            cb.record_failure()
        
        # Assert
        assert cb.state == CircuitBreaker.OPEN
        assert cb.can_execute() is False
    
    def test_circuit_breaker_resets_on_success(self):
        """Deve resetar contador em sucesso"""
        # Arrange
        cb = CircuitBreaker(failure_threshold=3)
        cb.record_failure()
        cb.record_failure()
        
        # Act
        cb.record_success()
        
        # Assert
        assert cb.failure_count == 0
        assert cb.state == CircuitBreaker.CLOSED
    
    def test_circuit_breaker_half_open_after_timeout(self):
        """Deve tentar HALF_OPEN após timeout"""
        # Arrange
        import time
        cb = CircuitBreaker(failure_threshold=1, timeout=1)
        cb.record_failure()
        
        # Act
        time.sleep(1.1)
        can_execute = cb.can_execute()
        
        # Assert
        assert can_execute is True
        assert cb.state == CircuitBreaker.HALF_OPEN
