# Análise de Problemas Recorrentes — 13/05 a 28/05/2026

**Gerado em**: 2026-05-28  
**Base**: 16 dias de logs, 412 ciclos, ~2.442 trades avaliados

---

## Visão geral por dia

| Data | Ciclos | MentorDown | MESA_DEGRADED | CAOS% | DSR_viol | BetaHalluc | GEM exec |
|------|--------|-----------|---------------|-------|----------|------------|----------|
| 13/05 | 79 | 0 | 0 | 0% | 0 | 0 | 0 |
| 14/05 | 44 | 0 | 0 | 0% | 0 | 0 | 0 |
| 15/05 | 38 | 0 | 0 | 7% | 0 | 0 | 0 |
| 16/05 | 32 | 0 | 0 | **78%** | 0 | 0 | 0 |
| 17/05 | 34 | 0 | 0 | 44% | 0 | 0 | 3 |
| 18/05 | 13 | 2 | 0 | 44% | 0 | 0 | 0 |
| 19/05 | 4 | 3 | 0 | 28% | 0 | 0 | 2 |
| 20/05 | 14 | 6 | 0 | 27% | 1 | 0 | 5 |
| 21/05 | 20 | 5 | 6 | 20% | 1 | 0 | 1 |
| 22/05 | 12 | **19** | 7 | 20% | 0 | 0 | 0 |
| 23/05 | 3 | 2 | 1 | 43% | 0 | 0 | 0 |
| 24/05 | 4 | 0 | **21** | **75%** | 0 | 0 | 0 |
| 25/05 | 14 | **69** | 4 | 4% | 10 | 0 | 0 |
| 26/05 | 17 | **66** | 3 | 3% | 27 | 6 | 2 |
| 27/05 | 43 | **77** | 1 | 2% | 173 | 63 | 0 |
| 28/05 | 37 | 1 | 4 | 18% | 103* | 59* | 0 |

*28/05: DSR e BetaHalluc corrigidos às 15:27 (restart). Pós-restart: 0 ocorrências.

---

## Os 4 problemas recorrentes identificados

---

### Problema 1 — Mesa CAOS (presente desde 15/05, nunca resolvido)

**O que é:** Mesa retorna 1/1/1 vote split entre as 3 personas (Tudor/Radar/LIDAR).
Quando isso acontece, o sistema aborta por "desacordo genuíno".

**Frequência histórica:**
- 16/05: **78%** dos trades abortados por CAOS
- 17/05: 44% | 18/05: 44% | 24/05: 75%
- Hoje (28/05): 18% — ainda presente

**Causa raiz:** Não é bug — é comportamento esperado quando o mercado está
ambíguo. Mas a frequência alta (>40% em vários dias) sugere que as personas
estão calibradas de forma muito divergente para o regime atual (BEAR).

**Nunca foi endereçado diretamente.** Todas as sessões trataram outros
problemas enquanto CAOS continuou bloqueando 20-78% dos trades.

**Impacto:** Em dias com CAOS >40%, o sistema efetivamente para de funcionar
mesmo quando os outros gates passariam.

---

### Problema 2 — Mentor indisponível (surgiu 18/05, pico 25-27/05)

**O que é:** `Invoke-MentorCascade` retorna null → fallback "VETO por segurança".

**Evolução:**
- 18/05: 2 ocorrências (início)
- 22/05: 19 ocorrências
- 25/05: **69 ocorrências** (quase todos os ciclos)
- 26/05: **66 ocorrências**
- 27/05: **77 ocorrências** (pico máximo)
- 28/05: 1 ocorrência (resolvido)

**Causa raiz identificada em 27/05:** `warmup_llm_endpoints.ps1` havia sido
deletado. O daemon reiniciava às 03:00 com endpoints frios → primeiro ciclo
falhava → cascade null → VETO automático. O script foi recriado em 27/05.

**Status:** ✅ Resolvido em 27/05.

---

### Problema 3 — MESA_DEGRADED / 0/3 drones null (surgiu 21/05)

