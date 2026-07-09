# 🔍 INVESTIGATION 2026-07-08 — Fable (dados REAIS, sem projeção fabricada)

> Executado pelo comando único Fable. Todos os números abaixo vêm de
> `journal/decision_grades.jsonl` (n=1500), `journal/signal_triggers.jsonl` (n=2417)
> e `logs/master_*.log`. Nenhum número é projetado/estimado sem base.

---

## 0. CORREÇÃO DE PREMISSA (importante)

A premissa "130 trades para grading" era **falsa**: `trade_outcomes.jsonl` tem 130
*linhas* de JSON pretty-printed = **8 trades**, todos `open`, registrados 07-06/07
via position sync. Não existe dataset de trades fechados ali.

O dataset real de aprendizado é **`decision_grades.jsonl`: 1500 decisões LLM
gradeadas** contra candles reais (D+2, threshold ±3%, neutros excluídos) — o
grading ESTÁ rodando (última rodada 2026-07-09 01:32Z), ao contrário do memo
"0/130 graded".

---

## 1. BUCKETS REAIS (decision_grades, n=1500)

| Bolso | n | Acurácia | avg_move_dir | Leitura |
|---|---|---|---|---|
| APROVAR (total) | 107 | **20.6%** | — | Mentor aprova MAL |
| APROVAR LONG BULL_STRONG | 21 | 10% | -19.2% | rótulo de regime anti-preditivo |
| APROVAR LONG BULL_WEAK | 34 | 23% | -4.7% | idem |
| APROVAR SHORT BEAR_WEAK | 38 | 32% | **-205.5%** | classe SIREN (squeeze 13x) |
| VETAR LONG BULL_WEAK | 290 | 37% | +13.3% | **63% de falso-veto**, +13% perdido/veto |
| VETAR SHORT BEAR_WEAK | 507 | 46% | -28.9% | 54% dos SHORTs vetados teriam ganho |
| VETAR SHORT BEAR_STRONG | 265 | 43% | -4.8% | 57% falso-veto |
| VETAR LONG BULL_STRONG | 302 | **80%** | -11.4% | único bolso bem calibrado |

**Conclusões:**
- **A (ruins):** as aprovações do mentor (todas as combinações, 107 casos) têm
  20.6% de acerto — pior que moeda. A classe mais destrutiva: SHORT aprovado em
  microcap pumpando (SIRENUSDT 5x aprovado com move contra de -1330% a -1361%).
  *Decisão do user 2026-07-08: NÃO adicionar veto de SHORT — mitigação fica por
  conta da calibração injetada no prompt do mentor ([CALIBRACAO]) + stops.*
- **B/C (falso-veto = trades omitidos):** 673 vetos com would_win=true, move médio
  +14.7% na direção. O sistema **veta demais** — o gargalo de lucro não é entrar
  errado, é NÃO entrar.
- **D (bom):** VETAR LONG em BULL_STRONG (acc 80%) — manter.
- **Regime suspeito:** em BULL_STRONG, LONGs perdem na média (-11 a -19% em D+2).
  O rótulo BULL_STRONG do classificador é anti-preditivo → auditar
  `regime detector` (h24_p3) antes de confiar em qualquer gate regime-based.

> Caveat honesto: `move_dir_d2` é hold-até-D+2 SEM stop. Com stop 1% (Regra de
> Ouro), a perda realizada dos bad-approvals seria muito menor que o avg -103%.
> Os números medem qualidade direcional da decisão, não PnL realizado.

## 2. FUNIL DE EXECUÇÃO (signal_triggers, n=2417)

```
2417 triggers gerados (tori_ripe 1214, funding 568, sentinel 508, whale 87, vol_climax 2)
  → 2327 skipped (96.3%)  — TODOS com nota catch-all "gem_safety_blocked"
  → 45 processed (1.9%)
```

Razão real dos blocks recentes (logs 07-07/08): **8× `BLOCKED sizing: proposto
$102-103 > cap $100`** — o sizer propõe ~2.75% acima do cap e o guard binário
mata o trade inteiro em vez de clampar.

## 3. FIXES DEPLOYADOS HOJE (live)

1. **Sizing clamp** — `Resolve-SizingClamp` em [lib_live_guards.ps1](../agents/lib_live_guards.ps1)
   + wire em [gem_executor.ps1](../agents/gem_executor.ps1): overage ≤10% clampa
   pro cap e o trade SEGUE; >10% continua bloqueando (fail-closed preservado).
2. **Razão real no trigger** — [gem_loop.ps1](../scripts/gem_loop.ps1): nota do
   skip agora grava `blocked: <blocked_by real>` em vez do catch-all
   `gem_safety_blocked`, e marca só o trigger processado (match por `id`), não
   todos os triggers do market.
3. **BOM UTF-8 em gem_executor.ps1** — o arquivo estava SEM BOM = 12 erros de
   parse no PS 5.1 (frota roda powershell.exe 5.1). Agora parse 0 erros.
4. *(Revertido a pedido do user)* Guard 5 anti-squeeze para SHORT — implementado
   e removido na mesma sessão. SHORTs não sofrem veto novo.

TDD: `tests/live_guards.Tests.ps1` **22/22 PASS** (7 novos p/ clamp).
Parse PS 5.1: lib_live_guards / gem_executor / gem_loop = 0 erros.

## 4. IMPACTO QUANTIFICADO (base real, sem fantasia)

- Clamp: 8 entradas/2 dias morriam por $2.75 de overage → ~4 entries/dia
  destravadas na configuração atual (cap $100, sizing 2%).
- Observabilidade: próxima investigação verá a razão REAL de cada um dos ~1200
  skips/mês em vez de um único rótulo — pré-requisito pra atacar o funil de 96%.
- Falso-veto (673 casos, +14.7% médio perdido): maior alavanca de lucro
  identificada. Caminho: usar `llm_calibration.json` (já injetado no prompt) +
  revisar limiar de veto do mentor em bolsos com acc<45%. NÃO deployado hoje —
  requer decisão de risco do user.

## 5. PRÓXIMOS PASSOS (dados, não cronograma fabricado)

1. **48h:** medir taxa processed/skipped pós-fix (baseline: 1.9%).
2. **Auditar regime detector** — rótulos BULL_* anti-preditivos (seção 1).
3. **Recalibrar veto do mentor** nos bolsos com falso-veto >55% (VETAR SHORT
   BEAR_STRONG 57%, VETAR LONG BULL_WEAK 63%) — proposta: piso de aprovação
   quando calibração histórica do bolso mostra would_win>55%.
4. **Consertar registro de outcomes fechados** — sem trades fechados no journal,
   Kelly e win-rate real continuam incalculáveis (só 8 posições abertas hoje).
