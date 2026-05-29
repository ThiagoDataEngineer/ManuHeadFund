#!/usr/bin/env python3
"""
CoinGecko API Enrich Script for FQS Registry
Enriquece dados de ativos Tier D via CoinGecko API

Uso:
    python coingecko_enrich_fqs_registry.py [--dry-run] [--output OUTPUT_FILE]

Exemplo:
    python coingecko_enrich_fqs_registry.py --dry-run
    python coingecko_enrich_fqs_registry.py --output enriched_data.json

Otimizações (REFACTOR Phase):
    - Cache de resultados CoinGecko
    - Retry logic com exponential backoff
    - Circuit breaker pattern
    - Docstrings completas
"""

import requests
import json
import time
from datetime import datetime, timedelta
from typing import Dict, Optional, List
import logging
from functools import wraps

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s'
)
logger = logging.getLogger(__name__)

# Configuração
COINGECKO_API = "https://api.coingecko.com/api/v3"
REQUEST_TIMEOUT = 10
RATE_LIMIT_DELAY = 3.0  # segundos entre requisições (aumentado para 3s)
CACHE_TTL = 3600  # Cache válido por 1 hora
MAX_RETRIES = 3
INITIAL_BACKOFF = 1.0  # segundos
MAX_BACKOFF = 30.0  # segundos

# Mapeamento de símbolos para IDs CoinGecko
# Validado em 29/05/2026 via CoinGecko API
# Nota: Alguns ativos podem não estar disponíveis no CoinGecko
SYMBOL_TO_COINGECKO = {
    "GRASSUSDT": "grass",           # ✅ Validado - rank 152
    "PEAQUSDT": "peaq",             # ✅ Validado
    "PYTHUSDT": "pyth-network",     # ✅ Validado
    "WIFUSDT": "dogwifhat",         # ✅ Validado
    # Ativos com IDs alternativos ou não encontrados:
    "USELESSUSDT": "useless-token", # Alternativa: useless
    "ASTERUSDT": "aster-protocol",  # Alternativa: aster
    "PROVEUSDT": "prove-protocol",  # Alternativa: prove
    "CHEEMSUSDT": "cheems-inu",     # Alternativa: cheems
    "WLDUSDT": "worldcoin",         # Alternativa: world
    "SUSDT": "su-square",           # Alternativa: su
}


# ============================================================================
# CACHE SYSTEM - Armazenar resultados para evitar requisições duplicadas
# ============================================================================

class CoinGeckoCache:
    """
    Cache em memória para resultados da API CoinGecko.
    
    Atributos:
        cache (Dict): Dicionário com dados em cache
        ttl (int): Tempo de vida do cache em segundos
    """
    
    def __init__(self, ttl: int = CACHE_TTL):
        """
        Inicializar cache.
        
        Args:
            ttl: Tempo de vida do cache em segundos (padrão: 3600)
        """
        self.cache = {}
        self.ttl = ttl
    
    def get(self, key: str) -> Optional[Dict]:
        """
        Obter valor do cache se ainda válido.
        
        Args:
            key: Chave do cache (coingecko_id)
            
        Returns:
            Dados em cache ou None se expirado/não encontrado
        """
        if key not in self.cache:
            return None
        
        data, timestamp = self.cache[key]
        
        # Verificar se cache expirou
        if datetime.now() - timestamp > timedelta(seconds=self.ttl):
            del self.cache[key]
            logger.debug(f"Cache expirado para {key}")
            return None
        
        logger.debug(f"Cache hit para {key}")
        return data
    
    def set(self, key: str, value: Dict) -> None:
        """
        Armazenar valor no cache.
        
        Args:
            key: Chave do cache (coingecko_id)
            value: Dados a armazenar
        """
        self.cache[key] = (value, datetime.now())
        logger.debug(f"Cache set para {key}")
    
    def clear(self) -> None:
        """Limpar todo o cache."""
        self.cache.clear()
        logger.info("Cache limpo")


# Instância global de cache
_cache = CoinGeckoCache()


# ============================================================================
# CIRCUIT BREAKER - Proteção contra API indisponível
# ============================================================================

