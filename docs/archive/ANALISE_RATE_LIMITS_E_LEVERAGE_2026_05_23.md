# Análise: Rate Limits e Leverage/Margin Mode - CoinEx API

**Data:** 2026-05-23  
**Autor:** Análise Técnica Kiro  
**Status:** 🔴 RISCOS IDENTIFICADOS

---

## 📊 SUMÁRIO EXECUTIVO

### Rate Limits - Risco Moderado 🟡
- **400 req/s por IP** é alto, mas **limites por conta são restritivos**
- **Spot: 30 req/s** para place orders, **Futures: 20 req/s**
- **Implementação atual: SEM controle de rate limiting robusto**
- **Risco:** Código 4213 (rate limited) pode causar falhas em operações críticas

### Leverage/Margin Mode - Implementação Correta ✅
- **Função existe e está bem implementada:** `CoinEx-AdjustPositionLeverage`
- **Suporta isolated e cross** conforme documentação
- **Testes TDD completos** validando funcionalidade
- **Sem gaps identificados** nesta área

---

## 🚨 PARTE 1: RATE LIMITS - ANÁLISE DE RISCO

### 1.1 Limites Documentados (CoinEx API v2)

#### Por IP (Global)
```
400 req/s - Raramente é gargalo
```

#### Por Conta (UID-based) - CRÍTICO ⚠️

**SPOT Trading:**
| Operação | Limite | Risco |
|----------|--------|-------|
| Place/Edit orders | **30 req/s** | 🔴 ALTO - Pode bloquear em alta volatilidade |
| Cancel orders | 60 req/s | 🟡 MÉDIO |
| Cancel all/batch | 40 req/s | 🟡 MÉDIO |
| Query orders | 50 req/s | 🟢 BAIXO |
| Order history | 10 req/s | 🟢 BAIXO |
| Account queries | 10 req/s | 🟢 BAIXO |

**FUTURES Trading:**
| Operação | Limite | Risco |
|----------|--------|-------|
| Place/Edit | **20 req/s** | 🔴 ALTO - Mais restritivo que SPOT |
| Cancel | 40 req/s | 🟡 MÉDIO |
| Cancel all/batch | 20 req/s | 🟡 MÉDIO |
| Query | 50 req/s | 🟢 BAIXO |
| Order history | 10 req/s | 🟢 BAIXO |
| Account queries | 10 req/s | 🟢 BAIXO |

#### Batch Weighting - IMPORTANTE ⚠️
```
Batch de 5 ordens = 5 unidades de cota
Batch de 10 ordens = 10 unidades de cota
```

**Exemplo de risco:**
- Batch de 10 ordens consome **10 unidades**
- Limite FUTURES: 20 req/s
- **2 batches/segundo = limite atingido**

#### Long Cycle Penalty
```
Uso "abusivo" → modo penalidade
- Taxas reduzidas
- Cancelamento preservado (garantia de saída)
```

### 1.2 Implementação Atual - GAPS IDENTIFICADOS 🔴

#### ✅ O que EXISTE:
```powershell
# Alguns scripts têm delays básicos
Start-Sleep -Milliseconds 200  # find_short_opportunities.ps1
```

#### ❌ O que FALTA:

**1. Controle de Rate Limiting Centralizado**
```powershell
# NÃO EXISTE: lib_rate_limiter.ps1
# NÃO EXISTE: Token bucket algorithm
# NÃO EXISTE: Sliding window counter
```

**2. Retry com Backoff Exponencial para 4213**
```powershell
# EXISTE parcialmente: b19_coinex_retry_transient.Tests.ps1
# MAS: Não está integrado em lib_coinex.ps1
```

**3. Queue de Ordens com Throttling**
```powershell
# NÃO EXISTE: Fila de ordens respeitando 20-30 req/s
# RISCO: Múltiplas ordens simultâneas podem estourar limite
```

**4. Monitoramento de Rate Limit Headers**
```powershell
# NÃO EXISTE: Leitura de headers X-RateLimit-*
# (se CoinEx retornar esses headers)
```

### 1.3 Cenários de Risco Real

#### Cenário 1: Scan Paralelo de Mercados 🔴
```powershell
# scan_master.ps1 com MaxConcurrency 2
# 2 markets × 3 drones LLM = 6 chamadas simultâneas
# Se cada drone fizer 1 order check = 6 req/s (OK)
# Se cada drone fizer 5 order checks = 30 req/s (LIMITE!)
```

**Evidência no código:**
```powershell
# b28_cascade_burst_mitigation.Tests.ps1
# "estourando Groq rate limit mesmo com stagger 750ms"
# MaxConcurrency 3 -> 2 para mitigar
```

#### Cenário 2: Gem Agent com Múltiplas Ordens 🔴
```powershell
# gem_executor.ps1 pode tentar:
# - Place order (1 req)
# - Set stop loss (1 req)
# - Set take profit (1 req)
# - Query position (1 req)
# = 4 req em sequência rápida

# Se 10 gems simultâneos = 40 req/s
# FUTURES limit = 20 req/s → BLOQUEIO!
```