**O que é:** Todos os 3 drones da Mesa retornam null no mesmo ciclo.
Diferente do CAOS (que é desacordo real), DEGRADED é falha técnica de LLM.

**Frequência:**
- 21/05: 6 | 22/05: 7 | 24/05: **21** | 25/05: 4 | 26/05: 3 | 27/05: 1

**Causa raiz:** Burst de 21 chamadas LLM em ~5 minutos (3 drones × 7 ativos
em paralelo) esgota Groq (30 RPM) + Gemini (15 RPM) simultaneamente.
Haiku deveria ser o fallback final mas às vezes também falha por timeout.

**Parcialmente resolvido:** Groq dual-key (60 RPM combinado) adicionado em
algum momento. Mas ainda ocorre esporadicamente (4 vezes hoje).

**Status:** ⚠️ Mitigado, não resolvido.

---

### Problema 4 — LLM usando DSR/beta como veto (surgiu 26/05, pico 27/05)

**O que é:** O LLM do Mentor usava `n_trades=0` e `beta viola BLOCK` como
razão de ABORTAR mesmo quando eram dados informativos ou matematicamente errados.

**Frequência:**
- 26/05: 27 DSR + 6 beta | 27/05: **173 DSR + 63 beta** | 28/05: 103+59 (antes fix)
- 28/05 pós-restart: **0 ocorrências**

**Causa raiz:** Regra DSR não estava no `MENTOR_DEBATE_SYSTEM` (string literal
hardcoded). A regra existia em `lib_mentor_rules.ps1` mas nunca era injetada
no system prompt enviado ao LLM.

**Status:** ✅ Resolvido em 28/05 (restart 15:27).

---

## Padrão geral: o que está realmente acontecendo

```
13-14/05  Sistema novo, sem problemas, sem trades aprovados (gems bloqueados)
15-17/05  CAOS começa — Mesa divergindo em mercado ambíguo
18-22/05  Mentor começa a falhar (warmup deletado gradualmente)
23-24/05  MESA_DEGRADED pico — rate limit burst não controlado
25-27/05  Mentor quase 100% down + DSR/beta hallucination explode
28/05     Tudo corrigido, mas CAOS ainda presente (18%)
```

**O problema de fundo que nenhuma sessão resolveu:**
Nenhum trade foi executado desde 20/05 (último GEM exec). O sistema está
tecnicamente funcional mas o mercado (BEAR_STRONG, BTC -10.5%) + os gates
defensivos (consensus FORTE obrigatório para Tier B) criam uma combinação
onde nada passa. Isso pode ser correto — ou pode indicar que os thresholds
estão calibrados para um mercado que não existe agora.

---

## Problemas ainda abertos

| # | Problema | Frequência atual | Prioridade |
|---|----------|-----------------|------------|
| 1 | Mesa CAOS alto em bear market | 18% hoje | Alta |
| 2 | MESA_DEGRADED esporádico | 4 hoje | Média |
| 3 | Gemini 429 no warmup | Toda sessão | Baixa (cosmético) |
| 4 | Zero trades executados desde 20/05 | 8 dias | Alta |
| 5 | Kelly graduation travado em 6/10 | Sem novos trades | Alta |

---

## O que foi resolvido nesta jornada (28/05)

| Fix | Sessão | Status |
|-----|--------|--------|
| Regime-aware tier_level (whitelist BEAR rebaixada) | 2 | ✅ |
| Living Whitelist conectada ao cron semanal | 2 | ✅ |
| Beta cap phase-aware ativado (1.4 em bear) | 4 | ✅ |
| Regra beta matemática no system prompt | 4 | ✅ |
| Frases DSR na lista forbidden phrases | 5 | ✅ |
| Regra DSR no MENTOR_DEBATE_SYSTEM | 6 | ✅ |
| Restart com 130/130 testes passando | 7 | ✅ |
| Validação pós-restart: 0 frases DSR | 8 | ✅ |
