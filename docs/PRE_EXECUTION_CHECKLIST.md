# ✅ PRÉ-EXECUÇÃO CHECKLIST — 10 Trades + Recalibração

> **Status**: 2026-06-06 (HOJE)  
> **Capital**: $5,000 account  
> **Histórico**: 6 trades (2 wins, 33% rate)  
> **Alvo**: 10 trades novos (dias 1-4), re-calibra dia 5  
> **Esperado**: 50%+ win rate após recalibração

---

## ☑️ PRÉ-FLIGHT (AGORA)

### 1. Validar Regime Atual
```powershell
# Verificar regime — determine SHORT availability
$regime = Get-CurrentRegime  # ou ler de journal/REGIME.flag

# Se BEAR: SHORT BLOQUEADO (Fase 0)
# Se BULL/SIDEWAYS: SHORT Fase 1 OK (3 wins needed)
```
**Status**: _____ (check your regime)

### 2. Validar Account Balance
```powershell
# Verificar saldo real na CoinEx
$balance = Get-CoinExBalance  # ex: $5,000

# Base position size = 1% = $50
# Max position = 2% = $100
# Min position = 0.1% = $5
```
**Status**: $_____ ✅

### 3. Validar Gates Ativados
```powershell
# Verificar flags no journal/
Test-Path "journal/PERFORMANCE_GATE_ENABLED.flag"  # Should be $true
Test-Path "journal/VOLATILITY_FILTER_ENABLED.flag"  # Should be $true
Test-Path "journal/MCE_GATES_ENABLED.flag"  # Should be $true
Test-Path "journal/POSITION_SIZING_ENABLED.flag"  # Should be $true

# Se algum for $false, ative:
"1" | Set-Content "journal/PERFORMANCE_GATE_ENABLED.flag"
```
**Status**: All flags ✅ / ❌ (need to enable)

### 4. Validar Calibração Carregada
```powershell
# Verificar signal_thresholds.json (da calibração anterior)
$thresholds = Get-Content "journal/signal_thresholds.json" | ConvertFrom-Json

# Deve ter:
# - faro_v3_threshold: 65+
# - tori_threshold: 50+
# - dsr_threshold: 60+
```
**Status**: _____ ✅ / ❌ (criar se missing)

### 5. Validar Logs Limpos
```powershell
# Resetar day-counter pra dia 1
$today = (Get-Date).Date

# Limpar métricas antigas (opcional, pra limpeza mental)
# Ou: apenas monitor dia 1-4

"Journal ready" | Out-File "journal/START_DATE_$(Get-Date -Format yyyyMMdd).txt"
```
**Status**: ✅ Ready

---

## 📊 PRIMEIRA EXECUÇÃO (DIA 1 — HOJE)

### Setup Ordem 1: LONG com Confluência 5/5

**Pré-requisitos**:
- ✅ Mentor confidence >= 80
- ✅ Confluence 5/5 (FARO + Tori + DSR + Mentor + Mesa)
- ✅ Vol <= 3% (OK action)
- ✅ BRT window 11h-15h (melhor volume)
- ✅ Regime != BEAR
- ✅ Position size < 2% (capital safety)

**Script de Entrada**:
```powershell
# 1. Selecionar market (ex: LINKUSDT)
$market = "LINKUSDT"

# 2. Validar dados
$validation = Test-InputDataNormality -Market $market `
    -CurrentPrice 9.58 `
    -Change24hPct 2.5 `
    -VolumeUsd 50000000 `
    -AtrPct 2.0

if (-not $validation.is_valid) {
    Write-Host "❌ DATA INVALID: $($validation.errors)"
    exit
}

# 3. Confluência
$perf = Invoke-PerformanceRefiner `
    -Market $market `
    -FaroV3Score 75 `
    -ToriProximity 80 `
    -DsrConfidence 70 `
    -MentorConviction 85 `
    -MesaConsensus "FORTE_3" `
    -VolatilityChange5mPct 1.5

if (-not $perf.approved) {
    Write-Host "❌ CONFLUENCE FAIL: $($perf.reason)"
    exit
}

# 4. Position Size
$dsr = Get-DsrConfidenceLevel -TradeHistory (Get-TradeHistory)
$sizing = Invoke-DynamicPositionSize `
    -Market $market `
    -AccountEquityUsd 5000 `
    -BetaVsBtc 1.5 `
    -ConfluenceCount $perf.confluence_count `
    -Regime "BULL"

# 5. SL/TP Refinado
$sltp = Invoke-RefinedStopLossTarget `
    -EntryPrice 9.58 `
    -AtrPct 2.0 `
    -PositionConfidence 1.0 `
    -Direction "LONG" `
    -Regime "BULL"

# 6. Log Entry
$tradeRecord = New-TradeAuditRecord `
    -Market $market `
    -Direction "LONG" `
    -EntryPrice 9.58 `
    -StoplossPrice $sltp.stop_loss `
    -TargetPrice $sltp.target `
    -PositionSizeUsd $sizing.final_size_usd `
    -ModelConfidence $perf.confluence_score `
    -DecisionReasoning "$($perf.confluence_count)/5 confluência + DSR $($dsr.level)" `
    -IsLiveExecution $true `
    -ConfluenceScore $perf.confluence_score

