# Design: Mentor LLM com poder de destravar gates de qualidade/sinal

**Data:** 2026-07-24
**Contexto:** Blueprint audit encontrou que o mentor LLM (`Invoke-MentorDebate`,
cascade Sonnet/Groq/Mistral/Haiku) nunca foi conectado ao executor real
(`gem_executor.ps1`). Owner aprovou dar ao LLM poder de veto real E de
destravar gates de qualidade/sinal, com 2 invariantes protegidas (não
negociáveis): stop loss obrigatório e cap de risco de 3%/trade continuam
sempre aplicados, fora do alcance do LLM (já implementados em
`a0f03f1` — fail-safe fecha posição sem proteção + hard cap 3% centralizado).

## Por que não reescrever a função inteira

`Invoke-GemExecute` (2284 linhas) tem 27 pontos de `return blocked` em
sequência, cada um dependendo de estado computado pelos anteriores
(`$direction`, `$btcScenario`, `$price`, `$stop_price`...). Reescrever
para "acumular decisões e resolver no final" mudaria a ordem de
avaliação e o timing dos side-effects (chamadas de API, gravação em
cache/journal) de forma que só um erro sutil revelaria em produção real
— inaceitável dado que abre ordens reais.

## Abordagem escolhida: interceptação pontual, não reescrita

Em vez de remover os `return`, cada um dos gates de **qualidade/sinal**
(12 dos 27 — ver tabela) passa a chamar uma função nova,
`Test-MentorOverride`, IMEDIATAMENTE ANTES do `return blocked`. Se o
mentor aprovar o override, o `return` não acontece e a função continua
seu fluxo normal (como se o gate tivesse passado). Se o mentor vetar,
falhar, ou timeout: comportamento idêntico ao atual (bloqueia, `return`
acontece exatamente como hoje). **A estrutura sequencial da função não
muda em nenhum outro aspecto.**

```powershell
# ANTES (exemplo: gate token_structural_quality, linha ~1861)
if ($structQuality.verdict -eq "BLOCK") {
    Write-Host "BLOQUEADO: ..." -ForegroundColor Red
    return [PSCustomObject]@{ blocked = $true; blocked_by = @("token_structural_quality:...") }
}

# DEPOIS
if ($structQuality.verdict -eq "BLOCK") {
    $override = Test-MentorOverride -Market $mkt -GateTag "token_structural_quality" `
        -GateReason $structQuality.reason -Direction $direction -Price $price `
        -Change24h $gemChange24h -Regime "$($btcScenario.scenario)"
    if (-not $override.approved) {
        Write-Host "BLOQUEADO: ..." -ForegroundColor Red
        return [PSCustomObject]@{ blocked = $true; blocked_by = @("token_structural_quality:...") }
    }
    Write-Host "  [MENTOR OVERRIDE] $mkt -- $($override.motivo)" -ForegroundColor Magenta
}
```

## Quais gates são elegíveis para override (12 de 27)

Baseado na categorização do blueprint audit — só QUALIDADE DE SINAL, nunca
SEGURANÇA/INFRAESTRUTURA nem CÁLCULO/VALIDAÇÃO:

| linha (aprox) | gate_tag | elegível? | motivo |
|---|---|---|---|
| 444 | `score_below_min` | SIM | qualidade de sinal (score do Gem) |
| 580 | `breadth/pump/entry_timing` | SIM | qualidade de sinal — maior volume de edge medido (`BEAR\|LONG\|breadth_long_blocked` n=62 hit_rate 67.7%) |
| 627 | `spike_BEARISH_G1B` | SIM | qualidade de sinal |
| 1082 | `cenario:$scenario` | SIM | qualidade de sinal (cenário BTC-core) |
| 1111 | `crowding` | SIM | qualidade de sinal |
| 1131 | `chart_pattern` | SIM | qualidade de sinal |
| 1186 | `tori_confluence` | SIM | qualidade de sinal |
| 1235 | `conviction_gate_failed` | SIM | qualidade de sinal |
| 1366 | `tori_skip/wait` | SIM | qualidade de sinal |
| 1489 | `no_direction_confidence` | SIM | qualidade de sinal |
| 1581 | `quality_gate` | SIM | qualidade de sinal |
| 1773 | `multi_tf_misalignment` | SIM | qualidade de sinal |
| 1861 | `token_structural_quality` | SIM | qualidade de sinal |
| **416** | `recent_decision_cache` | **NÃO** | infra (evita re-veto loop / custo LLM) |
| **426** | `circuit_breaker_daily_loss` | **NÃO** | proteção de capital agregada — NUNCA destravável |
| **623** | `sizing_invalido` | **NÃO** | cálculo/validação |
| **658** | `route_NONE_delisted` | **NÃO** | infra (mercado pode estar sendo deslistado) |
| **807** | `market_unsafe_coinex` | **NÃO** | infra (aviso da própria corretora) |
| **853/862** | `cascade_leverage/add_position_max` | **NÃO** | proteção de concentração |
| **884** | `gem_safety` | **NÃO** | proteção de exposição agregada |
| **918** | `exposure_cap` | **NÃO** | proteção de exposição agregada |
| **1254/1275** | `tori_unavailable/error` | **NÃO** | infra (falha de dado, fail-closed correto) |
| **1519** | `short_requires_futures_spot_only` | **NÃO** | cálculo/validação (impossibilidade técnica) |
| **1552** | `calculate_stoptarget_error` | **NÃO** | cálculo/validação |
| **1736** | `tp_validation_failed` | **NÃO** | cálculo/validação |
| **1921** | `entry_lock_held_by_other_engine` | **NÃO** | concorrência entre motores |
| **1955** | `leverage_adjust_failed` | **NÃO** | proteção contra leverage descontrolada (achado histórico: SUIUSDT 50x) |

## `Test-MentorOverride` — contrato

```powershell
function Test-MentorOverride {
    param(
        [string] $Market, [string] $GateTag, [string] $GateReason,
        [string] $Direction, [double] $Price, [double] $Change24h,
        [string] $Regime
    )
    # Retorna sempre [PSCustomObject]@{ approved=bool; motivo=string }
    # FAIL-CLOSED: qualquer excecao, timeout, ou LLM indisponivel -> approved=$false
    # (mantem o gate original bloqueando -- nunca abre por causa de falha do LLM)
}
```

Implementado em `agents/lib_mentor_live.ps1` (substitui/estende
`lib_mentor_shadow.ps1` da Fase 0), reaproveitando `Invoke-V6Cascade`
(Triagem→Mesa→Mentor) já validado na Fase 0. Diferença chave da Fase 0:
o resultado agora É USADO para decisão real, não só logado.

## Budget de chamadas por ciclo (mitigação do custo mapeado)

Pesquisa anterior mostrou até 1min+ por avaliação completa (Mesa 3
chamadas + Mentor até 2 chamadas). Para não estourar o ciclo de 5min:
- `Test-MentorOverride` só é chamado quando um gate de qualidade JÁ
  bloqueou (não em toda avaliação) — reduz drasticamente o volume vs.
  rodar em todo mercado escaneado.
- Orçamento máximo de overrides por ciclo via
  `journal/MENTOR_OVERRIDE_BUDGET.flag` (ex: conteúdo "3" = no máximo 3
  chamadas de override por execução do `gem_executor.ps1`) — acima do
  budget, `Test-MentorOverride` retorna `approved=$false` sem sequer
  chamar o LLM.

## Gated por flag — liga/desliga sem novo deploy

`journal/MENTOR_OVERRIDE_ENABLED.flag` — ausência = `Test-MentorOverride`
retorna `approved=$false` imediatamente (comportamento idêntico ao
sistema atual, 100% determinístico). Presença = ativa a consulta real ao
LLM nos 12 gates elegíveis.

## Plano de teste (TDD) antes do commit

1. Testes unitários de `Test-MentorOverride` (mock de `Invoke-V6Cascade`):
   aprova, veta, timeout/exceção (deve ser fail-closed), budget excedido.
2. Testes de integração por gate elegível: confirma que o `return blocked`
   original AINDA acontece quando `Test-MentorOverride` nega (regressão
   zero no comportamento determinístico quando o flag está ausente).
3. Rodar suite completa de `gem_executor.Tests.ps1` e afins — zero
   regressão obrigatória antes de qualquer commit.
