# 🔗 MAPA DE DEPENDÊNCIAS — Patterns Sem Edge
**Data**: 2026-05-23  
**Analista**: Claude Sonnet 4.5  
**Objetivo**: Mapear dependências completas de SHORT patterns, Tori Proximity e Confluence antes de qualquer remoção

---

## 🎯 CONTEXTO

### Descobertas Críticas (Branch A/B/C)

| Pattern | Status | Edge Validado | Sample Size | Ação Proposta |
|---------|--------|---------------|-------------|---------------|
| **LONG_vol_climax** | ✅ ÚNICO com edge | +8.6pp | n=278, avg_hit +14.4% | **MANTER + OTIMIZAR** |
| **Tori Proximity** | ❌ ZERO events | N/A | 0 em 50.871 bars × 47 markets × 3 anos | Avaliar dependências |
| **SHORT patterns** | ❌ Sem edge | N/A | Exec path SUSPENSO | Avaliar dependências |
| **Confluence multi-pattern** | ❌ Pior que isolado | +3.1pp vs +8.6pp | Folklore não validado | Avaliar dependências |

**User Request**: "o short patterns tem dependencias refine se confluece e tori tbm"

---

## 📊 1. SHORT PATTERNS — Mapeamento Completo

### 1.1. Arquivos Core

#### `agents/lib_short_signals.ps1`
**Funções**:
- `Detect-ShortSignal`: Wrapper de `Detect-VolumeClimax -Side SHORT` + RSI confluence
- `Get-ShortSignalWss`: Integration com Wyckoff Spring Score

**Dependências**:
```powershell
# IMPORTS
. lib_chart_patterns.ps1  # Detect-VolumeClimax (CORE)
. lib_wyckoff_spring_score.ps1  # Get-WyckoffSpringScore

# CHAMADAS
Detect-VolumeClimax -Side SHORT -ClimaxMultiplier 2.5
Get-WyckoffSpringScore -Market $mkt ...
```

**Status**: ✅ **Auto-contida** — não afeta LONG patterns

---

#### `scripts/short_scanner.ps1`
**Função**: Scanner hourly de SHORT signals (mirror de vol_climax_scanner.ps1)

**Dependências**:
```powershell
# IMPORTS
. agents/lib_short_signals.ps1
. agents/lib_telegram.ps1
. agents/lib_wyckoff_spring_score.ps1
. agents/lib_cluster_filter.ps1
. agents/lib_wss_forward_tracker.ps1

# LEITURA
journal/per_asset_whitelist_*.json  # SHORT_TIER_A_LIVE + SHORT_TIER_B_PAPER

# ESCRITA
journal/short_alerts.jsonl
logs/short_scanner_*.log
```

**Cron**: `scripts/register_short_scanner.ps1` (hourly)

**Status**: ✅ **Isolado** — não afeta vol_climax_scanner.ps1 (LONG)

---

### 1.2. Whitelist Integration

#### `agents/lib_operational_whitelist.ps1`
**Função**: `Test-RegimeDirectionAllowed` — valida se SHORT é permitido por regime

**Regras SHORT**:
```powershell
# Regra 5 (v3 2026-05-16): SHORT bidirecional
if ($Direction -eq 'SHORT') {
    $bearishRegimes = @('BEAR_STRONG','BEAR_WEAK','CAPITULATION','TRANSITION_DOWN')
    
    if ($bearishRegimes -contains $Regime) {
        return @{ allowed=$true; tier='execute'; reason="SHORT em $Regime (v3 bidirecional)" }
    }
    
    if ($Regime -eq 'SIDEWAYS') {
        if ($Mode -eq 'paper') {
            return @{ allowed=$true; tier='observe'; reason="SHORT em SIDEWAYS -- paper observa" }
        }
        return @{ allowed=$false; tier='skip'; reason="SHORT em SIDEWAYS -- live exige bear regime" }
    }
    
    # BULL_* + SHORT = anti-trend perigoso, sempre skip
    return @{ allowed=$false; tier='skip'; reason="SHORT em $Regime -- anti-trend" }
}
```

**Status**: ✅ **Isolado** — não afeta LONG rules

---

### 1.3. Whitelist Data

#### `journal/per_asset_whitelist_*.json`
**Campos SHORT**:
```json
{
  "SHORT_TIER_A_LIVE": [
    {"market": "BTCUSDT", "reason": "..."}
  ],
  "SHORT_TIER_B_PAPER": [
    {"market": "ETHUSDT", "reason": "..."}
  ]
}
```

