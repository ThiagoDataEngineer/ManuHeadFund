#!/usr/bin/env python3
"""
Execução Real - CoinGecko Enrich
Executa enrich real para todos os 10 ativos com API CoinGecko
"""

import requests
import json
import time
from datetime import datetime
from typing import Dict, Optional

COINGECKO_API = "https://api.coingecko.com/api/v3"
REQUEST_TIMEOUT = 15
RATE_LIMIT_DELAY = 10.0  # 10 segundos entre requisições (aumentado)

# IDs CoinGecko para os 10 ativos (CORRIGIDOS)
SYMBOL_TO_COINGECKO = {
    "GRASSUSDT": "grass",              # ✅ Validado
    "PEAQUSDT": "peaq",                # ✅ Validado
    "PYTHUSDT": "pyth-network",        # ✅ Validado
    "WIFUSDT": "dogwifhat",            # ✅ Validado
    "USELESSUSDT": "useless-token",    # CORRIGIDO: useless → useless-token
    "ASTERUSDT": "aster-protocol",     # CORRIGIDO: aster → aster-protocol
    "PROVEUSDT": "prove-protocol",     # CORRIGIDO: prove → prove-protocol
    "CHEEMSUSDT": "cheems-inu",        # CORRIGIDO: cheems → cheems-inu
    "WLDUSDT": "worldcoin",            # CORRIGIDO: world → worldcoin
    "SUSDT": "su-square",              # CORRIGIDO: su → su-square
}


def calculate_age(date_str: Optional[str]) -> Optional[float]:
    """Calcular idade em anos"""
    if not date_str:
        return None
    try:
        from datetime import datetime
        date_str_clean = date_str.replace("Z", "+00:00")
        date = datetime.fromisoformat(date_str_clean)
        age = (datetime.now(date.tzinfo) - date).days / 365.25
        return round(age, 1)
    except:
        return None


def calculate_utility_score(data: Dict) -> float:
    """Calcular utility score"""
    try:
        market_cap_rank = data.get("market_cap_rank")
        developer_data = data.get("developer_data", {})
        community_data = data.get("community_data", {})
        
        rank_score = 0.0
        if market_cap_rank and market_cap_rank > 0:
            rank_score = max(0, 1 - (market_cap_rank / 10000))
        
        commits_4w = developer_data.get("commit_count_4_weeks", 0) or 0
        dev_score = min(1.0, commits_4w / 100)
        
        twitter_followers = community_data.get("twitter_followers", 0) or 0
        comm_score = min(1.0, twitter_followers / 100000)
        
        utility = (rank_score * 0.4) + (dev_score * 0.3) + (comm_score * 0.3)
        return round(utility, 2)
    except:
        return 0.0


def extract_concentration(data: Dict) -> Optional[float]:
    """Extrair concentração"""
    try:
        market_cap_rank = data.get("market_cap_rank")
        if not market_cap_rank:
            return None
        
        if market_cap_rank > 5000:
            return 0.6
        elif market_cap_rank > 1000:
            return 0.5
        else:
            return 0.4
    except:
        return None


def fetch_coingecko_data(coingecko_id: str, attempt: int = 1) -> Optional[Dict]:
    """Buscar dados do CoinGecko com retry"""
    try:
        url = f"{COINGECKO_API}/coins/{coingecko_id}"
        params = {
            "localization": "false",
            "tickers": "false",
            "market_data": "true",
            "community_data": "true",
            "developer_data": "true"
        }
        
        print(f"  [Tentativa {attempt}] Buscando {coingecko_id}...", end=" ", flush=True)
        response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
        
        if response.status_code == 200:
            print("OK")
            return response.json()
        elif response.status_code == 429:
            print(f"Rate limit (429)")
            if attempt < 3:
                print(f"  Aguardando {RATE_LIMIT_DELAY * 2}s...")
                time.sleep(RATE_LIMIT_DELAY * 2)
                return fetch_coingecko_data(coingecko_id, attempt + 1)
            return None
        elif response.status_code == 404:
            print(f"Não encontrado (404)")
            return None
        else:
            print(f"Erro {response.status_code}")
            return None
    
    except requests.exceptions.Timeout:
        print("Timeout")
        if attempt < 3:
            print(f"  Aguardando {RATE_LIMIT_DELAY}s...")
            time.sleep(RATE_LIMIT_DELAY)
            return fetch_coingecko_data(coingecko_id, attempt + 1)
        return None
    except Exception as e:
        print(f"Erro: {e}")
        return None


def enrich_asset(symbol: str, coingecko_id: str) -> Optional[Dict]:
    """Enriquecer um ativo"""
    data = fetch_coingecko_data(coingecko_id)
    if not data:
        return None
    
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
        "source": "coingecko_api_real",
        "enriched_date": datetime.now().isoformat(),
        "market_cap_rank": data.get("market_cap_rank"),
        "genesis_date": genesis_date,
        "ath_date": ath_date
    }
    
    return enriched


def main():
    """Executar enrich real"""
    
    print("=" * 70)
    print("ENRICH REAL - COINGECKO API")
    print("=" * 70)
    print()
    
    results = {
        "timestamp": datetime.now().isoformat(),
        "total_assets": len(SYMBOL_TO_COINGECKO),
        "successful": 0,
        "failed": 0,
        "assets": {}
    }
    
    print("Enriquecendo ativos com API CoinGecko...\n")
    
    for symbol, coingecko_id in SYMBOL_TO_COINGECKO.items():
        print(f"[{symbol}]")
        enriched = enrich_asset(symbol, coingecko_id)
        
        if enriched:
            results["assets"][symbol] = enriched
            results["successful"] += 1
            
            utility = enriched["utility_score"]
            if utility >= 0.8:
                tier = "A"
            elif utility >= 0.6:
                tier = "B"
            elif utility >= 0.4:
                tier = "C"
            else:
                tier = "D"
            
            print(f"  [OK] Enriquecido: utility={utility}, tier={tier}\n")
        else:
            results["failed"] += 1
            print(f"  [FAIL] Falha ao enriquecer\n")
        
        time.sleep(RATE_LIMIT_DELAY)
    
    # Sumário
    print("=" * 70)
    print("SUMÁRIO")
    print("=" * 70)
    print(f"Total: {results['total_assets']}")
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
    
    # Salvar
    with open("coingecko_enrich_real_20260529.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n[OK] Resultados salvos em: coingecko_enrich_real_20260529.json")
    
    return results


if __name__ == "__main__":
    main()