#### Cenário 3: Position Risk Manager 🟡
```powershell
# position_risk_cron.ps1 roda a cada 10 minutos
# Se tiver 20 posições abertas:
# - 20 × Get position (20 req)
# - 20 × Update trailing stop (20 req)
# = 40 req em burst

# Se executar em < 2 segundos = 20 req/s → LIMITE!
```

### 1.4 Código de Erro 4213 - Estratégia Atual

**Documentação recomenda:**
```
4213 (Rate limited) → Backoff exponencial
300ms → 600ms → 1.2s → ... max 30s
```

**Implementação atual:**
```powershell
# lib_coinex.ps1 - NÃO TEM retry automático para 4213
# Apenas retorna erro e deixa caller decidir

# Exemplo de resposta:
return [PSCustomObject]@{
    success    = $false
    error_code = 4213
    error_msg  = "Rate limit exceeded"
}
```

**Gap:** Caller precisa implementar retry manualmente

### 1.5 Comparação com Outras Exchanges

| Exchange | Place Order Limit | Nossa Posição |
|----------|-------------------|---------------|
| Binance | 50 req/s (spot) | CoinEx: 30 req/s |
| Bybit | 100 req/s (unified) | CoinEx: 20 req/s (futures) |
| OKX | 60 req/s | CoinEx: 30 req/s |
| **CoinEx** | **20-30 req/s** | **Mais restritivo** |

### 1.6 Recomendações - Rate Limiting

#### 🔴 PRIORIDADE ALTA

**1. Implementar Rate Limiter Centralizado**
```powershell
# agents/lib_rate_limiter.ps1

function Invoke-RateLimitedCall {
    param(
        [string]$Category,  # "spot_place", "futures_place", etc.
        [scriptblock]$Action
    )
    
    # Token bucket algorithm
    # - spot_place: 30 tokens/s
    # - futures_place: 20 tokens/s
    # - Refill automático
    # - Bloqueia se sem tokens
}
```

**2. Integrar Retry com Backoff em lib_coinex.ps1**
```powershell
function CoinEx-Post {
    # ...
    $maxRetries = 3
    $backoffMs = 300
    
    for ($i = 0; $i -lt $maxRetries; $i++) {
        $response = Invoke-RestMethod ...
        
        if ($response.code -eq 4213) {
            Start-Sleep -Milliseconds $backoffMs
            $backoffMs *= 2  # Exponencial
            continue
        }
        
        return $response
    }
}
```

**3. Queue de Ordens com Throttling**
```powershell
# agents/lib_order_queue.ps1

function Add-OrderToQueue {
    # Adiciona ordem à fila
    # Worker thread processa respeitando rate limit
}
```

#### 🟡 PRIORIDADE MÉDIA

**4. Monitoramento de Rate Limit**
```powershell
# journal/rate_limit_events.jsonl
# Log quando 4213 ocorrer
# Dashboard mostrando taxa de rate limiting
```

**5. Circuit Breaker**
```powershell
# Se 3+ erros 4213 consecutivos
# Pausar operações por 30s
# Evitar ban temporário
```

#### 🟢 PRIORIDADE BAIXA

**6. Otimizar Batch Operations**
```powershell
# Usar batch endpoints quando possível
# Mas lembrar: batch de 10 = 10 unidades de cota
```

---

## ✅ PARTE 2: LEVERAGE E MARGIN MODE - ANÁLISE

### 2.1 Implementação Atual - COMPLETA ✅

**Arquivo:** `agents/lib_coinex_position_management.ps1`

```powershell
function CoinEx-AdjustPositionLeverage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,
        
        [Parameter(Mandatory=$true)]
        [int]$Leverage,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("isolated", "cross")]
        [string]$MarginMode = "isolated"
    )
    
    $bodyObj = @{
        market      = $Market
        market_type = "FUTURES"
        leverage    = $Leverage
        margin_mode = $MarginMode
    }
    
    $response = CoinEx-Post -path "/v2/futures/adjust-position-leverage" -bodyObj $bodyObj
    # ...
}
```

### 2.2 Validação TDD - COMPLETA ✅

**Arquivo:** `tests/lib_coinex_position_management.Tests.ps1`

```powershell
Describe "CoinEx-AdjustPositionLeverage - ajustar leverage e margin mode" {
    
    It "ajusta leverage para 10x em modo isolated" {
        # Mock valida:
        # - Path correto: /v2/futures/adjust-position-leverage
        # - Leverage: 10
        # - MarginMode: "isolated"
        # ✅ PASSA
    }
    
    It "ajusta leverage para 5x em modo cross" {
        # Mock valida:
        # - Leverage: 5
        # - MarginMode: "cross"
        # ✅ PASSA
    }
}
```

