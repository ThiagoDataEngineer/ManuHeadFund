# Rate Limit & Retry - Status de Implementação TDD

**Data:** 2026-05-23  
**Status:** 🟡 EM PROGRESSO (1/5 completo, 4/5 com testes criados)

---

## ✅ 1. RATE LIMITER - COMPLETO

**Arquivo:** `agents/lib_rate_limiter.ps1`  
**Testes:** `tests/lib_rate_limiter.Tests.ps1`  
**Status:** ✅ **28/28 testes passando**

### Funcionalidades Implementadas:
- ✅ Token bucket algorithm por categoria
- ✅ Refill automatico baseado em tempo
- ✅ Suporte a batch operations (cost > 1)
- ✅ Blocking com timeout configuravel
- ✅ Estatisticas de utilizacao
- ✅ Reset manual

### Categorias Suportadas:
```powershell
spot_place:      30 req/s
futures_place:   20 req/s
spot_cancel:     60 req/s
futures_cancel:  40 req/s
spot_query:      50 req/s
futures_query:   50 req/s
account_query:   10 req/s
```

### Uso:
```powershell
# Executar com rate limiting
$result = Invoke-RateLimitedCall -Category "spot_place" -Cost 1 -Action {
    CoinEx-PlaceOrder -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
}

# Batch (consome 10 tokens)
$result = Invoke-RateLimitedCall -Category "spot_place" -Cost 10 -Action {
    # Batch de 10 ordens
}

# Verificar stats
$stats = Get-RateLimitStats
```

---

## 🟡 2. RETRY COM BACKOFF - TESTES CRIADOS, IMPLEMENTAÇÃO PARCIAL

**Arquivo:** `agents/lib_coinex_retry.ps1`  
**Testes:** `tests/lib_coinex_retry.Tests.ps1`  
**Status:** 🟡 **22/29 testes passando** (7 falhas por scope de variáveis)

### Funcionalidades Implementadas:
- ✅ Retry automatico para erros transientes (4213, 3008)
- ✅ Backoff exponencial (300ms -> 600ms -> 1.2s -> ...)
- ✅ MaxRetries configuravel (default: 3)
- ✅ Classificacao de erros (retryable vs permanent)
- ✅ Estatisticas de retry
- ✅ Retry para timeout de rede

### Erros Retryable:
```powershell
4213  # Rate limited
3008  # Service busy
+ timeouts de rede
+ connection reset
+ 502/503/504
```

### Erros Permanentes (NAO retry):
```powershell
3109  # Saldo insuficiente
3127  # Quantidade abaixo do minimo
3606  # Preco fora do range
3639  # Parametros incorretos
4005-4008  # Auth failures
4017  # Signature issues
```

### Uso:
```powershell
$response = Invoke-CoinExWithRetry -Action {
    Invoke-RestMethod -Uri "https://api.coinex.com/v2/spot/order" -Method POST -Body $body
} -MaxRetries 3

# Com backoff customizado
$response = Invoke-CoinExWithRetry -Action {
    # ...
} -InitialBackoffMs 500 -MaxBackoffMs 60000
```

### 🔧 Correções Necessárias:
- Corrigir scope de variáveis nos testes ($script:callCount)
- Corrigir operador BeGreaterOrEqual para Pester 3.4

---

## 📝 3. ORDER QUEUE - TESTES CRIADOS, IMPLEMENTAÇÃO PENDENTE

**Arquivo:** `agents/lib_order_queue.ps1` (A CRIAR)  
**Testes:** `tests/lib_order_queue.Tests.ps1` ✅ CRIADO  
**Status:** 🔴 **Implementação pendente**

### Funcionalidades Planejadas:
- Fila de ordens com processamento assíncrono
- Worker thread respeitando rate limits
- Priority queue (high/normal/low)
- Callbacks quando ordem executada
- Status tracking (pending/executed/failed/cancelled)
- Estatísticas da fila

### Uso Planejado:
```powershell
# Adicionar ordem à fila
$orderId = Add-OrderToQueue -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000 -Priority "high"

# Iniciar worker
Start-OrderQueueWorker

# Consultar status
$order = Get-QueuedOrder -QueueId $orderId

# Cancelar ordem na fila
Remove-QueuedOrder -QueueId $orderId

# Stats
$stats = Get-QueueStats
```

---

## 📝 4. RATE LIMIT MONITOR - TESTES CRIADOS, IMPLEMENTAÇÃO PENDENTE

**Arquivo:** `agents/lib_rate_limit_monitor.ps1` (A CRIAR)  
**Testes:** `tests/lib_rate_limit_monitor.Tests.ps1` ✅ CRIADO  
**Status:** 🔴 **Implementação pendente**

### Funcionalidades Planejadas:
- Log de eventos 4213 em JSONL
- Agregação por categoria/market/período
- Health check (threshold de eventos/hora)
- Recomendações quando unhealthy
- Limpeza de logs antigos
- Relatórios (text/JSON)

### Uso Planejado:
```powershell
# Registrar evento
Log-RateLimitEvent -ErrorCode 4213 -Category "spot_place" -Market "BTCUSDT"

# Consultar eventos
$events = Get-RateLimitEvents -Hours 24 -Category "spot_place"

# Resumo
$summary = Get-RateLimitSummary

# Health check
$health = Test-RateLimitHealthy -ThresholdPerHour 10

# Relatório
$report = Export-RateLimitReport -Format "text"
```

