# Mentor E2 — Grounded v2 (GATE STATUS block + forbidden phrases guard)

> Pattern: doc-alongside-TDD. Esta evolução ataca diretamente o problema documentado
> de 7/7 hallucinations (PM6+870min).

## Objetivo

Eliminar capacidade do LLM Mentor de hallucinar "FQS indisponivel"/"Mesa pulou"
quando contexto tem dados claros. Substitui CONTEXTO free-form por GATE STATUS
estruturado com [TAG] explicit + ABSENT explicit quando ausente.

## Motivação (concrete evidence)

PM6+870min audit revelou **7/7 markets** com Mentor inventando "FQS indisponivel"
apesar do FullContext ter FQS valid (DYDX FQS=5, LIT/TAO/JTO FQS=4). 7 trades
vetados artificialmente.

Tauric resolveu pattern similar removendo capacidade de hallucinar (sentiment_analyst
não tem mais tool de fetch, só recebe blocos pre-injected). Aqui aplicamos pattern
analogo: **CADA GATE TEM SLOT EXPLICITO. Se ausente, [TAG] ABSENT (reason). Nunca silent.**

## Design

### Build-GateStatusBlock

Toma `FullContext` PSCustomObject e retorna string multilinha:

```
=== GATE STATUS (this trade) ===
[FQS]          score=4/7 QUALITY (BLUE_CHIP=6+, AVOID<=1)
[BETA]         asset=1.115 portfolio_after_add=1.118 (cap 1.0 WARN, 1.2 BLOCK)
[DSR_HISTORY]  n_trades=23 dsr=0.42 sharpe_30d=2.1
[REGIME]       phase=phase_3_bear bias=neutral
[DRAWDOWN]     vs_peak=-3.2% level=GREEN streak=0
[TORI_PROX]    side=LONG proximity=2.3% line=100.5 touches=4 slope=22deg rsi=35 -> RIPENING
[MODE]         STANDARD
=== END GATE STATUS ===
```

Gates ausentes (FullContext sem campo OU campo null):

```
[FQS]          ABSENT (no data)
[BETA]         ABSENT (no beta_vs_btc.json entry)
[DSR_HISTORY]  ABSENT (no per_market entry in dsr_global.json)
[REGIME]       ABSENT (no regime_state.json)
[DRAWDOWN]     ABSENT (no tier_a_drawdown_*.json or market not in latest)
[TORI_PROX]    ABSENT (snapshot stale or no setup detected)
```

### Test-PromptForbiddenPhrases (smart guard)

Lista de forbidden phrases (Tauric-inspired ban list):
- `Mesa pulou` / `Mesa pulada` (trigger words que LLM echo)
- `FQS indisponivel` / `FQS nao declarado` / `FQS missing` (typical hallucinations)
- `alerta critico` (vague — exige gate name explicit)

**Smart detection**: phrase "FQS indisponivel" é forbidden APENAS se GATE STATUS
não tem `[FQS] ABSENT` (i.e., FQS estava DISPONÍVEL). Se gate é realmente ABSENT,
LLM tem razão em mencionar — não flagada.

### Wire em mentor_agent.ps1

1. **Pre-LLM**: `ctxBlock` agora usa `Build-GateStatusBlock` (com fallback graceful pro free-form se lib não loaded)
2. **Pós-LLM**: `Test-PromptForbiddenPhrases` em `result.mentor_mensagem` com smart context
3. Hallucination event logged em `journal/mentor_hallucinations.jsonl` type="forbidden_phrase"

## TDD Coverage

`tests/lib_mentor_gate_block.Tests.ps1` — **20/20 PASS**:

| Group | Tests | Coverage |
|---|---|---|
| Build-GateStatusBlock | 10 | All gates present / ABSENT variations / TORI ripening tags / MODE |
| Test-PromptForbiddenPhrases | 5 | Clean text / Mesa pulou / smart FQS detection / multiple phrases |
| Get-MentorForbiddenPhrasesList | 2 | Non-empty / contains expected phrase |
| Property: determinism | 1 | Same input → same block |
| Property: each gate appears 1x | 1 | Tag uniqueness |
| Property: ABSENT count consistency | 1 | N absent = N missing fields |

## Design decisions

1. **GATE STATUS over CONTEXTO**: structured block com brackets é mais parse-friendly
   pra LLM. Reduce ambiguidade. Tauric pattern.

2. **ABSENT always explicit (never silent omission)**: ataca root cause direto.
   LLM "vê" todo gate, mesmo se ausente. Não pode "esquecer" um gate.

3. **Smart forbidden detection (context-aware)**: evita false positive (LLM justificadamente
   menciona "FQS indisponivel" se gate é ABSENT). Detection só fires se gate tem valor.

4. **Fallback graceful**: se lib não loaded, mentor_agent usa free-form CONTEXTO antigo.
   Zero risco de break em prod.

5. **Pós-LLM logging (não block)**: forbidden phrase detection LOGA hallucination
   mas NÃO força ABORTAR. Razão: lib_mentor_hallucination_detector já existe e gerencia
   isso; esta é segunda camada de detection. Add-HallucinationEvent dual-event tipo
   "forbidden_phrase" complementa tipo "fqs_missing".

## Custo estimado

- Token overhead: ~+150 tokens/call (block é mais verboso que free-form). 
- Custo em Sonnet: ~$0.0005/call × 30 calls/day = **+$0.015/day** ($0.45/mes).
- ROI: 1 hallucination prevented = trade rescued = potential $5-$50 P&L. Pays itself.

## Forward links

- **E1 (Schema 5-tier)**: vai validar veredicto contra schema; falha = re-prompt com block reminder
- **E3 (Reflection)**: reflections cited prior decisions com GATE STATUS preservado

## Skill insight permanente

> **"Structured slots > free-form context para LLM grounding"**.
>
> LLM pode "esquecer" ou "inventar" baseado em ausência. Slot estruturado com
> [TAG] explicit ABSENT force LLM a confrontar a ausência. Pattern aplicável
> a TODO uso de LLM com structured data.
>
> Implementation: bracket-tagged blocks + ABSENT marker + smart guard que
> distingue justified mention vs hallucination via context check.

## Artefatos

- Código: [agents/lib_mentor_gate_block.ps1](../../agents/lib_mentor_gate_block.ps1)
- TDD: [tests/lib_mentor_gate_block.Tests.ps1](../../tests/lib_mentor_gate_block.Tests.ps1) (20 PASS)
- Wire: [agents/mentor_agent.ps1](../../agents/mentor_agent.ps1) (ctxBlock + post-LLM guard)
- Doc: este arquivo
