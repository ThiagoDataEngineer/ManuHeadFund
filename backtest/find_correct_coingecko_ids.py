#!/usr/bin/env python3
"""
Encontrar IDs corretos do CoinGecko para todos os 10 ativos Tier D
Usa busca por símbolo para encontrar os IDs corretos
"""

import requests
import json
import time

COINGECKO_API = "https://api.coingecko.com/api/v3"

# Ativos a encontrar
SYMBOLS_TO_FIND = {
    "GRASSUSDT": "grass",           # ✅ Já validado
    "PEAQUSDT": "peaq",             # ✅ Já validado
    "PYTHUSDT": "pyth-network",     # ✅ Já validado
    "WIFUSDT": "dogwifhat",         # ✅ Já validado
    "USELESSUSDT": "useless",
    "ASTERUSDT": "aster",
    "PROVEUSDT": "prove",
    "CHEEMSUSDT": "cheems",
    "WLDUSDT": "world",
    "SUSDT": "su",
}

def search_coin(query: str) -> list:
    """Buscar moeda por nome/símbolo"""
    try:
        url = f"{COINGECKO_API}/search"
        params = {"query": query}
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        return data.get("coins", [])
    except Exception as e:
        print(f"Erro ao buscar {query}: {e}")
        return []

def main():
    print("=" * 70)
    print("ENCONTRAR IDs CORRETOS DO COINGECKO")
    print("=" * 70)
    
    results = {}
    
    for symbol, default_id in SYMBOLS_TO_FIND.items():
        print(f"\n🔍 Procurando {symbol}...")
        
        # Tentar com o ID padrão primeiro
        try:
            url = f"{COINGECKO_API}/coins/{default_id}"
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                name = data.get("name", "Unknown")
                rank = data.get("market_cap_rank", "N/A")
                print(f"  ✅ {default_id}: {name} (rank: {rank})")
                results[symbol] = default_id
                time.sleep(1)
                continue
        except:
            pass
        
        # Se não encontrou, buscar por símbolo
        print(f"  Buscando por símbolo...")
        coins = search_coin(symbol.replace("USDT", ""))
        
        if coins:
            for coin in coins[:3]:  # Top 3 resultados
                coin_id = coin.get("id")
                coin_name = coin.get("name", "Unknown")
                coin_symbol = coin.get("symbol", "").upper()
                print(f"    - {coin_id}: {coin_name} ({coin_symbol})")
                
                # Tentar validar
                try:
                    url = f"{COINGECKO_API}/coins/{coin_id}"
                    response = requests.get(url, timeout=10)
                    if response.status_code == 200:
                        data = response.json()
                        rank = data.get("market_cap_rank", "N/A")
                        print(f"      ✅ Validado (rank: {rank})")
                        results[symbol] = coin_id
                        break
                except:
                    pass
                
                time.sleep(1)
        
        if symbol not in results:
            print(f"  ❌ Não encontrado")
            results[symbol] = None
        
        time.sleep(1)
    
    # Sumário
    print("\n" + "=" * 70)
    print("SUMÁRIO")
    print("=" * 70)
    
    valid = sum(1 for v in results.values() if v is not None)
    invalid = len(results) - valid
    
    print(f"\nTotal: {len(results)}")
    print(f"Válidos: {valid} ✅")
    print(f"Inválidos: {invalid} ❌")
    
    print("\n" + "-" * 70)
    print("MAPEAMENTO CORRETO:")
    print("-" * 70)
    
    print("\nSYMBOL_TO_COINGECKO = {")
    for symbol in sorted(results.keys()):
        coingecko_id = results[symbol]
        if coingecko_id:
            print(f'    "{symbol}": "{coingecko_id}",')
        else:
            print(f'    # "{symbol}": "???",  # NÃO ENCONTRADO')
    print("}")
    
    # Salvar
    with open("coingecko_ids_corrected_20260529.json", "w") as f:
        json.dump(results, f, indent=2)
    
    print(f"\n✅ Resultados salvos em: coingecko_ids_corrected_20260529.json")

if __name__ == "__main__":
    main()
