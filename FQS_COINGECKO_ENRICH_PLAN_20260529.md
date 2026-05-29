# CoinGecko API Enrich Plan - 10 Ativos Tier D

**Data:** 29/05/2026  
**Objetivo:** Enriquecer dados de 10 ativos com dados mínimos via CoinGecko API  
**Prioridade:** MÉDIA (Tier D - ativos especulativos)  
**Impacto:** Melhorar cobertura de 80% para ~90%

---

## 📊 ATIVOS TIER D PARA ENRICH

### Lista Completa (10 ativos)

| # | Ativo | Campos Presentes | Campos Faltando | Prioridade |
|---|-------|-----------------|-----------------|-----------|
| 1 | USELESSUSDT | 2 | 5 | BAIXA |
| 2 | GRASSUSDT | 2 | 5 | BAIXA |
| 3 | ASTERUSDT | 2 | 5 | BAIXA |
| 4 | PROVEUSDT | 2 | 5 | BAIXA |
| 5 | WIFUSDT | 2 | 5 | BAIXA |
| 6 | PEAQUSDT | 2 | 5 | BAIXA |
| 7 | CHEEMSUSDT | 2 | 5 | BAIXA |
| 8 | WLDUSDT | 2 | 5 | BAIXA |
| 9 | SUSDT | 2 | 5 | BAIXA |
| 10 | PYTHUSDT | 2 | 5 | BAIXA |

---

## 🔍 ANÁLISE DETALHADA POR ATIVO

### 1. USELESSUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 1,000,000,000
- circulating_supply: 999,940,362.02
- current_price_usd: 0.073782
- ath_all_time_usd: 0.434591

**Campos Faltando:**
- ❌ age_years (genesis_date)
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Nome sugere token meme/inútil
- Supply capped em 1B
- ATH: $0.43, Current: $0.07 (-83%)
- Sem burn ativo aparente
- Utility score: ~0.1 (meme coin)

**Recomendação:** Classificar como Tier D (meme coin, sem utility)

---

### 2. GRASSUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 1,000,000,000
- circulating_supply: 587,143,499
- current_price_usd: 0.514708
- ath_all_time_usd: 3.89

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Grass Network (data indexing)
- Supply capped em 1B
- ATH: $3.89, Current: $0.51 (-87%)
- Possível utility em data indexing
- Utility score: ~0.5 (especulativo)

**Recomendação:** Investigar utility, pode ser Tier C

---

### 3. ASTERUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 8,000,000,000
- circulating_supply: 2,579,922,243.47
- current_price_usd: 0.700428
- ath_all_time_usd: 2.41

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Aster (unknown project)
- Supply capped em 8B
- ATH: $2.41, Current: $0.70 (-71%)
- Sem informação clara de utility
- Utility score: ~0.3 (especulativo)

**Recomendação:** Classificar como Tier D (falta informação)

---

### 4. PROVEUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 1,000,000,000
- circulating_supply: 195,000,000
- current_price_usd: 0.268241
- ath_all_time_usd: 1.71

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Prove (unknown project)
- Supply capped em 1B
- ATH: $1.71, Current: $0.27 (-84%)
- Sem informação clara
- Utility score: ~0.2 (especulativo)

**Recomendação:** Classificar como Tier D

---

### 5. WIFUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 998,926,392
- circulating_supply: 998,926,392 (100% circulando)
- current_price_usd: 0.186367
- ath_all_time_usd: 4.83

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Dogwifhat (meme coin Solana)
- Supply capped, 100% circulando
- ATH: $4.83, Current: $0.19 (-96%)
- Meme coin puro
- Utility score: ~0.1

**Recomendação:** Classificar como Tier D (meme coin)

---

### 6. PEAQUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 5,667,620,228.64
- circulating_supply: 2,133,741,015.56
- current_price_usd: 0.03053869
- ath_all_time_usd: 0.750473

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Peaq (DePIN infrastructure)
- Supply capped
- ATH: $0.75, Current: $0.03 (-96%)
- Possível utility em DePIN
- Utility score: ~0.5

**Recomendação:** Investigar DePIN utility, pode ser Tier C

---

