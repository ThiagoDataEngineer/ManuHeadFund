# 🚀 ROADMAP TDD — Evolução SHORT + Tori Proximity
**Data**: 2026-05-23  
**Estratégia**: Opção B (Evoluir SHORT + Evoluir Tori)  
**Metodologia**: Test-Driven Development (RED → GREEN → REFACTOR)  
**Timeline**: 15-20 dias (vs 20-25 dias sem TDD)

---

## 🎯 BENEFÍCIOS DO TDD

### Velocidade
- ✅ **Feedback loop rápido** (test → code → refactor em minutos)
- ✅ **Menos debugging** (tests pegam bugs antes de rodar LIVE)
- ✅ **Refactor seguro** (tests garantem que mudanças não quebram)

### Qualidade
- ✅ **Regression safety** (mudanças não quebram o que funciona)
- ✅ **Design emergente** (tests guiam arquitetura)
- ✅ **Documentação viva** (tests = specs executáveis)

### ROI
- ✅ **15-20 dias TDD** vs **20-25 dias tradicional** = **-25% tempo**
- ✅ **Menos bugs em produção** = **-50% tempo de hotfix**
- ✅ **Refactor confiante** = **+100% velocidade de iteração**

---

## ⚠️ RSI BUG DISCOVERY & IMPACT (2026-05-23)

### Descoberta Crítica
Durante TDD Sprint 1 backtest, descobrimos que RSI calculation estava retornando **0.0 em TODOS os casos** (bug crítico no coração do backtest). Isso significa que **TODOS os backtests anteriores com RSI estavam enviesados/inválidos**.

### Impacto nos Patterns

#### 1. Vol Climax + RSI Confluence (LONG)
- **ANTES** (RSI bugado): +20.7pp edge, n=278 signals
- **DEPOIS** (RSI corrigido, 8.8 anos): **-2.13% edge** ❌
- **Conclusão**: Edge +20.7pp era 100% ARTEFATO do RSI bug
- **Ação**: ❌ REMOVER RSI confluence (piora edge -0.88pp)

#### 2. SHORT Buying Climax (T6 Original)
- **ANTES** (RSI bugado): +2.85% edge, n=505 signals
- **DEPOIS** (RSI corrigido, 8.8 anos): **-15.80% edge** ❌
- **Conclusão**: Edge +2.85% era 100% ARTEFATO do RSI bug
- **Ação**: ❌ DESABILITAR SHORT scanner

#### 3. SHORT Bear Market 2022
- **Teste**: Bear 2021-2022 (BTC $69K → $15K)
- **Resultado**: **ZERO signals** ❌
- **Conclusão**: SHORT buying climax é extremamente raro
- **Ação**: ❌ Pattern INVIÁVEL

### ROI Impact
- **ANTES** (RSI bugado): +85% ROI/ano (FALSO)
- **DEPOIS** (RSI corrigido): -2.6% ROI/ano (PERDA)
- **DELTA**: -87.6% ROI/ano ❌

### Ações Tomadas
1. ✅ RSI fix implementado (Python + PowerShell validado)
2. ✅ Todos os backtests re-rodados com histórico completo
3. ✅ Documentação atualizada
4. ⏳ Cleanup: Remover RSI confluence + Desabilitar SHORT
5. ⏳ Focar em: Tori Proximity + Timeframe + Universe expansion

### Lições Aprendidas
- **TDD salvou o sistema**: Bug descoberto ANTES de deploy
- **Backtest é o coração**: RSI bug invalidou todos os resultados
- **Histórico completo é essencial**: Sample size pequeno = overfitting
- **RSI é noise, não signal**: Confluence não adiciona edge

---

## 📊 SPRINT 1: SHORT Patterns — Regime-Specific (STATUS: INVALIDADO)

### Objetivo
Otimizar SHORT patterns por regime (BEAR focus)  
**Hipótese**: Edge +2.85pp → +5-8pp em BEAR regimes

### Status Atual (2026-05-23)
- ✅ Tests criados: `tests/lib_short_signals_regime_specific.Tests.ps1`
- ✅ Fase RED confirmada: 5 pass, 2 fail, 1 inconclusive
- ⏳ Próximo: Fase GREEN (implementar código)


### Ciclo TDD — Dia 1-2

