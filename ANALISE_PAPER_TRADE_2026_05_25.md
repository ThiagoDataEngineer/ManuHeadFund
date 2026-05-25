# 📊 ANÁLISE: Paper Trade Live + Trailing Stop — 2026-05-25

---

## 🎯 PARTE 1: Posições Vivas + Trailing

| Par | Lev | Entry | Atual | %vs Entry | Phase | Stop | %Stop | Target | %Target | Progresso | Status |
|-----|-----|-------|-------|-----------|-------|------|-------|--------|---------|-----------|--------|
| **UNIUSDT** | 5x | $3.46 | $3.39 | **-2.0%** | 0 | $3.30 | -2.7% | $3.60 | +6.2% | **-49%** | 🔴 Em prejuízo, próximo do stop |
| **LINKUSDT** | 5x | $9.59 | $9.61 | +0.3% | 0 | $9.15 | -4.8% | $10.00 | +4.0% | 7% | 🟡 Neutro |
| **BNBUSDT** | 50x | $647 | $672 | **+3.8%** | **1** | **$648** | -3.6% | $680 | +1.2% | **76%** | 🟢 Lucrando, BE protegido |
| **SOLUSDT** | 5x | $86.04 | $86.31 | +0.3% | 0 | $82.30 | -4.7% | $89.60 | +3.8% | 8% | 🟡 Neutro |

### 🚨 ALERTAS
- **UNIUSDT**: -2% no entry, stop a apenas **2.7%** do preço atual. Trailing não ativa em prejuízo (correto). Se cair mais 2-3%, stop é acionado = -1% no capital.
- **BNBUSDT**: 76% rumo ao target. Se chegar a $680, target hit → close. **Considerar mover target ou subir para $700+** para deixar correr (50x leverage = ganho enorme).

### ✅ TRAILING SAUDÁVEL
- BNB já está em **breakeven protegido** ($647.71 vs entry $647.06) — qualquer queda fecha sem perda
- LINK e SOL têm folga grande (4.7-4.8% até stop) — sem urgência

---

## 🤖 PARTE 2: Mentor Decidindo (3 testes feitos)

### ZECUSDT — REVISAR
- Tech: LONG, score 85, RR 2.99
- Mentor: "Encontrou um setup tecnicamente decente e destruiu com alvo preguiçoso. R:R 1.5 é suicídio estatístico"
- ⚠️ Mentor errou no cálculo de RR (real: 2.99, ele disse 1.5)
- Decisão: **REVISAR** (refazer com alvo melhor)

### BCHUSDT — ABORTAR (corretíssimo)
- Tech: SHORT, mas score 10/100 (péssimo)
- Mentor: "Score 10/100 é seu próprio sistema gritando para não entrar. Livermore: nunca perdi dinheiro ficando parado"
- Decisão: **ABORTAR** ✅ acertou

### SUIUSDT — ABORTAR
- Tech: LONG, score 85, RR 3.0
- Mentor: "R:R 2.5 é veto automático" (errou de novo no número)
- Reasoning correto: "Elder Triple Screen — semanal Fase 4 downtrend, contradição"
- Decisão: **ABORTAR**

---

## 🔍 PARTE 3: Insights Críticos

### ✅ O que está funcionando
1. **Mentor dá reasoning de qualidade** (Weinstein, Livermore, Tudor Jones, Elder)
2. **Identifica contradições**: tech LONG vs macro BEAR
3. **Defende capital** — todos os 3 abortaram por bom motivo
4. **Tempo razoável**: ~30s por análise (Anthropic Sonnet 4.6)

### ⚠️ Bugs identificados
1. **Mentor errando RR computado**:
   - ZEC: RR real 2.99, Mentor disse 1.5
   - SUI: RR real 3.0, Mentor disse 2.5
   - Causa: Mentor recalcula RR no prompt mas usa números errados
   - Impacto: VETOS por motivo errado

2. **Pre-screen é generoso demais**:
   - BCH passou com score 10 → tempo desperdiçado em análise LLM
   - Deveria filtrar antes (custo: ~$0.02/análise)

3. **TechAgent gerando RR baixos**:
   - Setups com RR 2.5-3.0 são comuns
   - Com RR_MINIMO = 3.0, qualquer 2.99 é abortado (margem zero)

---

## 🎯 PARTE 4: O Que Fazer AGORA

### Para as posições vivas:

**UNIUSDT (urgente)**:
- Em -2%, precisa decidir: deixar stop em $3.30 ou apertar para reduzir perda?
- Recomendação: **manter stop original** (foi escolhido por estrutura). Forçar saída em loss prematuro = trade ruim virou pior trade.

**LINKUSDT/SOLUSDT (passivo)**:
- Esperar trailing acionar. Phase 0, sem urgência.

**BNBUSDT (importante)**:
- 76% rumo ao target. Se hit, fecha em +5% (~$32 profit).
- **Decisão**: deixar correr ou aumentar target?
- Se aumentar target para $700: novo R:R 1:8 (excelente), mas trailing pega tudo no caminho.

### Para o sistema:

1. ✅ **Sistema funcionando** — Mentor analisa de verdade
2. ⚠️ **Calibrar Mentor** para calcular RR corretamente (bug nos prompts)
3. ⚠️ **Reduzir RR_MINIMO** para 2.5 temporariamente — destrava setups marginais
4. 📊 **Acumular paper trades** — cada análise grava em `decisions.csv`

---

## 📈 PARTE 5: Próximos Passos

| Ação | Prioridade | Tempo |
|------|-----------|-------|
| Investigar bug RR no Mentor | Alta | 30min |
| Reduzir RR_MINIMO temporariamente | Média | 1min |
| Avaliar movimento do BNB target | Média | manual |
| Deixar paper trades acumularem 7 dias | Passivo | 7 dias |
| Rodar `scan_master` em loop manual | Opcional | contínuo |