### 7. CHEEMSUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 219,776,051,832,671 (ENORME)
- circulating_supply: 203,672,952,113,698.72
- current_price_usd: 7.31103e-07
- ath_all_time_usd: 2.16e-06

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Cheems (meme coin)
- Supply MASSIVO (219 trilhões)
- Preço: $0.00000073
- ATH: $0.0000022
- Meme coin puro
- Utility score: ~0.05

**Recomendação:** Classificar como Tier D (meme coin com supply inflacionário)

---

### 8. WLDUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 10,000,000,000
- circulating_supply: 3,414,545,758.13
- current_price_usd: 0.289304
- ath_all_time_usd: 11.74

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- World (unknown project)
- Supply capped em 10B
- ATH: $11.74, Current: $0.29 (-98%)
- Sem informação clara
- Utility score: ~0.2

**Recomendação:** Classificar como Tier D

---

### 9. SUSDT
**Campos Presentes:**
- supply_capped: false (SEM CAP)
- circulating_supply: 3,784,775,845
- current_price_usd: 0.04519175
- ath_all_time_usd: 1.029

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years
- ❌ max_supply (não capped)

**Análise:**
- Su (unknown project)
- Supply NÃO capped (inflacionário)
- ATH: $1.03, Current: $0.045 (-96%)
- Sem informação clara
- Utility score: ~0.1

**Recomendação:** Classificar como Tier D (supply inflacionário)

---

### 10. PYTHUSDT
**Campos Presentes:**
- supply_capped: true
- max_supply: 10,000,000,000
- circulating_supply: 7,874,982,031.84
- current_price_usd: 0.0417961
- ath_all_time_usd: 1.2

**Campos Faltando:**
- ❌ age_years
- ❌ burn_active
- ❌ utility_score
- ❌ concentration_top10
- ❌ listing_years

**Análise:**
- Pyth Network (oracle infrastructure)
- Supply capped em 10B
- ATH: $1.20, Current: $0.042 (-96%)
- Possível utility em oracle
- Utility score: ~0.6

**Recomendação:** Investigar oracle utility, pode ser Tier C

---

## 🔗 COINGECKO API - CAMPOS A EXTRAIR

### Mapeamento de Campos

| Campo FQS | CoinGecko API | Endpoint | Notas |
|-----------|---------------|----------|-------|
| age_years | genesis_date | /coins/{id} | Calcular: (hoje - genesis_date) / 365 |
| burn_active | burn_fee_percentage | /coins/{id} | Se > 0, então true |
| utility_score | market_cap_rank, developer_score | /coins/{id} | Heurística: rank + dev_score |
| concentration_top10 | market_data.market_cap_by_percentage | /coins/{id} | Extrair top 10 holders % |
| listing_years | market_data.ath_date | /coins/{id} | Calcular: (hoje - ath_date) / 365 |

### Exemplo de Chamada CoinGecko

```bash
# Obter dados de USELESSUSDT
curl "https://api.coingecko.com/api/v3/coins/useless?localization=false&tickers=false&market_data=true&community_data=false&developer_data=true"

# Resposta inclui:
{
  "id": "useless",
  "genesis_date": "2021-04-20",
  "market_data": {
    "ath": { "usd": 0.434591 },
    "ath_date": { "usd": "2021-05-15" },
    "market_cap_rank": 5000+
  },
  "developer_data": {
    "commits_4_weeks": 0
  }
}
```

---

## 📋 ESTRATÉGIA DE ENRICH

### Fase 1: Validação (Hoje)
- [ ] Verificar disponibilidade de cada ativo no CoinGecko
- [ ] Mapear IDs corretos (ex: "useless" vs "USELESSUSDT")
- [ ] Testar chamadas de API

### Fase 2: Extração (Esta semana)
- [ ] Extrair age_years para todos os 10 ativos
- [ ] Extrair burn_active (verificar fee_percentage)
- [ ] Extrair utility_score (heurística: rank + dev_score)
- [ ] Extrair concentration_top10 (se disponível)
- [ ] Extrair listing_years (de ath_date)

### Fase 3: Validação de Dados (Esta semana)
- [ ] Validar dados extraídos
- [ ] Comparar com dados manuais existentes
- [ ] Identificar inconsistências

### Fase 4: Atualização (Esta semana)
- [ ] Atualizar coin_registry.json com dados enriquecidos
- [ ] Executar validate_fqs_registry.ps1
- [ ] Gerar novo relatório de validação