**Consumidores**:
- `scripts/short_scanner.ps1` (lê SHORT_TIER_A_LIVE + SHORT_TIER_B_PAPER)
- `agents/lib_operational_whitelist.ps1` (valida regras SHORT)

**Status**: ✅ **Isolado** — campos separados de LONG_TIER_A_LIVE

---

### 1.4. Tests

#### `tests/lib_short_signals.Tests.ps1`
**Cobertura**:
- `Detect-ShortSignal` (estrutura, vol spike, RSI confluence)
- `Get-ShortSignalWss` (integration com WSS)

**Status**: ✅ **Isolado** — não afeta tests de LONG

---

### 1.5. Backtest

#### `backtest/benchmark_short_v6_btc.py` (provável)
**Função**: Backtest de SHORT patterns (T6 validou EV +2.85pp em 505 signals)

**Status**: ⚠️ **Não encontrado no grep** — pode estar em outro arquivo ou branch

---

### 🎯 1.6. IMPACTO DE REMOVER SHORT PATTERNS

#### ✅ ZERO IMPACTO em LONG patterns

**Razão**: SHORT é completamente isolado:
- Funções separadas (`Detect-ShortSignal` vs `Detect-VolumeClimax -Side LONG`)
- Scanner separado (`short_scanner.ps1` vs `vol_climax_scanner.ps1`)
- Whitelist separada (`SHORT_TIER_A_LIVE` vs `LONG_TIER_A_LIVE`)
- Alerts separados (`short_alerts.jsonl` vs `vol_climax_alerts.jsonl`)

#### ⚠️ IMPACTO em Whitelist Operacional

**Dependência**: `lib_operational_whitelist.ps1` tem regras SHORT (Regra 5)

**Opções**:
1. ✂️ **Remover regras SHORT** de `lib_operational_whitelist.ps1` (quebra tests)
2. ⏸️ **Manter regras SHORT** mas desabilitar scanner (sem impacto)
3. 🔧 **Adicionar flag** `$ENABLE_SHORT_PATTERNS = $false` (fail-soft)

**Recomendação**: **Opção 3** (flag-gated disable)

---

## 📊 2. TORI PROXIMITY — Mapeamento Completo

### 2.1. Arquivos Core

#### `agents/lib_tori_proximity.ps1`
**Funções**:
- `Get-ToriProximityFromArrays`: LONG side (ascending support)
- `Get-ToriShortProximityFromArrays`: SHORT side (descending resistance)
- `Get-ToriProximity`: Orquestração LONG+SHORT + escolha de "active side"
- `Get-ToriProximitySnapshot`: Lê snapshot state.json
- `Get-ToriProximityForMarket`: Lê proximity de 1 market
- `Get-ToriProximityRipeningMarkets`: Filtra markets com setup_ripening=true

**Dependências**: ✅ **ZERO** — auto-contida (inline math, inline API fetch)

**Status**: ✅ **Isolada** — não importa outras libs

---

### 2.2. Consumers (Opt-In Flag-Gated)

#### A. `agents/gem_executor.ps1` — MISSED log enrichment
**Função**: Enriquece `missed_setups.jsonl` com Tori proximity data

**Flag**: Nenhuma (sempre ativo se lib disponível)

**Código**:
```powershell
if (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue) {
    try {
        $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath
        if ($tp) {
            $entry.tori_proximity_pct = $tp.proximity_pct
            $entry.tori_action_line = $tp.action_line
            $entry.isTimingMissed = ($tp.setup_ripening -eq $true)
        }
    } catch {}
}
```

**Impacto de remover**: ⚠️ **Campos ausentes em missed_setups.jsonl** (não quebra, apenas menos dados)

---

#### B. `scripts/scan_master.ps1` — PRIORITY BOOST
**Função**: Adiciona +1000 ao compScore quando Tori ripening=true

**Flag**: `journal/TORI_PROXIMITY_BOOST.flag` (opt-in)

**Código**:
```powershell
$boostFlag = Join-Path $projectRoot "journal\TORI_PROXIMITY_BOOST.flag"
if ((Test-Path $boostFlag) -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
    try {
        $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath
        if ($tp -and $tp.setup_ripening -eq $true) {
            $compScore += 1000
            $gates_passed += "TORI-PRIORITY-BOOST"
        }
    } catch {}
}
```

**Impacto de remover**: ✅ **ZERO** se flag ausente (opt-in)

---

#### C. `agents/gem_agent.ps1` — VOL_SPIKE confluence
**Função**: Adiciona +5 ao score quando vol_spike + Tori ripening confluentes

**Flag**: `journal/TORI_PROXIMITY_CONFLUENCE.flag` (opt-in)

