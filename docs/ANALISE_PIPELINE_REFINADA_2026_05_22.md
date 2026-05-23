# 🔬 ANÁLISE REFINADA DO PIPELINE — ManuHeadFund
**Data**: 2026-05-22  
**Analista**: Claude Sonnet 4.5  
**Status**: Análise completa das funções e interdependências

---

## 🎯 ENTENDIMENTO DO PIPELINE ATUAL

### Arquitetura Geral

```
┌─────────────────────────────────────────────────────────────┐
│                    PIPELINE V6 COMPLETO                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  1. DISCOVERY LAYER (Universe Scan)                         │
│     ├─ Weekly Discovery (goldilocks filter)                 │
│     ├─ Cross-Asset Matrix                                   │
│     └─ Narrative Scan (CLARITY Act, etc)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  2. PATTERN DETECTION LAYER                                 │
│     ├─ Vol_Climax Scanner ✅ (ÚNICO com edge +8.6pp)        │
│     ├─ Tori Proximity ❌ (ZERO events em 3 anos)            │
│     ├─ SHORT Patterns ❌ (sem edge validado)                │
│     └─ Confluence Multi ❌ (pior que isolado)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  3. SCORING & FILTERING LAYER                               │
│     ├─ WSS (Wyckoff Spring Score) 0-100                     │
│     ├─ Cluster Filter (risk control)                        │
│     ├─ FQS (Fundamental Quality Score)                      │
│     └─ 15+ Gates Anti-Overfitting                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  4. TIER CLASSIFICATION                                     │
│     ├─ Tier S (WSS ≥85) → Paper-trade eligible             │
│     ├─ Tier A (WSS 70-84) → Observatory                     │
│     └─ Tier B (WSS 50-69) → Silent log                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  5. EXECUTION LAYER                                         │
│     ├─ Telegram Approval (human-in-loop)                    │
│     ├─ Order Routing (CoinEx API)                           │
│     └─ Trailing Stop (3 fases)                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔬 ANÁLISE DETALHADA — VOL_CLIMAX SCANNER

### Função Principal: `Detect-VolumeClimax`

**Localização**: `agents/lib_chart_patterns.ps1`

**O que faz**:
```powershell
# Detecta "selling climax" (LONG) ou "buying climax" (SHORT)

LONG (Selling Climax):
1. Volume spike ≥ 2.5x média 20d
2. Low quebra mínimo recente (20d)
3. Close acima do low (rejeição)
4. RSI < 30 (confluence opcional)

SHORT (Buying Climax):
1. Volume spike ≥ 2.5x média 20d
2. High quebra máximo recente (20d)
3. Close abaixo do high (rejeição)
4. RSI > 70 (confluence opcional)
```

**Parâmetros Refinados** (2026-05-22):
```powershell
ClimaxMultiplier = 2.5  # (vs 3.0 default)
RsiOversoldMax = 30     # Confluence
Lookback = 20           # Janela de análise
```

**Edge Validado**:
- **LONG_vol_climax**: +8.6pp (n=278, avg_hit +14.4%)
- **SHORT_vol_climax**: Sem edge validado (exec path SUSPENSO)

---

## 🔗 INTERDEPENDÊNCIAS DO PIPELINE

### 1. Vol_Climax Scanner → WSS Scoring

```powershell
# vol_climax_scanner.ps1 (linha 150+)

# 1. Detecta vol_climax
$r = Detect-VolumeClimax -Volumes $vols -Lows $lows ...

