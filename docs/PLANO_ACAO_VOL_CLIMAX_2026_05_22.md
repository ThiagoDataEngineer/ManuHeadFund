# 🎯 PLANO DE AÇÃO — VOL_CLIMAX EDGE ÚNICO
**Data**: 2026-05-22  
**Analista**: Claude Sonnet 4.5  
**Status**: Estratégia focada no ÚNICO edge validado

---

## 🔬 CONTEXTO — DESCOBERTAS CRÍTICAS

### Realidade Brutal (Branch A Findings)

| Pattern | Status | Edge Validado | Sample Size |
|---------|--------|---------------|-------------|
| **Tori Proximity (4-AND)** | ❌ ZERO events | N/A | 0 em 50.871 bars × 47 markets × 3 anos |
| **LONG_vol_climax** | ✅ **ÚNICO com edge** | **+8.6pp** | **n=278, avg_hit +14.4%** |
| **SHORT patterns** | ❌ Sem edge | N/A | Exec path SUSPENSO |
| **Confluence multi-pattern** | ❌ Pior que isolado | +3.1pp vs +8.6pp | Folklore não validado |

### 🚨 Implicação

**Sistema opera com honestidade brutal** — só patterns com edge data-driven entram em produção.

**ÚNICO edge validado**: **LONG_vol_climax** (+8.6pp, n=278)

---

## 💡 ESTRATÉGIA — FOCAR NO QUE FUNCIONA

### Princípio: "Do More of What Works"

Em vez de tentar "consertar" patterns sem edge, vamos **MAXIMIZAR** o único edge validado:

```
LONG_vol_climax:
- Edge: +8.6pp
- Sample size: n=278 (robusto)
- Avg hit: +14.4%
- Status: ✅ VALIDADO
```

### 3 Caminhos Possíveis

| Caminho | Objetivo | Esforço | Probabilidade Sucesso |
|---------|----------|---------|----------------------|
| **α) Otimizar vol_climax** | Refinar thresholds, adicionar filters | 2-4h | Alta (~70%) |
| **β) Expandir vol_climax** | Testar em mais markets/regimes | 3-5h | Média (~50%) |
| **γ) Simplificar sistema** | Remover patterns sem edge, focar vol_climax | 1-2h | Alta (~80%) |

**Recomendação**: **γ + α** — Simplificar primeiro, depois otimizar.

---

## 🎯 PLANO DE AÇÃO — FASE 1: SIMPLIFICAÇÃO

### Objetivo

**Remover complexidade desnecessária** e focar no único edge validado.

### Ações Concretas

#### 1. ✂️ **Remover Patterns Sem Edge** (1h)

**O que remover**:
- ❌ Tori Proximity (4-AND) → ZERO events em 3 anos
- ❌ SHORT patterns → Sem edge, exec path SUSPENSO
- ❌ Confluence multi-pattern → Pior que isolado

**O que manter**:
- ✅ LONG_vol_climax → ÚNICO com edge (+8.6pp)
- ✅ Gates anti-overfitting → Protegem contra false positives
- ✅ Risk management → Inviolável

**Benefícios**:
- Reduz complexidade do código
- Elimina false signals
- Foca recursos no que funciona
- Facilita manutenção

#### 2. 📊 **Criar "Vol_Climax Only" Mode** (30min)

**Implementação**:
```powershell
# agents/config.local.ps1
$STRATEGY_MODE = "VOL_CLIMAX_ONLY"  # vs "FULL_PIPELINE"

# Desabilita:
# - Tori Proximity scan
# - SHORT patterns
# - Confluence scoring

# Habilita:
# - LONG_vol_climax detection
# - Gates anti-overfitting
# - Risk management
```

**Vantagens**:
- Sistema mais rápido (menos scans)
- Menos ruído (menos false signals)
- Mais fácil de debugar
- Edge concentrado

#### 3. 📝 **Documentar Edge Único** (30min)

**Criar**: `knowledge/VOL_CLIMAX_EDGE.md`

**Conteúdo**:
- Definição técnica de vol_climax
- Thresholds validados
- Sample size e edge (+8.6pp)
- Regimes onde funciona
- Regimes onde NÃO funciona
- Exemplos históricos (n=278)

---

## 🎯 PLANO DE AÇÃO — FASE 2: OTIMIZAÇÃO

### Objetivo

**Maximizar o edge do vol_climax** através de refinamento.

### Ações Concretas

#### 4. 🔬 **Refinar Thresholds Vol_Climax** (2h)

