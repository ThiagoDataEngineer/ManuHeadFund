# lib_gate_audit.ps1 -- Gate chain orchestrator + audit trail
# Objetivo: Centralizar TODA decisao de gate (pre-trade) e registrar em journal/gate_audit_trail.jsonl
# Cada gate result == auditavel, fail-closed

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-AllGates {
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $VolumeUsd,
        [Parameter(Mandatory)] [double] $EquityTodayPct,
        [Parameter(Mandatory)] [int] $CurrentTierACount,
        [string[]] $CurrentTierAMarkets = @(),
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $tradeId = "$Market-$(New-Guid)"
    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $auditTrailPath = Join-Path $JournalDir "gate_audit_trail.jsonl"

    # Array de resultados dos gates
    $gateResults = @()
    $allPass = $true
    $blockReasons = @()

    # GATE 1: Concentration Limit (max 17 Tier A live)
    $gate1 = Test-ConcentrationLimitGate -CurrentTierACount $CurrentTierACount -Market $Market
    $gateResults += $gate1
    if (-not $gate1.passes) { $allPass = $false; $blockReasons += $gate1.reason }

    # GATE 2: Minimum Volume
    $gate2 = Test-MinVolumeGate -VolumeUsd $VolumeUsd -Market $Market
    $gateResults += $gate2
    if (-not $gate2.passes) { $allPass = $false; $blockReasons += $gate2.reason }

    # GATE 3: Daily Loss Circuit
    $gate3 = Test-DailyLossCircuitGate -EquityTodayPct $EquityTodayPct -Market $Market
    $gateResults += $gate3
    if (-not $gate3.passes) { $allPass = $false; $blockReasons += $gate3.reason }

    # Registra CADA gate result em audit trail
    foreach ($gate in $gateResults) {
        $auditEntry = [ordered]@{
            timestamp = $timestamp
            trade_id = $tradeId
            market = $Market
            gate_name = $gate.gate_name
            passes = $gate.passes
            reason = $gate.reason
            details = $gate.details
        } | ConvertTo-Json -Compress

        Add-Content -Path $auditTrailPath -Value $auditEntry -Encoding UTF8
    }

    # Resultado final
    $finalDecision = if ($allPass) { "ENTER" } else { "BLOCKED" }
    $blockReason = if ($blockReasons.Count -gt 0) { ($blockReasons -join " | ") } else { "" }

    return [PSCustomObject]@{
        passes = $allPass
        reason = $blockReason
        final_decision = $finalDecision
        gates_results = $gateResults
        gate_audit_trail_path = $auditTrailPath
        trade_id = $tradeId
    }
}

function Test-ConcentrationLimitGate {
    param(
        [int] $CurrentTierACount,
        [string] $Market
    )

    $MAX_TIER_A = 17
    $passes = $CurrentTierACount -le $MAX_TIER_A

    return [PSCustomObject]@{
        gate_name = "CONCENTRATION_LIMIT"
        passes = $passes
        reason = if ($passes) { "OK" } else { "Max $MAX_TIER_A Tier A reached ($CurrentTierACount)" }
        details = @{ max = $MAX_TIER_A; current = $CurrentTierACount; market = $Market }
    }
}

function Test-MinVolumeGate {
    param(
        [double] $VolumeUsd,
        [string] $Market
    )

    $MIN_VOLUME = 1000000  # 1M minimum
    $passes = $VolumeUsd -ge $MIN_VOLUME

    return [PSCustomObject]@{
        gate_name = "MIN_VOLUME"
        passes = $passes
        reason = if ($passes) { "OK" } else { "Volume $VolumeUsd < minimum $MIN_VOLUME" }
        details = @{ minimum = $MIN_VOLUME; current = $VolumeUsd; market = $Market }
    }
}

function Test-DailyLossCircuitGate {
    param(
        [double] $EquityTodayPct,
        [string] $Market
    )

    $DD_LIMIT = -5  # Halt if -5% today
    $passes = $EquityTodayPct -gt $DD_LIMIT

    return [PSCustomObject]@{
        gate_name = "DAILY_LOSS_CIRCUIT"
        passes = $passes
        reason = if ($passes) { "OK" } else { "Daily DD $EquityTodayPct% <= limit $DD_LIMIT%" }
        details = @{ limit = $DD_LIMIT; current = $EquityTodayPct; market = $Market }
    }
}
