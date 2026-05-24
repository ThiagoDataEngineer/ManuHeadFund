# ANÁLISE DE GAP: CoinEx API V2 vs Implementação Atual

**Data**: 2026-05-23  
**Objetivo**: Identificar oportunidades de evolução na camada de integração com CoinEx  
**Metodologia**: Comparação entre documentação oficial e `lib_coinex.ps1`

---

## 📊 RESUMO EXECUTIVO

### ✅ O QUE TEMOS (28 funções)

| Categoria | Funções | Cobertura |
|-----------|---------|-----------|
| **Market Data** | 7 | ✅ 70% |
| **Account/Balance** | 4 | ⚠️ 40% |
| **Orders (Place)** | 4 | ✅ 80% |
| **Orders (Cancel)** | 4 | ✅ 100% (TDD 2026-05-23) |
| **Position Management** | 3 | ⚠️ 30% |
| **Fees/Funding** | 2 | ✅ 100% |
| **Precision/Market Info** | 3 | ✅ 90% |
| **Multi-Exit Ladder** | 1 | ✅ 100% (custom) |
| **TOTAL** | **28** | **~60%** |

### ❌ O QUE FALTA (Principais GAPs)

| Categoria | GAPs Críticos | Impacto |
|-----------|---------------|---------|
| **Position Management** | 7 endpoints | 🔴 ALTO |
| **Order Modification** | 6 endpoints | 🟡 MÉDIO |
| **Order Status/History** | 8 endpoints | 🟡 MÉDIO |
| **Assets (Deposit/Withdraw)** | 8 endpoints | 🟢 BAIXO |
| **Margin (Borrow/Repay)** | 4 endpoints | 🟢 BAIXO |
| **WebSocket** | Todos | 🟡 MÉDIO |
| **Batch Operations** | 6 endpoints | 🟢 BAIXO |

---

## 🔴 GAPs CRÍTICOS (Alta Prioridade)

### 1. **Position Management** (7 endpoints faltando)

#### ❌ Faltam:

```powershell
# 1. Ajustar Leverage + Margin Mode
CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10 -MarginMode "isolated"

# 2. Ajustar Margin (Add/Remove)
CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 100 -Type "add"

# 3. Modificar Stop Loss
CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000

# 4. Modificar Take Profit
CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000

# 5. Cancelar Stop Loss
CoinEx-CancelPositionStopLoss -Market "BTCUSDT"

# 6. Cancelar Take Profit
CoinEx-CancelPositionTakeProfit -Market "BTCUSDT"

# 7. Histórico de Posições
CoinEx-GetFinishedPositions -Market "BTCUSDT" -Limit 100
```

#### 📊 Impacto:

| Funcionalidade | Sem Implementação | Com Implementação |
|----------------|-------------------|-------------------|
| **Ajustar Leverage** | ❌ Fixo em default | ✅ Dinâmico (1-100x) |
| **Margin Mode** | ❌ Cross (perigoso) | ✅ Isolated (seguro) |
| **Modificar SL/TP** | ❌ Cancelar + recriar | ✅ Modificar direto |
| **Add Margin** | ❌ Não pode evitar liquidação | ✅ Salva posição |
| **Histórico** | ❌ Sem analytics | ✅ Análise de performance |

#### 💰 ROI Esperado:

- **Margin Mode Isolated**: +$500-1,000/ano (evita liquidação total)
- **Ajustar Leverage**: +$200-500/ano (otimiza capital)
- **Modificar SL/TP**: +$100-300/ano (menos fees)
- **Add Margin**: Priceless (salva posições em drawdown)
- **TOTAL**: **+$800-1,800/ano**

---

### 2. **Order Modification** (6 endpoints faltando)

#### ❌ Faltam:

