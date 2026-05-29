#!/usr/bin/env python3
"""
Validar IDs do CoinGecko para todos os ativos Tier D
Encontrar os IDs corretos via busca na API
"""

import requests
import json
from typing import Dict, Optional

COINGECKO_API = "https://api.coingecko.com/api/v3"
REQUEST_TIMEOUT = 10

# Ativos a validar
SYMBOLS_TO_VALIDATE = {
    "USELESSUSDT": ["useless", "useless-token"],
    "GRASSUSDT": ["grass"],
    "ASTERUSDT": ["aster", "aster-protocol"],
    "PROVEUSDT": ["prove", "prove-protocol"],
    "WIFUSDT": ["dogwifhat", "wif"],
    "PEAQUSDT": ["peaq"],
    "CHEEMSUSDT": ["cheems", "cheems-inu"],
    "WLDUSDT": ["world", "world-coin", "worldcoin"],
    "SUSDT": ["su", "su-square"],
    "PYTHUSDT": ["pyth", "pyth-network"],
}


def search_coingecko_id(symbol: str, candidates: list) -> Optional[str]:
    """
    Buscar ID correto do CoinGecko testando candidatos
    
    Args:
        symbol: Símbolo do ativo (ex: GRASSUSDT)
        candidates: Lista de IDs candidatos a testar
        
    Returns:
        ID correto ou None se não encontrado
    """
    print(f"\n🔍 Validando {symbol}...")
    
    for candidate_id in candidates:
        try:
            url = f"{COINGECKO_API}/coins/{candidate_id}"
            params = {
                "localization": "false",
                "tickers": "false",
                "market_data": "true",
            }
            
            response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
            
            if response.status_code == 200:
                data = response.json()
                rank = data.get("market_cap_rank", "N/A")
                name = data.get("name", "Unknown")
                print(f"  ✅ {candidate_id}: {name} (rank: {rank})")
                return candidate_id
            elif response.status_code == 404:
                print(f"  ❌ {candidate_id}: Não encontrado (404)")
            elif response.status_code == 429:
                print(f"  ⚠️  {candidate_id}: Rate limit (429) - aguardando...")
                import time
                time.sleep(2)
                # Tentar novamente
                response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
                if response.status_code == 200:
                    data = response.json()
                    rank = data.get("market_cap_rank", "N/A")
                    name = data.get("name", "Unknown")
                    print(f"  ✅ {candidate_id}: {name} (rank: {rank})")
                    return candidate_id
            else:
                print(f"  ⚠️  {candidate_id}: Erro {response.status_code}")
        
        except requests.exceptions.RequestException as e:
            print(f"  ❌ {candidate_id}: Erro de conexão - {e}")
        
        import time
        time.sleep(1)  # Rate limiting
    
    print(f"  ❌ Nenhum ID válido encontrado para {symbol}")
    return None


def main():
    """Validar todos os IDs"""
    
    print("=" * 70)
    print("VALIDAÇÃO DE IDs DO COINGECKO")
    print("=" * 70)
    
    results = {}
    
    for symbol, candidates in SYMBOLS_TO_VALIDATE.items():
        valid_id = search_coingecko_id(symbol, candidates)
        results[symbol] = valid_id
    
    # Sumário
    print("\n" + "=" * 70)
    print("SUMÁRIO DE VALIDAÇÃO")
    print("=" * 70)
    
    valid_count = sum(1 for v in results.values() if v is not None)
    invalid_count = len(results) - valid_count
    
    print(f"\nTotal: {len(results)}")
    print(f"Válidos: {valid_count} ✅")
    print(f"Inválidos: {invalid_count} ❌")
    
    print("\n" + "-" * 70)
    print("MAPEAMENTO CORRETO:")
    print("-" * 70)
    
    print("\nSYMBOL_TO_COINGECKO = {")
    for symbol in sorted(results.keys()):
        coingecko_id = results[symbol]
        status = "✅" if coingecko_id else "❌"
        if coingecko_id:
            print(f'    "{symbol}": "{coingecko_id}",  # {status}')
        else:
            print(f'    # "{symbol}": "???",  # {status} NÃO ENCONTRADO')
    print("}")
    
    # Salvar resultados
    with open("coingecko_ids_validation_20260529.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n✅ Resultados salvos em: coingecko_ids_validation_20260529.json")


if __name__ == "__main__":
    main()