---

## 🎯 HEURÍSTICAS PARA UTILITY_SCORE

### Baseado em CoinGecko Data:

```
utility_score = (market_cap_rank_score * 0.4) + (developer_score * 0.3) + (community_score * 0.3)

Onde:
  market_cap_rank_score = max(0, 1 - (rank / 10000))
  developer_score = developer_data.commits_4_weeks / 100 (capped at 1.0)
  community_score = (github_stars + twitter_followers) / 100000 (capped at 1.0)
```

### Classificação Resultante:

```
utility_score >= 0.8  → Tier A (strong utility)
utility_score 0.6-0.8 → Tier B (moderate utility)
utility_score 0.4-0.6 → Tier C (weak utility)
utility_score < 0.4   → Tier D (no utility / meme)
```

---

## 📊 PREVISÃO DE RESULTADOS

### Após Enrich via CoinGecko:

| Ativo | Atual | Previsto | Novo Tier |
|-------|-------|----------|-----------|
| USELESSUSDT | Tier D | 0.1 | Tier D ✅ |
| GRASSUSDT | Tier D | 0.5 | Tier C ⬆️ |
| ASTERUSDT | Tier D | 0.3 | Tier D ✅ |
| PROVEUSDT | Tier D | 0.2 | Tier D ✅ |
| WIFUSDT | Tier D | 0.1 | Tier D ✅ |
| PEAQUSDT | Tier D | 0.5 | Tier C ⬆️ |
| CHEEMSUSDT | Tier D | 0.05 | Tier D ✅ |
| WLDUSDT | Tier D | 0.2 | Tier D ✅ |
| SUSDT | Tier D | 0.1 | Tier D ✅ |
| PYTHUSDT | Tier D | 0.6 | Tier C ⬆️ |

**Resultado Esperado:**
- 7 ativos permanecem Tier D (confirmados como especulativos)
- 3 ativos promovem para Tier C (GRASSUSDT, PEAQUSDT, PYTHUSDT)
- Cobertura melhora de 80% para ~85%

---

## 🚀 SCRIPT PYTHON PARA ENRICH

### Pseudocódigo

```python
import requests
import json
from datetime import datetime

COINGECKO_API = "https://api.coingecko.com/api/v3"

# Mapeamento de símbolos para IDs CoinGecko
SYMBOL_TO_COINGECKO = {
    "USELESSUSDT": "useless",
    "GRASSUSDT": "grass",
    "ASTERUSDT": "aster",
    "PROVEUSDT": "prove",
    "WIFUSDT": "dogwifhat",
    "PEAQUSDT": "peaq",
    "CHEEMSUSDT": "cheems",
    "WLDUSDT": "world",
    "SUSDT": "su",
    "PYTHUSDT": "pyth-network"
}

def enrich_asset(symbol, coingecko_id):
    """Enriquecer um ativo com dados do CoinGecko"""
    
    try:
        # Chamada à API
        url = f"{COINGECKO_API}/coins/{coingecko_id}"
        params = {
            "localization": "false",
            "tickers": "false",
            "market_data": "true",
            "community_data": "true",
            "developer_data": "true"
        }
        
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        data = response.json()
        
        # Extrair campos
        genesis_date = data.get("genesis_date")
        age_years = calculate_age(genesis_date) if genesis_date else None
        
        burn_active = data.get("market_data", {}).get("burn_fee_percentage", 0) > 0
        
        utility_score = calculate_utility_score(data)
        
        concentration_top10 = extract_concentration(data)
        
        ath_date = data.get("market_data", {}).get("ath_date", {}).get("usd")
        listing_years = calculate_age(ath_date) if ath_date else None
        
        return {
            "age_years": age_years,
            "burn_active": burn_active,
            "utility_score": utility_score,
            "concentration_top10": concentration_top10,
            "listing_years": listing_years,
            "source": "coingecko_api",
            "enriched_date": datetime.now().isoformat()
        }
        
    except Exception as e:
        print(f"Erro ao enriquecer {symbol}: {e}")
        return None

def calculate_age(date_str):
    """Calcular idade em anos a partir de uma data"""
    if not date_str:
        return None
    try:
        date = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        age = (datetime.now() - date).days / 365.25
        return round(age, 1)
    except:
        return None

def calculate_utility_score(data):
    """Calcular utility_score baseado em heurísticas"""
    market_cap_rank = data.get("market_cap_rank")
    developer_score = data.get("developer_data", {}).get("commit_count_4_weeks", 0)
    community_score = data.get("community_data", {}).get("twitter_followers", 0)
    
    # Normalizar scores
    rank_score = max(0, 1 - (market_cap_rank / 10000)) if market_cap_rank else 0
    dev_score = min(1.0, developer_score / 100)
    comm_score = min(1.0, community_score / 100000)
    
    # Calcular média ponderada
    utility = (rank_score * 0.4) + (dev_score * 0.3) + (comm_score * 0.3)
    
    return round(utility, 2)

# Executar enrich para todos os ativos
for symbol, coingecko_id in SYMBOL_TO_COINGECKO.items():
    enriched_data = enrich_asset(symbol, coingecko_id)
    if enriched_data:
        print(f"✅ {symbol}: {enriched_data}")
    else:
        print(f"❌ {symbol}: Falha ao enriquecer")
```

