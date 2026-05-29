#!/usr/bin/env python3
"""
Teste de Integração - CoinGecko Enrich com Dados Mockados
Simula enrich real com dados de exemplo para validação
"""

import json
from datetime import datetime
from coingecko_enrich_fqs_registry import (
    calculate_age,
    calculate_utility_score,
    extract_concentration,
    enrich_asset,
    SYMBOL_TO_COINGECKO
)

# Dados mockados do CoinGecko para testes
MOCK_COINGECKO_DATA = {
    "grass": {
        "id": "grass",
        "name": "Grass",
        "genesis_date": "2024-04-20",
        "market_cap_rank": 152,
        "market_data": {
            "burn_fee_percentage": 0,
            "ath_date": {"usd": "2024-11-08T12:26:05.892Z"}
        },
        "developer_data": {
            "commit_count_4_weeks": 45
        },
        "community_data": {
            "twitter_followers": 25000
        }
    },
    "peaq": {
        "id": "peaq",
        "name": "Peaq",
        "genesis_date": "2024-01-15",
        "market_cap_rank": 287,
        "market_data": {
            "burn_fee_percentage": 0,
            "ath_date": {"usd": "2024-05-20T10:00:00.000Z"}
        },
        "developer_data": {
            "commit_count_4_weeks": 120
        },
        "community_data": {
            "twitter_followers": 45000
        }
    },
    "pyth-network": {
        "id": "pyth-network",
        "name": "Pyth Network",
        "genesis_date": "2021-08-01",
        "market_cap_rank": 89,
        "market_data": {
            "burn_fee_percentage": 0,
            "ath_date": {"usd": "2024-12-15T15:30:00.000Z"}
        },
        "developer_data": {
            "commit_count_4_weeks": 250
        },
        "community_data": {
            "twitter_followers": 150000
        }
    },
    "dogwifhat": {
        "id": "dogwifhat",
        "name": "dogwifhat",
        "genesis_date": None,
        "market_cap_rank": 1250,
        "market_data": {
            "burn_fee_percentage": 0,
            "ath_date": {"usd": "2024-06-01T08:00:00.000Z"}
        },
        "developer_data": {
            "commit_count_4_weeks": 5
        },
        "community_data": {
            "twitter_followers": 80000
        }
    }
}


def enrich_asset_mock(symbol: str, coingecko_id: str) -> dict:
    """
    Enriquecer ativo com dados mockados
    
    Args:
        symbol: Símbolo do ativo
        coingecko_id: ID do CoinGecko
        
    Returns:
        Dados enriquecidos
    """
    
    # Obter dados mockados
    if coingecko_id not in MOCK_COINGECKO_DATA:
        return None
    
    data = MOCK_COINGECKO_DATA[coingecko_id]
    
    # Extrair campos
    genesis_date = data.get("genesis_date")
    age_years = calculate_age(genesis_date)
    
    market_data = data.get("market_data", {})
    burn_fee = market_data.get("burn_fee_percentage", 0)
    burn_active = burn_fee > 0 if burn_fee else False
    
    utility_score = calculate_utility_score(data)
    
    concentration_top10 = extract_concentration(data)
    
    ath_date = market_data.get("ath_date", {}).get("usd")
    listing_years = calculate_age(ath_date)
    
    enriched = {
        "symbol": symbol,
        "coingecko_id": coingecko_id,
        "age_years": age_years,
        "burn_active": burn_active,
        "utility_score": utility_score,
        "concentration_top10": concentration_top10,
        "listing_years": listing_years,
        "source": "coingecko_api_mock",
        "enriched_date": datetime.now().isoformat(),
        "market_cap_rank": data.get("market_cap_rank"),
        "genesis_date": genesis_date,
        "ath_date": ath_date
    }
    
    return enriched


def main():
    """Executar teste de integração"""
    
    print("=" * 70)
    print("TESTE DE INTEGRAÇÃO - COINGECKO ENRICH")
    print("=" * 70)
    print()
    
    results = {
        "timestamp": datetime.now().isoformat(),
        "total_assets": 4,  # Apenas 4 com dados mockados
        "successful": 0,
        "failed": 0,
        "assets": {}
    }
    
    # Ativos com dados mockados
    test_symbols = {
        "GRASSUSDT": "grass",
        "PEAQUSDT": "peaq",
        "PYTHUSDT": "pyth-network",
        "WIFUSDT": "dogwifhat"
    }
    
    print("Enriquecendo ativos com dados mockados...\n")
    
    for symbol, coingecko_id in test_symbols.items():
        enriched = enrich_asset_mock(symbol, coingecko_id)
        
        if enriched:
            results["assets"][symbol] = enriched
            results["successful"] += 1
            
            # Determinar tier
            utility = enriched["utility_score"]
            if utility >= 0.8:
                tier = "A"
            elif utility >= 0.6:
                tier = "B"
            elif utility >= 0.4:
                tier = "C"
            else:
                tier = "D"
            
            print(f"[OK] {symbol}: utility={utility}, tier={tier}, age={enriched.get('age_years', 'N/A')}y")
        else:
            results["failed"] += 1
            print(f"[FAIL] {symbol}: Dados não encontrados")
    
    # Sumário
    print("\n" + "=" * 70)
    print("SUMÁRIO DE ENRICH")
    print("=" * 70)
    print(f"Total de ativos: {results['total_assets']}")
    print(f"Sucesso: {results['successful']}")
    print(f"Falha: {results['failed']}")
    
    # Distribuição por tier
    tier_dist = {"A": 0, "B": 0, "C": 0, "D": 0}
    
    print(f"\n{'Ativo':<15} {'Utility':<10} {'Tier':<6} {'Age':<8} {'Burn':<6}")
    print(f"{'-'*70}")
    
    for symbol, data in sorted(results["assets"].items()):
        utility = data["utility_score"]
        
        if utility >= 0.8:
            tier = "A"
        elif utility >= 0.6:
            tier = "B"
        elif utility >= 0.4:
            tier = "C"
        else:
            tier = "D"
        
        tier_dist[tier] += 1
        
        age = data["age_years"] or "N/A"
        burn = "Y" if data["burn_active"] else "N"
        
        print(f"{symbol:<15} {utility:<10.2f} {tier:<6} {str(age):<8} {burn:<6}")
    
    print(f"\n{'='*70}")
    print("DISTRIBUIÇÃO POR TIER")
    print(f"{'='*70}")
    print(f"Tier A (utility >= 0.8): {tier_dist['A']}")
    print(f"Tier B (utility 0.6-0.8): {tier_dist['B']}")
    print(f"Tier C (utility 0.4-0.6): {tier_dist['C']}")
    print(f"Tier D (utility < 0.4): {tier_dist['D']}")
    
    # Salvar resultados
    with open("coingecko_enrich_integration_test_20260529.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n[OK] Resultados salvos em: coingecko_enrich_integration_test_20260529.json")
    
    return results


if __name__ == "__main__":
    main()