**Grid Search**:
```python
# Testar combinações:
vol_threshold = [1.5, 2.0, 2.5, 3.0]  # Múltiplo de ATR
rsi_threshold = [25, 30, 35]          # RSI oversold
btc_drawdown = [-5, -10, -15]         # BTC drawdown mínimo

# Objective: maximizar edge mantendo sample size > 200
```

**Metodologia**:
- Walk-forward validation (5 folds)
- Bootstrap CI 95%
- PBO < 0.3 (anti-overfitting)

**Expected outcome**:
- Edge atual: +8.6pp
- Edge otimizado: +10-12pp (target)
- Sample size: > 200 (mínimo)

#### 5. 📊 **Adicionar Filters Complementares** (1h)

**Filters que NÃO destroem edge**:
- ✅ **Volume spike** (vol > 2x média 20d)
- ✅ **BTC regime** (BULL_STRONG ou TRANSITION_UP)
- ✅ **Market quality** (FQS ≥ 3)
- ✅ **Sector diversification** (max 2/setor)

**Filters que DESTROEM edge** (evitar):
- ❌ Confluence multi-pattern (+3.1pp vs +8.6pp)
- ❌ Tori Proximity (ZERO events)
- ❌ SHORT patterns (sem edge)

#### 6. 🎯 **Criar "Vol_Climax Score"** (1h)

**Scoring system** (0-100):
```
Base score: 50

+20: Vol spike > 3x média
+15: RSI < 25 (extreme oversold)
+10: BTC drawdown > -15%
+10: Market quality FQS = 5
+5:  Sector não concentrado
-10: Phase boundary (halving)
-5:  Low volume market

Final score: 0-100
Threshold: ≥ 70 para TIER_A_LIVE
```

**Benefícios**:
- Ranking objetivo de setups
- Priorização automática
- Backtest comparável

---

## 🎯 PLANO DE AÇÃO — FASE 3: EXPANSÃO

### Objetivo

**Testar vol_climax em mais markets/regimes** para aumentar sample size.

### Ações Concretas

#### 7. 🌐 **Expandir Universe** (2h)

**Testar vol_climax em**:
- ✅ **Mais markets CoinEx** (atual: 139 → target: 200+)
- ✅ **Timeframes diferentes** (4h, 1h além de 1d)
- ✅ **Outros exchanges** (Binance, Bybit via API)

**Expected outcome**:
- Sample size: n=278 → n=500+ (target)
- Edge mantém: +8-10pp
- Mais oportunidades/mês

#### 8. 📊 **Regime-Specific Optimization** (2h)

**Testar vol_climax por regime**:
```
BULL_STRONG:     Edge = ?
BULL_WEAK:       Edge = ?
TRANSITION_UP:   Edge = ?
SIDEWAYS:        Edge = ?
TRANSITION_DOWN: Edge = ?
BEAR:            Edge = ?
```

**Hypothesis**:
- Edge maior em BULL_WEAK (bounce natural)
- Edge menor em BEAR (dead cat bounce)

**Outcome**:
- Regime-specific thresholds
- Adaptive scoring
- Melhor timing

#### 9. 🔬 **Testar Vol_Climax + DCA** (1h)

**Hybrid strategy**:
```
Vol_climax signal → Entry 50% position
DCA down -5%     → Entry 25% position
DCA down -10%    → Entry 25% position

Exit: Trailing stop ATR×2
```

**Benefícios**:
- Reduz timing risk
- Aumenta win rate
- Mantém edge

---

## 📊 MÉTRICAS DE SUCESSO

### KPIs — Fase 1 (Simplificação)

| KPI | Baseline | Target | Status |
|-----|----------|--------|--------|
| **Código removido** | 0 LOC | 500+ LOC | 🎯 |
| **Patterns ativos** | 4 | 1 (vol_climax) | 🎯 |
| **False signals/mês** | 10-15 | 3-5 | 🎯 |
| **Execution time** | 30s | 10s | 🎯 |

### KPIs — Fase 2 (Otimização)

| KPI | Baseline | Target | Status |
|-----|----------|--------|--------|
| **Edge vol_climax** | +8.6pp | +10-12pp | 🎯 |
| **Sample size** | n=278 | n=300+ | 🎯 |
| **Win rate** | ~55% | ~60% | 🎯 |
| **Avg R** | +0.3R | +0.5R | 🎯 |

### KPIs — Fase 3 (Expansão)

| KPI | Baseline | Target | Status |
|-----|----------|--------|--------|
| **Markets testados** | 139 | 200+ | 🎯 |
| **Sample size** | n=278 | n=500+ | 🎯 |
| **Oportunidades/mês** | 3-5 | 10-15 | 🎯 |
| **Edge mantém** | +8.6pp | +8-10pp | 🎯 |