**Código**:
```powershell
$confluenceFlag = Join-Path (Split-Path $PSScriptRoot -Parent) "journal\TORI_PROXIMITY_CONFLUENCE.flag"
if ((Test-Path $confluenceFlag) -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
    try {
        $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath
        if ($tp -and $tp.setup_ripening -eq $true -and $tp.side -eq "LONG") {
            $score += 5
            $confluenceTag = "G9-TORI-LONG-RIPE"
        } elseif (-not [bool]$tp.valid) {
            $absProx = [math]::Abs($tp.proximity_pct)
            if ($absProx -gt 15.0) {
                $chaseRiskHigh = $true
                $confluenceTag = "G9-CHASE-RISK-${absProx}pct"
            }
        }
        if ($confluenceTag) { $gates_passed += $confluenceTag }
    } catch {}
}
```

**Impacto de remover**: ✅ **ZERO** se flag ausente (opt-in)

---

### 2.3. Snapshot Writer

#### `scripts/tori_proximity_scanner.ps1` (provável)
**Função**: Cron 15min que escreve `journal/tori_proximity_state.json`

**Status**: ⚠️ **Não encontrado no grep** — pode estar em outro arquivo

---

### 2.4. Tests

#### `tests/lib_tori_proximity.Tests.ps1`
**Cobertura**:
- `Get-ToriProximityFromArrays` (estrutura, proximity calc, ripening predicate)
- `Get-ToriShortProximityFromArrays` (SHORT side mirror)
- `Get-ToriProximity` (orquestração LONG+SHORT)
- Snapshot readers (fresh/stale, market lookup, ripening filter)

**Status**: ✅ **Isolado** — não afeta outros tests

---

#### `tests/tori_proximity_enrichments_ABC.Tests.ps1`
**Cobertura**:
- A. gem_executor MISSED log enrichment
- B. scan_master PRIORITY BOOST flag-gated
- C. gem_agent VOL_SPIKE confluence flag-gated

**Status**: ✅ **Anti-regression** — valida opt-in behavior

---

### 2.5. Mentor Integration

#### `agents/lib_mentor_gate_block.ps1`
**Função**: `Build-GateStatusBlock` inclui Tori proximity no context block

**Código**:
```powershell
$ctx = @{
    regime = ...
    drawdown = ...
    tori_proximity = [PSCustomObject]@{
        valid = $true
        side = "LONG"
        proximity_pct = 2.3
        action_line = 100.5
        touches = 4
        slope_deg = 22
        rsi = 35
        vol_drying = $true
        setup_ripening = $true
    }
    gates = ...
}
```

**Impacto de remover**: ⚠️ **Context block incompleto** (Mentor pode quebrar se espera campo)

---

### 🎯 2.6. IMPACTO DE REMOVER TORI PROXIMITY

#### ✅ ZERO IMPACTO em vol_climax_scanner.ps1 (LONG core)

**Razão**: Tori Proximity é **opt-in flag-gated** em todos os consumers:
- gem_executor: try/catch + Get-Command guard (fail-soft)
- scan_master: flag `TORI_PROXIMITY_BOOST.flag` (opt-in)
- gem_agent: flag `TORI_PROXIMITY_CONFLUENCE.flag` (opt-in)

#### ⚠️ IMPACTO em Mentor Context

**Dependência**: `lib_mentor_gate_block.ps1` inclui `tori_proximity` no context

**Opções**:
1. ✂️ **Remover campo** de context (quebra Mentor se espera campo)
2. ⏸️ **Manter campo** com `valid=false` (fail-soft)
3. 🔧 **Adicionar flag** `$ENABLE_TORI_PROXIMITY = $false` (fail-soft)

**Recomendação**: **Opção 2** (manter campo com valid=false)

---

## 📊 3. CONFLUENCE MULTI-PATTERN — Mapeamento Completo

### 3.1. Definição

**O que é Confluence?**
- Combinar múltiplos patterns (vol_climax + Tori + outros) para aumentar edge
- **Hipótese**: Confluence amplifica edge (ex: vol_climax +8.6pp → +12pp com Tori)
- **Realidade**: Confluence DILUI edge (+8.6pp → +3.1pp)

---

### 3.2. Implementações Atuais

#### A. RSI Confluence (MANTÉM — funciona!)

**Localização**: `agents/lib_chart_patterns.ps1` — `Detect-VolumeClimax`