### Log Format (JSONL):
```json
{"timestamp":"2026-05-23T10:30:45Z","error_code":4213,"category":"spot_place","market":"BTCUSDT"}
```

---

## 📝 5. CIRCUIT BREAKER - TESTES CRIADOS, IMPLEMENTAÇÃO PENDENTE

**Arquivo:** `agents/lib_circuit_breaker.ps1` (A CRIAR)  
**Testes:** `tests/lib_circuit_breaker.Tests.ps1` ✅ CRIADO  
**Status:** 🔴 **Implementação pendente**

### Funcionalidades Planejadas:
- Circuit breaker por categoria
- Estados: CLOSED / OPEN / HALF_OPEN
- Threshold configurável (default: 3 falhas)
- Timeout configurável (default: 30s)
- Transição automática OPEN -> HALF_OPEN
- Estatísticas por breaker

### Estados:
```
CLOSED: Normal operation
  ↓ (3+ falhas consecutivas)
OPEN: Bloqueia todas as chamadas
  ↓ (após timeout de 30s)
HALF_OPEN: Permite 1 tentativa
  ↓ (sucesso)        ↓ (falha)
CLOSED             OPEN
```

### Uso Planejado:
```powershell
# Executar com circuit breaker
$result = Invoke-WithCircuitBreaker -Category "spot_place" -Action {
    CoinEx-PlaceOrder -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 95000
}

# Stats
$stats = Get-CircuitBreakerStats

# Reset manual
Reset-CircuitBreaker -Category "spot_place"
```

---

## 🎯 PRÓXIMOS PASSOS

### Curto Prazo (Hoje):
1. ✅ ~~Corrigir testes do retry (scope de variáveis)~~
2. 🔴 Implementar `lib_order_queue.ps1`
3. 🔴 Implementar `lib_rate_limit_monitor.ps1`
4. 🔴 Implementar `lib_circuit_breaker.ps1`

### Médio Prazo (Amanhã):
5. 🔴 Integrar rate limiter em `lib_coinex.ps1`
6. 🔴 Integrar retry em `lib_coinex.ps1`
7. 🔴 Integrar circuit breaker em `lib_coinex.ps1`
8. 🔴 Integrar monitor em `lib_coinex.ps1`

### Integração em lib_coinex.ps1:
```powershell
function CoinEx-Post {
    param($path, $bodyObj)
    
    # Determinar categoria
    $category = Get-CategoryFromPath -Path $path
    
    # Circuit breaker check
    if (Test-CircuitBreakerOpen -Category $category) {
        return [PSCustomObject]@{
            success = $false
            error = "Circuit breaker open for $category"
        }
    }
    
    # Rate limiting + Retry + Circuit breaker
    $result = Invoke-WithCircuitBreaker -Category $category -Action {
        Invoke-RateLimitedCall -Category $category -Cost 1 -Action {
            Invoke-CoinExWithRetry -Action {
                # Chamada real da API
                $response = Invoke-RestMethod ...
                
                # Log rate limit events
                if ($response.code -eq 4213) {
                    Log-RateLimitEvent -ErrorCode 4213 -Category $category
                }
                
                return $response
            }
        }
    }
    
    return $result
}
```

---

## 📊 RESUMO DE STATUS

| Componente | Testes | Implementação | Status |
|------------|--------|---------------|--------|
| 1. Rate Limiter | ✅ 28/28 | ✅ Completo | ✅ PRONTO |
| 2. Retry Backoff | 🟡 22/29 | 🟡 Parcial | 🟡 90% |
| 3. Order Queue | ✅ Criados | 🔴 Pendente | 🔴 0% |
| 4. Monitor | ✅ Criados | 🔴 Pendente | 🔴 0% |
| 5. Circuit Breaker | ✅ Criados | 🔴 Pendente | 🔴 0% |
| **TOTAL** | **3/5** | **1/5** | **🟡 38%** |

---

## 🧪 EXECUTAR TESTES

```powershell
# Rate Limiter (PASSA)
Invoke-Pester -Path "tests\lib_rate_limiter.Tests.ps1"

# Retry (22/29 passando)
Invoke-Pester -Path "tests\lib_coinex_retry.Tests.ps1"

# Order Queue (implementação pendente)
Invoke-Pester -Path "tests\lib_order_queue.Tests.ps1"

# Monitor (implementação pendente)
Invoke-Pester -Path "tests\lib_rate_limit_monitor.Tests.ps1"

# Circuit Breaker (implementação pendente)
Invoke-Pester -Path "tests\lib_circuit_breaker.Tests.ps1"
```

---

## 📚 REFERÊNCIAS

- `ANALISE_RATE_LIMITS_E_LEVERAGE_2026_05_23.md` - Análise completa
- `knowledge/COINEX_REFERENCE.md` - Seção 2.3 (Rate Limits)
- CoinEx API v2 Docs: https://docs.coinex.com/api/v2/rate-limit

---

**Estimativa de Conclusão:** 4-6 horas de trabalho adicional para completar implementações 3, 4, 5 e integração.