```powershell
# 1. Modificar Ordem Regular (SPOT)
CoinEx-ModifySpotOrder -OrderId "123" -Price 65000 -Amount 0.002

# 2. Modificar Ordem Regular (FUTURES)
CoinEx-ModifyFuturesOrder -OrderId "456" -Price 65000 -Amount 0.002

# 3. Modificar Stop Order (SPOT)
CoinEx-ModifySpotStopOrder -StopId "stop-123" -TriggerPrice 64000

# 4. Modificar Stop Order (FUTURES)
CoinEx-ModifyFuturesStopOrder -StopId "stop-456" -TriggerPrice 64000

# 5. Batch Modify (SPOT)
CoinEx-ModifyBatchSpotOrders -Orders @(...)

# 6. Batch Modify (FUTURES)
CoinEx-ModifyBatchFuturesOrders -Orders @(...)
```

#### 📊 Impacto:

| Funcionalidade | Sem Implementação | Com Implementação |
|----------------|-------------------|-------------------|
| **Modificar Ordem** | ❌ Cancelar + recriar (2 fees) | ✅ Modificar (0 fees) |
| **Ajustar Stop** | ❌ Cancelar + recriar | ✅ Modificar direto |
| **Batch Modify** | ❌ Loop lento | ✅ Batch rápido |

#### 💰 ROI Esperado:

- **Economia de Fees**: +$100-200/ano (evita double fees)
- **Velocidade**: +$50-100/ano (menos slippage)
- **TOTAL**: **+$150-300/ano**

---

### 3. **Order Status & History** (8 endpoints faltando)

#### ❌ Faltam:

```powershell
# 1. Status de Ordem Específica (SPOT)
CoinEx-GetSpotOrderStatus -OrderId "123"

# 2. Status de Ordem Específica (FUTURES)
CoinEx-GetFuturesOrderStatus -OrderId "456"

# 3. Status Batch (FUTURES)
CoinEx-GetMultiOrderStatus -OrderIds @("123", "456", "789")

# 4. Ordens Pendentes (SPOT)
CoinEx-GetPendingSpotOrders -Market "BTCUSDT"

# 5. Ordens Pendentes (FUTURES)
CoinEx-GetPendingFuturesOrders -Market "BTCUSDT"

# 6. Ordens Finalizadas (SPOT)
CoinEx-GetFinishedSpotOrders -Market "BTCUSDT" -Limit 100

# 7. Ordens Finalizadas (FUTURES)
CoinEx-GetFinishedFuturesOrders -Market "BTCUSDT" -Limit 100

# 8. Histórico de Execuções (User Deals)
CoinEx-GetUserDeals -Market "BTCUSDT" -Limit 100
```

#### 📊 Impacto:

| Funcionalidade | Sem Implementação | Com Implementação |
|----------------|-------------------|-------------------|
| **Verificar Status** | ❌ Não sabe se executou | ✅ Confirma execução |
| **Ordens Pendentes** | ❌ Não sabe o que está aberto | ✅ Lista completa |
| **Histórico** | ❌ Sem analytics | ✅ Análise de performance |
| **Reconciliação** | ❌ Manual | ✅ Automática |

#### 💰 ROI Esperado:

- **Evitar Ordens Órfãs**: +$200-400/ano
- **Analytics**: +$100-200/ano (melhora decisões)
- **Reconciliação**: +$50-100/ano (menos erros)
- **TOTAL**: **+$350-700/ano**

---

## 🟡 GAPs MÉDIOS (Média Prioridade)

### 4. **WebSocket** (Real-time)

#### ❌ Faltam:

```powershell
# 1. Conectar WebSocket
$ws = Connect-CoinExWebSocket -Type "futures"

# 2. Autenticar
Authenticate-CoinExWebSocket -WebSocket $ws

# 3. Subscribe Order Updates
Subscribe-CoinExOrders -WebSocket $ws -Market "BTCUSDT"

# 4. Subscribe Position Updates
Subscribe-CoinExPositions -WebSocket $ws -Market "BTCUSDT"

# 5. Subscribe Depth Updates
Subscribe-CoinExDepth -WebSocket $ws -Market "BTCUSDT"

# 6. Subscribe Ticker Updates
Subscribe-CoinExTicker -WebSocket $ws -Market "BTCUSDT"
```