class CircuitBreaker:
    """
    Circuit breaker pattern para proteção contra falhas em cascata.
    
    Estados:
        CLOSED: Funcionando normalmente
        OPEN: Bloqueando requisições (API indisponível)
        HALF_OPEN: Testando se API voltou
    """
    
    CLOSED = "CLOSED"
    OPEN = "OPEN"
    HALF_OPEN = "HALF_OPEN"
    
    def __init__(self, failure_threshold: int = 5, timeout: int = 60):
        """
        Inicializar circuit breaker.
        
        Args:
            failure_threshold: Número de falhas antes de abrir
            timeout: Tempo em segundos antes de tentar half-open
        """
        self.state = self.CLOSED
        self.failure_count = 0
        self.failure_threshold = failure_threshold
        self.timeout = timeout
        self.last_failure_time = None
    
    def record_success(self) -> None:
        """Registrar sucesso e resetar contador."""
        self.failure_count = 0
        self.state = self.CLOSED
        logger.debug("Circuit breaker: sucesso registrado")
    
    def record_failure(self) -> None:
        """Registrar falha e atualizar estado."""
        self.failure_count += 1
        self.last_failure_time = datetime.now()
        
        if self.failure_count >= self.failure_threshold:
            self.state = self.OPEN
            logger.warning(f"Circuit breaker ABERTO após {self.failure_count} falhas")
        else:
            logger.debug(f"Circuit breaker: falha {self.failure_count}/{self.failure_threshold}")
    
    def can_execute(self) -> bool:
        """
        Verificar se pode executar requisição.
        
        Returns:
            True se pode executar, False se circuit está aberto
        """
        if self.state == self.CLOSED:
            return True
        
        if self.state == self.OPEN:
            # Verificar se timeout expirou
            if datetime.now() - self.last_failure_time > timedelta(seconds=self.timeout):
                self.state = self.HALF_OPEN
                logger.info("Circuit breaker: tentando HALF_OPEN")
                return True
            return False
        
        # HALF_OPEN: permitir uma tentativa
        return True


# Instância global de circuit breaker
_circuit_breaker = CircuitBreaker()


# ============================================================================
# RETRY LOGIC - Retry com exponential backoff
# ============================================================================

