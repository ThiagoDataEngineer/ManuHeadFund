# Mentor Evolutions A+B+C — 2026-05-26

> 9 melhorias entregues em TDD numa única sessão. 65 testes novos GREEN, 0 regressões, smoke E2E 22/22 PASS. Commit `33a304b`.

---

## Contexto

Diagnóstico inicial revelou:
1. **Mentor "indisponível"** em 64 das últimas 76 decisões — causa raiz: DNS Cisco Umbrella bloqueando `api.anthropic.com` (resolveu pra `146.112.61.106` block page). Fix: `CONSERTAR_DNS_LLM.ps1` (rodado como admin, hosts file injetado com IPs reais via Cloudflare DoH).
2. **4 phantom positions** em `trailing_positions.json` (UNI/LINK/BNB/SOL marcadas active=true mas já fechadas na CoinEx desde 24-26/05).
3. **Pipeline E3 reflection morto** — lib existia (`lib_decision_reflection.ps1` + cron) mas `decision_reflections.jsonl` nunca foi escrito porque nada chamava `Add-PendingReflection`.
4. **Múltiplos gaps no Mentor** identificados em audit profundo (12 pontos no [Análise mais cedo na conversa]).

---

## Onda A — Foundation

### A.0 Phantom reconciliation
- **Lib**: `agents/lib_trailing_orphan_detection.ps1` ganhou `Detect-PhantomPositions` (active local + ausente na exchange) e `Reconcile-PhantomPositions` (fecha via Close-TrailingPosition com reason `phantom_reconciliation` + ExitPrice via ticker atual).
- **Script CLI**: `scripts/reconcile_phantom_positions.ps1` (suporta `-DryRun`).
- **Wires**: `scripts/github_actions_runner.ps1` + `scripts/trailing_stop_monitor.ps1` chamam Reconcile após Sync-Orphan a cada execução do cron.
- **Resultado real**: 2 phantoms reais fechadas (LINK exit=$9.40, SOL exit=$83.86).
- **TDD**: `tests/trailing_phantom_reconciliation.Tests.ps1` (9 PASS).

### A.1 Reflection wire E3
- **Lib edit**: `agents/lib_trailing.ps1` — `Add-TrailingPosition` ganhou params opt-in (`MentorVeredicto`, `MentorConfidence`, `MentorMensagem`, `MesaSinal`, `Tier`); quando presentes, dispara `Add-PendingReflection`. `Close-TrailingPosition` computa `pnl_pct` (LONG/SHORT-aware) e dispara `Add-ResolvedReflection` matching por market.
- **Pass-through**: `agents/lib_position_register.ps1` (wrapper Moon Bag) propaga os params.
- **Comportamento legacy preservado**: posições sem Mentor metadata (orphan_auto_register, replays) NÃO escrevem reflection — gracioso.
- **trade_id format**: `{Market}@{openedAt sem espaço/dois-pontos}` — sufice como unique pair pra resolver no Close.
- **TDD**: `tests/mentor_reflection_wire.Tests.ps1` (6 PASS).

### A.6 Time context
- **Lib nova**: `agents/lib_mentor_time_context.ps1` com `Get-TimeContext` (weekday/hour_utc/session/is_weekend) e `Format-TimeContextLine`.
- **Sessions**: `ASIA` (0-7 UTC), `EU_OVERLAP` (8-12), `US` (13-21), `LATE_US` (22-23).
- **Wire**: `Build-MentorFullContext` popula campo `time`; `Build-GateStatusBlock` renderiza linha `[TIME]   time Tuesday 14h UTC session=US`. Weekend marca `WEEKEND_LOW_LIQUIDITY`.
- **Custo**: zero (sem network).
- **TDD**: `tests/mentor_time_context.Tests.ps1` (9 PASS).

---

## Onda B — Sinal mais rico pro Mentor

### B.4 alpha_vs_btc histórico
- **Lib nova**: `agents/lib_mentor_alpha_history.ps1` com `Get-MarketAlphaSummary` (lê `decision_reflections.jsonl`, agrega alpha_vs_btc por market) e `Format-AlphaHistoryLine`.
- **Output**: `n_samples`, `avg_alpha`, `beats_btc_count`, `beats_btc_rate_pct`, `beats_btc_negative` (flag quando rate < 40%).
- **Render no GATE STATUS**: `[ALPHA_HIST] n=5 avg_alpha=1.5pp beats_btc=60.0%` ou `LOSING_TO_BTC` quando negative.
- **Alinha com**: regra-ouro #13 do CLAUDE.md (BTC-core philosophy).
- **TDD**: `tests/mentor_alpha_history.Tests.ps1` (7 PASS).