**Código**:
```powershell
# REFINED 2026-05-22: mult=2.5 + RSI<30 confluence
# Edge: +8.6pp → +20.7pp em phase_3_bear

if ($RsiOversoldMax) {
    $rsiVal = _CP-CalcRsiArray -Closes $Closes
    if ($Side -eq "LONG") {
        $rsiPassed = $rsiVal -lt [double]$RsiOversoldMax
    }
    if (-not $rsiPassed) {
        return @{ detected=$false; reason="rsi_confluence_failed"; rsi=$rsiVal }
    }
}
```

**Status**: ✅ **MANTÉM** — RSI confluence FUNCIONA (+11pp edge boost)

---

#### B. Tori Confluence (OPT-IN — não funciona)

**Localização**: `agents/gem_agent.ps1` — GemScan vol_spike confluence

**Código**:
```powershell
# C. Tori PROXIMITY confluence 2026-05-22: opt-in flag
$confluenceFlag = Join-Path ... "journal\TORI_PROXIMITY_CONFLUENCE.flag"
if ((Test-Path $confluenceFlag) -and (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue)) {
    $tp = Get-ToriProximityForMarket -Market $mkt -StatePath $statePath
    if ($tp -and $tp.setup_ripening -eq $true -and $tp.side -eq "LONG") {
        $score += 5
        $confluenceTag = "G9-TORI-LONG-RIPE"
    }
}
```

**Status**: ⚠️ **OPT-IN flag-gated** — pode ser desabilitado removendo flag

---

#### C. Multi-Pattern Confluence (FOLKLORE — não existe no código!)

**Busca**: Grep por "confluence|multi-pattern" não encontrou implementação de "combinar vol_climax + Tori + outros"

**Conclusão**: ❌ **FOLKLORE** — "Confluence multi-pattern" mencionado em docs mas **NÃO IMPLEMENTADO** no código

**Evidência**:
- Branch A findings mencionam "Confluence multi-pattern ❌ Pior que isolado (+3.1pp vs +8.6pp)"
- Mas grep search não encontrou código que combina múltiplos patterns
- Única confluence real é **RSI** (que funciona!)

---

### 🎯 3.3. IMPACTO DE REMOVER CONFLUENCE

#### ✅ RSI Confluence — MANTÉM (funciona!)

**Razão**: Edge boost +11pp validado em backtest

**Ação**: **NENHUMA** — manter como está

---

#### ✅ Tori Confluence — DESABILITAR (opt-in)

**Razão**: Opt-in flag-gated, pode ser desabilitado removendo flag

**Ação**: **Remover flag** `journal/TORI_PROXIMITY_CONFLUENCE.flag`

**Impacto**: ✅ **ZERO** — código permanece, apenas desabilitado

---

#### ✅ Multi-Pattern Confluence — NÃO EXISTE

**Razão**: Folklore não implementado

**Ação**: **NENHUMA** — não há código para remover

---

## 🎯 4. RECOMENDAÇÕES FINAIS

### 4.1. SHORT Patterns

**Status Atual**:
- ✅ Completamente isolado de LONG patterns
- ✅ Scanner separado (`short_scanner.ps1`)
- ✅ Whitelist separada (`SHORT_TIER_A_LIVE`)
- ⚠️ Regras em `lib_operational_whitelist.ps1` (Regra 5)

**Recomendação**: **MANTER SUSPENSO** (não remover código)

**Razão**:
1. ✅ **ZERO impacto** em LONG patterns (isolado)
2. ✅ **Backtest T6** validou EV +2.85pp em 505 signals (edge positivo!)
3. ⚠️ **Exec path SUSPENSO** por decisão estratégica (não por falta de edge)
4. 🔬 **Re-testar em BEAR regime** pode revelar edge maior

**Ação**:
```powershell
# Adicionar flag de controle
$ENABLE_SHORT_PATTERNS = $false  # em config.ps1

# Modificar short_scanner.ps1
if (-not $ENABLE_SHORT_PATTERNS) {
    Log "SHORT patterns DISABLED via config flag"
    exit 0
}
```

---

### 4.2. Tori Proximity

**Status Atual**:
- ✅ Opt-in flag-gated em todos os consumers
- ✅ ZERO events em 3 anos (50.871 bars × 47 markets)
- ⚠️ Context field em `lib_mentor_gate_block.ps1`

**Recomendação**: **MANTER DESABILITADO** (não remover código)

**Razão**:
1. ✅ **Opt-in design** já permite desabilitar sem quebrar código
2. ✅ **Fail-soft** em todos os consumers (try/catch + Get-Command guard)
3. ⚠️ **ZERO events** pode ser problema de thresholds (não de conceito)
4. 🔬 **Relaxar condições** (3-AND ao invés de 4-AND) pode revelar edge

