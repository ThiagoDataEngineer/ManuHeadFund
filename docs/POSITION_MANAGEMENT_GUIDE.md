# Position Management - Guia Completo

## 📋 Visão Geral

Sistema completo de gestão de posições com 7 funções críticas + módulo de risk management automático.

## 🎯 Funcionalidades

### 1. **Funções Base** (`lib_coinex_position_management.ps1`)

#### CoinEx-AdjustPositionLeverage
Ajusta leverage e margin mode de uma posição.

```powershell
# Ajustar para 10x isolated
CoinEx-AdjustPositionLeverage -Market "BTCUSDT" -Leverage 10 -MarginMode "isolated"

# Ajustar para 5x cross
CoinEx-AdjustPositionLeverage -Market "ETHUSDT" -Leverage 5 -MarginMode "cross"
```

**Casos de Uso:**
- Reduzir leverage em alta volatilidade
- Aumentar leverage em mercados calmos
- Mudar de isolated para cross margin

#### CoinEx-AdjustPositionMargin
Adiciona ou remove margin de uma posição.

```powershell
# Adicionar 100 USDT de margin (evitar liquidação)
CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 100 -Type "add"

# Remover 50 USDT de margin (liberar capital)
CoinEx-AdjustPositionMargin -Market "BTCUSDT" -Amount 50 -Type "remove"
```

**Casos de Uso:**
- Posição próxima de liquidação → adicionar margin
- Posição com lucro grande → remover margin para usar em outro trade
- Ajuste fino de risco/retorno

#### CoinEx-ModifyPositionStopLoss
Modifica stop loss sem cancelar ordem (economiza fees).

```powershell
# Modificar SL para 95000 (mark price trigger)
CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000

# Modificar SL usando latest price trigger
CoinEx-ModifyPositionStopLoss -Market "BTCUSDT" -Price 95000 -TriggerType "latest_price"
```

**Casos de Uso:**
- Trailing stops manuais
- Ajustar SL após notícias
- Proteger lucros parciais

#### CoinEx-ModifyPositionTakeProfit
Modifica take profit sem cancelar ordem.

```powershell
# Modificar TP para 105000
CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000

# Modificar TP com latest price trigger
CoinEx-ModifyPositionTakeProfit -Market "BTCUSDT" -Price 105000 -TriggerType "latest_price"
```

**Casos de Uso:**
- Ajustar target após breakout
- Reduzir target em resistência forte
- Gestão dinâmica de exits

#### CoinEx-CancelPositionStopLoss
Cancela stop loss da posição.

```powershell
# Cancelar SL (use com cuidado!)
CoinEx-CancelPositionStopLoss -Market "BTCUSDT"
```

**Casos de Uso:**
- Remover SL temporariamente durante alta volatilidade
- Substituir por SL manual mais complexo

#### CoinEx-CancelPositionTakeProfit
Cancela take profit da posição.

```powershell
# Cancelar TP
CoinEx-CancelPositionTakeProfit -Market "BTCUSDT"
```

**Casos de Uso:**
- Deixar posição correr sem limite
- Substituir por TP escalonado

#### CoinEx-GetFinishedPositions
Busca histórico de posições finalizadas.

```powershell
# Buscar últimas 50 posições de BTCUSDT
CoinEx-GetFinishedPositions -Market "BTCUSDT" -Limit 50

# Buscar todas as posições (últimas 100)
CoinEx-GetFinishedPositions -Limit 100
```

**Casos de Uso:**
- Analytics de performance
- Calcular win rate
- Identificar padrões de erro

---

### 2. **Risk Manager Automático** (`lib_position_risk_manager.ps1`)

#### Update-TrailingStop
Trailing stop dinâmico baseado em ATR.

```powershell
# Trailing stop com ATR 2.5x, ativa após 3% lucro
Update-TrailingStop -Market "BTCUSDT" -AtrMultiplier 2.5 -MinProfitPct 3

# Dry run (simular sem executar)
Update-TrailingStop -Market "BTCUSDT" -DryRun
```

**Como Funciona:**
1. Calcula ATR (14 períodos, 1h)
2. Verifica se posição tem lucro mínimo (default 2%)
3. Calcula novo SL = preço atual - (ATR × multiplicador)
4. Atualiza SL apenas se melhor que atual
5. Usa `ModifyPositionStopLoss` (sem fees extras)

**Exemplo Real:**
```
BTC @ 100,000 (entry 98,000)
ATR = 800
Multiplicador = 2.0
Novo SL = 100,000 - (800 × 2.0) = 98,400
Lucro protegido: +0.4%
```

