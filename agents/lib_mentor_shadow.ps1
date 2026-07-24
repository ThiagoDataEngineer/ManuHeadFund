# lib_mentor_shadow.ps1 -- Fase 0 do plano de integracao do Mentor LLM
# (Sonnet/Groq/Mistral com debate + deteccao de alucinacao, ver
# agents/mentor_agent.ps1::Invoke-MentorDebate).
#
# Achado 2026-07-24: o mentor LLM completo (Invoke-MentorDebate, via
# Invoke-V6Cascade em orchestrator_v6.ps1) nunca foi conectado ao executor
# real (gem_executor.ps1) -- decisao de entrada roda 100% deterministica
# hoje. Antes de dar poder de veto ao LLM, esta Fase 0 so REGISTRA o que o
# LLM teria decidido, comparando com a decisao real, sem influenciar nada.
#
# Contrato: Invoke-MentorShadowObservation NUNCA deve afetar a execucao real
# (nunca lanca excecao pro chamador, nunca modifica $usd_size/$direction/
# bloqueio). Gated por journal/MENTOR_SHADOW_ENABLED.flag -- ausencia do
# flag = no-op total (nem tenta rodar, nem faz dot-source das libs pesadas).

$script:__mentorShadowLibsLoaded = $false

function _Import-MentorShadowDependencies {
    if ($script:__mentorShadowLibsLoaded) { return $true }
    if (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue) {
        $script:__mentorShadowLibsLoaded = $true
        return $true
    }
    try {
        . (Join-Path $PSScriptRoot "mentor_agent.ps1")
        . (Join-Path $PSScriptRoot "mesa_agent.ps1")
        . (Join-Path $PSScriptRoot "triagem_agent.ps1")
        . (Join-Path $PSScriptRoot "orchestrator_v6.ps1")
        $script:__mentorShadowLibsLoaded = $null -ne (Get-Command Invoke-V6Cascade -ErrorAction SilentlyContinue)
        return $script:__mentorShadowLibsLoaded
    } catch {
        Write-Host "  [MENTOR SHADOW WARN] falha ao carregar dependencias: $_" -ForegroundColor DarkYellow
        return $false
    }
}

function Invoke-MentorShadowObservation {
    <#
    .SYNOPSIS
    Roda a cascade Triagem->Mesa->Mentor (orchestrator_v6.ps1) em modo
    observacao pura e loga o resultado vs a decisao real do gem_executor.
    Falha sempre silenciosa -- nunca deve afetar o caminho de execucao real.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $RealDirection,
        [Parameter(Mandatory)] [double] $RealPrice,
        [Parameter(Mandatory)] [double] $RealUsdSize,
        [double] $Change24h = 0,
        [string] $Regime = "UNKNOWN"
    )

    $flagPath = Join-Path $PSScriptRoot "..\journal\MENTOR_SHADOW_ENABLED.flag"
    if (-not (Test-Path $flagPath)) { return }

    if (-not (_Import-MentorShadowDependencies)) { return }

    try {
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
        $setup = if ($RealDirection -eq "SHORT") {
            [PSCustomObject]@{
                entry  = $RealPrice
                stop   = [math]::Round($RealPrice * (1 + $stopPct / 100), 6)
                target = [math]::Round($RealPrice * (1 - $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        } else {
            [PSCustomObject]@{
                entry  = $RealPrice
                stop   = [math]::Round($RealPrice * (1 - $stopPct / 100), 6)
                target = [math]::Round($RealPrice * (1 + $stopPct * $rr / 100), 6)
                rr     = $rr
            }
        }

        $started = Get-Date
        $cascade = Invoke-V6Cascade -Market $Market -Context $context -Setup $setup
        $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds

        $llmDecision = if ($cascade.decisao -eq "ABORTAR") { "SKIP" }
                       elseif ($cascade.mentor -and $cascade.mentor.decision) { [string]$cascade.mentor.decision }
                       else { "UNKNOWN" }

        $entry = [ordered]@{
            ts_utc         = (Get-Date).ToUniversalTime().ToString("o")
            market         = $Market
            real_direction = $RealDirection
            real_usd_size  = $RealUsdSize
            llm_decision   = $llmDecision
            llm_motivo     = [string]$cascade.motivo
            triagem_tier   = if ($cascade.triagem) { [string]$cascade.triagem.tier } else { $null }
            mesa_consensus = if ($cascade.mesa) { [string]$cascade.mesa.consensus } else { $null }
            elapsed_ms     = $elapsedMs
            agrees_with_real = ($llmDecision -eq "APROVAR")
        }

        $logPath = Join-Path $PSScriptRoot "..\journal\mentor_shadow_log.jsonl"
        Add-Content -Path $logPath -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    } catch {
        # Fase 0 e' observacao pura -- qualquer falha aqui NUNCA deve
        # propagar pro executor real. So loga um warning leve.
        Write-Host "  [MENTOR SHADOW WARN] $_" -ForegroundColor DarkYellow
    }
}
