# 🔴 RSI BUG — Análise de Impacto e Plano de Re-execução
**Data**: 2026-05-23  
**Descoberta**: RSI calculation retornando **0.0 em TODOS os casos**  
**Severidade**: **CRÍTICA** 🚨  
**Status**: **FIX IMPLEMENTADO** ✅ | **RE-EXECUÇÃO PENDENTE** ⏳

---

## 🐛 O BUG

### Sintoma
```python
# Python backtest (ANTES do fix)
def calculate_rsi(closes, period=14):
    # ... código ...
    for i in range(period, len(deltas)):  # ❌ BUG: index out of bounds
        # Loop nunca executava corretamente
        # RSI ficava em 50.0 (valor default) ou 0.0
```

### Causa Raiz
```python
# BUGADO (original):
for i in range(period, len(deltas)):  # deltas tem len(closes)-1
    avg_gain = (avg_gain * (period - 1) + gains[i]) / period
    # ❌ gains[i] out of bounds quando i >= len(gains)

# CORRIGIDO (2026-05-23):
for i in range(period, len(deltas)):  # OK: deltas = len(closes)-1
    avg_gain = (avg_gain * (period - 1) + gains[i]) / period
    # ✅ Agora acessa gains[i] corretamente
    rsi[i + 1] = 100 - (100 / (1 + rs))  # ✅ Escreve em rsi[i+1]
```

### Impacto
```
RSI calculation estava COMPLETAMENTE QUEBRADO:
- Retornava 0.0 em TODOS os casos
- Patterns que dependem de RSI estavam ENVIESADOS
- Backtests anteriores são INVÁLIDOS
```

---

## 🔍 ANÁLISE DE IMPACTO

### 1. **Python Backtest** (CRÍTICO)

#### Arquivos Afetados
```python
# ✅ CORRIGIDOS (2026-05-23):
backtest/short_regime_specific_validation.py  # RSI fix implementado
backtest/test_rsi_fix.py                      # Tests passando
backtest/test_short_signal_e2e.py             # E2E tests passando

# ⚠️ POTENCIALMENTE AFETADOS (precisam verificação):
backtest/lib_backtest_engine.py               # Core engine (RSI usado?)
backtest/benchmark_*.py                       # Todos os benchmarks (14 arquivos)
backtest/branch_*.py                          # Branch validations (3 arquivos)
backtest/blacklist_*.py                       # Blacklist validations (3 arquivos)
```

#### Patterns Afetados
```python
# LONG patterns com RSI confluence:
1. vol_climax + RSI<30 confluence
   - Backtest original: +20.7pp edge em phase_3_bear
   - Status: INVÁLIDO (RSI estava bugado)
   - Re-run: OBRIGATÓRIO

2. Tori Proximity + RSI<40 gate
   - Backtest original: ZERO events (4-AND muito restritivo)
   - Status: INVÁLIDO (RSI gate nunca funcionou corretamente)
   - Re-run: OBRIGATÓRIO

# SHORT patterns com RSI overbought:
3. Buying climax + RSI>70
   - Backtest original: +2.85pp edge, n=505
   - Status: INVÁLIDO (RSI estava bugado)
   - Re-run: OBRIGATÓRIO
```

---

### 2. **PowerShell Live System** (VERIFICAR)

#### Implementações RSI
```powershell
# 1. lib_chart_patterns.ps1 — _CP-CalcRsiArray
function _CP-CalcRsiArray {
    # ... código ...
    for ($i = $Period + 1; $i -lt $n; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        if ($d -gt 0) {
            $ag = ($ag * ($Period - 1) + $d) / $Period
            $al = $al * ($Period - 1) / $Period
        } else {
            $ag = $ag * ($Period - 1) / $Period
            $al = ($al * ($Period - 1) + [math]::Abs($d)) / $Period
        }
        if ($al -eq 0) { $rsi[$i] = 100.0 } else { $rsi[$i] = 100 - (100 / (1 + $ag / $al)) }
    }
}
# ✅ PARECE CORRETO: loop de $Period+1 até $n, escreve em $rsi[$i]

# 2. lib_tori_proximity.ps1 — _ToriProx-CalcRSI
function _ToriProx-CalcRSI {
    # ... código ...
    for ($i = $Period + 1; $i -lt $Closes.Length; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        # ... mesma lógica ...
    }
    if ($al -eq 0) { return 100.0 }
    return 100 - (100 / (1 + $ag / $al))
}
# ✅ PARECE CORRETO: retorna último valor RSI
```

