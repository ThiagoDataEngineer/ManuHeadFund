# lib_short_pipeline_advanced.ps1 — SHORT Pipeline: Fase-based ramp-up
# PROBLEMA: Hoje 0/4 pass em BEAR_STRONG — SHORT muito arriscado sem validação
# SOLUÇÃO: 4 fases com requerimentos cada vez mais rígidos

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Get-ShortPhase {
    <#
    .SYNOPSIS
    Determina em qual FASE do SHORT pipeline você está baseado no histórico.
    Fase 0: BLOCKED (BEAR regime, não testado)
    Fase 1: PILOT (2% max loss, 50% posição, 3+ wins)
    Fase 2: RAMP (4% max loss, full position, 7+ wins)
    Fase 3: FULL (unlimited, proven edge)
    #>
    param(
        [Parameter(Mandatory)] [string] $Regime,
        [array] $ShortTradeHistory = @(),
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    # === FASE 0: BLOCKED em BEAR ===
    if ($Regime -match "BEAR") {
        return [PSCustomObject]@{
            phase = 0
            name = "BLOCKED"
            reason = "BEAR regime: SHORT não aprovado"
            max_loss_pct = 0
            max_position_pct = 0
            min_wins_required = 0
            status = "BLOCKED"
            next_unlock = "Aguarde regime mudar para BULL/SIDEWAYS"
        }
    }

    # === FASE 1: PILOT ===
    $shortWins = ($ShortTradeHistory | Where-Object { $_.direction -eq "SHORT" -and $_.win }).Count
    $shortTotal = ($ShortTradeHistory | Where-Object { $_.direction -eq "SHORT" }).Count
    $shortWinRate = if ($shortTotal -gt 0) { $shortWins / $shortTotal } else { 0 }

    if ($shortTotal -lt 3) {
        return [PSCustomObject]@{
            phase = 1
            name = "PILOT"
            reason = "Testando SHORT em pequena escala"
            max_loss_pct = 2.0
            max_position_pct = 0.5
            min_wins_required = 3
            current_wins = $shortTotal
            win_rate = [Math]::Round($shortWinRate, 3)
            status = "ACTIVE"
            next_unlock = "Precisa de 3+ SHORT wins pra avançar"
        }
    }

    # === FASE 2: RAMP ===
    if ($shortWins -ge 3 -and $shortWins -lt 7) {
        return [PSCustomObject]@{
            phase = 2
            name = "RAMP"
            reason = "SHORT validado, aumentando escala"
            max_loss_pct = 4.0
            max_position_pct = 1.0
            min_wins_required = 7
            current_wins = $shortWins
            win_rate = [Math]::Round($shortWinRate, 3)
            status = "ACTIVE"
            next_unlock = "Precisa de 7+ SHORT wins pra FULL mode"
        }
    }

    # === FASE 3: FULL ===
    if ($shortWins -ge 7) {
        return [PSCustomObject]@{
            phase = 3
            name = "FULL"
            reason = "SHORT edge comprovado"
            max_loss_pct = 10.0
            max_position_pct = 2.0
            min_wins_required = 7
            current_wins = $shortWins
            win_rate = [Math]::Round($shortWinRate, 3)
            status = "ACTIVE"
            next_unlock = "N/A — Full mode ativado"
        }
    }
}

function Test-ShortApproval {
    <#
    .SYNOPSIS
    Valida se SHORT entra pode ser aprovado nesta fase.
    Checklist:
    1. Regime não é BEAR
    2. Mentor conviction >= 70
    3. Confluence >= 3/5
    4. Position size respeitando fase limit
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Regime,
        [Parameter(Mandatory)] [double] $MentorConviction,
        [Parameter(Mandatory)] [int] $ConfluenceCount,
        [Parameter(Mandatory)] [double] $ProposedSizeUsd,
        [Parameter(Mandatory)] [double] $MaxPositionUsd,
        [array] $ShortTradeHistory = @(),
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $shortLogPath = Join-Path $JournalDir "short_pipeline_audit.jsonl"

    # Obter fase
    $phase = Get-ShortPhase -Regime $Regime -ShortTradeHistory $ShortTradeHistory -JournalDir $JournalDir

    # === Checklist ===
    $checks = @{
        regime_ok = $phase.phase -gt 0
        conviction_ok = $MentorConviction -ge 70
        confluence_ok = $ConfluenceCount -ge 3
        size_ok = $ProposedSizeUsd -le $MaxPositionUsd
    }

    $approved = $checks.regime_ok -and $checks.conviction_ok -and $checks.confluence_ok -and $checks.size_ok
    $reason = @()
    if (-not $checks.regime_ok) { $reason += "Regime bloqueado (BEAR)" }
    if (-not $checks.conviction_ok) { $reason += "Conviction $MentorConviction < 70" }
    if (-not $checks.confluence_ok) { $reason += "Confluence $ConfluenceCount < 3" }
    if (-not $checks.size_ok) { $reason += "Size $ProposedSizeUsd > limit $MaxPositionUsd" }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        phase = $phase.phase
        phase_name = $phase.name
        approved = $approved
        reason = if ($reason) { $reason -join " | " } else { "OK — aprovado" }
        mentor_conviction = $MentorConviction
        confluence_count = $ConfluenceCount
        proposed_size_usd = $ProposedSizeUsd
        max_position_usd = $MaxPositionUsd
        regime = $Regime
    } | ConvertTo-Json -Compress

    Add-Content -Path $shortLogPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        approved = $approved
        phase = $phase.phase
        phase_name = $phase.name
        reason = if ($reason) { $reason -join " | " } else { "OK" }
        max_loss_pct = $phase.max_loss_pct
        max_position_pct = $phase.max_position_pct
        timestamp = $timestamp
    }
}

function Invoke-ShortRiskCheck {
    <#
    .SYNOPSIS
    Verifica se SHORT atual respeita stop loss da fase.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $StopLossPrice,
        [Parameter(Mandatory)] [double] $MaxLossPctPhase,
        [Parameter(Mandatory)] [double] $AccountBalance
    )

    $actualLossPct = [Math]::Abs(($StopLossPrice - $EntryPrice) / $EntryPrice) * 100
    $passes = $actualLossPct -le $MaxLossPctPhase

    return [PSCustomObject]@{
        market = $Market
        entry_price = $EntryPrice
        stoploss_price = $StopLossPrice
        actual_loss_pct = [Math]::Round($actualLossPct, 2)
        max_loss_pct_phase = [Math]::Round($MaxLossPctPhase, 2)
        passes = $passes
        reason = if ($passes) {
            "OK — $actualLossPct% <= $MaxLossPctPhase%"
        } else {
            "REJECTED — $actualLossPct% > $MaxLossPctPhase%"
        }
    }
}