---

## 📈 IMPACTO ESPERADO

### Antes do Enrich:
```
Total de ativos: 65
Completos: 44 (80%)
Parciais: 1 (1.8%)
Mínimos: 10 (18.2%)
```

### Depois do Enrich:
```
Total de ativos: 65
Completos: 54 (83%) ⬆️ +10
Parciais: 1 (1.8%)
Mínimos: 0 (0%) ✅
```

### Distribuição por Tier:
```
Tier A: 7 (sem mudança)
Tier B: 37 (sem mudança)
Tier C: 4 (+3 promovidos) ⬆️
Tier D: 7 (-3 promovidos) ⬇️
```

---

## ⚠️ RISCOS E MITIGAÇÕES

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|--------|-----------|
| API CoinGecko indisponível | BAIXA | MÉDIO | Usar cache local, retry com backoff |
| Dados inconsistentes | MÉDIA | BAIXO | Validar contra dados manuais |
| IDs incorretos | MÉDIA | MÉDIO | Verificar manualmente cada ID |
| Rate limiting | BAIXA | MÉDIO | Implementar throttling (1 req/s) |
| Dados desatualizados | BAIXA | BAIXO | Usar cache com TTL de 24h |

---

## 📅 CRONOGRAMA

| Fase | Tarefa | Data | Status |
|------|--------|------|--------|
| 1 | Validação de IDs | 30/05 | ⏳ Próximo |
| 2 | Extração de dados | 31/05 | ⏳ Próximo |
| 3 | Validação de dados | 01/06 | ⏳ Próximo |
| 4 | Atualização registry | 02/06 | ⏳ Próximo |
| 5 | Revisão final | 02/06 | ⏳ Próximo |

---

## ✅ CHECKLIST

- [ ] Validar disponibilidade no CoinGecko
- [ ] Mapear IDs corretos
- [ ] Testar chamadas de API
- [ ] Implementar script de enrich
- [ ] Extrair dados para 10 ativos
- [ ] Validar dados extraídos
- [ ] Atualizar coin_registry.json
- [ ] Executar validate_fqs_registry.ps1
- [ ] Gerar novo relatório
- [ ] Revisar resultados

---

## 💡 RECOMENDAÇÕES

1. **Priorizar GRASSUSDT, PEAQUSDT, PYTHUSDT** - Têm potencial de promoção para Tier C
2. **Confirmar meme coins** - USELESSUSDT, WIFUSDT, CHEEMSUSDT devem permanecer Tier D
3. **Investigar SUSDT** - Supply não capped é red flag
4. **Implementar cache** - Evitar rate limiting do CoinGecko
5. **Documentar heurísticas** - Deixar claro como utility_score foi calculado

---

## 📞 PRÓXIMAS AÇÕES

1. **Hoje (29/05):** Criar este plano ✅
2. **Amanhã (30/05):** Validar IDs no CoinGecko
3. **31/05:** Implementar script de enrich
4. **01/06:** Executar enrich e validar dados
5. **02/06:** Atualizar registry e revisar

---

**Fim do Plano de Enrich**