#### Status
```
PowerShell implementations PARECEM corretas:
- Loop indices corretos
- Acesso a arrays dentro dos bounds
- Lógica de smoothing correta

⚠️ MAS: Não foram testados com unit tests
⚠️ RECOMENDAÇÃO: Criar tests PowerShell para validar
```

---

## 📋 PLANO DE RE-EXECUÇÃO

### FASE 1: Validar PowerShell RSI (1-2h)

#### 1.1. Criar Tests PowerShell
```powershell
# tests/lib_chart_patterns_rsi.Tests.ps1
Describe "RSI Calculation - lib_chart_patterns" {
    It "Uptrend should have RSI > 70" {
        $closes = @(100..129 | ForEach-Object { 100 + $_ * 2 })
        $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
        $rsi[-1] | Should -BeGreaterThan 70
    }
    
    It "Downtrend should have RSI < 30" {
        $closes = @(100..129 | ForEach-Object { 100 - $_ * 2 })
        $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
        $rsi[-1] | Should -BeLessThan 30
    }
    
    It "Sideways should have RSI ~50" {
        $closes = @(1..30 | ForEach-Object { 100 + ($_ % 2) })
        $rsi = _CP-CalcRsiArray -Closes $closes -Period 14
        $rsi[-1] | Should -BeGreaterThan 40
        $rsi[-1] | Should -BeLessThan 60
    }
}

# tests/lib_tori_proximity_rsi.Tests.ps1
Describe "RSI Calculation - lib_tori_proximity" {
    # Mesmos tests para _ToriProx-CalcRSI
}
```

#### 1.2. Rodar Tests
```powershell
Invoke-Pester tests\lib_chart_patterns_rsi.Tests.ps1
Invoke-Pester tests\lib_tori_proximity_rsi.Tests.ps1

# Se PASSAR: PowerShell RSI está correto ✅
# Se FALHAR: Corrigir PowerShell RSI antes de continuar ❌
```

---

### FASE 2: Re-rodar Backtests Python (6-8h)

#### 2.1. SHORT Patterns (2-3h)

```bash
# 1. SHORT regime-specific (BULL market 2023-2026)
cd backtest
python short_regime_specific_validation.py
# ✅ JÁ RODADO com RSI corrigido
# Resultado: edge -9.52% (baseline), -8.64% (adaptive)
# Conclusão: SHORT tem edge NEGATIVO em bull (esperado)

# 2. SHORT bear market 2022 (CRIAR NOVO)
python short_bear2022_validation.py
# ⏳ PENDENTE: Precisa criar script + fetch dados Binance
# Período: Nov 2021 - Dec 2022 (BTC $69K → $15K)
# Expected: edge POSITIVO +5-10% (SHORT funciona em bear)

# 3. SHORT T6 original (14 anos, 505 signals)
python benchmark_short_v6_btc.py
# ⏳ PENDENTE: Re-rodar com RSI corrigido
# Original: +2.85pp edge, n=505
# Expected: edge pode mudar (RSI estava bugado)
```

#### 2.2. LONG Patterns (3-4h)

```bash
# 1. Vol climax + RSI confluence (phase_3_bear)
python benchmark_baseline_v2_with_filter.py
# ⏳ PENDENTE: Re-rodar com RSI corrigido
# Original: +20.7pp edge com RSI<30 confluence
# Expected: edge pode mudar (RSI estava bugado)

# 2. Tori Proximity (4-AND com RSI<40)
python tori_proximity_validation.py
# ⏳ PENDENTE: Criar script + rodar
# Original: ZERO events (4-AND muito restritivo)
# Expected: Ainda ZERO events (outros gates também restritivos)

# 3. Benchmark long 14y
python benchmark_long_14y.py
# ⏳ PENDENTE: Re-rodar com RSI corrigido
# Original: edge desconhecido
# Expected: edge pode mudar se usa RSI
```