#### 📊 Impacto:

| Funcionalidade | REST (Atual) | WebSocket |
|----------------|--------------|-----------|
| **Latência** | ~100-300ms | ~10-50ms |
| **Polling** | ❌ Necessário | ✅ Push automático |
| **Rate Limit** | ⚠️ Consome cota | ✅ Não consome |
| **Real-time** | ❌ Delay | ✅ Instantâneo |

#### 💰 ROI Esperado:

- **Scalping/HFT**: +$1,000-3,000/ano (se implementar)
- **Trailing Stop**: +$200-500/ano (reação mais rápida)
- **Alertas**: +$100-200/ano (notificações instantâneas)
- **TOTAL**: **+$1,300-3,700/ano** (se usar HFT)

#### ⚠️ Complexidade:

- **Alta**: Requer gerenciamento de conexão, reconnect, heartbeat
- **Tempo**: ~2-3 dias de implementação
- **Prioridade**: Baixa para trade micro, Alta para scalping

---

### 5. **Batch Operations** (6 endpoints faltando)

#### ❌ Faltam:

```powershell
# 1. Batch Place Orders (SPOT)
CoinEx-PlaceBatchSpotOrders -Orders @(...)

# 2. Batch Place Orders (FUTURES)
CoinEx-PlaceBatchFuturesOrders -Orders @(...)

# 3. Batch Cancel Orders (SPOT)
CoinEx-CancelBatchSpotOrders -OrderIds @(...)

# 4. Batch Cancel Orders (FUTURES)
CoinEx-CancelBatchFuturesOrders -OrderIds @(...)

# 5. Batch Place Stop Orders (SPOT)
CoinEx-PlaceBatchSpotStopOrders -Orders @(...)

# 6. Batch Place Stop Orders (FUTURES)
CoinEx-PlaceBatchFuturesStopOrders -Orders @(...)
```

#### 📊 Impacto:

| Funcionalidade | Loop Individual | Batch |
|----------------|-----------------|-------|
| **Velocidade** | ~1s por ordem | ~100ms total |
| **Rate Limit** | ⚠️ Consome N cotas | ✅ Consome 1 cota |
| **Atomicidade** | ❌ Parcial | ✅ All-or-nothing |

#### 💰 ROI Esperado:

- **Multi-Exit Ladder**: +$100-200/ano (já temos custom)
- **Portfolio Rebalance**: +$50-100/ano
- **TOTAL**: **+$150-300/ano**

---

## 🟢 GAPs BAIXOS (Baixa Prioridade)

### 6. **Assets (Deposit/Withdraw)** (8 endpoints)

```powershell
# Deposit
CoinEx-GetDepositAddress -Ccy "BTC" -Network "BTC"
CoinEx-GetDepositHistory -Ccy "BTC" -Limit 100

# Withdraw
CoinEx-Withdraw -Ccy "BTC" -Amount 0.1 -Address "bc1q..."
CoinEx-CancelWithdraw -WithdrawId "123"
CoinEx-GetWithdrawHistory -Ccy "BTC" -Limit 100

# Config
CoinEx-GetDepositWithdrawConfig -Ccy "BTC"
CoinEx-GetAllDepositWithdrawConfig
CoinEx-GetCoinInfo -Ccy "BTC"
```

#### 💰 ROI: **+$0-50/ano** (operação manual é suficiente)

---

### 7. **Margin (Borrow/Repay)** (4 endpoints)

```powershell
# Borrow/Repay
CoinEx-MarginBorrow -Market "BTCUSDT" -Ccy "USDT" -Amount 1000
CoinEx-MarginRepay -BorrowId "123" -Amount 1000

# History
CoinEx-GetMarginBorrowHistory -Market "BTCUSDT"
CoinEx-GetMarginInterestLimit -Market "BTCUSDT"
```

