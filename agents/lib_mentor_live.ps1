# lib_mentor_live.ps1 -- Mentor LLM com poder REAL de destravar gates de
# qualidade/sinal (ver docs/DESIGN_MENTOR_LLM_OVERRIDE_2026_07_24.md).
#
# Contrato NAO-NEGOCIAVEL:
# - FAIL-CLOSED: qualquer excecao/timeout/LLM indisponivel -> approved=$false
#   (gate original continua bloqueando, nunca abre por falha do LLM).
# - So gates de QUALIDADE/SINAL sao elegiveis (whitelist abaixo, defesa em
#   profundidade -- mesmo que o caller passe um GateTag errado). Gates de
#   SEGURANCA/INFRAESTRUTURA e CALCULO/VALIDACAO NUNCA sao destravaveis:
#   circuit_breaker_daily_loss, exposure_cap, entry_lock_held_by_other_engine,
#   leverage_adjust_failed, cascade_leverage_max, cascade_add_position_max,
#   gem_safety, route_NONE_delisted, market_unsafe_coinex, tori_unavailable,
#   tori_error, sizing_invalido, short_requires_futures_spot_only,
#   calculate_stoptarget_error, tp_validation_failed, recent_decision_cache.
# - Sem journal/MENTOR_OVERRIDE_ENABLED.flag = no-op total, approved=$false
#   sempre, sem tentar carregar nada (comportamento deterministico hoje
#   preservado 100%).
# - Budget por ciclo via journal/MENTOR_OVERRIDE_BUDGET.flag (numero de
#   overrides permitidos por execucao do processo) -- acima do budget,
#   nega sem chamar o LLM (custo/latencia controlados).

# 2026-07-25 FIX (achado no 2o ciclo real, run 30145266606): dot-source
# DENTRO de uma funcao define as funcoes carregadas so no escopo LOCAL
# dessa funcao -- mesmo bug documentado no comentario de topo de
# lib_loader_auto.ps1 ("dot-source dentro de funcao -> nao visivel pro
# caller"). Antes, o dot-source de mentor_agent.ps1/mesa_agent.ps1/
# triagem_agent.ps1/orchestrator_v6.ps1 rodava dentro de
# _Import-MentorLiveDependencies -- Invoke-V6Cascade "existia" ali dentro
# (confirmava sucesso) mas sumia assim que a funcao retornava, causando
# "The term 'Invoke-V6Cascade' is not recognized" na chamada real dentro
# de Test-MentorOverride. Fix: dot-source AQUI, no nivel de modulo do
# arquivo (fora de qualquer funcao) -- herda o escopo de quem fizer
# ". lib_mentor_live.ps1" (gem_executor.ps1), igual o padrao ja usado por
# lib_loader_auto.ps1. So carrega se ainda nao existir Invoke-V6Cascade
# (evita custo de I/O redundante quando ja veio de outro caminho).
if (-not (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue)) {
    try {
        . (Join-Path $PSScriptRoot "mentor_agent.ps1")
        . (Join-Path $PSScriptRoot "mesa_agent.ps1")
        . (Join-Path $PSScriptRoot "triagem_agent.ps1")
        . (Join-Path $PSScriptRoot "orchestrator_v6.ps1")
    } catch {
        Write-Host "  [MENTOR LIVE WARN] falha ao carregar dependencias: $_" -ForegroundColor DarkYellow
    }
}

$script:__mentorLiveLibsLoaded = $null -ne (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue)
$script:__mentorOverrideCallsThisRun = 0

# Gates de QUALIDADE/SINAL elegiveis pra override (ver design doc, tabela
# completa dos 27 gates categorizados). Qualquer tag fora desta lista e'
# negada sem consultar o LLM.
$script:MENTOR_OVERRIDE_ELIGIBLE_GATES = @(
    "score_below_min",
    "breadth_long_blocked", "breadth_short_blocked",
    "pump_long_blocked", "pump_short_blocked", "entry_timing_skip",
    "spike_BEARISH_G1B",
    "cenario",
    "crowding",
    "chart_pattern",
    "tori_confluence",
    "conviction_gate_failed",
    "tori_skip", "tori_wait",
    "no_direction_confidence",
    "quality_gate",
    "multi_tf_misalignment",
    "token_structural_quality"
)

