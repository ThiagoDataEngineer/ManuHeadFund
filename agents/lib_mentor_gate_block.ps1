# lib_mentor_gate_block.ps1 -- Grounded GATE STATUS block para prompt Mentor.
#
# E2 Grounded v2 (Tauric-inspired): substitui CONTEXTO free-form por bloco estruturado
# com [TAG] explicit. Cada gate ausente vira "[TAG] ABSENT (reason)" — nunca silent.
#
# Combat hallucination root: LLM nao pode dizer "FQS indisponivel" se o prompt
# explicitamente declara "[FQS] score=4/7 QUALITY". Se context diz ABSENT, eh
# real ausencia (e LLM cita "[FQS] ABSENT" textualmente).
#
# Tambem provee Test-PromptForbiddenPhrases — guard pos-resposta que detecta frases
# que indicam hallucination ou violacao de regras (Mesa pulou, FQS indisponivel,
# DSR como veto, etc). Ver MENTOR_FORBIDDEN_PHRASES abaixo.
#
# 4b 2026-05-28: adicionadas frases DSR/n_trades a MENTOR_FORBIDDEN_PHRASES.
# Problema: LLM usava "DSR n_trades=0 e track record inexistente" como razao de
# ABORTAR mesmo com [DSR_HISTORY] INFO-ONLY no gate block e regra 5 no system
# prompt. O guard nao detectava porque as frases nao estavam na lista.
# Fix: 9 frases adicionadas. Ver tests/dsr_forbidden_phrases.Tests.ps1 (38 testes).
#
# PS 5.1. UTF-8 BOM.


# ─── Forbidden phrases (Tauric-inspired ban list) ─────────────────────────────

$script:MENTOR_FORBIDDEN_PHRASES = @(
    "Mesa pulou",
    "Mesa pulada",
    "FQS indisponivel",
    "FQS nao declarado",
    "FQS missing",
    "alerta critico",  # use sempre com gate name explicit
    # 4b 2026-05-28: DSR/n_trades NAO sao gate de bloqueio.
    # LLM usava "DSR n_trades=0 e track record inexistente" como razao de ABORTAR
    # mesmo com [DSR_HISTORY] INFO-ONLY no gate block e regra 5 no system prompt.
    # Solucao: adicionar frases ao guard pos-resposta para detectar violacao.
    "track record inexistente",
    "track record zerado",
    "zero track record",
    "sem track record",        # cobre "sem track record validado/neste ativo/etc"
    "DSR n_trades=0",
    "n_trades=0 e track",
    "n_trades=0 elimina",
    "n_trades=0 significa"
    # NOTA: "track record validado" (afirmativo) NAO esta na lista -- falso positivo
    # em contextos como "track record validado por 15 trades". A negacao ja e coberta
    # por "sem track record" acima.
)


# ─── Build GATE STATUS block ──────────────────────────────────────────────────