#### Adjust-LeverageByVolatility
Ajusta leverage automaticamente por volatilidade.

```powershell
# Leverage 3x-10x baseado em volatilidade
Adjust-LeverageByVolatility -Market "BTCUSDT" -MaxLeverage 10 -MinLeverage 3

# Dry run
Adjust-LeverageByVolatility -Market "BTCUSDT" -DryRun
```

**Como Funciona:**
1. Calcula ATR% = (ATR / preço) × 100
2. Mapeia ATR% para leverage:
   - ATR% < 1% → leverage máximo (mercado calmo)
   - ATR% > 5% → leverage mínimo (mercado volátil)
   - Entre 1-5% → interpolação linear
3. Ajusta leverage se diferente do atual

**Exemplo Real:**
```
BTC @ 100,000
ATR = 500
ATR% = 0.5% → Baixa volatilidade
Leverage: 10x (máximo permitido)

vs.

BTC @ 100,000
ATR = 6,000
ATR% = 6% → Alta volatilidade
Leverage: 3x (mínimo, proteção)
```

#### Protect-FromLiquidation
Adiciona margin quando próximo de liquidação.

```powershell
# Adicionar 100 USDT se distância < 15%
Protect-FromLiquidation -Market "BTCUSDT" -ThresholdPct 15 -MarginToAdd 100

# Dry run
Protect-FromLiquidation -Market "BTCUSDT" -DryRun
```

**Como Funciona:**
1. Calcula distância até liquidation price
2. Se distância < threshold → adiciona margin
3. Envia alerta Telegram
4. Afasta liquidation price

**Exemplo Real:**
```
LONG BTC @ 100,000
Liquidation: 92,000
Preço atual: 93,000
Distância: 7.5% < 10% threshold
→ Adiciona 100 USDT margin
→ Nova liquidation: 90,000
→ Nova distância: 13.3% (seguro)
```

#### Invoke-PositionRiskScan
Scan completo de todas as posições.

```powershell
# Scan automático de todas as posições
Invoke-PositionRiskScan

# Dry run (simular)
Invoke-PositionRiskScan -DryRun
```

**O que faz:**
1. Busca todas as posições abertas
2. Para cada posição:
   - Atualiza trailing stop
   - Ajusta leverage por volatilidade
   - Protege de liquidação
3. Envia resumo via Telegram

---

## 🤖 Automação com Cron

### Setup do Cron Job

**Windows (Task Scheduler):**
```powershell
# Criar tarefa que roda a cada 15 minutos
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-File C:\Users\thiag\Coinex_AI_USER_API\scripts\position_risk_cron.ps1"

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)

Register-ScheduledTask -TaskName "CoinEx_PositionRisk" -Action $action -Trigger $trigger
```

**Linux (crontab):**
```bash
# Editar crontab
crontab -e

# Adicionar linha (roda a cada 15 minutos)
*/15 * * * * /usr/bin/pwsh /home/user/Coinex_AI_USER_API/scripts/position_risk_cron.ps1
```

### Teste Manual

```powershell
# Rodar uma vez manualmente
cd C:\Users\thiag\Coinex_AI_USER_API
.\scripts\position_risk_cron.ps1
```

---

## 📊 Exemplos de Integração

### Exemplo 1: Trailing Stop no gem_executor

```powershell
# Após abrir posição GEM, ativar trailing stop
$gemResult = Invoke-GemExecute -Gem $gem

if ($gemResult.success -and -not $gemResult.dry_run) {
    # Aguardar 1 minuto para posição aparecer
    Start-Sleep -Seconds 60
    
    # Ativar trailing stop (ATR 2x, ativa após 2% lucro)
    Update-TrailingStop -Market $gem.market -AtrMultiplier 2.0 -MinProfitPct 2.0
}
```

### Exemplo 2: Ajuste de Leverage Pré-Trade

```powershell
# Antes de abrir posição, ajustar leverage por volatilidade
$market = "BTCUSDT"

# Ajustar leverage baseado em volatilidade atual
Adjust-LeverageByVolatility -Market $market -MaxLeverage 10 -MinLeverage 3

# Aguardar ajuste
Start-Sleep -Seconds 2

# Abrir posição com leverage otimizado
CoinEx-PlaceFuturesOrder -Market $market -Side "buy" -Amount 0.001
```

### Exemplo 3: Proteção Contínua

```powershell
# Loop infinito de proteção (rodar em background)
while ($true) {
    try {
        # Scan completo a cada 15 minutos
        Invoke-PositionRiskScan
        
        Write-Host "Próximo scan em 15 minutos..." -ForegroundColor DarkGray
        Start-Sleep -Seconds (15 * 60)
    }
    catch {
        Write-Host "Erro: $_" -ForegroundColor Red
        Start-Sleep -Seconds 60
    }
}
```

