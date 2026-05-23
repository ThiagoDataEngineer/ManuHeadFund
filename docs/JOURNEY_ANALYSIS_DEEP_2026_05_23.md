# 🔍 JOURNEY ANALYSIS DEEP — End-to-End 2026-05-23

**Data**: 2026-05-23 02:45 BRT  
**Status**: **ANÁLISE PROFUNDA EM PROGRESSO** 🔬  
**Metodologia**: TDD (Test-Driven Development)  
**Objetivo**: Identificar TODOS os pontos de aprimoramento

---

## 📊 ESCOPO DA ANÁLISE

### JORNADAS A ANALISAR:

1. **JORNADA GEM** (high-conviction setups)
   - Discovery → Triagem → Mesa → Mentor → Executor → Monitoring
   
2. **JORNADA COMUM** (standard flow)
   - Discovery → Triagem → Mesa → Mentor → Executor → Monitoring

### METODOLOGIA:

Para cada peça:
1. **Mapear fluxo atual** (como funciona hoje)
2. **Identificar inputs/outputs** (contratos)
3. **Medir performance** (latência, taxa de erro, edge)
4. **Identificar gargalos** (bottlenecks)
5. **Propor melhorias** (data-driven)
6. **Estimar impacto** (ROI esperado)

---

## 🎯 JORNADA GEM (High-Conviction)

### VISÃO GERAL:

```
┌─────────────┐
│   RADAR     │ Scan 1.017 markets, 15min cycle
│  (Discovery)│ Output: 5-10 candidates/cycle
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  GEM_AGENT  │ Deep analysis (Claude)
│  (Triagem)  │ Output: 1-3 gems/cycle (quality A/A+)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MESA_AGENT  │ Risk/reward analysis
│   (Mesa)    │ Output: APROVAR/VETAR + score
└──────┬──────┘
       │
       ▼
┌─────────────┐
│MENTOR_AGENT │ Final veto (RAG + knowledge)
│  (Mentor)   │ Output: APROVAR/VETAR + confidence
└──────┬──────┘
       │
       ▼
┌─────────────┐
│GEM_EXECUTOR │ Execute trade (CoinEx API)
│ (Executor)  │ Output: Position opened
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MONITORING  │ Trailing stop, TP management
│             │ Output: Position closed
└─────────────┘
```

---

## 🔬 PEÇA 1: RADAR (Discovery)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/radar_agent.ps1` (?)  
**Frequência**: 15min cycle  
**Input**: 1.017 markets (CoinEx universe)  
**Output**: 5-10 candidates/cycle  

### FLUXO:

1. Fetch OHLCV (1H, 4H, 1D) para 1.017 markets
2. Calcular indicadores (volume spike, price change, etc)
3. Filtrar top 5-10 por score
4. Passar para GEM_AGENT

### PERFORMANCE ATUAL:

**Latência**: ? (MEDIR)  
**Taxa de acerto**: ? (quantos gems viram trades?)  
**False positives**: ? (quantos candidates são rejeitados?)  

### GARGALOS IDENTIFICADOS:

1. ❓ **Latência desconhecida** - precisa medir
2. ❓ **Taxa de false positives** - quantos candidates são ruído?
3. ❓ **Critérios de seleção** - são ótimos ou podem melhorar?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir latência atual (baseline)
2. Medir taxa de conversão (candidates → gems → trades)
3. Analisar false positives (por que foram rejeitados?)
4. Otimizar critérios de seleção (data-driven)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🔬 PEÇA 2: GEM_AGENT (Triagem)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/gem_agent.ps1`  
**Frequência**: On-demand (quando RADAR envia candidate)  
**Input**: Candidate (market + OHLCV + indicators)  
**Output**: Gem (quality A/A+) ou REJECT  

### FLUXO:

1. Recebe candidate do RADAR
2. Fetch dados adicionais (on-chain, funding, news)
3. Chama Claude (tech_agent prompt)
4. Analisa resposta (quality, setup_type, confluências)
5. Se quality >= A → passa para MESA
6. Se quality < A → REJECT

### PERFORMANCE ATUAL:

**Latência**: ~30-60s (Claude call)  
**Taxa de aprovação**: ? (quantos candidates viram gems?)  
**Edge dos gems**: ? (qual edge médio dos gems aprovados?)  

### GARGALOS IDENTIFICADOS:

1. ⚠️ **Latência alta** (30-60s por candidate)
2. ❓ **Taxa de aprovação desconhecida**
3. ❓ **Edge dos gems** - gems aprovados têm edge real?
4. ❓ **Critérios de quality** - A/A+ são ótimos ou muito restritivos?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir taxa de aprovação (candidates → gems)
2. Medir edge dos gems (backtest retrospectivo)
3. Analisar gems rejeitados pela MESA/MENTOR (por quê?)
4. Otimizar prompt (reduzir latência sem perder qualidade)

**POSSÍVEIS OTIMIZAÇÕES**:
1. Cache de análises (se market já foi analisado recentemente)
2. Parallel processing (analisar múltiplos candidates simultaneamente)
3. Pre-filtering (eliminar candidates óbvios antes de Claude)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🔬 PEÇA 3: MESA_AGENT (Mesa)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/mesa_agent.ps1`  
**Frequência**: On-demand (quando GEM_AGENT aprova)  
**Input**: Gem (quality A/A+)  
**Output**: APROVAR/VETAR + score  