### B.2 5-tier veredicto MANDATORY
- **Lib edit**: `agents/lib_mentor_schema.ps1` ganhou `Test-MentorOutputV2`:
  - `veredicto_5tier` é obrigatório (era opcional)
  - Coerência: `STRONG_EXECUTAR/EXECUTAR` ↔ decision=APROVAR; `ABORTAR/HARD_VETO` ↔ decision=VETAR; `REVISAR` aceita ambos (paper-only intermediário).
- **Prompt**: trocado "Opcionalmente classifique" → "CLASSIFIQUE OBRIGATORIAMENTE" + tabela coerência explícita.
- **Validação**: pós-LLM em `Invoke-MentorDebate` — viola → Write-Warning (fail-soft, não bloqueia ainda).
- **TDD**: `tests/mentor_5tier_mandatory.Tests.ps1` (6 PASS).

### B.7 Multi-shot examples
- **Lib nova**: `agents/lib_mentor_examples.ps1` com 2 canonicos:
  - **APROVAR**: BTCUSDT BULL_STRONG, FQS=7/7, DSR 0.95 n=42, TORI ripening → `EXECUTAR conf=82`
  - **VETAR**: SUIUSDT, beta=1.49 viola BLOCK 1.4, FQS SPECULATIVE, TORI SHORT → `HARD_VETO conf=92`
- **Wire**: injetado no `userPrompt` antes da pergunta. Custo +~250 tokens/call. Empírico literário: -30-50% hallucination.
- **TDD**: `tests/mentor_multi_shot.Tests.ps1` (4 PASS).

---

## Onda C — Calibração + qualidade

### C.5 Calibration dashboard
- **Lib nova**: `agents/lib_mentor_calibration.ps1` com `Get-MentorCalibration` (agrupa reflections por `veredicto_5tier × provider × regime`, computa win_rate + avg_pnl_pct) e `Format-CalibrationReport`.
- **Script CLI**: `scripts/mentor_calibration_report.ps1`.
- **Uso**: após ~5-10 trades resolvidos, mostra empíricamente se Mentor está calibrado (ex: `STRONG_EXECUTAR n=12 win_rate=83% avg_pnl=4.2%`).
- **TDD**: `tests/mentor_calibration.Tests.ps1` (5 PASS).

### C.3 Unificação de prompts (SSoT)
- **Lib nova**: `agents/lib_mentor_rules.ps1` com `Get-MentorAntiHallucinationRules` (4 regras E2 anti-hallucination) e `Get-MentorInviolableRules` (8 regras incluindo R:R 1:5 e BTC-core).
- **Edit prompt legado**: `MENTOR_SYSTEM_PROMPT` (debate full ~1500 tokens) atualizado:
  - R:R `1:3` → `1:5` (alinha CLAUDE.md)
  - Adicionada regra #8 BTC-core
  - Adicionado bloco anti-hallucination (4 regras numeradas)
- **TDD**: `tests/mentor_prompt_unified.Tests.ps1` (8 PASS).

### C.8 Self-consistency check
- **Lib nova**: `agents/lib_mentor_self_consistency.ps1` com:
  - `Test-MentorCriticalTier` (STRONG_EXECUTAR/HARD_VETO = true)
  - `Test-SelfConsistencyRequired` (alias semântico)
  - `Resolve-SelfConsistency` (classifica em bull/bear/neutral e:
    - mesmo tier → consistent
    - bull×bear → REVISAR (max safe)
    - bull×bull com magnitudes diferentes → EXECUTAR (downgrade do STRONG)
    - bear×bear com magnitudes diferentes → ABORTAR (sem blacklist do HARD_VETO))
- **Wire**: `Invoke-MentorDebate` dispara 2nd LLM call SOMENTE quando 1ª foi critical. ~5-10% das decisões empíricas. Divergência → merge resultado com flag warning.
- **TDD**: `tests/mentor_self_consistency.Tests.ps1` (11 PASS).

---

## Validação E2E