---

## 🚀 ROADMAP DE EXECUÇÃO

### Sprint 1 — Simplificação (1-2 dias)

```
Dia 1:
✅ Remover Tori Proximity code
✅ Remover SHORT patterns code
✅ Remover Confluence scoring
✅ Criar VOL_CLIMAX_ONLY mode

Dia 2:
✅ Documentar edge único (VOL_CLIMAX_EDGE.md)
✅ Testar sistema simplificado
✅ Validar que edge mantém
```

### Sprint 2 — Otimização (2-3 dias)

```
Dia 3:
✅ Grid search thresholds vol_climax
✅ Walk-forward validation

Dia 4:
✅ Adicionar filters complementares
✅ Criar Vol_Climax Score (0-100)

Dia 5:
✅ Backtest otimizado
✅ Validar edge melhorou
```

### Sprint 3 — Expansão (3-4 dias)

```
Dia 6-7:
✅ Expandir universe (200+ markets)
✅ Testar timeframes diferentes

Dia 8-9:
✅ Regime-specific optimization
✅ Testar Vol_Climax + DCA hybrid
```

**Total**: 7-9 dias de trabalho focado

---

## 💰 IMPACTO ESPERADO

### Cenário Conservador

```
Capital: $5.000 (sweet spot)
Oportunidades/mês: 10 (vs 3-5 atual)
Win rate: 55% (mantém)
Avg R: +0.5R (vs +0.3R atual)
Edge: +10pp (vs +8.6pp atual)

Expected return/mês:
10 trades × 55% win × +0.5R × $50 (1% risk) = +$137.50/mês
Anualizado: +$1.650/ano = +33% ROI
```

### Cenário Otimista

```
Capital: $5.000
Oportunidades/mês: 15 (expansão universe)
Win rate: 60% (otimização)
Avg R: +0.7R (filters complementares)
Edge: +12pp

Expected return/mês:
15 trades × 60% win × +0.7R × $50 = +$315/mês
Anualizado: +$3.780/ano = +75% ROI
```

---

## 🎯 DECISÃO ESTRATÉGICA

### Opção A: "Simplificar e Focar" ✅ RECOMENDADO

**Filosofia**: "Do more of what works"

- ✅ Remove patterns sem edge
- ✅ Foca no único edge validado
- ✅ Otimiza vol_climax
- ✅ Expande universe

**Vantagens**:
- Sistema mais simples
- Edge concentrado
- Fácil de manter
- Probabilidade sucesso alta (~70%)

**Desvantagens**:
- Menos diversificação de strategies
- Dependência de um único pattern

### Opção B: "Continuar Buscando Edges"

**Filosofia**: "Keep searching"

- ⚠️ Continua testando Tori Proximity
- ⚠️ Tenta rescue SHORT patterns
- ⚠️ Explora novas confluências

**Vantagens**:
- Pode descobrir novos edges
- Diversificação de strategies

**Desvantagens**:
- Tempo/esforço alto
- Probabilidade sucesso baixa (~20%)
- Complexidade aumenta
- Risco de overfitting

---

## 💬 RECOMENDAÇÃO FINAL

Shiny, minha recomendação é **OPÇÃO A: "Simplificar e Focar"**.

### Por quê?

1. ✅ **Temos UM edge validado** (+8.6pp, n=278) — isso é OURO
2. ✅ **Simplicidade > Complexidade** — menos código, menos bugs
3. ✅ **Probabilidade sucesso alta** (~70% vs ~20%)
4. ✅ **Execução rápida** (7-9 dias vs meses)
5. ✅ **ROI claro** (+33% conservador, +75% otimista)

### Próximos Passos Imediatos

**Sprint 1 — Simplificação** (começar AGORA):

1. ✂️ Remover Tori Proximity code
2. ✂️ Remover SHORT patterns code
3. ✂️ Remover Confluence scoring
4. 📊 Criar VOL_CLIMAX_ONLY mode
5. 📝 Documentar edge único

**Esforço**: 1-2 dias  
**Impacto**: Sistema 3x mais simples, edge mantém

---

## 🤔 O QUE VOCÊ QUER FAZER?

1. 🚀 **Executar Sprint 1** (Simplificação) — começar agora?
2. 🔬 **Analisar vol_climax em detalhe** — entender o edge melhor?
3. 📊 **Criar Vol_Climax Score** — sistema de ranking?
4. 🌐 **Expandir universe** — testar em mais markets?
5. 💰 **Refinar roadmap de capital** — quando aumentar para $5K?

**Qual caminho você prefere?**