### FLUXO:

1. Recebe gem do GEM_AGENT
2. Calcula risk/reward (R:R ratio)
3. Verifica capital disponível
4. Verifica correlação com posições abertas
5. Calcula score (0-100)
6. Se score >= threshold → APROVAR
7. Se score < threshold → VETAR

### PERFORMANCE ATUAL:

**Latência**: ~5-10s (cálculos)  
**Taxa de aprovação**: ? (quantos gems passam?)  
**Edge dos aprovados**: ? (gems aprovados pela MESA têm edge?)  

### GARGALOS IDENTIFICADOS:

1. ❓ **Taxa de aprovação desconhecida**
2. ❓ **Threshold ótimo** - score threshold é ideal?
3. ❓ **R:R calculation** - está correto? Inclui taxas?
4. ❓ **Correlação check** - está funcionando?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir taxa de aprovação (gems → aprovados MESA)
2. Medir edge dos aprovados (backtest retrospectivo)
3. Analisar gems vetados (por quê? R:R baixo? Capital?)
4. Otimizar threshold (data-driven)

**POSSÍVEIS OTIMIZAÇÕES**:
1. Dynamic threshold (ajustar baseado em performance)
2. Better R:R calculation (incluir slippage, taxas, funding)
3. Portfolio optimization (max correlação, diversificação)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🔬 PEÇA 4: MENTOR_AGENT (Mentor)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/mentor_agent.ps1`  
**Frequência**: On-demand (quando MESA aprova)  
**Input**: Gem aprovado pela MESA  
**Output**: APROVAR/VETAR + confidence + mentor_mensagem  

### FLUXO:

1. Recebe gem aprovado pela MESA
2. Busca knowledge relevante (RAG)
3. Chama Claude (mentor prompt)
4. Analisa resposta (APROVAR/VETAR + confidence)
5. Se APROVAR → passa para EXECUTOR
6. Se VETAR → REJECT (com reason)

### PERFORMANCE ATUAL:

**Latência**: ~30-60s (Claude call + RAG)  
**Taxa de aprovação**: ? (quantos gems passam?)  
**Taxa de veto correto**: ? (vetos salvaram de losses?)  
**Taxa de veto incorreto**: ? (vetos bloquearam winners?)  

### GARGALOS IDENTIFICADOS:

1. ⚠️ **Latência alta** (30-60s)
2. ❓ **Taxa de veto** - quantos gems são vetados?
3. ❓ **Veto accuracy** - vetos são corretos?
4. ❓ **RAG effectiveness** - knowledge retrieval ajuda?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir taxa de veto (gems MESA → vetados MENTOR)
2. Medir veto accuracy (retrospectivo: vetos corretos vs incorretos)
3. Analisar vetos incorretos (bloquearam winners?)
4. Medir RAG effectiveness (knowledge usado vs não usado)

**POSSÍVEIS OTIMIZAÇÕES**:
1. Cache de análises (se setup similar já foi analisado)
2. Faster RAG (pre-index knowledge, semantic search)
3. Confidence threshold (só vetar se confidence > 80%)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🔬 PEÇA 5: GEM_EXECUTOR (Executor)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/gem_executor.ps1`  
**Frequência**: On-demand (quando MENTOR aprova)  
**Input**: Gem aprovado pelo MENTOR  
**Output**: Position opened (CoinEx API)  

### FLUXO:

1. Recebe gem aprovado pelo MENTOR
2. Calcula position size (risk management)
3. Calcula entry price (limit order)
4. Calcula stop-loss e take-profit
5. Envia ordem para CoinEx API
6. Confirma execução
7. Registra position em journal

### PERFORMANCE ATUAL:

**Latência**: ~5-10s (API call)  
**Taxa de execução**: ? (quantas ordens são preenchidas?)  
**Slippage médio**: ? (diferença entry esperado vs real)  
**Taxa de erro**: ? (ordens falhadas)  

### GARGALOS IDENTIFICADOS:

1. ❓ **Taxa de execução** - ordens são preenchidas?
2. ❓ **Slippage** - quanto perdemos em slippage?
3. ❓ **Timing** - entramos no melhor momento?
4. ❓ **Position sizing** - está otimizado?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir taxa de execução (ordens enviadas vs preenchidas)
2. Medir slippage médio (entry esperado vs real)
3. Analisar timing (entramos cedo/tarde/ideal?)
4. Otimizar position sizing (Kelly criterion? Fixed %?)

**POSSÍVEIS OTIMIZAÇÕES**:
1. Smart order routing (limit vs market, baseado em liquidez)
2. Partial fills (aceitar fills parciais?)
3. Retry logic (se ordem não preenche, retry com ajuste?)
4. Dynamic position sizing (baseado em volatilidade)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🔬 PEÇA 6: MONITORING (Trailing Stop + TP)

### FUNÇÃO ATUAL:

**Arquivo**: `agents/trailing_stop_manager.ps1` (?)  
**Frequência**: Continuous (check a cada 1-5min)  
**Input**: Position aberta  
**Output**: Position fechada (quando TP/SL hit)  

### FLUXO:

1. Monitor posições abertas
2. Atualizar trailing stop (se preço subiu)
3. Check take-profit levels (TP1, TP2, TP3)
4. Check stop-loss (trailing ou fixo)
5. Se TP/SL hit → fechar posição
6. Registrar resultado em journal

### PERFORMANCE ATUAL:

**Latência**: ~1-5min (check interval)  
**TP hit rate**: ? (quantas posições atingem TP?)  
**SL hit rate**: ? (quantas posições atingem SL?)  
**Average hold time**: ? (quanto tempo seguramos posições?)  
**Edge real**: ? (PnL médio das posições fechadas)  

### GARGALOS IDENTIFICADOS:

1. ❓ **Check interval** - 1-5min é ideal ou pode ser mais rápido?
2. ❓ **Trailing stop logic** - está otimizado?
3. ❓ **TP levels** - TP1/TP2/TP3 são ideais?
4. ❓ **Hold time** - seguramos muito/pouco tempo?

### MELHORIAS PROPOSTAS:

**A INVESTIGAR**:
1. Medir TP/SL hit rates
2. Medir average hold time
3. Medir edge real (PnL médio)
4. Analisar exits prematuros (saímos cedo demais?)
5. Analisar exits tardios (seguramos demais?)

**POSSÍVEIS OTIMIZAÇÕES**:
1. Dynamic TP levels (baseado em volatilidade)
2. Time-based exits (se não move em X horas, sair)
3. Faster check interval (1min vs 5min)
4. ATR-based trailing stop (mais adaptativo)

**IMPACTO ESPERADO**: TBD (após medição)

---

## 🎯 JORNADA COMUM (Standard Flow)

### VISÃO GERAL:

```
┌─────────────┐
│   SCANNER   │ Scan 1.017 markets, 1H cycle
│ (Discovery) │ Output: 10-20 candidates/cycle
└──────┬──────┘
       │
       ▼
┌─────────────┐
│TRIAGEM_AGENT│ Quick filter (hardcoded rules)
│  (Triagem)  │ Output: 3-5 candidates/cycle
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MESA_AGENT  │ Risk/reward analysis
│   (Mesa)    │ Output: APROVAR/VETAR + score
└──────┬──────┘
       │
       ▼
┌─────────────┐
│MENTOR_AGENT │ Final veto (RAG + knowledge)
│  (Mentor)   │ Output: APROVAR/VETAR + confidence
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  EXECUTOR   │ Execute trade (CoinEx API)
│             │ Output: Position opened
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ MONITORING  │ Trailing stop, TP management
│             │ Output: Position closed
└─────────────┘
```

---

## 🔬 DIFERENÇAS: GEM vs COMUM

| Aspecto | GEM | COMUM |
|---------|-----|-------|
| **Discovery** | RADAR (15min, high-freq) | SCANNER (1H, low-freq) |
| **Triagem** | GEM_AGENT (Claude, deep) | TRIAGEM_AGENT (rules, fast) |
| **Quality** | A/A+ only | B+ acceptable |
| **Frequency** | 5-10 candidates/cycle | 10-20 candidates/cycle |
| **Latency** | ~60-120s (Claude calls) | ~10-20s (hardcoded) |
| **Edge esperado** | High (gems) | Medium (standard) |

---

## 📊 MÉTRICAS A COLETAR (30 DIAS)

### JORNADA GEM:

**Discovery (RADAR)**:
- [ ] Latência média (scan 1.017 markets)
- [ ] Candidates gerados/cycle
- [ ] Taxa de conversão (candidates → gems)