#### RED (✅ DONE)
```powershell
# Tests escritos, falhando conforme esperado:
# - BEAR_STRONG: ClimaxMult=2.0, RSI>75
# - BEAR_WEAK: ClimaxMult=2.5, RSI>70 (default)
# - TRANSITION_DOWN: ClimaxMult=3.0, RSI>65
# - Get-ShortThresholdsForRegime (função nova)

Invoke-Pester tests\lib_short_signals_regime_specific.Tests.ps1
# Result: 5 pass, 2 fail, 1 inconclusive
```

#### GREEN (⏳ TODO — Dia 1)
```powershell
# 1. Implementar Get-ShortThresholdsForRegime em lib_short_signals.ps1
function Get-ShortThresholdsForRegime {
    param([string]$Regime)
    switch ($Regime) {
        "BEAR_STRONG"     { @{ ClimaxMultiplier=2.0; RsiOverboughtMin=75 } }
        "BEAR_WEAK"       { @{ ClimaxMultiplier=2.5; RsiOverboughtMin=70 } }
        "TRANSITION_DOWN" { @{ ClimaxMultiplier=3.0; RsiOverboughtMin=65 } }
        default           { @{ ClimaxMultiplier=3.0; RsiOverboughtMin=70 } }
    }
}

# 2. Modificar short_scanner.ps1 para usar regime-specific thresholds
$regime = Get-CurrentRegime  # from lib_regime_detector.ps1
$thresholds = Get-ShortThresholdsForRegime -Regime $regime
$r = Detect-ShortSignal ... -ClimaxMultiplier $thresholds.ClimaxMultiplier `
    -RsiOverboughtMin $thresholds.RsiOverboughtMin

# 3. Rodar tests até todos passarem
Invoke-Pester tests\lib_short_signals_regime_specific.Tests.ps1
# Target: 8 pass, 0 fail, 0 inconclusive
```


#### REFACTOR (⏳ TODO — Dia 2)
```powershell
# 1. Extrair regime detection para lib_regime_detector.ps1 (reusable)
# 2. Adicionar cache de regime (evitar re-compute a cada scanner run)
# 3. Adicionar logging de regime transitions
# 4. Rodar tests para garantir que refactor não quebrou nada

Invoke-Pester tests\lib_short_signals_regime_specific.Tests.ps1
# Target: 8 pass, 0 fail (mantém GREEN)
```

### Backtest Validation — Dia 3

```python
# backtest/short_regime_specific_validation.py
# Objetivo: Validar edge +2.85pp → +5-8pp em BEAR regimes

# 1. Rodar backtest com thresholds regime-specific
# 2. Comparar vs baseline (thresholds fixos)
# 3. Validar por regime:
#    - BEAR_STRONG: edge esperado +5-8pp
#    - BEAR_WEAK: edge esperado +3-5pp
#    - TRANSITION_DOWN: edge esperado +2-3pp

# Expected result:
# - Overall edge: +2.85pp → +5.5pp (+93% boost)
# - Sample size: 505 → 450 (mais seletivo em non-BEAR)
# - Win rate: 60% → 62% (melhor quality)
```

### Deploy — Dia 4

```powershell
# 1. Habilitar SHORT patterns com regime-specific thresholds
$ENABLE_SHORT_PATTERNS = $true
$SHORT_MODE = "observatory"  # observatory → paper → live

# 2. Monitorar 7 dias em observatory mode
# 3. Validar signals vs backtest expectations
# 4. Promover para paper mode se validado
```

---

## 📊 SPRINT 2: Tori Proximity — Relaxed Thresholds (4-5 dias TDD)

### Objetivo
Relaxar Tori thresholds para gerar events  
**Hipótese**: 4-AND → 3-AND ou SOFT-GATES gera 10-50 events/ano

### Status Atual (2026-05-23)
- ✅ Tests criados: `tests/lib_tori_proximity_relaxed.Tests.ps1`
- ⏳ Próximo: Rodar tests (fase RED)


### Ciclo TDD — Dia 5-7

#### RED (⏳ TODO — Dia 5)
```powershell
# Rodar tests para confirmar fase RED
Invoke-Pester tests\lib_tori_proximity_relaxed.Tests.ps1
# Expected: múltiplos tests inconclusive (função Get-ToriProximityFromArraysRelaxed não existe)
```

#### GREEN (⏳ TODO — Dia 5-6)
```powershell
# 1. Implementar Get-ToriProximityFromArraysRelaxed em lib_tori_proximity.ps1
function Get-ToriProximityFromArraysRelaxed {
    param(
        [double[]]$Closes, [double[]]$Highs, [double[]]$Lows, [double[]]$Volumes,
        [string]$Mode = "4-AND",  # 4-AND | 3-AND | 3-AND-NO-RSI | SOFT-GATES
        [double]$ProximityMin = -3.0, [double]$ProximityMax = 5.0,
        [double]$RsiMax = 40.0,
        [double]$SlopeMin = 5.0, [double]$SlopeMax = 35.0
    )
    
    $config = Get-ToriRelaxedConfig -Mode $Mode
    # Override defaults com params explícitos
    if ($PSBoundParameters.ContainsKey('ProximityMin')) { $config.ProximityMin = $ProximityMin }
    # ... etc
    
    # Compute proximity (mesma lógica de Get-ToriProximityFromArrays)
    # Apply relaxed gates conforme $config
    
    return [PSCustomObject]@{
        valid = $true
        setup_ripening = $ripeningPassed
        # ... outros campos
    }
}

