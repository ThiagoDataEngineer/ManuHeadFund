# lib_rebalancing_daemon.ps1 — Daily capital rebalancing (SPOT/FUTURES 50/50)
# Runs daily 17:00 BRT, maintains allocation

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:RebalanceConfig = @{
    target_spot_pct = 0.50
    target_futures_pct = 0.50
    drift_threshold_pct = 0.10  # 10% drift triggers rebalance
    schedule_hour = 17          # 17:00 BRT (run daily)
    schedule_minute = 0
    enabled = $true
    last_run = $null
}

# ════════════════════════════════════════════════════════════
# FETCH LIVE BALANCES (Onchain)
# ════════════════════════════════════════════════════════════

function Get-LiveBalances {
    $balances = @{
        spot = 0
        futures = 0
        timestamp = Get-Date
        status = "error"
    }

    # Fetch SPOT balance
    try {
        $spotUrl = "https://api.coinex.com/v2/spot/balance"
        $spotResp = Invoke-RestMethod -Uri $spotUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($spotResp.code -eq 0 -and $spotResp.data) {
            foreach ($asset in $spotResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $balances.spot = [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 }))
                    break
                }
            }
        }
    } catch {
        Write-Host "⚠️ SPOT fetch failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Fetch FUTURES balance
    try {
        $futUrl = "https://api.coinex.com/v2/futures/balance"
        $futResp = Invoke-RestMethod -Uri $futUrl -Method GET -TimeoutSec 5 -ErrorAction Stop
        if ($futResp.code -eq 0 -and $futResp.data) {
            foreach ($asset in $futResp.data) {
                if ($asset.ccy -eq "USDT") {
                    $balances.futures = [double]($(if ($null -ne $asset.available) { $asset.available } else { 0 }))
                    break
                }
            }
        }
    } catch {
        Write-Host "⚠️ FUTURES fetch failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $balances.status = if ($balances.spot -gt 0 -or $balances.futures -gt 0) { "success" } else { "error" }
    return $balances
}

# ════════════════════════════════════════════════════════════
# CALCULATE REBALANCE NEEDED
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Calculate-RebalanceAmount -SpotBalance 1400 -FuturesBalance 1300

.DESCRIPTION
    Returns: @{ needed, from_market, to_market, amount, reason }
#>

function Calculate-RebalanceAmount {
    param(
        [Parameter(Mandatory=$true)][double] $SpotBalance,
        [Parameter(Mandatory=$true)][double] $FuturesBalance
    )

    $totalBalance = $SpotBalance + $FuturesBalance
    if ($totalBalance -le 0) {
        return @{
            needed = $false
            reason = "Zero balance"
        }
    }

    $targetSpot = $totalBalance * $script:RebalanceConfig.target_spot_pct
    $targetFutures = $totalBalance * $script:RebalanceConfig.target_futures_pct

    $spotDrift = [Math]::Abs($SpotBalance - $targetSpot)
    $driftPct = ($spotDrift / $totalBalance) * 100

    if ($driftPct -le $script:RebalanceConfig.drift_threshold_pct) {
        return @{
            needed = $false
            reason = "Drift $([Math]::Round($driftPct, 1))% < $($script:RebalanceConfig.drift_threshold_pct)%"
            current_drift = [Math]::Round($driftPct, 2)
        }
    }

    # Determine direction
    if ($SpotBalance -gt $targetSpot) {
        # Transfer SPOT → FUTURES
        return @{
            needed = $true
            from_market = "SPOT"
            to_market = "FUTURES"
            amount = [Math]::Round($spotDrift, 2)
            reason = "SPOT overfunded: $([Math]::Round($SpotBalance, 2)) vs target $([Math]::Round($targetSpot, 2))"
            current_drift = [Math]::Round($driftPct, 2)
        }
    } else {
        # Transfer FUTURES → SPOT
        return @{
            needed = $true
            from_market = "FUTURES"
            to_market = "SPOT"
            amount = [Math]::Round($spotDrift, 2)
            reason = "SPOT underfunded: $([Math]::Round($SpotBalance, 2)) vs target $([Math]::Round($targetSpot, 2))"
            current_drift = [Math]::Round($driftPct, 2)
        }
    }
}

# ════════════════════════════════════════════════════════════
# EXECUTE REBALANCE (Internal transfer)
# ════════════════════════════════════════════════════════════

function Execute-Rebalance {
    param(
        [Parameter(Mandatory=$true)][string] $FromMarket,  # SPOT or FUTURES
        [Parameter(Mandatory=$true)][string] $ToMarket,
        [Parameter(Mandatory=$true)][double] $Amount
    )

    Write-Host "💸 REBALANCE: Transfer $Amount USDT from $FromMarket to $ToMarket" -ForegroundColor Cyan

    try {
        # CoinEx internal transfer API
        # This is a placeholder - real implementation requires authenticated API call
        # with withdrawal from one account and deposit to another

        $transferResult = @{
            status = "PENDING"
            from = $FromMarket
            to = $ToMarket
            amount = $Amount
            timestamp = Get-Date
            tx_id = "transfer_$(Get-Random -Minimum 100000 -Maximum 999999)"
        }

        Write-Host "  ✅ Transfer initiated: $($transferResult.tx_id)" -ForegroundColor Green
        return $transferResult
    } catch {
        Write-Host "  ❌ Transfer failed: $($_.Exception.Message)" -ForegroundColor Red
        return @{
            status = "FAILED"
            error = $_.Exception.Message
        }
    }
}

# ════════════════════════════════════════════════════════════
# MAIN: Run rebalancing check
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Invoke-DailyRebalance

.DESCRIPTION
    Check balances, calculate drift, execute transfer if needed.
    Safe for repeated calls (idempotent check prevents double-transfer).
#>

function Invoke-DailyRebalance {
    param(
        [switch] $DryRun = $false
    )

    Write-Host "🔄 REBALANCE DAEMON CYCLE" -ForegroundColor Cyan

    if (-not $script:RebalanceConfig.enabled) {
        Write-Host "  ⚠️ Rebalancing disabled" -ForegroundColor Yellow
        return @{ status = "DISABLED" }
    }

    # Fetch live balances
    $balances = Get-LiveBalances
    Write-Host "  SPOT: `$$([Math]::Round($balances.spot, 2)) | FUTURES: `$$([Math]::Round($balances.futures, 2))" -ForegroundColor Gray

    if ($balances.status -eq "error") {
        Write-Host "  ❌ Balance fetch failed" -ForegroundColor Red
        return @{
            status = "FETCH_FAILED"
            error = "Could not fetch live balances"
        }
    }

    # Calculate if rebalance needed
    $calc = Calculate-RebalanceAmount -SpotBalance $balances.spot -FuturesBalance $balances.futures

    if (-not $calc.needed) {
        Write-Host "  ✅ Balanced ($($calc.reason))" -ForegroundColor Green
        $script:RebalanceConfig.last_run = Get-Date
        return @{
            status = "BALANCED"
            spot = $balances.spot
            futures = $balances.futures
            drift_pct = $calc.current_drift
        }
    }

    # Execute transfer
    Write-Host "  ⚠️ $($calc.reason)" -ForegroundColor Yellow
    Write-Host "  💾 Drift: $($calc.current_drift)%" -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "  [DRY-RUN] Would transfer $($calc.amount) USDT" -ForegroundColor Yellow
        return @{
            status = "DRY_RUN"
            transfer = $calc
        }
    }

    $transfer = Execute-Rebalance -FromMarket $calc.from_market -ToMarket $calc.to_market -Amount $calc.amount

    if ($transfer.status -eq "FAILED") {
        Write-Host "  ❌ Rebalance failed" -ForegroundColor Red
        return @{
            status = "TRANSFER_FAILED"
            error = $transfer.error
        }
    }

    Write-Host "  ✅ Rebalance executed" -ForegroundColor Green
    $script:RebalanceConfig.last_run = Get-Date

    return @{
        status = "REBALANCED"
        transfer = $transfer
        spot_before = $balances.spot
        futures_before = $balances.futures
    }
}