function Build-GateStatusBlock {
    <#
    .SYNOPSIS
    Constroi bloco GATE STATUS estruturado a partir do FullContext.

    .DESCRIPTION
    Retorna string multi-linha:
      === GATE STATUS (this trade) ===
      [FQS]          score=4/7 QUALITY (BLUE_CHIP=6+, AVOID<=1)
      [BETA]         asset=1.115 portfolio_after_add=1.118 (cap 1.0 WARN, 1.2 BLOCK)
      [DSR_HISTORY]  n_trades=23 dsr=0.42 sharpe_30d=2.1
      [REGIME]       phase=phase_3_bear bias=neutral
      [DRAWDOWN]     vs_peak=-3.2% level=GREEN streak=0
      [TORI_PROX]    side=LONG proximity=2.3% ripening=true touches=4 slope=22deg
      === END GATE STATUS ===

    Gates ausentes (FullContext sem campo OU campo null) viram:
      [BETA]         ABSENT (no beta_vs_btc.json entry — enrich pending)

    Isso elimina ambiguidade do tipo "LLM disse 'beta indisponivel' mas ctx tinha beta".

    .PARAMETER FullContext
    PSCustomObject produzido por Build-MentorFullContext.

    .EXAMPLE
    $block = Build-GateStatusBlock -FullContext (Build-MentorFullContext -Market BTCUSDT)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSCustomObject] $FullContext)

    $lines = @("=== GATE STATUS (this trade) ===")

    # FQS
    if ($FullContext.PSObject.Properties['fqs'] -and $FullContext.fqs -and $null -ne $FullContext.fqs.score) {
        $lines += "[FQS]          score=$($FullContext.fqs.score)/7 $($FullContext.fqs.category) (BLUE_CHIP=6+, AVOID<=1)"
    } elseif ($FullContext.PSObject.Properties['fqs'] -and $FullContext.fqs -and $FullContext.fqs.category -eq "N/A_no_registry") {
        $lines += "[FQS]          ABSENT (market sem entry no registry -- enrich agendado)"
    } else {
        $lines += "[FQS]          ABSENT (no data)"
    }

    # BETA (2026-05-22 PM fix: cap dinamico phase-aware quando disponivel no payload)
    if ($FullContext.PSObject.Properties['beta'] -and $FullContext.beta) {
        $b = $FullContext.beta
        $portStr = if ($null -ne $b.portfolio_after) { " portfolio_after_add=$($b.portfolio_after)" } else { "" }
        $capStr = if ($b.PSObject.Properties['current_cap_block']) {
            "(phase=$($b.cap_phase) cap WARN=$($b.current_cap_warn) BLOCK=$($b.current_cap_block))"
        } else {
            "(cap 1.0 WARN, 1.2 BLOCK)"
        }
        $lines += "[BETA]         asset=$($b.asset)$portStr $capStr"
    } else {
        $lines += "[BETA]         ABSENT (no beta_vs_btc.json entry)"
    }

    # DSR_HISTORY -- INFORMATIVO apenas, nao e gate de bloqueio
    if ($FullContext.PSObject.Properties['historical'] -and $FullContext.historical) {
        $h = $FullContext.historical
        $lines += "[DSR_HISTORY]  n_trades=$($h.n_trades) dsr=$($h.dsr) sharpe_30d=$($h.sharpe_30d) [INFO-ONLY: nao bloqueia]"
    } else {
        $lines += "[DSR_HISTORY]  ABSENT [INFO-ONLY: nao bloqueia -- sistema em fase de acumulo de historico]"
    }

    # REGIME
    if ($FullContext.PSObject.Properties['regime'] -and $FullContext.regime) {
        $r = $FullContext.regime
        $biasStr = if ($r.bias) { " bias=$($r.bias)" } else { "" }
        $lines += "[REGIME]       phase=$($r.phase)$biasStr"
    } else {
        $lines += "[REGIME]       ABSENT (no regime_state.json)"
    }

    # DRAWDOWN
    if ($FullContext.PSObject.Properties['drawdown'] -and $FullContext.drawdown) {
        $d = $FullContext.drawdown
        $lines += "[DRAWDOWN]     vs_peak=$($d.vs_peak_pct)% level=$($d.level) streak=$($d.flag_streak)"
    } else {
        $lines += "[DRAWDOWN]     ABSENT (no tier_a_drawdown_*.json or market not in latest)"
    }

    # TORI_PROX
    if ($FullContext.PSObject.Properties['tori_proximity'] -and $FullContext.tori_proximity -and $FullContext.tori_proximity.valid) {
        $tp = $FullContext.tori_proximity
        $ripeningTag = if ($tp.setup_ripening) { "RIPENING" } else { "watch" }
        $lines += "[TORI_PROX]    side=$($tp.side) proximity=$($tp.proximity_pct)% line=$($tp.action_line) touches=$($tp.touches) slope=$($tp.slope_deg)deg rsi=$($tp.rsi) -> $ripeningTag"
    } else {
        $lines += "[TORI_PROX]    ABSENT (snapshot stale or no setup detected)"
    }

    # ALPHA_CORR (E4 refinement) — Beta rolling correlation vs BTC
    if ($FullContext.PSObject.Properties['alpha_correlation'] -and $FullContext.alpha_correlation) {
        $ac = $FullContext.alpha_correlation
        $status = if ($ac.pass) { "OK" } else { "DEMOTE" }
        $lines += "[ALPHA_CORR]   corr=$($ac.correlation) trend=$($ac.trend) status=$status"
    } else {
        $lines += "[ALPHA_CORR]   ABSENT (no rolling correlation data)"
    }

    # GATES (passed/total)
    if ($FullContext.PSObject.Properties['gates'] -and $FullContext.gates) {
        $g = $FullContext.gates
        $lines += "[GATES]        passed=$($g.passed)/$($g.total)"
    }

    # MODE (always present)
    if ($FullContext.PSObject.Properties['mode']) {
        $lines += "[MODE]         $($FullContext.mode)"
    }

    # TIME (A.6 2026-05-26) -- weekday/hour/session, weekend warning
    if ($FullContext.PSObject.Properties['time'] -and $FullContext.time -and (Get-Command Format-TimeContextLine -ErrorAction SilentlyContinue)) {
        try {
            $tline = Format-TimeContextLine -TimeContext $FullContext.time
            $lines += "[TIME]         $tline"
        } catch {}
    }

    # ALPHA_HISTORY (B.4 2026-05-26) -- avg alpha vs BTC + LOSING_TO_BTC flag
    if ($FullContext.PSObject.Properties['alpha_history'] -and $FullContext.alpha_history -and (Get-Command Format-AlphaHistoryLine -ErrorAction SilentlyContinue)) {
        try {
            $aline = Format-AlphaHistoryLine -Summary $FullContext.alpha_history
            $lines += "[ALPHA_HIST]   $aline"
        } catch {}
    }

    $lines += "=== END GATE STATUS ==="

    return ($lines -join "`n")
}