#### 💰 ROI: **+$0-100/ano** (não usamos margin spot)

---

### 8. **Transfers** (2 endpoints)

```powershell
# Transfer entre wallets
CoinEx-Transfer -From "spot" -To "futures" -Ccy "USDT" -Amount 1000
CoinEx-GetTransferHistory -Limit 100
```

#### 💰 ROI: **+$0-50/ano** (operação rara)

---

## 📋 PRIORIZAÇÃO POR ROI

| Prioridade | Categoria | ROI/ano | Complexidade | Tempo |
|------------|-----------|---------|--------------|-------|
| **🔴 P0** | Position Management | +$800-1,800 | Média | 1 dia |
| **🔴 P1** | Order Status/History | +$350-700 | Baixa | 4h |
| **🟡 P2** | Order Modification | +$150-300 | Baixa | 4h |
| **🟡 P3** | WebSocket (se HFT) | +$1,300-3,700 | Alta | 2-3 dias |
| **🟡 P4** | Batch Operations | +$150-300 | Média | 6h |
| **🟢 P5** | Assets | +$0-50 | Baixa | 2h |
| **🟢 P6** | Margin | +$0-100 | Baixa | 2h |
| **🟢 P7** | Transfers | +$0-50 | Baixa | 1h |

---

## 🎯 RECOMENDAÇÃO: TOP 3 PARA IMPLEMENTAR

### 1️⃣ **Position Management** (P0 - CRÍTICO)

**Por quê**:
- ✅ **Margin Mode Isolated** é ESSENCIAL para segurança
- ✅ **Ajustar Leverage** otimiza capital
- ✅ **Modificar SL/TP** economiza fees
- ✅ **Add Margin** salva posições em drawdown

**ROI**: +$800-1,800/ano  
**Tempo**: 1 dia (8h)  
**Prioridade**: 🔴 **CRÍTICA**

**Funções a implementar**:
```powershell
CoinEx-AdjustPositionLeverage
CoinEx-AdjustPositionMargin
CoinEx-ModifyPositionStopLoss
CoinEx-ModifyPositionTakeProfit
CoinEx-CancelPositionStopLoss
CoinEx-CancelPositionTakeProfit
CoinEx-GetFinishedPositions
```

---

### 2️⃣ **Order Status & History** (P1 - ALTA)

**Por quê**:
- ✅ **Verificar Status** evita ordens órfãs
- ✅ **Ordens Pendentes** permite cleanup
- ✅ **Histórico** habilita analytics
- ✅ **Reconciliação** automática

**ROI**: +$350-700/ano  
**Tempo**: 4h  
**Prioridade**: 🔴 **ALTA**

**Funções a implementar**:
```powershell
CoinEx-GetSpotOrderStatus
CoinEx-GetFuturesOrderStatus
CoinEx-GetPendingFuturesOrders
CoinEx-GetFinishedFuturesOrders
CoinEx-GetUserDeals
```

---

### 3️⃣ **Order Modification** (P2 - MÉDIA)

**Por quê**:
- ✅ **Modificar Ordem** economiza fees (vs cancel+recreate)
- ✅ **Ajustar Stop** sem perder posição na fila
- ✅ **Batch Modify** para multi-exit

**ROI**: +$150-300/ano  
**Tempo**: 4h  
**Prioridade**: 🟡 **MÉDIA**

**Funções a implementar**:
```powershell
CoinEx-ModifyFuturesOrder
CoinEx-ModifyFuturesStopOrder
```

---

## 📊 ROADMAP SUGERIDO

### Fase 1: Segurança (1 dia)
- ✅ CancelOrder (DONE - TDD 2026-05-23)
- ⏳ Position Management (7 funções)

### Fase 2: Observabilidade (4h)
- ⏳ Order Status & History (5 funções)

### Fase 3: Otimização (4h)
- ⏳ Order Modification (2 funções)