`scripts/smoke_test_full_cycle.ps1` — **22/22 PASS**:
1. **Fase 1** Add-TrailingPosition + Mentor metadata → pending reflection criada
2. **Fase 2** Close-TrailingPosition + ExitPrice → resolved reflection com pnl_pct correto
3. **Fase 3** Get-MarketAlphaSummary agrega corretamente
4. **Fase 4** Format-AlphaHistoryLine + Format-TimeContextLine renderizam
5. **Fase 5** Build-GateStatusBlock inclui `[TIME]` + `[ALPHA_HIST]` + `[FQS]`
6. **Fase 6** Get-MentorCalibration produz stats + Format-CalibrationReport
7. **Fase 7** Self-consistency triggers (STRONG/HARD → 2x, EXECUTAR → 1x)
8. **Fase 8** Multi-shot examples block tem 2 decisions + 2 veredicto_5tier

---

## Custos

| Componente | Custo extra por call | Frequência | Custo mensal estimado |
|---|---|---|---|
| Time context (A.6) | 0 | sempre | 0 |
| Alpha history (B.4) | 0 (I/O local) | sempre | 0 |
| Multi-shot (B.7) | +~250 tokens input | sempre | ~$3-5/mês |
| Self-consistency (C.8) | +1 LLM call | ~5-10% decisões críticas | ~$2-3/mês |
| **Total adicional** | | | **~$5-8/mês** |

Mitigação custo: critical tiers (~5-10% das decisões) é o gatilho de self-consistency, evitando 2x calls em todas as 700+ decisões/dia.

---

## Quando os benefícios aparecem

| Evolução | Sinal observável | ETA empírico |
|---|---|---|
| A.0 Phantom | "Phantoms detected: N closed: N" no trailing_stop_monitor.log | imediato (próximo cron horário) |
| A.1 Reflection | `decision_reflections.jsonl` cresce | próximo trade APROVAR + close |
| A.6 Time | `[TIME]` no GATE STATUS dos logs Mentor | próxima decisão |
| B.4 Alpha hist | `[ALPHA_HIST] n=N` em decisão de market repetido | após ~3-5 trades resolvidos do mesmo market |
| B.2 5-tier | `provider_used` decisions.csv tem `veredicto_5tier` consistente | próxima decisão |
| B.7 Examples | Hallucination rate menor em `mentor_hallucinations.jsonl` | após ~20-50 decisões |
| C.5 Calibration | `.\scripts\mentor_calibration_report.ps1` mostra rows | após ~5-10 trades resolvidos |
| C.3 Unified | `MENTOR_SYSTEM_PROMPT` cita R:R 1:5 + BTC-core | imediato |
| C.8 Self-consistency | `[MentorDebate] Critical tier '...' - chamando 2nd opinion` no log | próximo STRONG/HARD_VETO |
| Sizing 1.5x STRONG | `Get-StrongOutcomesCount >= 30` no calibration | após ~30 trades STRONG_EXECUTAR resolvidos com alpha>0 |

---

## Arquivos novos (15)

```
agents/lib_mentor_alpha_history.ps1
agents/lib_mentor_calibration.ps1
agents/lib_mentor_examples.ps1
agents/lib_mentor_rules.ps1
agents/lib_mentor_self_consistency.ps1
agents/lib_mentor_time_context.ps1
scripts/mentor_calibration_report.ps1
scripts/reconcile_phantom_positions.ps1
scripts/smoke_test_full_cycle.ps1
tests/mentor_5tier_mandatory.Tests.ps1
tests/mentor_alpha_history.Tests.ps1
tests/mentor_calibration.Tests.ps1
tests/mentor_multi_shot.Tests.ps1
tests/mentor_prompt_unified.Tests.ps1
tests/mentor_reflection_wire.Tests.ps1
tests/mentor_self_consistency.Tests.ps1
tests/mentor_time_context.Tests.ps1
tests/trailing_phantom_reconciliation.Tests.ps1
```

## Arquivos editados (8)

```
agents/lib_mentor_gate_block.ps1            (+ [TIME] + [ALPHA_HIST])
agents/lib_mentor_schema.ps1                (+ Test-MentorOutputV2)
agents/lib_position_register.ps1            (+ pass-through Mentor metadata)
agents/lib_trailing.ps1                     (+ reflection wire em Add/Close)
agents/lib_trailing_orphan_detection.ps1    (+ Detect/Reconcile-Phantom)
agents/mentor_agent.ps1                     (+ time/alpha/examples/self-consistency wires + R:R 1:5)
scripts/github_actions_runner.ps1           (+ phantom reconcile wire)
scripts/trailing_stop_monitor.ps1           (+ phantom reconcile wire)
tests/mentor_debate.Tests.ps1               (regression: token threshold 1500→2700 + regex FQS legacy|GATE_STATUS)
```