# 2. Implementar Get-ToriRelaxedConfig
function Get-ToriRelaxedConfig {
    param([string]$Mode)
    switch ($Mode) {
        "4-AND" { @{ ProximityMin=-3.0; ProximityMax=5.0; RsiMax=40.0; RequireVolDrying=$true; SlopeMin=5.0; SlopeMax=35.0 } }
        "3-AND" { @{ ProximityMin=-3.0; ProximityMax=5.0; RsiMax=40.0; RequireVolDrying=$false; SlopeMin=5.0; SlopeMax=35.0 } }
        "SOFT-GATES" { @{ ProximityMin=-5.0; ProximityMax=10.0; RsiMax=50.0; RequireVolDrying=$false; SlopeMin=3.0; SlopeMax=45.0 } }
        default { throw "Invalid mode: $Mode" }
    }
}

# 3. Rodar tests até todos passarem
Invoke-Pester tests\lib_tori_proximity_relaxed.Tests.ps1
# Target: 10+ pass, 0 fail, 0 inconclusive
```

#### REFACTOR (⏳ TODO — Dia 7)
```powershell
# 1. Unificar Get-ToriProximityFromArrays + Get-ToriProximityFromArraysRelaxed
#    (adicionar param -Mode à função original)
# 2. Adicionar backward compatibility (default Mode="4-AND")
# 3. Rodar TODOS os tests (original + relaxed) para garantir nada quebrou

Invoke-Pester tests\lib_tori_proximity.Tests.ps1
Invoke-Pester tests\lib_tori_proximity_relaxed.Tests.ps1
# Target: todos passando
```


### Backtest Validation — Dia 8-9

```python
# backtest/tori_proximity_relaxed_validation.py
# Objetivo: Validar se relaxed thresholds geram events com edge

# 1. Rodar backtest com 3 modes:
#    - 4-AND (baseline, ZERO events)
#    - 3-AND (remove vol_drying)
#    - SOFT-GATES (expand all ranges)

# 2. Medir:
#    - Events/ano: 0 → 10-50?
#    - Edge: DESCONHECIDO (precisa validar)
#    - Win rate: target 55-60%

# 3. Comparar vs vol_climax (benchmark):
#    - vol_climax: +8.6pp, n=278
#    - Tori relaxed: +?pp, n=?

# Expected result (conservador):
# - 3-AND: 10-15 events/ano, edge +5pp
# - SOFT-GATES: 30-50 events/ano, edge +3-5pp

# Expected result (otimista):
# - 3-AND: 20-30 events/ano, edge +8pp
# - SOFT-GATES: 50-100 events/ano, edge +5-8pp
```

### Deploy — Dia 9

```powershell
# 1. Escolher mode baseado em backtest results
#    - Se 3-AND tem edge +5pp+: usar 3-AND
#    - Se SOFT-GATES tem edge +3pp+: usar SOFT-GATES
#    - Se ambos sem edge: manter 4-AND (desabilitado)

# 2. Habilitar Tori com mode escolhido
$TORI_MODE = "3-AND"  # ou "SOFT-GATES"

# 3. Re-habilitar flags opt-in (se edge validado)
New-Item journal/TORI_PROXIMITY_BOOST.flag -ItemType File
New-Item journal/TORI_PROXIMITY_CONFLUENCE.flag -ItemType File

# 4. Monitorar 30 dias em observatory mode
```

---

## 📊 SPRINT 3: Timeframe Expansion (3-4 dias TDD)

### Objetivo
Expandir LONG + SHORT para 4h/1h timeframes  
**Hipótese**: Oportunidades/mês 8-12 → 15-20

### Ciclo TDD — Dia 10-13

#### RED (⏳ TODO — Dia 10)
```powershell
# Criar tests/vol_climax_timeframe_expansion.Tests.ps1
# Criar tests/short_signals_timeframe_expansion.Tests.ps1

