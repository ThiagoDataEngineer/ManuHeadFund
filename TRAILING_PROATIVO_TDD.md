# 🧠 Trailing Proativo — Implementação TDD

**Data inicio:** 2026-05-25  
**Metodologia:** RED → GREEN → REFACTOR

---

## 📋 ESTRUTURA DE ARQUIVOS

```
agents/
  lib_trailing.ps1                   # Existente - reativo (Camada 1)
  lib_trailing_smart.ps1             # NOVO - Camadas 2-5
  lib_trailing_exhaustion.ps1        # NOVO - detectores Camada 3

tests/
  trailing_smart_atr.Tests.ps1       # Camada 2: ATR adaptativo
  trailing_exhaustion.Tests.ps1      # Camada 3: doji, vol, wick, divergence
  trailing_microstructure.Tests.ps1  # Camada 4 (Fase 2)
  trailing_macro.Tests.ps1           # Camada 5 (Fase 3)
  trailing_integration.Tests.ps1     # End-to-end
```

---

## 🎯 FASE 1 — Camadas 2 e 3 (esta sessao)

### Camada 2: ATR Adaptativo
**Funções:**
- `Get-AtrStopDistance` — retorna stop em ATRs
- `Calculate-AdaptiveStopPrice` — preço de stop adaptativo

**Tests:**
```powershell
It "Get-AtrStopDistance returns 2.5 ATR for LOW_VOL pair" {
    Get-AtrStopDistance -AtrPct 1.5 | Should Be 2.5
}
It "Get-AtrStopDistance returns 1.5 ATR for HIGH_VOL pair" {
    Get-AtrStopDistance -AtrPct 5.0 | Should Be 1.5
}
It "Calculate-AdaptiveStopPrice for LONG with ATR=2 entry=100 returns 95" {
    Calculate-AdaptiveStopPrice -Side LONG -Entry 100 -AtrAbs 2.0 -AtrMultiple 2.5 |
        Should Be 95.0
}
```

### Camada 3: Exhaustion Detection

**3 Detectores:**

#### 3.1 — Doji Top (`Test-DojiTop`)
- Candle no topo dos últimos N
- Range body / range high-low < 0.3
- Wick superior > 1.5x body
```powershell
It "Detects doji at top of recent range" {
    $candles = @(... pump candles + doji at end ...)
    Test-DojiTop -Candles $candles | Should Be $true
}
```

#### 3.2 — Volume Drying (`Test-VolumeDrying`)
- Vol últimas 3h < 50% média 24h
- Indica falta de interesse no movimento
```powershell
It "Detects volume drying when last 3h is half of 24h avg" {
    $candles = @(... high vol then drying ...)
    Test-VolumeDrying -Candles $candles | Should Be $true
}
```

#### 3.3 — Wick Top (`Test-WickTop`)
- Candle 1h com wick superior > 2x body
- Sinal de rejeição em LONG
```powershell
It "Detects wick rejection at top" {
    $candle = @{ open=100; high=110; low=99; close=101 }  # wick=9, body=1
    Test-WickTop -Candle $candle | Should Be $true
}
```

#### 3.4 — Score Combinado (`Get-ExhaustionScore`)
Retorna score 0-100 baseado em quantos sinais detectaram:
```powershell
It "Returns score 100 when all 3 signals fire" {
    # mock 3 detectores retornando true
    Get-ExhaustionScore -Candles $candles | Should Be 100
}
It "Returns 0 when no signals" {
    Get-ExhaustionScore -Candles $cleanCandles | Should Be 0
}
```

#### 3.5 — Stop Tightening Recommendation
```powershell
It "Suggests tighter stop when exhaustion >=66" {
    $r = Get-StopRecommendation -ExhaustionScore 70 -CurrentStop 90 -CurrentPrice 100
    $r.suggestedStop | Should BeGreaterThan 90  # mais próximo do preço
}
```

---

## 🎯 FASE 2 — Camada 4: Microstructure

### 4.1 — Open Interest Divergence
- Preço em HH mas OI cai = falta convicção
- Função: `Test-OiDivergence`