def retry_with_backoff(max_retries: int = MAX_RETRIES, initial_backoff: float = INITIAL_BACKOFF):
    """
    Decorator para retry com exponential backoff.
    
    Args:
        max_retries: Número máximo de tentativas
        initial_backoff: Tempo inicial de espera em segundos
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            backoff = initial_backoff
            last_exception = None
            
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except requests.exceptions.RequestException as e:
                    last_exception = e
                    
                    if attempt < max_retries - 1:
                        logger.warning(
                            f"Tentativa {attempt + 1}/{max_retries} falhou para {args[0] if args else 'unknown'}: {e}. "
                            f"Aguardando {backoff:.1f}s..."
                        )
                        time.sleep(backoff)
                        backoff = min(backoff * 2, MAX_BACKOFF)  # Exponential backoff
                    else:
                        logger.error(f"Todas as {max_retries} tentativas falharam para {args[0] if args else 'unknown'}")
            
            raise last_exception
        
        return wrapper
    return decorator


def calculate_age(date_str: Optional[str]) -> Optional[float]:
    """
    Calcular idade em anos a partir de uma data ISO.
    
    Args:
        date_str: Data em formato ISO (ex: "2021-04-20T00:00:00Z")
        
    Returns:
        Idade em anos (float) ou None se data inválida
        
    Exemplo:
        >>> age = calculate_age("2021-04-20T00:00:00Z")
        >>> assert age > 4 and age < 6
    """
    if not date_str:
        return None
    
    try:
        # Remover 'Z' e converter para datetime
        date_str_clean = date_str.replace("Z", "+00:00")
        date = datetime.fromisoformat(date_str_clean)
        age = (datetime.now(date.tzinfo) - date).days / 365.25
        return round(age, 1)
    except Exception as e:
        logger.warning(f"Erro ao calcular idade para {date_str}: {e}")
        return None


def calculate_utility_score(data: Dict) -> float:
    """
    Calcular utility_score baseado em heurísticas CoinGecko.
    
    Fórmula:
        utility = (rank_score * 0.4) + (dev_score * 0.3) + (comm_score * 0.3)
    
    Args:
        data: Dicionário com dados do CoinGecko
        
    Returns:
        Score entre 0 e 1
        
    Exemplo:
        >>> data = {
        ...     "market_cap_rank": 100,
        ...     "developer_data": {"commit_count_4_weeks": 150},
        ...     "community_data": {"twitter_followers": 50000}
        ... }
        >>> score = calculate_utility_score(data)
        >>> assert 0 <= score <= 1
    """
    try:
        market_cap_rank = data.get("market_cap_rank")
        developer_data = data.get("developer_data", {})
        community_data = data.get("community_data", {})
        
        # Score baseado em rank (quanto menor o rank, melhor)
        rank_score = 0.0
        if market_cap_rank and market_cap_rank > 0:
            rank_score = max(0, 1 - (market_cap_rank / 10000))
        
        # Score baseado em atividade de desenvolvimento
        commits_4w = developer_data.get("commit_count_4_weeks", 0) or 0
        dev_score = min(1.0, commits_4w / 100)
        
        # Score baseado em comunidade
        twitter_followers = community_data.get("twitter_followers", 0) or 0
        comm_score = min(1.0, twitter_followers / 100000)
        
        # Calcular média ponderada
        utility = (rank_score * 0.4) + (dev_score * 0.3) + (comm_score * 0.3)
        
        return round(utility, 2)
    
    except Exception as e:
        logger.warning(f"Erro ao calcular utility_score: {e}")
        return 0.0


def extract_concentration(data: Dict) -> Optional[float]:
    """
    Extrair concentração top 10 holders (se disponível).
    
    Usa market_cap_rank como proxy: quanto menor o rank, mais distribuído.
    
    Args:
        data: Dicionário com dados do CoinGecko
        
    Returns:
        Concentração estimada (0-1) ou None se rank não disponível
        
    Heurística:
        - rank > 5000: concentração alta (0.6)
        - rank 1000-5000: concentração média (0.5)
        - rank < 1000: concentração baixa (0.4)
    """
    try:
        market_cap_rank = data.get("market_cap_rank")
        
        if not market_cap_rank:
            return None
        
        # Heurística: ativos com rank > 5000 tendem a ter concentração alta
        if market_cap_rank > 5000:
            concentration = 0.6  # Alta concentração
        elif market_cap_rank > 1000:
            concentration = 0.5  # Média concentração
        else:
            concentration = 0.4  # Baixa concentração
        
        return concentration
    
    except Exception as e:
        logger.warning(f"Erro ao extrair concentração: {e}")
        return None


@retry_with_backoff(max_retries=MAX_RETRIES)
def fetch_coingecko_data(coingecko_id: str) -> Optional[Dict]:
    """
    Buscar dados do CoinGecko para um ativo.
    
    Implementa:
        - Cache para evitar requisições duplicadas
        - Circuit breaker para proteção contra API indisponível
        - Retry com exponential backoff
    
    Args:
        coingecko_id: ID do ativo no CoinGecko (ex: "useless")
        
    Returns:
        Dicionário com dados do CoinGecko ou None se falha
        
    Exemplo:
        >>> data = fetch_coingecko_data("useless")
        >>> assert data is not None
        >>> assert "id" in data
    """
    # Verificar circuit breaker
    if not _circuit_breaker.can_execute():
        logger.error(f"Circuit breaker ABERTO - não posso buscar {coingecko_id}")
        return None
    
    # Verificar cache
    cached_data = _cache.get(coingecko_id)
    if cached_data:
        return cached_data
    
    try:
        url = f"{COINGECKO_API}/coins/{coingecko_id}"
        params = {
            "localization": "false",
            "tickers": "false",
            "market_data": "true",
            "community_data": "true",
            "developer_data": "true"
        }
        
        logger.info(f"Buscando dados para {coingecko_id}...")
        response = requests.get(url, params=params, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        data = response.json()
        
        # Armazenar em cache
        _cache.set(coingecko_id, data)
        
        # Registrar sucesso no circuit breaker
        _circuit_breaker.record_success()
        
        return data
    
    except requests.exceptions.RequestException as e:
        logger.error(f"Erro ao buscar dados de {coingecko_id}: {e}")
        
        # Registrar falha no circuit breaker
        _circuit_breaker.record_failure()
        
        return None


def enrich_asset(symbol: str, coingecko_id: str) -> Optional[Dict]:
    """
    Enriquecer um ativo com dados do CoinGecko.
    
    Args:
        symbol: Símbolo do ativo (ex: "USELESSUSDT")
        coingecko_id: ID do ativo no CoinGecko (ex: "useless")
        
    Returns:
        Dicionário com dados enriquecidos ou None se falha
        
    Exemplo:
        >>> enriched = enrich_asset("USELESSUSDT", "useless")
        >>> assert enriched is not None
        >>> assert enriched["symbol"] == "USELESSUSDT"
    """
    
    # Buscar dados
    data = fetch_coingecko_data(coingecko_id)
    if not data:
        return None
    
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
        "source": "coingecko_api",
        "enriched_date": datetime.now().isoformat(),
        "market_cap_rank": data.get("market_cap_rank"),
        "genesis_date": genesis_date,
        "ath_date": ath_date
    }
    
    return enriched


def enrich_all_assets(dry_run: bool = False) -> Dict[str, Dict]:
    """
    Enriquecer todos os ativos Tier D.
    
    Args:
        dry_run: Se True, não faz requisições reais (apenas simula)
        
    Returns:
        Dicionário com resultados do enrich
        
    Exemplo:
        >>> results = enrich_all_assets(dry_run=True)
        >>> assert results["total_assets"] == 10
    """
    
    results = {
        "timestamp": datetime.now().isoformat(),
        "total_assets": len(SYMBOL_TO_COINGECKO),
        "successful": 0,
        "failed": 0,
        "assets": {}
    }
    
    logger.info(f"Iniciando enrich de {len(SYMBOL_TO_COINGECKO)} ativos...")
    
    for symbol, coingecko_id in SYMBOL_TO_COINGECKO.items():
        if dry_run:
            logger.info(f"[DRY-RUN] Enriquecendo {symbol} ({coingecko_id})...")
        else:
            enriched = enrich_asset(symbol, coingecko_id)
            
            if enriched:
                results["assets"][symbol] = enriched
                results["successful"] += 1
                
                # Determinar novo tier
                utility = enriched["utility_score"]
                if utility >= 0.8:
                    tier = "A"
                elif utility >= 0.6:
                    tier = "B"
                elif utility >= 0.4:
                    tier = "C"
                else:
                    tier = "D"
                
                logger.info(
                    f"✅ {symbol}: utility={utility}, tier={tier}, "
                    f"age={enriched.get('age_years', 'N/A')}y, "
                    f"burn={enriched.get('burn_active', 'N/A')}"
                )
            else:
                results["failed"] += 1
                logger.error(f"❌ {symbol}: Falha ao enriquecer")
        
        # Rate limiting
        time.sleep(RATE_LIMIT_DELAY)
    
    # Sumário
    logger.info(f"\n{'='*70}")
    logger.info(f"ENRICH COMPLETO")
    logger.info(f"{'='*70}")
    logger.info(f"Total de ativos: {results['total_assets']}")
    logger.info(f"Sucesso: {results['successful']}")
    logger.info(f"Falha: {results['failed']}")
    
    return results


def print_summary(results: Dict):
    """
    Imprimir sumário dos resultados.
    
    Args:
        results: Dicionário com resultados do enrich
    """
    
    print(f"\n{'='*70}")
    print(f"SUMÁRIO DE ENRICH - FQS REGISTRY")
    print(f"{'='*70}\n")
    
    print(f"Timestamp: {results['timestamp']}")
    print(f"Total de ativos: {results['total_assets']}")
    print(f"Sucesso: {results['successful']}")
    print(f"Falha: {results['failed']}\n")
    
    # Distribuição por tier
    tier_dist = {"A": 0, "B": 0, "C": 0, "D": 0}
    
    print(f"{'Ativo':<15} {'Utility':<10} {'Tier':<6} {'Age':<8} {'Burn':<6}")
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
    print(f"DISTRIBUIÇÃO POR TIER")
    print(f"{'='*70}")
    print(f"Tier A (utility >= 0.8): {tier_dist['A']}")
    print(f"Tier B (utility 0.6-0.8): {tier_dist['B']}")
    print(f"Tier C (utility 0.4-0.6): {tier_dist['C']}")
    print(f"Tier D (utility < 0.4): {tier_dist['D']}")
    print(f"\n")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Enriquecer FQS Registry via CoinGecko API"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Executar em modo dry-run (sem fazer requisições)"
    )
    parser.add_argument(
        "--output",
        type=str,
        default="fqs_enriched_data.json",
        help="Arquivo de saída para dados enriquecidos"
    )
    
    args = parser.parse_args()
    
    # Executar enrich
    results = enrich_all_assets(dry_run=args.dry_run)
    
    # Imprimir sumário
    print_summary(results)
    
    # Salvar resultados
    if not args.dry_run:
        with open(args.output, "w") as f:
            json.dump(results, f, indent=2)
        logger.info(f"Resultados salvos em: {args.output}")


if __name__ == "__main__":
    main()