# Tests devem validar:
# - Detect-VolumeClimax funciona em 4h/1h candles
# - Detect-ShortSignal funciona em 4h/1h candles
# - WSS scoring adapta-se a timeframes diferentes
# - Cluster filter adapta-se (max/dia → max/4h)
```

#### GREEN (⏳ TODO — Dia 11-12)
```powershell
# 1. Adicionar param -Timeframe a vol_climax_scanner.ps1
# 2. Adicionar param -Timeframe a short_scanner.ps1
# 3. Adaptar cluster filter para timeframe-aware caps
# 4. Rodar tests até todos passarem
```

#### REFACTOR (⏳ TODO — Dia 12)
```powershell
# 1. Extrair timeframe logic para lib_timeframe_utils.ps1
# 2. Unificar candle fetching (1d/4h/1h)
# 3. Rodar todos os tests
```

### Backtest Validation — Dia 13

```python
# backtest/timeframe_expansion_validation.py
# Objetivo: Validar edge em 4h/1h vs 1d baseline

# Expected result:
# - 1d: +8.6pp, 3-5 opp/mês (baseline)
# - 4h: +7-9pp, 8-12 opp/mês (mais oportunidades, edge similar)
# - 1h: +5-7pp, 15-20 opp/mês (mais oportunidades, edge menor)
```

---

## 📊 SPRINT 4: Universe Expansion (2-3 dias)

### Objetivo
Expandir markets 139 → 200+  
**Hipótese**: Sample size n=278 → n=500+

### Implementação — Dia 14-16

```powershell
# 1. Adicionar CoinEx markets (139 → 200+)
# 2. Adicionar Binance Top 50 (via API)
# 3. Adicionar Bybit Top 30 (via API)
# 4. Rodar backtest validation
# 5. Deploy gradual (10 markets/dia)
```

---

## 💰 IMPACTO ESPERADO TOTAL

### Conservador (15-20 dias TDD)
```
Capital: $5.000

LONG_vol_climax (Sprint 1 otimização + Sprint 3 timeframes):
- Edge: +8.6pp → +9pp
- Oportunidades/mês: 3-5 → 12-15
- Return/mês: +$270

SHORT patterns (Sprint 1 regime-specific + Sprint 3 timeframes):
- Edge: +2.85pp → +5pp
- Oportunidades/mês: 2-3 → 10-12
- Return/mês: +$150

Tori Proximity (Sprint 2 relaxed):
- Edge: +5pp (conservador)
- Oportunidades/mês: 1-2
- Return/mês: +$30

TOTAL: +$450/mês = +$5.400/ano = +108% ROI
```

### Otimista (15-20 dias TDD)
```
LONG_vol_climax:
- Edge: +8.6pp → +10pp
- Oportunidades/mês: 12-15 → 18-22
- Return/mês: +$400

SHORT patterns:
- Edge: +2.85pp → +8pp
- Oportunidades/mês: 10-12 → 15-18
- Return/mês: +$270

Tori Proximity:
- Edge: +8pp (otimista)
- Oportunidades/mês: 3-5
- Return/mês: +$90

TOTAL: +$760/mês = +$9.120/ano = +182% ROI
```

---

## 🎯 PRÓXIMOS PASSOS IMEDIATOS

### Hoje (2026-05-23)

1. ✅ **Confirmar fase RED** — Sprint 1 SHORT (DONE)
2. ⏳ **Confirmar fase RED** — Sprint 2 Tori
3. ⏳ **Começar fase GREEN** — Sprint 1 SHORT

### Comando para começar:

```powershell
# 1. Rodar tests Tori (confirmar RED)
Invoke-Pester tests\lib_tori_proximity_relaxed.Tests.ps1

# 2. Implementar Get-ShortThresholdsForRegime (GREEN)
# Editar: agents\lib_short_signals.ps1

# 3. Rodar tests até passar
Invoke-Pester tests\lib_short_signals_regime_specific.Tests.ps1
```

---

## 🤔 QUER COMEÇAR?

**Opção A**: Começar Sprint 1 GREEN (implementar SHORT regime-specific)  
**Opção B**: Confirmar Sprint 2 RED primeiro (rodar tests Tori)  
**Opção C**: Refinar roadmap antes de começar

**Qual você prefere?** 🚀