Write-Host "✅ ENTRADA APROVADA:"
Write-Host "  Market: $market"
Write-Host "  Entry: 9.58"
Write-Host "  SL: $($sltp.stop_loss)"
Write-Host "  Target: $($sltp.target)"
Write-Host "  Size: $($sizing.final_size_usd) USD"
Write-Host "  Mode: LIVE"
Write-Host ""
Write-Host "→ COLOQUE A ORDEM NO COINEX MANUALMENTE"
Write-Host "→ OU execute PlaceOrder com IDs da wallet"
```

**Esperado**:
- ✅ 1 trade executado
- ✅ Log em trade_audit_records.jsonl
- ✅ Status = LIVE

---

## 🔄 DIA 2-4: CONTINUE MONITORANDO

### Horário 11h BRT
```powershell
# Execute DAILY_MONITOR.ps1
.\journal\DAILY_MONITOR.ps1

# Esperado output:
# 📊 Trades (live): 1
# Win rate: ??%
# 🛡️ Gate block rate: 0%
# Status: 🟡 YELLOW (learning mode)
```

### Horário 14h BRT
```powershell
# Mesmos checks
# + Verificar volatilidade média
# + Revisar confluence das entradas
```

### Horário 18h BRT
```powershell
# DAILY SUMMARY
# IF win_rate >= 40% AND no_oversized THEN: VERDE ✅
# ELSE IF win_rate 20-40% THEN: AMARELO 🟡
# ELSE: VERMELHO 🔴 (investigate)
```

---

## 📋 DIA 4 PM: RE-CALIBRAÇÃO (IMPORTANTE!)

### 1. Coletar Métricas
```powershell
# Carregar últimos 10 trades
$allTrades = @(Get-Content "journal/trade_audit_records.jsonl" | `
    ConvertFrom-Json | `
    Where-Object { $_.is_live_execution })

$wins = ($allTrades | Where-Object { $_.pnl_usd -gt 0 }).Count
$total = $allTrades.Count
$winRate = if ($total -gt 0) { ($wins / $total) * 100 } else { 0 }

"Total trades: $total"
"Wins: $wins"
"Win rate: $([Math]::Round($winRate, 0))%"
```

### 2. Re-calibrar Sinais
```powershell
# FARO V3
$faroCalib = Invoke-SignalCalibration `
    -TradeHistory $allTrades `
    -SignalName "FARO_V3"

Write-Host "FARO novo threshold: $($faroCalib.recommended_threshold)"

# TORI
$toriCalib = Invoke-SignalCalibration `
    -TradeHistory $allTrades `
    -SignalName "TORI"

Write-Host "TORI novo threshold: $($toriCalib.recommended_threshold)"

# DSR
$dsrNew = Get-DsrConfidenceLevel -TradeHistory $allTrades
Write-Host "DSR novo level: $($dsrNew.level) ($($dsrNew.confidence_pct)%)"
```

### 3. Aplicar Novos Thresholds
```powershell
# Se win_rate >= 40%:
Update-SignalThresholds `
    -NewFaroThreshold $faroCalib.recommended_threshold `
    -NewToriThreshold $toriCalib.recommended_threshold `
    -NewDsrThreshold 60 `
    -TradeHistory $allTrades

Write-Host "✅ Novos thresholds aplicados"
Write-Host "   Dia 5+ usa calibração atualizada"
```

---

## 🎯 DECISION TREE (DIA 4 PM)

```
IF win_rate >= 50% AND pnl > 0 THEN
  ✅ SISTEMA OK — continue trades normalmente
  💡 Pode aumentar position sizing (0.8x → 1.0x)

ELSE IF win_rate 35-50% AND pnl >= -100 THEN
  🟡 AMARELO — continue 10 mais trades, re-calibra dia 8
  ⚠️ Não aumenta size, monitora confluência

ELSE IF win_rate < 35% OR pnl < -100 THEN
  🔴 VERMELHO — PAUSE trading, investigar
  🔍 Revisa: confluence muito alta? BEAR regime bloqueando? DSR subestimado?
```

---

## 📱 ALERTAS CRÍTICOS (STOP IMEDIATAMENTE)

```
IF oversized_trade == 1 (> 2% capital)
  🛑 STOP — capital safety quebrou
  → Investigar position_sizing_audit.jsonl
  → Não trade até fix

IF dd <= -15%
  🛑 STOP — emergency halt
  → Fecho posições abertas
  → Aguarde regime mudar

IF volatility_filter blocks > 50% em dia
  🟡 CAUTION — mercado muito barulhento
  → Reduce size 50%
  → Ou pause até próximo dia
```

---

## ✅ CHECKLIST ANTES DE COMEÇAR (AGORA!)

- [ ] Regime verificado (qual é?)
- [ ] Balance confirmado ($5000)
- [ ] Gates ativados (4 flags)
- [ ] Calibração carregada (thresholds.json)
- [ ] Primeira ordem pronta (5/5 confluence)
- [ ] CoinEx API conectada (ou manual order ready)
- [ ] Logs zerados (START_DATE criado)
- [ ] DAILY_MONITOR.ps1 pronto
- [ ] Timezone = BRT (11h-15h window)

**STATUS**: ___________________

---

## 🚀 INÍCIO

```
DIA 1 (HOJE): 1+ ordem
DIA 2: Monitor, +1 ordem
DIA 3: Monitor, +1 ordem  
DIA 4: Monitor, +1 ordem + RE-CALIBRA PM

Esperado DIA 5:
  - 4-5 novas ordens executadas
  - Win rate 40-50%+
  - Novos thresholds carregados
  - Pronto para dias 5-10 com calibração melhorada
```

---

**Ready?** ✅

Execute a primeira ordem agora com 5/5 confluência.

Depois volte aqui amanhã pra check-in diário.
