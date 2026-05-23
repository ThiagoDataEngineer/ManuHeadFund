# Mentor E3 — Decision Reflection Loop (2026-05-22)

> Pattern: doc-alongside-TDD. Esta evolução fecha o loop pending→resolved→reflection,
> habilitando aprendizado entre decisões mesmo market.

## Objetivo

Habilitar Mentor a aprender com decisões passadas mesmo market. Hoje cada decisão
é stateless — Mentor não sabe se decidiu EXECUTAR DYDX há 2 semanas e deu loss.
Próxima decisão DYDX, mesmas razões podem ser citadas → mesmo erro repetido.

## Motivação (Tauric-inspired)

Tauric tem reflection loop:
```
[decision pending] → trade closes → outcome computed → Haiku distila lesson 2-4 frases
→ próxima decisão same-ticker injeta 5 reflections no prompt
```

Resultado: Mentor cita "ultima vez RENDER GPU narrative segurou, mas entry tarde (16%
above trendline). Lesson: NEAR proximity scanner needed before entry trigger". Aplica
lesson em vez de re-tentar mesmo erro.

Diferencial nosso vs Tauric: `alpha_vs_btc` (regra-ouro #13) ao invés de SPY/N225.

## Design

### Append-only JSONL (`journal/decision_reflections.jsonl`)

Cada trade gera 2 entries:
```json
{"trade_id":"T123","market":"BTCUSDT","entry_date_utc":"2026-05-20",
 "mentor_veredicto":"EXECUTAR","mentor_confidence":75,"status":"pending","added_at":"..."}
{"trade_id":"T123","status":"resolved","exit_date_utc":"2026-05-22",
 "pnl_pct":3.2,"alpha_vs_btc":1.1,"holding_days":2,
 "reflection":"Bull thesis held...","resolved_at":"..."}
```

### Cron MentorReflector (diário 04:00 BRT após DaemonRestart)

[scripts/cron_mentor_reflector.ps1](../../scripts/cron_mentor_reflector.ps1)

Operação:
1. Le pending reflections via `Get-PendingReflections`
2. Pra cada pending: cruza com trade close (`journal.csv` / `gem_trades.csv`)
3. Se match: computa `alpha_vs_btc`, spawn Haiku call ($0.001) pra distilar
4. Append resolved entry no JSONL
5. Skip pending sem trade match (tenta próximo cron)

### Mentor prompt injection

`mentor_agent.ps1:Invoke-MentorDebate` agora inclui após GATE STATUS:

```
=== PRIOR RESOLVED DECISIONS (this market, last 5) ===
[2026-05-18 EXECUTAR conf=72] +3.2% alpha 1.1pp vs BTC in 4d
  REFLECTION: Bull thesis on RENDER GPU narrative held; entry timing late.
[2026-05-10 ABORTAR conf=30] (n/a — vetoed)
=== END PRIOR ===
```

Mentor pode citar essas reflections nas decisões.

### Custo

- Haiku call: $0.001 × ~50 trades fechados/semana = $0.05/semana = **$2.60/ano**
- Token overhead prompt: +200 tokens/call × 30 calls/day = $0.018/day = $6.50/ano
- **Total: ~$9/ano**. ROI assimétrico — 1 lesson previne 1 trade ruim = paga 100+ anos.

## TDD Coverage

`tests/lib_decision_reflection.Tests.ps1` — **14/14 PASS**:

| Group | Tests | Coverage |
|---|---|---|
| Add-PendingReflection | 2 | Cria entry + idempotente (skip dup trade_id) |
| Get-PendingReflections | 4 | Empty / single pending / pending after resolved / multiplos |
| Add-ResolvedReflection | 1 | Append preservando alpha=null |
| Get-PriorReflectionsForMarket | 3 | No match / market filter / MaxN limit |
| Format-PriorReflectionsBlock | 3 | Vazio / format / alpha null |
| Property: determinismo | 1 | Mesma sequencia → mesmo Get |

## Design decisions

1. **Append-only JSONL**: race-safe writes (`Add-Content` atomic em NTFS). Bate o pattern já estabelecido (B15 DSR atomic).

2. **Pending → Resolved como ENTRIES SEPARADAS (não update)**: append-only mantém audit trail completo. Resolved não sobrescreve pending; aggregator (`Get-PriorReflectionsForMarket`) faz join.

3. **Idempotency em Add-PendingReflection**: skip se trade_id já existe. Evita duplicação se hook for chamado 2x.

4. **Cron daily ao invés de hook close-trade**: desacopla. Se close-trade fail, próximo cron pega. Não bloqueia close path.

5. **Fail-soft em LLM call**: se Haiku falha, fallback text genérico "[llm_failed]". Reflection ainda adicionada (com aviso). Cron próxima tentativa pode re-resolver se for re-fired (idempotency).

6. **Holding days computed simples**: `[datetime]exit - [datetime]entry`. Suficiente pra contexto.

7. **PRIOR RESOLVED block após GATE STATUS no prompt**: ordem ROOT → CONTEXT → PRIOR HISTORY. Mentor lê tudo antes de decidir.

## Limitações declaradas

1. **Trade close match é crude**: usa apenas market+status, não trade_id real. Risk: se 2 trades same market closed no mesmo dia, match pode acertar o errado. Mitigação: trade_id incluído em Add-PendingReflection, futuramente refinar match com trade_id em close hook.

2. **Reflection LLM pode ser genérica**: Haiku às vezes produz "trade went well, keep doing this". Mitigação parcial: prompt obriga `noun+verb específico`. Acceptable variance.

3. **30-day stale cleanup não implementado**: pending entries sem close match continuam pending forever. Não é problema (Get-PendingReflections só skip se sem trade match). Mas pode crescer JSONL. TODO: cleanup script weekly.

4. **Reflection injection é APENAS no Mentor Debate path**: Mesa drones / GEM scanner não veem prior reflections. Intencional (são tactical/algorithmic, não strategic). Mas vale considerar futura extensão.

## Forward links

- **E1 Schema 5-tier**: STRONG_EXECUTAR sizing tilt requer 30+ outcomes validados. Reflection loop alimenta esse contador.
- **E4 alpha_vs_btc audit**: reflections com alpha persistido permitem `audit_alpha_negative_rate.ps1` correr direto sobre reflections.

## Skill insight permanente

> **"Loops fechados de aprendizado batem snapshots métricos"**.
>
> `replay_decisions_analyzer` computa métricas agregadas (∑PnL, hit-rate) — útil pra audit
> mas não habilita aprendizado individual. Reflection LLM-distilled em prompt next-time
> é qualitativamente diferente: Mentor "sabe" o que aconteceu da última vez.
>
> Pattern: pending entries em append-only JSONL + cron diário resolve + inject em next prompt.
> Aplicável a qualquer agente LLM com decisões repetidas mesmo contexto.

## Artefatos

- Código: [agents/lib_decision_reflection.ps1](../../agents/lib_decision_reflection.ps1)
- Cron: [scripts/cron_mentor_reflector.ps1](../../scripts/cron_mentor_reflector.ps1)
- TDD: [tests/lib_decision_reflection.Tests.ps1](../../tests/lib_decision_reflection.Tests.ps1) (14 PASS)
- Wire: [agents/mentor_agent.ps1](../../agents/mentor_agent.ps1) (Invoke-MentorDebate ctxBlock + priorBlock)
- Doc: este arquivo