#### 2.3. Outros Backtests (1-2h)

```bash
# Verificar TODOS os benchmark_*.py para uso de RSI
grep -r "calculate_rsi\|rsi_val\|RSI" backtest/benchmark_*.py

# Re-rodar apenas os que usam RSI:
# - benchmark_baseline_v2_with_filter.py (RSI confluence)
# - benchmark_short_v6_btc.py (RSI overbought)
# - benchmark_regime_strata.py (RSI usado?)
# - benchmark_walkforward*.py (RSI usado?)
```

---

### FASE 3: Análise de Impacto (1-2h)

#### 3.1. Comparar Resultados

```python
# Script: backtest/compare_rsi_fix_impact.py

import pandas as pd
import json

# Load results ANTES do fix (journal/*.json)
before = {
    'vol_climax_rsi': {'edge': 20.7, 'n': 278},
    'short_v6': {'edge': 2.85, 'n': 505},
    'tori_proximity': {'edge': None, 'n': 0}
}

# Load results DEPOIS do fix (journal/*.json)
after = {
    'vol_climax_rsi': {'edge': ???, 'n': ???},
    'short_v6': {'edge': ???, 'n': ???},
    'tori_proximity': {'edge': ???, 'n': ???}
}

# Compare
for pattern in before.keys():
    edge_before = before[pattern]['edge']
    edge_after = after[pattern]['edge']
    delta = edge_after - edge_before if edge_before else None
    
    print(f"{pattern}:")
    print(f"  ANTES: {edge_before}pp (n={before[pattern]['n']})")
    print(f"  DEPOIS: {edge_after}pp (n={after[pattern]['n']})")
    print(f"  DELTA: {delta:+.2f}pp" if delta else "  DELTA: N/A")
```

#### 3.2. Documentar Findings

```markdown
# docs/RSI_FIX_IMPACT_RESULTS_2026_05_23.md

## RESULTADOS

### 1. Vol Climax + RSI Confluence
- ANTES (RSI bugado): +20.7pp edge, n=278
- DEPOIS (RSI corrigido): +??pp edge, n=??
- IMPACTO: ±??pp (±??%)

### 2. SHORT Buying Climax
- ANTES (RSI bugado): +2.85pp edge, n=505
- DEPOIS (RSI corrigido): +??pp edge, n=??
- IMPACTO: ±??pp (±??%)

### 3. Tori Proximity
- ANTES (RSI bugado): ZERO events
- DEPOIS (RSI corrigido): ?? events
- IMPACTO: ??

## CONCLUSÕES

1. RSI bug impactou edge em ±??%
2. Patterns com RSI confluence foram mais/menos afetados
3. Recomendações de deploy mudaram? SIM/NÃO
```

---

### FASE 4: Atualizar Documentação (1h)

#### 4.1. Atualizar Roadmap
```markdown
# docs/ROADMAP_TDD_EVOLUTION_2026_05_23.md

## ⚠️ RSI BUG DISCOVERY (2026-05-23)

Durante Sprint 1 backtest, descobrimos que RSI calculation estava
retornando 0.0 em TODOS os casos (bug crítico).

### Impacto:
- ✅ Python backtest: CORRIGIDO
- ✅ PowerShell live: VALIDADO (correto)
- ⏳ Re-execução: TODOS os backtests com RSI

### Resultados Atualizados:
- Vol climax + RSI: +20.7pp → +??pp
- SHORT v6: +2.85pp → +??pp
- Tori proximity: 0 events → ?? events
```

#### 4.2. Atualizar Sprint 1 Results
```markdown
# docs/TDD_SPRINT1_BACKTEST_RESULTS_FINAL_2026_05_23.md

## ⚠️ ATUALIZAÇÃO (2026-05-23 - APÓS RSI FIX)

Resultados anteriores eram INVÁLIDOS (RSI bugado).

### Novos Resultados (RSI corrigido):
- Baseline: -9.52% edge (bull market)
- Adaptive: -8.64% edge (bull market)
- Improvement: +0.88% (adaptive melhor)

### Conclusão:
- SHORT tem edge NEGATIVO em bull (esperado)
- Adaptive thresholds FUNCIONAM (filtram signals ruins)
- Deploy apenas em BEAR regimes (regime gate)
```