### 4.2 — Funding Rate Flip
- LONG: funding positivo→negativo = vendedores agressivos
- Função: `Test-FundingFlip`

### 4.3 — Order Book Imbalance
- Bid wall removida = sem suporte abaixo
- Função: `Test-BidWallRemoved`

### 4.4 — Whale Dump Integration
- Já temos `lib_whale_watcher.ps1` — integrar
- Função: `Test-WhaleDumpDetected`

---

## 🎯 FASE 3 — Camada 5: Macro

### 5.1 — BTC Correlation Stress
- BTC -3% em 1h → todas alts em LONG: tighten
- Função: `Get-BtcCorrelationPressure`

### 5.2 — DXY Spike Detection
- DXY +1% rápido = bearish crypto
- Função: `Test-DxySpike` (via FRED API)

### 5.3 — Event-Driven Tightening
- FOMC, CPI dates → trailing ultra-apertado 24h
- Função: `Test-MacroEventWindow`

### 5.4 — Cross-asset Score
```powershell
Get-MacroPressureScore -Position $pos
# Returns 0-100 (0 = safe, 100 = max pressure)
```

---

## 🏗️ ALGORITMO INTEGRADOR

```powershell
function Get-SmartStop {
    param([PSCustomObject]$Position)
    
    # Camada 1: stop reativo atual
    $reactiveStop = Get-TrailingNewStop -Pos $Position
    
    # Camada 2: ATR adaptativo
    $atrStop = Calculate-AdaptiveStopPrice -Side $Position.side `
        -Entry $Position.entry -AtrAbs $atr -AtrMultiple 2.5
    
    # Camada 3: exhaustion
    $exhaustion = Get-ExhaustionScore -Candles $candles
    $exhaustionAdj = if ($exhaustion -ge 66) { 0.5 } # apertar 50%
                     elseif ($exhaustion -ge 33) { 0.75 }
                     else { 1.0 }
    
    # Camada 4: microstructure (Fase 2)
    $microPressure = Get-MicrostructurePressure -Market $Position.market
    
    # Camada 5: macro (Fase 3)
    $macroPressure = Get-MacroPressureScore -Position $Position
    
    # Stop final: mais conservador entre todos, ajustado por pressões
    $candidates = @($reactiveStop, $atrStop)
    $finalStop = if ($Position.side -eq "LONG") {
        ($candidates | Measure-Object -Maximum).Maximum
    } else {
        ($candidates | Measure-Object -Minimum).Minimum
    }
    
    # Aplicar tightening por exhaustion/micro/macro
    $totalPressure = ($exhaustion + $microPressure + $macroPressure) / 3
    if ($totalPressure -ge 50) {
        $tightenPct = $totalPressure / 200  # max 50% tighter
        $finalStop = $finalStop + ($Position.entry - $finalStop) * $tightenPct
    }
    
    # Hard rule: stop NUNCA recua (em LONG, só sobe)
    return [math]::Max($finalStop, $Position.stopCurrent)
}
```

---

## ✅ CRITÉRIOS DE ACEITAÇÃO

### Fase 1
- [ ] 15+ testes Pester passando para Camadas 2-3
- [ ] Backtest paper últimas 30 dias: trailing proativo vs reativo
- [ ] Integração no `Update-TrailingStops`
- [ ] Zero regressão nos 4 trades vivos

### Fase 2
- [ ] 10+ testes para Camada 4
- [ ] Whale watcher integrado
- [ ] OI/funding APIs validadas

### Fase 3
- [ ] 8+ testes para Camada 5
- [ ] BTC correlation funcionando
- [ ] FRED integration confirmada

---

## 🚀 ORDEM DE EXECUÇÃO

1. **RED**: Escrever testes que falham (TDD)
2. **GREEN**: Implementar código mínimo para passar
3. **REFACTOR**: Limpar e otimizar
4. **INTEGRATE**: Wire no `Update-TrailingStops`
5. **VALIDATE**: Rodar nos 4 trades reais (paper)
6. **DEPLOY**: Commit + GitHub Actions

Vamos começar pela **Camada 2** — mais simples, código já existe parcialmente.