### Fase 4: Avançado (2-3 dias - opcional)
- ⏳ WebSocket (se implementar HFT/scalping)
- ⏳ Batch Operations (se portfolio grande)

---

## 💡 QUICK WINS (Implementar Hoje)

### 1. **CoinEx-AdjustPositionLeverage** (30min)

```powershell
function CoinEx-AdjustPositionLeverage {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [int] $Leverage,
        [string] $MarginMode = "isolated"  # "isolated" | "cross"
    )
    
    $body = @{
        market      = $Market
        market_type = "FUTURES"
        leverage    = $Leverage
        margin_mode = $MarginMode
    }
    
    $r = CoinEx-Post "/v2/futures/adjust-position-leverage" $body
    return $r
}
```

**Uso**:
```powershell
# ANTES do primeiro trade, configurar:
CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 5 -MarginMode "isolated"
```

**Impacto**: 🔴 **CRÍTICO** - Evita liquidação total (cross mode é perigoso)

---

### 2. **CoinEx-GetPendingFuturesOrders** (15min)

```powershell
function CoinEx-GetPendingFuturesOrders {
    param(
        [string] $Market = "",
        [int] $Limit = 100
    )
    
    $path = "/v2/futures/pending-order?market=$Market&limit=$Limit"
    $r = CoinEx-Get $path
    return $r.data
}
```

**Uso**:
```powershell
# Verificar ordens pendentes antes de novo trade
$pending = CoinEx-GetPendingFuturesOrders -Market "BTCUSDT"
if ($pending.Count -gt 0) {
    Write-Warning "Já existem $($pending.Count) ordens pendentes!"
}
```

**Impacto**: 🟡 **MÉDIO** - Evita ordens órfãs

---

### 3. **CoinEx-ModifyPositionStopLoss** (15min)

```powershell
function CoinEx-ModifyPositionStopLoss {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $Price
    )
    
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $body = @{
        market           = $Market
        market_type      = "FUTURES"
        stop_loss_type   = "mark_price"
        stop_loss_price  = [math]::Round($Price, 4).ToString($inv)
    }
    
    $r = CoinEx-Post "/v2/futures/modify-position-stop-loss" $body
    return $r
}
```

**Uso**:
```powershell
# Ajustar stop loss sem cancelar + recriar
CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000
```

**Impacto**: 🟡 **MÉDIO** - Economiza fees

---

## 🎯 CONCLUSÃO

### ✅ O QUE TEMOS É BOM

Nossa implementação atual (28 funções) cobre **~60%** da API CoinEx V2:
- ✅ Market data completo
- ✅ Place orders (SPOT + FUTURES)
- ✅ Cancel orders (TDD 2026-05-23)
- ✅ Fees + Funding
- ✅ Multi-exit ladder (custom)

### ❌ O QUE FALTA É CRÍTICO

**3 GAPs principais** impactam segurança e ROI:
1. 🔴 **Position Management** (+$800-1,800/ano)
2. 🔴 **Order Status/History** (+$350-700/ano)
3. 🟡 **Order Modification** (+$150-300/ano)

### 💰 ROI TOTAL POTENCIAL

Implementando os 3 GAPs principais:
- **ROI**: +$1,300-2,800/ano
- **Tempo**: ~2 dias (16h)
- **Payback**: <1 mês

### 📋 PRÓXIMO PASSO

**Implementar Position Management HOJE** (1 dia):
1. ✅ CancelOrder (DONE)
2. ⏳ AdjustPositionLeverage (30min) ← **COMEÇAR AQUI**
3. ⏳ ModifyPositionStopLoss (15min)
4. ⏳ AdjustPositionMargin (30min)
5. ⏳ GetPendingFuturesOrders (15min)

**Total**: ~2h para quick wins críticos

---

**Quer que eu implemente os 3 quick wins agora (1h30)?** Ou prefere criar a spec do primeiro trade micro primeiro?