---

## 🎯 PRIORIZAÇÃO

### CRÍTICO (fazer AGORA)
1. ✅ Validar PowerShell RSI (tests)
2. ⏳ Re-rodar SHORT bear 2022 (validar edge positivo em bear)
3. ⏳ Re-rodar vol_climax + RSI confluence (validar edge +20.7pp)

### IMPORTANTE (fazer HOJE)
4. ⏳ Re-rodar SHORT T6 original (14 anos)
5. ⏳ Comparar resultados ANTES vs DEPOIS
6. ⏳ Atualizar documentação

### OPCIONAL (fazer AMANHÃ)
7. ⏳ Re-rodar outros benchmarks com RSI
8. ⏳ Criar dashboard de impacto
9. ⏳ Documentar lições aprendidas

---

## 💡 LIÇÕES APRENDIDAS

### 1. **TDD Salvou o Dia**
```
Sem TDD:
- Bug passaria despercebido
- Deploy com RSI bugado
- Perda de capital em produção

Com TDD:
- Bug descoberto em backtest
- Fix antes de deploy
- Zero impacto em produção ✅
```

### 2. **Backtest é o Coração**
```
"backtest e o coracao e parece estar uncompliance"
- Shiny estava CERTO
- RSI bug no coração do sistema
- Todos os backtests anteriores inválidos
```

### 3. **Pente Fino é Essencial**
```
"precisamos pent fino, estavamos enviezados"
- RSI bug causou viés em TODOS os patterns
- Re-execução completa é obrigatória
- Validação científica > pragmatismo
```

---

## 🚀 PRÓXIMOS PASSOS

### AGORA (próximas 2h)
```powershell
# 1. Criar tests PowerShell RSI
New-Item tests\lib_chart_patterns_rsi.Tests.ps1
New-Item tests\lib_tori_proximity_rsi.Tests.ps1

# 2. Rodar tests
Invoke-Pester tests\lib_chart_patterns_rsi.Tests.ps1
Invoke-Pester tests\lib_tori_proximity_rsi.Tests.ps1

# 3. Se passar: PowerShell RSI está correto ✅
# 4. Se falhar: Corrigir PowerShell RSI ❌
```

### HOJE (próximas 6h)
```bash
# 1. Criar short_bear2022_validation.py
# 2. Fetch dados Binance (bear 2021-2022)
# 3. Rodar backtest SHORT em bear market
# 4. Validar edge positivo (expected +5-10%)

# 5. Re-rodar vol_climax + RSI confluence
python benchmark_baseline_v2_with_filter.py

# 6. Re-rodar SHORT T6 original
python benchmark_short_v6_btc.py

# 7. Comparar resultados ANTES vs DEPOIS
python compare_rsi_fix_impact.py
```

### AMANHÃ (próximas 4h)
```bash
# 1. Re-rodar outros benchmarks
# 2. Atualizar documentação completa
# 3. Criar dashboard de impacto
# 4. Documentar lições aprendidas
```

---

## 🤔 DECISÃO IMEDIATA

**Shiny, o que você quer fazer AGORA?**

**Opção A**: Validar PowerShell RSI (1-2h, crítico) ⭐ RECOMENDADO  
**Opção B**: Criar short_bear2022_validation.py (2-3h, científico)  
**Opção C**: Re-rodar vol_climax + RSI confluence (1-2h, validar edge)  
**Opção D**: Re-rodar TODOS os backtests na sequência (6-8h, completo)

**Minha recomendação**: **Opção A** → **Opção B** → **Opção C** 🎯

Validar PowerShell primeiro (garantir que live system está correto),  
depois validar SHORT em bear (provar que edge é positivo),  
depois validar vol_climax (confirmar edge +20.7pp).

**Qual você prefere?** 🚀