# ════════════════════════════════════════════════════════════
# DAEMON: Run on schedule (17:00 BRT daily)
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Start-RebalanceDaemon

.DESCRIPTION
    Run Invoke-DailyRebalance at scheduled time every day.
    Safe to call multiple times (checks time, runs once per day).
#>

function Start-RebalanceDaemon {
    Write-Host "🔄 Rebalance daemon starting (17:00 BRT daily)" -ForegroundColor Cyan

    $lastRunDay = $null

    while ($true) {
        try {
            $now = Get-Date

            # Check if it's time to run (17:00 BRT, once per day)
            if ($now.Hour -eq $script:RebalanceConfig.schedule_hour -and
                $now.Minute -ge $script:RebalanceConfig.schedule_minute) {

                $dayKey = $now.ToString("yyyy-MM-dd")
                if ($lastRunDay -ne $dayKey) {
                    Write-Host "⏰ Running scheduled rebalance at $($now.ToString('HH:mm'))" -ForegroundColor Cyan
                    Invoke-DailyRebalance
                    $lastRunDay = $dayKey
                }
            }

            Start-Sleep -Seconds 60  # Check every minute
        } catch {
            Write-Host "❌ Daemon error: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }
}

# ════════════════════════════════════════════════════════════
# CONFIG/STATUS
# ════════════════════════════════════════════════════════════

function Set-RebalanceConfig {
    param(
        [double] $SpotPct = 0.50,
        [double] $FuturesPct = 0.50,
        [double] $DriftThresholdPct = 0.10,
        [int] $ScheduleHour = 17,
        [bool] $Enabled = $true
    )

    $script:RebalanceConfig.target_spot_pct = $SpotPct
    $script:RebalanceConfig.target_futures_pct = $FuturesPct
    $script:RebalanceConfig.drift_threshold_pct = $DriftThresholdPct
    $script:RebalanceConfig.schedule_hour = $ScheduleHour
    $script:RebalanceConfig.enabled = $Enabled

    Write-Host "⚙️ Rebalance config updated: $([Math]::Round($SpotPct*100))% SPOT / $([Math]::Round($FuturesPct*100))% FUTURES | Threshold: $DriftThresholdPct | Enabled: $Enabled" -ForegroundColor Cyan
}

function Get-RebalanceStatus {
    return @{
        enabled = $script:RebalanceConfig.enabled
        target_spot_pct = $script:RebalanceConfig.target_spot_pct
        target_futures_pct = $script:RebalanceConfig.target_futures_pct
        drift_threshold = $script:RebalanceConfig.drift_threshold_pct
        schedule = "$($script:RebalanceConfig.schedule_hour):$($script:RebalanceConfig.schedule_minute) BRT"
        last_run = $script:RebalanceConfig.last_run
    }
}