function _Test-MentorOverrideGateEligible {
    param([string] $GateTag)
    foreach ($eligible in $script:MENTOR_OVERRIDE_ELIGIBLE_GATES) {
        if ($GateTag -like "$eligible*" -or $GateTag -eq $eligible) { return $true }
    }
    return $false
}

function Test-MentorOverride {
    <#
    .SYNOPSIS
    Consulta o mentor LLM real (via Invoke-V6Cascade) para decidir se um
    gate de qualidade/sinal que JA bloqueou deve ser destravado. Chamado
    imediatamente ANTES do "return blocked" de cada gate elegivel -- nunca
    substitui a estrutura de controle da funcao chamadora.

    .OUTPUTS
    [PSCustomObject]@{ approved=bool; motivo=string }
    approved=$false em QUALQUER cenario de duvida (fail-closed).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $GateTag,
        [Parameter(Mandatory)] [string] $GateReason,
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [double] $Price,
        [double] $Change24h = 0,
        [string] $Regime = "UNKNOWN",
        [string] $FlagDir = ""
    )

    # 2026-07-25 FIX (achado no 1o ciclo real em producao): sem log explicito
    # em cada caminho de negacao, era impossivel diferenciar no log do
    # executor se o mentor foi consultado e negou, ou se nunca chegou a ser
    # chamado por erro/flag ausente -- opacidade total. Todo deny agora loga.
    $deny = {
        param($motivo)
        Write-Host "  [MENTOR OVERRIDE DENY] $Market/$GateTag -- $motivo" -ForegroundColor DarkGray
        [PSCustomObject]@{ approved = $false; motivo = $motivo }
    }.GetNewClosure()

    $journalDir = if ($FlagDir) { $FlagDir }
                  elseif ($global:JOURNAL_DIR) { $global:JOURNAL_DIR }
                  else { Join-Path $PSScriptRoot "..\journal" }

    $flagPath = Join-Path $journalDir "MENTOR_OVERRIDE_ENABLED.flag"
    if (-not (Test-Path $flagPath)) { return (& $deny "flag MENTOR_OVERRIDE_ENABLED ausente ($flagPath)") }

    if (-not (_Test-MentorOverrideGateEligible -GateTag $GateTag)) {
        return (& $deny "gate '$GateTag' nao elegivel para override (seguranca/infra/calculo)")
    }

    $budgetPath = Join-Path $journalDir "MENTOR_OVERRIDE_BUDGET.flag"
    $budget = 3
    if (Test-Path $budgetPath) {
        try {
            $budgetRaw = (Get-Content $budgetPath -Raw).Trim()
            if ($budgetRaw -match '^\d+$') { $budget = [int]$budgetRaw }
        } catch {}
    }
    if ($script:__mentorOverrideCallsThisRun -ge $budget) {
        return (& $deny "budget de overrides do ciclo excedido ($budget)")
    }

    if (-not $script:__mentorLiveLibsLoaded) {
        return (& $deny "dependencias do mentor (Invoke-V6Cascade) indisponiveis")
    }

    try {
        $script:__mentorOverrideCallsThisRun++

        # 2026-07-26 FIX: mentor_agent.ps1 tenta ler beta_history do Supabase
        # ANTES de montar o prompt do Mentor, mas nada nunca escrevia nessa
        # tabela em producao real -- Sync-AllBetasMultiTF (lib_beta_calculator_
        # multitf.ps1) so era chamado por scan_master.ps1, que NAO roda em
        # nenhum job do pipeline atual desde o refactor de 07-15 (substituido
        # por gem_scanner_executor_live.ps1/gem_loop.ps1). Resultado: "beta
        # ausente" aparecia em quase todo veto do Mentor. Fix: sincroniza o
        # beta do MERCADO ESPECIFICO aqui -- so quando o Mentor de fato vai
        # ser consultado (ja passou flag/gate-eligible/budget acima), nao
        # para todo candidato escaneado. Fail-soft: falha aqui nao bloqueia
        # a consulta ao Mentor, so significa que ele decide sem esse dado
        # (comportamento identico ao que ja acontecia antes deste fix).
        if (-not (Get-Command Get-BetaMultiTF -ErrorAction SilentlyContinue)) {
            try { . (Join-Path $PSScriptRoot "lib_beta_calculator_multitf.ps1") } catch {}
        }
        if (Get-Command Get-BetaMultiTF -ErrorAction SilentlyContinue) {
            try {
                $betaData = Get-BetaMultiTF -Market $Market
                if ($betaData.beta_weighted -and (Get-Command Publish-BetaToSupabase -ErrorAction SilentlyContinue)) {
                    Publish-BetaToSupabase -Market $Market -BetaData $betaData | Out-Null
                }
            } catch {
                Write-Host "  [MENTOR LIVE] beta sync falhou p/ ${Market} (nao bloqueia consulta): $_" -ForegroundColor DarkYellow
            }
        }

        $context = [PSCustomObject]@{
            pair_change_24h  = $Change24h
            mode             = "GEM"
            source           = "GEM"
            regime           = $Regime
            scanner_score    = 50
            scanner          = [PSCustomObject]@{ score = 50; change = $Change24h }
            macro            = [PSCustomObject]@{ macro_bias = "NEUTRAL" }
            seasonal         = [PSCustomObject]@{ dayOfWeek = (Get-Date).DayOfWeek.ToString(); marketTier = "alt"; momentScore = 50 }
            day_of_week_brt  = [int](Get-Date).DayOfWeek
        }

        $stopPct = [math]::Abs($Change24h) * 0.5
        if ($stopPct -lt 2.0) { $stopPct = 2.0 }
        if ($stopPct -gt 8.0) { $stopPct = 8.0 }
        $rr = 5.0
        $setup = if ($Direction -eq "SHORT") {
            [PSCustomObject]@{
                entry = $Price
                stop   = [math]::Round($Price * (1 + $stopPct / 100), 6)
                target = [math]::Round($Price * (1 - $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        } else {
            [PSCustomObject]@{
                entry  = $Price
                stop   = [math]::Round($Price * (1 - $stopPct / 100), 6)
                target = [math]::Round($Price * (1 + $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        }

        $cascade = Invoke-V6Cascade -Market $Market -Context $context -Setup $setup

        if ($cascade.decisao -eq "ABORTAR") {
            return (& $deny "cascade abortou: $($cascade.motivo)")
        }
        if (-not $cascade.mentor -or $cascade.mentor.decision -ne "APROVAR") {
            $mentorDec = if ($cascade.mentor) { [string]$cascade.mentor.decision } else { "sem_mentor" }
            return (& $deny "mentor decision=$mentorDec (gate original: $GateReason)")
        }

        $logPath = Join-Path $journalDir "mentor_override_log.jsonl"
        try {
            $entry = [ordered]@{
                ts_utc     = (Get-Date).ToUniversalTime().ToString("o")
                market     = $Market
                gate_tag   = $GateTag
                gate_reason = $GateReason
                direction  = $Direction
                mentor_confidence = $cascade.mentor.confidence
            }
            Add-Content -Path $logPath -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
        } catch {}

        return [PSCustomObject]@{
            approved = $true
            motivo   = "mentor APROVAR (confidence=$($cascade.mentor.confidence)) destravou gate '$GateTag'"
        }
    } catch {
        return (& $deny "excecao na cascade: $($_.Exception.Message)")
    }
}
