# lib_pyramid_exit.ps1 — Venda piramidal em topos cíclicos halving
# Vende 20% a cada novo ATH, prende ganho em stablecoin
# PS 5.1. UTF-8 BOM.

function Get-PyramidExitState {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $stateFile = Join-Path $journalDir "pyramid_exit_state.json"

    if (-not (Test-Path $stateFile)) {
        return @{
            positions = @()
            exit_history = @()
            gains_locked_usd = 0.0
        }
    }

    try {
        Get-Content $stateFile -Raw | ConvertFrom-Json
    } catch {
        return @{
            positions = @()
            exit_history = @()
            gains_locked_usd = 0.0
        }
    }
}

function Save-PyramidExitState {
    param(
        [object[]]$Positions,
        [object[]]$ExitHistory,
        [double]$GainsLockedUsd,
        [string]$JournalDir = $global:JOURNAL_DIR
    )

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    if (-not (Test-Path $journalDir)) { mkdir $journalDir | Out-Null }

    $state = @{
        positions = $Positions
        exit_history = $ExitHistory
        gains_locked_usd = $GainsLockedUsd
        updated_at = (Get-Date).ToString("o")
    }

    $state | ConvertTo-Json -AsArray | Set-Content (Join-Path $journalDir "pyramid_exit_state.json") -Encoding UTF8
}

function Test-NewAllTimeHigh {
    param(
        [double]$CurrentPrice,
        [double]$RecentHigh,
        [object]$ExitHistory  # array of past exits
    )

    # BTC ATH novo se:
    # 1. CurrentPrice > RecentHigh AND
    # 2. Não vendeu nos últimos 1% de movimento

    if ($CurrentPrice -le $RecentHigh) { return $false }

    # Check: last exit foi < 1% atrás
    if ($ExitHistory -and $ExitHistory.Count -gt 0) {
        $lastExit = $ExitHistory[-1]
        $exitPrice = [double]$lastExit.price
        $percentSince = ($CurrentPrice - $exitPrice) / $exitPrice
        if ($percentSince -lt 0.01) { return $false }  # too soon
    }

    return $true
}

function Invoke-PyramidExit {
    param(
        [double]$CurrentPrice,
        [object[]]$Positions,  # array of { market, qty, entry_price, ... }
        [double]$ExitPercentage = 0.20,  # 20% default
        [string]$JournalDir = $global:JOURNAL_DIR
    )

    if (-not $Positions -or $Positions.Count -eq 0) {
        return @{ executed=$false; reason="no_positions" }
    }

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $logFile = Join-Path $journalDir "pyramid_exits.jsonl"

    $exits = @()
    $totalGainUsd = 0.0

    foreach ($pos in $Positions) {
        $entryPrice = [double]$pos.entry_price
        $qty = [double]$pos.qty
        $exitQty = $qty * $ExitPercentage
        $proceedsUsd = $exitQty * $CurrentPrice
        $gainUsd = ($CurrentPrice - $entryPrice) * $exitQty

        $exit = @{
            timestamp = (Get-Date).ToString("o")
            market = $pos.market
            qty_sold = [math]::Round($exitQty, 8)
            entry_price = $entryPrice
            exit_price = $CurrentPrice
            proceeds_usd = [math]::Round($proceedsUsd, 2)
            gain_usd = [math]::Round($gainUsd, 2)
            gain_pct = [math]::Round(($CurrentPrice - $entryPrice) / $entryPrice * 100, 2)
            locked_to_usdt = $true
        } | ConvertTo-Json -Compress

        Add-Content -Path $logFile -Value $exit -Encoding UTF8 -ErrorAction SilentlyContinue

        $exits += @{
            market = $pos.market
            qty_sold = [math]::Round($exitQty, 8)
            proceeds_usd = [math]::Round($proceedsUsd, 2)
            gain_usd = [math]::Round($gainUsd, 2)
        }

        $totalGainUsd += $gainUsd
    }

    return @{
        executed = $true
        exits = $exits
        total_gain_usd = [math]::Round($totalGainUsd, 2)
        total_locked_usd = [math]::Round(($exits | Measure-Object -Property proceeds_usd -Sum).Sum, 2)
    }
}

function Get-PyramidExitStatistics {
    param([string]$JournalDir = $global:JOURNAL_DIR)

    $journalDir = if ($JournalDir) { $journalDir } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $logFile = Join-Path $journalDir "pyramid_exits.jsonl"

    if (-not (Test-Path $logFile)) {
        return @{ total_exits=0; total_gain_usd=0.0; total_locked_usd=0.0; avg_gain_pct=0.0 }
    }

    $exits = @()
    Get-Content $logFile | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try { $exits += (ConvertFrom-Json $_) } catch { }
    }

    $totalGain = ($exits | Measure-Object -Property gain_usd -Sum).Sum
    $totalLocked = ($exits | Measure-Object -Property proceeds_usd -Sum).Sum
    $avgGainPct = if ($exits.Count -gt 0) { ($exits | Measure-Object -Property gain_pct -Average).Average } else { 0 }

    return @{
        total_exits = $exits.Count
        total_gain_usd = [math]::Round($totalGain, 2)
        total_locked_usd = [math]::Round($totalLocked, 2)
        avg_gain_pct = [math]::Round($avgGainPct, 2)
        last_exit = if ($exits.Count -gt 0) { $exits[-1] } else { $null }
    }
}