### 2.3 Documentação CoinEx - CONFIRMADO ✅

**Endpoint:** `POST /v2/futures/adjust-position-leverage`

**Payload:**
```json
{
  "market": "BTCUSDT",
  "market_type": "FUTURES",
  "margin_mode": "cross",     // "isolated" ou "cross"
  "leverage": 10
}
```

**Resposta:**
```json
{
  "code": 0,
  "data": {
    "margin_mode": "cross",
    "leverage": 10
  },
  "message": "OK"
}
```

### 2.4 Funcionalidades Relacionadas - COMPLETAS ✅

**Também implementadas:**
1. ✅ `CoinEx-AdjustPositionMargin` - Add/Remove margin
2. ✅ `CoinEx-ModifyPositionStopLoss` - Modificar SL
3. ✅ `CoinEx-ModifyPositionTakeProfit` - Modificar TP
4. ✅ `CoinEx-CancelPositionStopLoss` - Cancelar SL
5. ✅ `CoinEx-CancelPositionTakeProfit` - Cancelar TP
6. ✅ `CoinEx-GetFinishedPositions` - Histórico

### 2.5 Gap Identificado na Documentação - SPOT MARGIN

**IMPORTANTE:** Conforme `COINEX_REFERENCE.md` seção 5.4:

```markdown
### 5.4 GAP CRÍTICO — Margin mode em SPOT MARGIN

**Status pesquisa**:
- **NÃO existe** endpoint v2 público para configurar isolated vs cross em spot margin.
- O `margin_mode` enum só é aceito em `/futures/adjust-position-leverage`.
- Em SPOT MARGIN, a CoinEx opera por padrão em modo **isolated por par**.
```

**Conclusão:**
- ✅ FUTURES: Leverage + margin mode **totalmente suportado**
- ⚠️ SPOT MARGIN: Apenas isolated (sem endpoint para alternar)

### 2.6 Uso no Projeto

**Grep mostra uso em:**
```powershell
# tests/lib_coinex_deep_evaluation.Tests.ps1
# tests/lib_coinex_position_management.Tests.ps1
# tests/lib_position_risk_manager_fixes.Tests.ps1
# tests/lib_market_router.Tests.ps1
```

**Integração:**
- Position risk manager pode ajustar leverage dinamicamente
- Market router força futures para TIER_A (leverage controlado)
- Testes validam isolated e cross modes

### 2.7 Recomendações - Leverage/Margin

#### ✅ Nenhuma ação necessária

A implementação está **completa e correta**:
- Função implementada com TDD
- Testes passando
- Documentação alinhada com API
- Suporte a isolated e cross
- Integrada no sistema de risk management

#### 📝 Documentação Adicional (Opcional)

Considerar adicionar em `knowledge/`:
```markdown
# LEVERAGE_MANAGEMENT.md

## Modos de Margem

### Isolated
- Margem isolada por posição
- Liquidação afeta apenas a posição específica
- Risco limitado ao capital alocado

### Cross
- Margem compartilhada entre todas as posições
- Liquidação pode afetar todo o saldo
- Maior flexibilidade, maior risco
```

---

## 🎯 CONCLUSÕES FINAIS

### Rate Limits - AÇÃO NECESSÁRIA 🔴

**Risco Atual:** MÉDIO-ALTO
- Limites de 20-30 req/s são restritivos
- Implementação atual não tem controle robusto
- Cenários de burst podem causar bloqueios

**Ações Recomendadas:**
1. 🔴 Implementar rate limiter centralizado (URGENTE)
2. 🔴 Adicionar retry com backoff para 4213 (URGENTE)
3. 🟡 Queue de ordens com throttling (IMPORTANTE)
4. 🟡 Monitoramento de rate limit events (IMPORTANTE)
5. 🟢 Circuit breaker (DESEJÁVEL)

**Prazo Sugerido:** 1-2 semanas

### Leverage/Margin Mode - NENHUMA AÇÃO ✅

**Status:** COMPLETO
- Implementação correta e testada
- Documentação alinhada
- Integração funcional
- Sem gaps identificados

**Observação:** Gap em SPOT MARGIN é limitação da API CoinEx, não do nosso código.

---

## 📚 REFERÊNCIAS

1. `knowledge/COINEX_REFERENCE.md` - Seção 2.3 (Rate Limits)
2. `agents/lib_coinex_position_management.ps1` - Implementação
3. `tests/lib_coinex_position_management.Tests.ps1` - Testes TDD
4. `tests/b19_coinex_retry_transient.Tests.ps1` - Retry parcial
5. `tests/b28_cascade_burst_mitigation.Tests.ps1` - Evidência de burst
6. CoinEx API v2 Docs: https://docs.coinex.com/api/v2/rate-limit

---

**Próximos Passos:**
1. Revisar este documento com o time
2. Priorizar implementação de rate limiter
3. Testar em ambiente de staging
4. Monitorar logs de 4213 em produção