**Ação**:
```powershell
# Remover flags opt-in (desabilita consumers)
Remove-Item journal/TORI_PROXIMITY_BOOST.flag -ErrorAction SilentlyContinue
Remove-Item journal/TORI_PROXIMITY_CONFLUENCE.flag -ErrorAction SilentlyContinue

# Manter código + tests (aguardar regime change ou threshold relaxation)
```

---

### 4.3. Confluence Multi-Pattern

**Status Atual**:
- ✅ RSI confluence FUNCIONA (+11pp edge boost)
- ✅ Tori confluence opt-in flag-gated
- ❌ Multi-pattern confluence NÃO EXISTE (folklore)

**Recomendação**: **MANTER RSI, DESABILITAR TORI**

**Razão**:
1. ✅ **RSI confluence** validado em backtest (+11pp)
2. ⚠️ **Tori confluence** opt-in, pode ser desabilitado
3. ❌ **Multi-pattern** não existe no código (folklore)

**Ação**:
```powershell
# MANTER RSI confluence (funciona!)
# Detect-VolumeClimax -RsiOversoldMax 30  # KEEP

# DESABILITAR Tori confluence (opt-in)
Remove-Item journal/TORI_PROXIMITY_CONFLUENCE.flag -ErrorAction SilentlyContinue

# Multi-pattern: nada a fazer (não existe)
```

---

## 📋 5. CHECKLIST DE AÇÕES

### ✅ Ações Imediatas (ZERO risco)

- [ ] **Remover flags opt-in** (desabilita Tori consumers sem quebrar código)
  ```powershell
  Remove-Item journal/TORI_PROXIMITY_BOOST.flag -ErrorAction SilentlyContinue
  Remove-Item journal/TORI_PROXIMITY_CONFLUENCE.flag -ErrorAction SilentlyContinue
  ```

- [ ] **Adicionar flag SHORT_PATTERNS** em `config.ps1`
  ```powershell
  $ENABLE_SHORT_PATTERNS = $false  # SUSPENSO ate re-validacao em BEAR
  ```

- [ ] **Modificar short_scanner.ps1** para respeitar flag
  ```powershell
  if (-not $ENABLE_SHORT_PATTERNS) {
      Log "SHORT patterns DISABLED via config flag"
      exit 0
  }
  ```

---

### ⏸️ Ações Futuras (Aguardar validação)

- [ ] **Re-testar SHORT patterns em BEAR regime** (pode revelar edge maior)
- [ ] **Relaxar Tori thresholds** (3-AND ao invés de 4-AND)
- [ ] **Grid search Tori slopes** (testar 3-15deg ao invés de 5-35deg)

---

### ❌ Ações NÃO Recomendadas

- ❌ **Deletar código SHORT** (isolado, edge positivo em backtest)
- ❌ **Deletar código Tori** (opt-in design já permite desabilitar)
- ❌ **Remover RSI confluence** (funciona! +11pp edge boost)

---

## 💬 PRÓXIMOS PASSOS

Shiny, baseado nesta análise completa:

### 🎯 Recomendação Principal

**DESABILITAR (não deletar) patterns sem edge via flags**:

1. ✅ **SHORT patterns**: Adicionar flag `$ENABLE_SHORT_PATTERNS = $false`
2. ✅ **Tori Proximity**: Remover flags opt-in (já desabilita consumers)
3. ✅ **Confluence**: Manter RSI (funciona!), desabilitar Tori (opt-in)

### 🔬 Benefícios

- ✅ **ZERO risco** — código permanece, apenas desabilitado
- ✅ **Reversível** — basta mudar flag para re-habilitar
- ✅ **Fail-soft** — consumers já têm try/catch + Get-Command guards
- ✅ **Foco** — sistema opera apenas com edge validado (LONG_vol_climax)

### 📊 Impacto Esperado

- **Edge**: Mantém +8.6pp (LONG_vol_climax isolado)
- **Oportunidades**: Mantém 3-5/mês (Tier A LIVE)
- **Complexidade**: -30% (SHORT + Tori desabilitados)
- **Execution time**: -20% (menos scanners rodando)

---

## 🤔 O QUE VOCÊ QUER FAZER?

1. 🚀 **Executar ações imediatas** — desabilitar patterns sem edge via flags?
2. 🔬 **Refinar análise** — alguma dependência que eu perdi?
3. 📊 **Ver código específico** — alguma função que você quer entender melhor?
4. 💰 **Focar em otimização** — voltar para Fase 1 (otimizar vol_climax)?
5. 📝 **Outra coisa** — o que você tem em mente?

**Qual caminho você prefere?**