# ─── Forbidden phrases guard ──────────────────────────────────────────────────

function Test-PromptForbiddenPhrases {
    <#
    .SYNOPSIS
    Retorna PSCustomObject @{has_forbidden, found=@(...)}. Use no PROMPT antes
    de enviar pra LLM (sanity check) OU na RESPOSTA pos-LLM (hallucination guard).

    .DESCRIPTION
    Forbidden phrases sao patterns que indicam:
      (a) hallucination — "FQS indisponivel" quando gate status diz "[FQS] score=4"
      (b) trigger words que LLM eco anteriormente (Mesa pulou)

    Lista mantida em $script:MENTOR_FORBIDDEN_PHRASES.

    Caller decide o que fazer:
      - has_forbidden=$true + no contexto: re-prompt LLM
      - has_forbidden=$true + na resposta: log hallucination, force ABORTAR

    .PARAMETER Text
    Texto a verificar (prompt ou resposta).

    .PARAMETER GateStatusBlock
    Opcional: o GATE STATUS block atual. Permite "smart" detection — phrase
    so eh forbidden se gate NAO esta ABSENT.

    .EXAMPLE
    $r = Test-PromptForbiddenPhrases -Text $mentorResponse
    if ($r.has_forbidden) { Write-Warning "Hallucination: $($r.found -join ', ')" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [string] $GateStatusBlock = ""
    )

    # Pre-compute FQS line status (line-level check, evita PS -like char-class trap em [FQS])
    $fqsLineIsAbsent = $false
    if ($GateStatusBlock) {
        foreach ($line in ($GateStatusBlock -split "`r?`n")) {
            if ($line -match '^\s*\[FQS\]' -and $line -match 'ABSENT') {
                $fqsLineIsAbsent = $true
                break
            }
        }
    }

    $found = @()
    foreach ($phrase in $script:MENTOR_FORBIDDEN_PHRASES) {
        if ($Text -like "*$phrase*") {
            # Smart detection: phrase 'FQS indisponivel/missing/nao declarado' eh JUSTIFICADA
            # apenas se gate [FQS] estiver ABSENT no block. Senao = hallucination.
            if ($fqsLineIsAbsent -and $phrase -like "FQS*") {
                continue
            }
            $found += $phrase
        }
    }

    # Force array (PS 5.1: single-element += can upcast to scalar)
    $foundArr = @($found)
    return [PSCustomObject]@{
        has_forbidden = ($foundArr.Count -gt 0)
        found         = $foundArr
    }
}


function Get-MentorForbiddenPhrasesList {
    <#
    .SYNOPSIS
    Retorna lista atual de forbidden phrases (pra inspect em tests ou audit).
    #>
    return ,$script:MENTOR_FORBIDDEN_PHRASES
}
