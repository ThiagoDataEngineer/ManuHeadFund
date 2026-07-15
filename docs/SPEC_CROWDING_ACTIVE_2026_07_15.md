# SPEC: Crowding/funding de SHADOW para ATIVO — gate 1d em gem_executor.ps1

> Escrita 2026-07-15 para implementação por agente executor. Âncoras referem-se
> ao commit `3f860b7`. Se linhas mudaram, buscar pelos textos-âncora.

## Contexto (por quê)

`agents/lib_crowding_signal.ps1` implementa o sinal de crowding via funding rate
com **evidência real** (estudo 2026-07-04, n=5.133 observações, 59 futures):
- funding ≥ +0.10%/período → retorno fwd 24h mediana **-0.73%** (baseline -0.15%),
  SHORT acerta 56% → `CROWDED_LONGS` (short_boost=true, long_caution=true)
- funding ≤ -0.10% → fwd24h -0.83%, LONG acerta só **43%** → `CROWDED_SHORTS`
  (long_caution=true; NÃO habilita long — knife-catching)

Hoje o sinal é **SHADOW**: alimenta só o prompt do mentor (`Get-CrowdingBlock`)
e o log `journal/crowding_shadow.jsonl`. Caso real medido: WAVESUSDT foi logada
`CROWDED_LONGS funding 0.43-0.47%` dias antes de cair -18% — o sinal previu, mas
nada agiu. Esta spec promove a parte de PROTEÇÃO a gate ativo.

## Objetivo (escopo v1 — deliberadamente contido)

No `agents/gem_executor.ps1`, inserir gate **1d CROWDING** logo após o gate 1c
(CENARIO):
- **LONG + long_caution → BLOQUEIA** (proteção com evidência: 43-46% win = edge
  negativo).
- **SHORT + short_boost → apenas LOGA** `[CROWDING] short_boost` (telemetria pra
  calibrar boost de conviction num v2 — NÃO alterar conviction nesta versão).
- Sinal indisponível/NEUTRAL → no-op silencioso (fail-open, não trava por dado
  ausente).

## Mudança exata — `agents/gem_executor.ps1`

**Âncora de inserção:** o fechamento do gate 1c. Localizar EXATAMENTE estas
linhas consecutivas (aprox. linhas 856-858 no commit 3f860b7):

```powershell
            Write-Host "  [CENARIO OK] ${mkt}: $($scen.scenario) -> $($scen.strategy) (libera $dirForGate)" -ForegroundColor DarkGray
        } catch { Write-Host "  [CENARIO] ${mkt}: check falhou (fallback allow): $_" -ForegroundColor Yellow }
    }
```

Inserir IMEDIATAMENTE APÓS o `}` final acima (antes do comentário
`# ── 2. CHART PATTERN GATE`):

```powershell

    # ── 1d. CROWDING GATE (2026-07-15: shadow -> ativo) ──
    # Evidencia n=5133 (ESTUDO 2026-07-04, lib_crowding_signal.ps1): funding
    # extremo+ -> fwd24h -0.73% e LONG vira edge negativo (43-46% win). Caso
    # real: WAVESUSDT logada CROWDED_LONGS (funding 0.43%) dias antes de -18%
    # -- o shadow previu, nada agiu. v1: LONG+long_caution = BLOCK;
    # SHORT+short_boost = so log (boost de conviction fica pro v2, apos
    # observar telemetria). Fail-open: sem funding/futures -> no-op.
    if (-not (Get-Command Get-CrowdingSignal -ErrorAction SilentlyContinue)) {
        $crowdLibPath = Join-Path $PSScriptRoot "lib_crowding_signal.ps1"
        if (Test-Path $crowdLibPath) { . $crowdLibPath }
    }
    if (Get-Command Get-CrowdingSignal -ErrorAction SilentlyContinue) {
        try {
            $crowd = Get-CrowdingSignal -Market $mkt
            if ($crowd -and $crowd.available) {
                $dirCrowd = "$($Gem.direction)".ToUpper()
                if ($dirCrowd -notin @("LONG","SHORT")) { $dirCrowd = "LONG" }
                if ($dirCrowd -eq "LONG" -and $crowd.long_caution) {
                    Write-Host "  [CROWDING BLOCK] ${mkt}: $($crowd.crowding) funding=$($crowd.funding_pct)% -- LONG edge negativo (hist 43-46% win)" -ForegroundColor Red
                    try { Send-TelegramAlert -Message "GEM bloqueado ${mkt}: crowding $($crowd.crowding) (funding $($crowd.funding_pct)%) -> LONG sem edge" | Out-Null } catch {}
                    if (Get-Command Add-GemRejection -ErrorAction SilentlyContinue) {
                        try { Add-GemRejection -Path (Join-Path $global:JOURNAL_DIR "gem_recent_decisions.json") -Market $mkt -Reason "crowding:$($crowd.crowding)" } catch {}
                    }
                    return [PSCustomObject]@{ blocked = $true; blocked_by = @("crowding:$($crowd.crowding)"); market = $mkt }
                }
                if ($dirCrowd -eq "SHORT" -and $crowd.short_boost) {
                    Write-Host "  [CROWDING] ${mkt}: short_boost ativo ($($crowd.crowding) funding=$($crowd.funding_pct)%) -- telemetria v1, sem alterar conviction" -ForegroundColor DarkYellow
                }
            }
        } catch { }
    }
```

Nota sobre `$dirCrowd`: usa `$Gem.direction` por VALOR (funciona pra hashtable e
PSCustomObject — mesma lição do bug 2026-07-09 documentado no gate 1c). NÃO usar
`$dirForGate` — essa variável é definida dentro do bloco 1c e pode não existir se
`Get-MarketScenario` estiver indisponível; o gate 1d deve ser independente.

## Regras INEGOCIÁVEIS

1. **PS 5.1**: proibido `??`, ternário `?:`, `?.`.
2. **NUNCA sed/regex-replace em massa** — Edit tool com old_string/new_string
   exatos.
3. **Fail-open** (não fail-closed): sem funding/sem futures/erro de API → no-op.
   Diferente dos gates fail-closed: crowding é REFINAMENTO, não segurança básica.
4. **Não tocar** nos gates 1c/2 existentes — inserção pura entre eles.
5. **Não alterar conviction/score** nesta versão (v1 = block LONG + log SHORT).

## Validação obrigatória (nesta ordem)

1. Parse PS5.1 de `agents/gem_executor.ps1` → 0 erros.
2. Baseline Pester ANTES e DEPOIS (idêntico):
   `Invoke-Pester -Script tests/gate_invariants_static.Tests.ps1, tests/lib_market_scenario.Tests.ps1 -PassThru`
   (Pester 3.4; há 1 falha pré-existente `ArgumentNullException` no
   gate_invariants — o critério é resultado IGUAL antes/depois, não zero).
3. `git diff agents/gem_executor.ps1` completo no relatório. NÃO commitar/push.

## Critério de sucesso

- Gate 1d presente entre 1c e o CHART PATTERN GATE; parse limpo; Pester
  idêntico ao baseline; LONG bloqueado só quando `available && long_caution`;
  SHORT nunca bloqueado por este gate (só log).