# 2. Se detectado, calcula WSS
if ($r.detected) {
    $wssResult = Get-WyckoffSpringScore `
        -Market $mkt `
        -BtcDrawdownPct $btcRegime.drawdown_pct `
        -BtcVol20d $btcRegime.vol_20d ...
    
    $tier = $wssResult.tier  # S, A, ou B
}
```

**Dependências**:
- ✅ `Detect-VolumeClimax` (lib_chart_patterns.ps1)
- ✅ `Get-WyckoffSpringScore` (lib_wyckoff_spring_score.ps1)
- ✅ BTC regime data (fetch via API)
- ✅ Market quality table (wyckoff_market_quality.json)

### 2. WSS Scoring → Tier Classification

```powershell
# lib_wyckoff_spring_score.ps1

function Get-WyckoffSpringScore {
    # Calcula score 0-100 baseado em 5 dimensões:
    
    1. Market Quality (0-20 pts)
       - FQS score do market
       - Liquidity, mcap, etc
    
    2. Vol Percentile (0-20 pts)
       - BTC vol_20d vs distribuição histórica
       - Maior vol = maior score
    
    3. Drawdown Zone (0-20 pts)
       - BTC drawdown -5% a -20% = sweet spot
       - Fora da zona = penalidade
    
    4. Months Post-Halving (0-20 pts)
       - Meses 12-26 post-halving = sweet spot
       - Fora da janela = penalidade
    
    5. Cluster Penalty (0-20 pts)
       - Cluster size 1-3 = OK
       - Cluster size 4+ = penalidade
    
    # Tier classification:
    if ($score >= 85) { $tier = "S" }  # Paper-trade eligible
    elseif ($score >= 70) { $tier = "A" }  # Observatory
    else { $tier = "B" }  # Silent log
}
```

**Dependências**:
- ✅ BTC regime (drawdown, vol_20d)
- ✅ Halving phase (months post-halving)
- ✅ Market quality table
- ✅ Cluster count (today's alerts)

### 3. Tier Classification → Telegram Alert

```powershell
# vol_climax_scanner.ps1 (linha 180+)

if ($tier -eq "S") {
    # TIER S: Full alert + paper-trade flag
    $msg = "[VOL CLIMAX][TIER S] $mkt
WSS=$($wssResult.wss) (paper-trade eligible)
strength=$($r.strength) vol_ratio=$($r.vol_ratio)x
BTC DD=$([math]::Round($btcRegime.drawdown_pct,1))%
OOS validated h20+h24 lift +3.2pp / -0.4pp"
    
    Send-TelegramAlert -Message $msg
    
} elseif ($tier -eq "A") {
    # TIER A: Observatory alert (no paper-trade)
    $msg = "[VOL CLIMAX][TIER A obs] $mkt WSS=$($wssResult.wss)
Observatory only (tier A nao paper-trade)"
    
    Send-TelegramAlert -Message $msg
    
} else {
    # TIER B: Silent log only (no alert)
}
```

**Dependências**:
- ✅ Tier classification (S/A/B)
- ✅ Telegram API (lib_telegram.ps1)
- ✅ Alert dedup logic (1 alert/market/dia)

### 4. Cluster Filter → Risk Control

```powershell
# lib_cluster_filter.ps1

function Test-ClusterCapExceeded {
    # Risk control: limita exposição em capitulações correlacionadas
    
    # Caps:
    # - Max 1 alert/dia (rolling 24h)
    # - Max 3 alerts/semana (rolling 7d)
    
    # Filosofia: vol_climax dispara em K markets simultâneos
    # em capitulações macro (ex: Jan 31 2026 = 7 markets).
    # Sem filter, ativar trade = K-leg exposure (1 macro-bet errada perde K vezes).
    
    if ($day_count >= $MaxPerDay) {
        return @{ exceeded=$true; reason="max_per_day" }
    }
    if ($week_count >= $MaxPerWeek) {
        return @{ exceeded=$true; reason="max_per_week" }
    }
    
    return @{ exceeded=$false }
}
```

**Dependências**:
- ✅ Alert history (vol_climax_alerts.jsonl)
- ✅ Rolling window logic (24h, 7d)

---

## 🎯 FUNÇÕES QUE **FUNCIONAM** (Manter)

### ✅ 1. Detect-VolumeClimax (CORE)

**Status**: ✅ **ÚNICO com edge validado** (+8.6pp, n=278)

**Uso**:
```powershell
$r = Detect-VolumeClimax `
    -Volumes $vols `
    -Lows $lows `
    -Highs $highs `
    -Closes $closes `
    -Side LONG `
    -ClimaxMultiplier 2.5 `
    -RsiOversoldMax 30
```

**Refinamentos Possíveis**:
1. 🔬 **Grid search thresholds** (ClimaxMultiplier 2.0-3.0, RSI 25-35)
2. 📊 **Regime-specific params** (BULL vs BEAR diferentes)
3. 🌐 **Timeframe expansion** (testar 4h, 1h além de 1d)

### ✅ 2. Get-WyckoffSpringScore (SCORING)

**Status**: ✅ **Funciona como risk control** (não edge proof)

**Uso**:
```powershell
$wssResult = Get-WyckoffSpringScore `
    -Market $mkt `
    -BtcDrawdownPct $btcRegime.drawdown_pct `
    -BtcVol20d $btcRegime.vol_20d `
    -NowUtc (Get-Date).ToUniversalTime() `
    -ClusterSize $clusterToday `
    -VolDistribution $btcRegime.vol_distribution `
    -QualityTable $wssQuality
```

**Refinamentos Possíveis**:
1. 🔬 **Otimizar pesos** (5 dimensões: 20pts cada → testar 15/25/20/20/20)
2. 📊 **Adicionar dimensões** (sector, beta, correlation)
3. 🎯 **Regime-adaptive thresholds** (Tier S = 85 em BULL, 80 em BEAR)

### ✅ 3. Test-ClusterCapExceeded (RISK CONTROL)

**Status**: ✅ **Funciona como risk control**

**Uso**:
```powershell
$cluster = Test-ClusterCapExceeded `
    -AlertsPath $alertsPath `
    -MaxPerDay 1 `
    -MaxPerWeek 3
```

**Refinamentos Possíveis**:
1. 🔬 **Caps adaptativos** (BULL: 2/dia, BEAR: 1/dia)
2. 📊 **Correlation-based** (se markets correlacionados, cap mais rígido)
3. 🎯 **Capital-scaled** (com $5K, permitir 2-3/dia)

### ✅ 4. FQS (Fundamental Quality Score)

**Status**: ✅ **Funciona como filter**

**Uso**: Já integrado no pipeline (gate G5)

**Refinamentos Possíveis**:
1. 🔬 **Lazy enrichment** (P3 design já existe)
2. 📊 **Sector-specific** (DeFi vs Layer1 vs Privacy diferentes)
3. 🎯 **Dynamic thresholds** (FQS ≥3 em BULL, ≥4 em BEAR)

### ✅ 5. 15+ Gates Anti-Overfitting

**Status**: ✅ **Funcionam como protection**

**Lista**:
1. Concentration (max 17% por market)
2. Daily loss cap (capital-scaled)
3. Sector (max 2/setor)
4. Cooldown 30d
5. Min volume ($500K)
6. Phase boundary (halving)
7. Funding Z-score
8. Cross-asset correlation
9. Beta concentration (avg ≤ 1.0)
10. FQS (≥3)
11. Pump buy gate
12. Time of week (DoW empírico)
13. Slippage budget
14. Asymmetric demote (3d FLAG)
15. Max days enforcement

**Refinamentos Possíveis**:
1. 🔬 **Gate weights** (alguns gates mais importantes que outros)
2. 📊 **Regime-adaptive** (gates diferentes por regime)
3. 🎯 **Fail-soft** (warning vs hard block)

---

## ❌ FUNÇÕES QUE **NÃO FUNCIONAM** (Avaliar)

### ❌ 1. Tori Proximity (4-AND)

**Status**: ❌ **ZERO events em 3 anos** (50.871 bars × 47 markets)

**Problema**: Condições muito restritivas, nunca dispara

**Opções**:
1. ✂️ **Remover** (desabilitar completamente)
2. 🔧 **Relaxar condições** (3-AND ao invés de 4-AND)
3. ⏸️ **Manter desabilitado** (aguardar regime change)

**Recomendação**: **Opção 3** (manter desabilitado, não deletar código)

### ❌ 2. SHORT Patterns

**Status**: ❌ **Sem edge validado** (exec path SUSPENSO)

**Problema**: Backtest mostrou edge negativo ou zero

**Opções**:
1. ✂️ **Remover** (desabilitar SHORT scanner)
2. 🔬 **Re-testar** (talvez funcione em BEAR regime)
3. ⏸️ **Manter SUSPENSO** (aguardar validação)

**Recomendação**: **Opção 3** (manter SUSPENSO, re-testar em BEAR)

### ❌ 3. Confluence Multi-Pattern

**Status**: ❌ **Pior que isolado** (+3.1pp vs +8.6pp)

**Problema**: Combinar patterns dilui edge ao invés de amplificar

**Opções**:
1. ✂️ **Remover** (desabilitar confluence scoring)
2. 🔬 **Re-testar** (talvez funcione com outros patterns)
3. ⏸️ **Manter desabilitado** (folklore não validado)

**Recomendação**: **Opção 1** (remover, folklore não validado)

---

## 🎯 PLANO DE REFINAMENTO — 3 FASES

### FASE 1: OTIMIZAÇÃO (Sem remover nada)

**Objetivo**: Melhorar o que já funciona

#### 1.1. Refinar Vol_Climax Thresholds (2h)

```powershell
# Grid search:
ClimaxMultiplier: [2.0, 2.5, 3.0]
RsiOversoldMax: [25, 30, 35]
Lookback: [15, 20, 25]

# Objective: maximizar edge mantendo sample size > 200
# Expected: edge +8.6pp → +10-12pp
```

#### 1.2. Otimizar WSS Weights (1h)

```powershell
# Testar pesos diferentes:
market_quality: [15, 20, 25]
vol_percentile: [15, 20, 25]
drawdown_zone: [15, 20, 25]
mph_score: [15, 20, 25]
cluster_penalty: [15, 20, 25]

# Objective: melhorar tier classification
# Expected: Tier S hit rate 55% → 60%
```

#### 1.3. Adaptar Cluster Caps (30min)

```powershell
# Caps regime-adaptive:
BULL_STRONG: MaxPerDay=2, MaxPerWeek=5
BULL_WEAK: MaxPerDay=1, MaxPerWeek=3
BEAR: MaxPerDay=1, MaxPerWeek=2

# Objective: capturar mais oportunidades em BULL
# Expected: oportunidades/mês 3-5 → 8-12
```

**Resultado Fase 1**:
- Edge: +8.6pp → +10-12pp
- Oportunidades/mês: 3-5 → 8-12
- Win rate: 55% → 60%
- **Nenhum código removido**

---

### FASE 2: EXPANSÃO (Adicionar capacidades)

**Objetivo**: Aumentar sample size e cobertura

#### 2.1. Expandir Universe (2h)

```powershell
# Adicionar markets:
- CoinEx: 139 → 200+ markets
- Binance: Top 50 markets (via API)
- Bybit: Top 30 markets (via API)

# Expected: sample size n=278 → n=500+
```

#### 2.2. Timeframe Expansion (2h)

```powershell
# Testar vol_climax em:
- 4h candles (mais oportunidades)
- 1h candles (timing melhor)

# Expected: oportunidades/mês 8-12 → 15-20
```

#### 2.3. Regime-Specific Optimization (2h)

```powershell
# Otimizar params por regime:
BULL_STRONG: ClimaxMult=2.0, RSI<35
BULL_WEAK: ClimaxMult=2.5, RSI<30
BEAR: ClimaxMult=3.0, RSI<25

# Expected: edge por regime +12-15pp
```

**Resultado Fase 2**:
- Sample size: n=278 → n=500+
- Oportunidades/mês: 8-12 → 15-20
- Edge por regime: +12-15pp
- **Nenhum código removido**

---

### FASE 3: SIMPLIFICAÇÃO (Opcional - só se necessário)

**Objetivo**: Remover complexidade desnecessária

#### 3.1. Desabilitar Tori Proximity (30min)

```powershell
# Adicionar flag no config:
$ENABLE_TORI_PROXIMITY = $false

# Código permanece, apenas desabilitado
```

#### 3.2. Manter SHORT SUSPENSO (já está)

```powershell
# SHORT já está SUSPENSO
# Não precisa fazer nada
```

#### 3.3. Remover Confluence Scoring (1h)

```powershell
# Confluence multi-pattern não adiciona valor
# Pode ser removido do pipeline
```

**Resultado Fase 3**:
- Código 10-15% mais simples
- Execution time 20-30% mais rápido
- **Edge mantém** (patterns removidos não tinham edge)

---

## 💰 IMPACTO ESPERADO POR FASE

### Fase 1: Otimização

```
Capital: $5.000
Edge: +8.6pp → +10-12pp
Oportunidades/mês: 3-5 → 8-12
Win rate: 55% → 60%

Expected return/mês:
10 trades × 60% win × +0.5R × $50 = +$150/mês
Anualizado: +$1.800/ano = +36% ROI
```

### Fase 2: Expansão

```
Capital: $5.000
Edge: +10-12pp (mantém)
Oportunidades/mês: 8-12 → 15-20
Win rate: 60% (mantém)

Expected return/mês:
17 trades × 60% win × +0.5R × $50 = +$255/mês
Anualizado: +$3.060/ano = +61% ROI
```

### Fase 3: Simplificação

```
Impacto: Neutro (não muda edge)
Benefício: Sistema mais simples e rápido
```

---

## 🤔 RECOMENDAÇÃO FINAL

Shiny, minha recomendação é executar **FASE 1 + FASE 2** (sem Fase 3 por enquanto):

### Por quê?

1. ✅ **Fase 1 (Otimização)** → Melhora edge sem remover nada
2. ✅ **Fase 2 (Expansão)** → Aumenta oportunidades sem remover nada
3. ⏸️ **Fase 3 (Simplificação)** → Opcional, só se sistema ficar lento

### Próximos Passos

**Sprint 1 — Otimização** (2-3 dias):
1. 🔬 Grid search vol_climax thresholds
2. 📊 Otimizar WSS weights
3. 🎯 Adaptar cluster caps por regime

**Sprint 2 — Expansão** (3-4 dias):
1. 🌐 Expandir universe (200+ markets)
2. ⏰ Testar timeframes (4h, 1h)
3. 🔬 Regime-specific optimization

**Total**: 5-7 dias de trabalho focado

---

## 💬 O QUE VOCÊ QUER FAZER?

1. 🚀 **Executar Fase 1** (Otimização) — começar grid search?
2. 🔬 **Analisar função específica** — qual você quer entender melhor?
3. 📊 **Ver código atual** — alguma função específica?
4. 💰 **Refinar roadmap** — quando aumentar capital?
5. 📝 **Outra coisa** — o que você tem em mente?

**Qual caminho você prefere?**