**Triagem (GEM_AGENT)**:
- [ ] Latência média (Claude call)
- [ ] Taxa de aprovação (candidates → gems)
- [ ] Edge dos gems (backtest retrospectivo)
- [ ] Quality distribution (A vs A+)

**Mesa (MESA_AGENT)**:
- [ ] Taxa de aprovação (gems → aprovados)
- [ ] Score distribution
- [ ] Motivos de veto (R:R, capital, correlação)

**Mentor (MENTOR_AGENT)**:
- [ ] Taxa de veto
- [ ] Veto accuracy (corretos vs incorretos)
- [ ] RAG usage (knowledge usado)
- [ ] Confidence distribution

**Executor (GEM_EXECUTOR)**:
- [ ] Taxa de execução (ordens preenchidas)
- [ ] Slippage médio
- [ ] Position size médio
- [ ] Timing (entry vs ideal)

**Monitoring**:
- [ ] TP hit rate
- [ ] SL hit rate
- [ ] Average hold time
- [ ] Edge real (PnL médio)
- [ ] Win rate
- [ ] R:R real (vs esperado)

### JORNADA COMUM:

**Discovery (SCANNER)**:
- [ ] Latência média
- [ ] Candidates gerados/cycle
- [ ] Taxa de conversão (candidates → aprovados)

**Triagem (TRIAGEM_AGENT)**:
- [ ] Latência média
- [ ] Taxa de aprovação
- [ ] Edge dos aprovados

**Mesa/Mentor/Executor/Monitoring**:
- [ ] Mesmas métricas da jornada GEM

---

## 🎯 PLANO DE AÇÃO (30 DIAS)

### SEMANA 1: Instrumentação

**Objetivo**: Adicionar logging/metrics em TODAS as peças

**Tasks**:
1. [ ] Adicionar timestamps em cada etapa
2. [ ] Adicionar counters (aprovados, vetados, etc)
3. [ ] Adicionar metrics (latência, edge, etc)
4. [ ] Criar dashboard (visualização)

**Deliverable**: Dashboard com métricas em tempo real

---

### SEMANA 2-4: Coleta de Dados

**Objetivo**: Coletar dados reais (PAPER mode)

**Tasks**:
1. [ ] Rodar sistema em PAPER mode
2. [ ] Coletar métricas diariamente
3. [ ] Analisar anomalias
4. [ ] Ajustar se necessário

**Deliverable**: 30 dias de dados reais

---

### SEMANA 5: Análise Profunda

**Objetivo**: Identificar gargalos e oportunidades

**Tasks**:
1. [ ] Analisar métricas coletadas
2. [ ] Identificar bottlenecks
3. [ ] Calcular impacto de melhorias
4. [ ] Priorizar otimizações

**Deliverable**: Relatório de análise + roadmap de melhorias

---

## 🚀 MELHORIAS POTENCIAIS (Hipóteses)

### HIGH IMPACT (Testar primeiro):

1. **Otimizar Tori** ✅ (FEITO: +77.6pp/ano)
2. **Otimizar TP levels** (hipótese: +10-20pp/ano)
3. **Otimizar trailing stop** (hipótese: +5-10pp/ano)
4. **Reduzir false positives** (hipótese: -50% latência)
5. **Otimizar position sizing** (hipótese: +10-15pp/ano)

### MEDIUM IMPACT:

6. **Cache de análises** (hipótese: -30% latência)
7. **Parallel processing** (hipótese: -40% latência)
8. **Dynamic thresholds** (hipótese: +5pp/ano)
9. **Better RAG** (hipótese: +2-5pp veto accuracy)
10. **Smart order routing** (hipótese: -20% slippage)

### LOW IMPACT (Fazer depois):

11. **Faster check interval** (hipótese: +1-2pp/ano)
12. **Better logging** (hipótese: melhor debugging)
13. **Better alerts** (hipótese: faster response)

---

## 📁 PRÓXIMOS PASSOS

### IMEDIATO (Hoje):

1. ✅ Deploy PAPER mode (Tori optimized)
2. [ ] Adicionar instrumentação básica
3. [ ] Criar dashboard simples

### CURTO PRAZO (Semana 1):

1. [ ] Instrumentação completa
2. [ ] Dashboard avançado
3. [ ] Começar coleta de dados

### MÉDIO PRAZO (30 dias):

1. [ ] Coletar 30 dias de dados
2. [ ] Análise profunda
3. [ ] Roadmap de melhorias

### LONGO PRAZO (60-90 dias):

1. [ ] Implementar melhorias priorizadas
2. [ ] Validar impacto
3. [ ] Iterar

---

**Status**: PLANO DEFINIDO - AGUARDANDO EXECUÇÃO  
**Data**: 2026-05-23 02:45 BRT  
**Próximo passo**: Deploy PAPER + Instrumentação 🚀
