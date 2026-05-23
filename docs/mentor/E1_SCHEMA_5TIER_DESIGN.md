# Mentor E1 — Schema 5-tier Veredicto + Sizing Tilt Cap (2026-05-22)

> Pattern: doc-alongside-TDD. Última evolução Mentor — fecha schema validation + sizing dinâmico.

## Objetivo

1. Expandir veredicto 3-tier (EXECUTAR/REVISAR/ABORTAR) → 5-tier com extremos:
   - **STRONG_EXECUTAR**: sizing 1.5x (high confidence)
   - **HARD_VETO**: skip + blacklist 24h (extreme caution)
2. Validar schema antes de aceitar resposta (retry 1x + force ABORTAR fallback)
3. **Sizing tilt cap**: STRONG amplifier desabilitado até 30+ outcomes validarem accuracy

## Motivação

Hoje sistema tem veredicto binário-ish (EXECUTAR/REVISAR/ABORTAR) + sizing fixo 1.0x.
Não distingue "moderate setup" de "high-confidence layup". Tauric tem 5-tier desde
v0.2.0. Permite:
- High-confidence trades ganham mais quando certos
- Extreme red flags vão pra blacklist (anti-revenge trade)

Risco do tilt: STRONG_EXECUTAR amplifica perda 50% se Mentor hallucina. Mitigação:
**cap 1.5x apenas após 30+ outcomes positive alpha validarem accuracy STRONG**.

## Design

### 5-tier sizing map

```
STRONG_EXECUTAR  -> 1.5x  (CAPPED em 1.0x até 30 outcomes)
EXECUTAR         -> 1.0x
REVISAR          -> 0.5x  (paper only)
ABORTAR          -> 0.0x  (skip)
HARD_VETO        -> 0.0x  (skip + blacklist 24h via downstream)
```

### Test-MentorOutput (schema validator)

Valida:
- `veredicto`: enum 5-tier
- `confianca_mentor`: int 0-100
- `risco_identificado`: enum BAIXO/MEDIO/ALTO/EXTREMO
- `mentor_mensagem`: max 600 chars
- `motivo_veto`: required se veredicto != EXECUTAR/STRONG_EXECUTAR

Returns: `@{valid, violations[]}`. Fail-soft (não throws).

### Get-SizingTiltMultiplier (safety-aware)

```powershell
$mult = Get-SizingTiltMultiplier -Veredicto "STRONG_EXECUTAR"
```

Look-up tier → multiplier. Special case STRONG_EXECUTAR:
- Chama `Get-StrongOutcomesCount` (lê decision_reflections.jsonl)
- Se contagem < 30: retorna 1.0 (cap)
- Senão: retorna 1.5

`ForceCap` param pra testing override.

### Invoke-MentorWithSchemaRetry

Wrapper around Mentor cascade:
1. Call Mentor
2. Validate response
3. Se invalid: re-prompt com schema reminder (2nd attempt)
4. Se 2nd também invalid: force ABORTAR fallback (seguro)

## TDD Coverage

`tests/lib_mentor_schema.Tests.ps1` — **24/24 PASS**:

| Group | Tests | Coverage |
|---|---|---|
| Test-MentorOutput basic | 9 | Veredicto enum / confianca range / risco enum / motivo_veto required / STRONG/HARD_VETO / JSON string parse / invalid JSON |
| Get-SizingTiltMultiplier | 7 | 5-tier values / STRONG cap < 30 outcomes / STRONG 1.5x ≥ 30 outcomes / ForceCap / unknown veredicto |
| Get-StrongOutcomesCount | 2 | Empty file / counts only STRONG+alpha>0 (excludes EXECUTAR + negative alpha) |
| Invoke-MentorWithSchemaRetry | 4 | 1st valid / 1st invalid → 2nd valid / 2x invalid force fallback / null response |
| Property: sizing safety bounds | 2 | All multipliers in [0, 1.5] / STRONG sem dados ≤ 1.0 |

## Design decisions

1. **5-tier ao invés de granular score (0-100)**: tier facilita classification por rules,
   sizing por lookup. Tauric pattern. Mais legível em audit.

2. **Sizing cap baseado em outcomes históricos (não tempo)**: 30 outcomes >>>> "30 dias".
   Outcomes validados são o sinal real de accuracy. Wire com E3 reflection loop.

3. **Retry 1x apenas**: 2 attempts max. Custo +1 LLM call quando triggered (~1% calls).
   Fallback ABORTAR é safe default — never propagate invalid schema downstream.

4. **fallback PSCustomObject (não exception)**: Invoke-MentorWithSchemaRetry sempre retorna
   estrutura dict. Caller não precisa try/catch.

5. **STRONG_EXECUTAR cap CONSERVADOR**: começa em 1.0x (= EXECUTAR equiv). Só destrava
   1.5x após 30+ outcomes ALPHA POSITIVE (não só "any outcome"). Anti-overconfidence guard.

6. **Wire deferido (não auto)**: Lib pronta mas wire em Invoke-MentorDebate (5-tier
   parsing + sizing call) requer migração do prompt + careful update downstream code
   que assume 3-tier. Fica como follow-up explícito com checklist:
   - Update MENTOR_DEBATE_SYSTEM prompt pra mencionar 5-tier
   - Update consumers em orchestrator (que matcham "EXECUTAR" "REVISAR" "ABORTAR")
   - Add STRONG_EXECUTAR + HARD_VETO branches
   - Wire Get-SizingTiltMultiplier em sizing calc

## Limitações declaradas

1. **n=30 threshold é arbitrário**: baseado em statistical convention pra "small sample".
   Pode subir pra 50 se quiser mais conservador, ou descer se prefere agility.

2. **HARD_VETO blacklist 24h não implementado aqui**: schema permite tier, mas mecanismo
   de blacklisting (suprimir market do scan por 24h) é responsabilidade downstream.
   Vira follow-up.

3. **STRONG outcomes counter conta apenas alpha>0**: trade que ganhou USD mas perdeu
   pra BTC NÃO conta. Coerente com regra-ouro #13. Mas pode ser visto como muito
   strict — alguns trades positive PnL mas neutral alpha (zero) também são "OK".
   Decidi count strict (alpha > 0) pra ser conservador.

## Forward links

- **Future wire em Invoke-MentorDebate**: parse 5-tier + call Get-SizingTiltMultiplier
- **Future blacklist mechanism**: lib_market_blacklist.ps1 com TTL 24h para HARD_VETO
- **E3 Reflection loop**: alimenta Get-StrongOutcomesCount continuamente

## Skill insight permanente

> **"Sizing amplifier requires capability validation, never trust untested expansion"**.
>
> STRONG_EXECUTAR tier amplifica perda 50% se errado. Schema permite tier;
> safety guard (outcomes ≥ 30) impede execução até accuracy provada.
>
> Pattern: ANY tier que amplifica risco deve ter (a) outcome counter (b) min threshold
> (c) auto-disabled state default. "Optimistic by config, pessimistic by default."

## Artefatos

- Código: [agents/lib_mentor_schema.ps1](../../agents/lib_mentor_schema.ps1)
- TDD: [tests/lib_mentor_schema.Tests.ps1](../../tests/lib_mentor_schema.Tests.ps1) (24 PASS)
- Doc: este arquivo