---

## 🧪 Testes

### Rodar Testes Unitários

```powershell
# Rodar todos os testes
Invoke-Pester ".\tests\lib_coinex_position_management.Tests.ps1" -Verbose

# Resultado esperado: 23 testes passando
```

### Teste Manual (Dry Run)

```powershell
# Testar trailing stop sem executar
Update-TrailingStop -Market "BTCUSDT" -DryRun

# Testar leverage adjustment sem executar
Adjust-LeverageByVolatility -Market "BTCUSDT" -DryRun

# Testar proteção de liquidação sem executar
Protect-FromLiquidation -Market "BTCUSDT" -DryRun

# Scan completo sem executar
Invoke-PositionRiskScan -DryRun
```

---

## ⚠️ Avisos Importantes

### 1. **Isolated vs Cross Margin**
- **Isolated**: Risco limitado à margin da posição (recomendado para GEMs)
- **Cross**: Usa todo o saldo da conta como margin (risco de liquidação total)

### 2. **Fees de Modificação**
- `ModifyPositionStopLoss/TakeProfit`: **SEM fees** (apenas atualiza ordem existente)
- `CancelPosition + PlaceOrder`: **COM fees** (2 operações)

### 3. **Rate Limits**
- CoinEx API: 20 req/s
- Position Management: ~3 req por posição
- Máximo: ~6 posições por segundo

### 4. **Liquidation Protection**
- Adicionar margin **NÃO garante** que não será liquidado
- Apenas **adia** a liquidação
- Use como **última linha de defesa**, não como estratégia principal

### 5. **Trailing Stops**
- Só ativa após lucro mínimo (default 2%)
- Não protege contra gaps (ex: crash súbito)
- Usa mark price por default (evita manipulação)

---

## 📈 Métricas e Monitoramento

### Logs Importantes

```powershell
# Ver últimas execuções do cron
Get-Content ".\journal\position_risk_log.txt" -Tail 50

# Ver alertas de liquidação
Get-Content ".\journal\liquidation_alerts.txt" -Tail 20

# Ver histórico de trailing stops
Get-Content ".\journal\trailing_stop_history.jsonl" -Tail 10
```

### Telegram Alerts

O sistema envia alertas para:
- ⚠️ Posição próxima de liquidação
- 📊 Resumo de ações tomadas (trailing/leverage/margin)
- 🚨 Erros críticos no cron job

---

## 🔧 Troubleshooting

### Problema: "CommandNotFoundException: CoinEx-AdjustPositionLeverage"

**Solução:**
```powershell
# Verificar se módulo está carregado
Get-Command CoinEx-AdjustPositionLeverage

# Se não estiver, carregar manualmente
. ".\agents\lib_coinex_position_management.ps1"
```

### Problema: "Position not found"

**Causas:**
1. Posição já foi fechada
2. Market name incorreto (verificar BTCUSDT vs BTC-USDT)
3. Posição em outro market type (SPOT vs FUTURES)

**Solução:**
```powershell
# Verificar posições abertas
$positions = CoinEx-GetPendingPositions
$positions | Format-Table market, side, amount, leverage
```

### Problema: Trailing stop não atualiza

**Causas:**
1. Lucro < MinProfitPct (default 2%)
2. Novo SL seria pior que atual
3. Dados insuficientes para calcular ATR

**Solução:**
```powershell
# Rodar com verbose para ver motivo
Update-TrailingStop -Market "BTCUSDT" -Verbose

# Reduzir MinProfitPct se necessário
Update-TrailingStop -Market "BTCUSDT" -MinProfitPct 1.0
```

---

## 📚 Referências

- **CoinEx API Docs**: https://docs.coinex.com/api/v2/futures
- **ATR (Average True Range)**: Indicador de volatilidade desenvolvido por J. Welles Wilder
- **Isolated vs Cross Margin**: https://www.binance.com/en/support/faq/isolated-margin-vs-cross-margin-360033162972

---

## 🎓 Próximos Passos

1. ✅ **Implementado**: 7 funções base + risk manager
2. ✅ **Implementado**: Testes unitários (23 testes)
3. ✅ **Implementado**: Cron job automático
4. 🔄 **Próximo**: Integrar com gem_executor
5. 🔄 **Próximo**: Dashboard de métricas
6. 🔄 **Próximo**: Machine learning para otimizar parâmetros

---

**Criado em**: 2026-05-23  
**Versão**: 1.0.0  
**Status**: ✅ Produção (testado com TDD rigoroso)
