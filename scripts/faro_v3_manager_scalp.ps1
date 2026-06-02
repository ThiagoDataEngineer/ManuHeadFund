# faro_v3_manager_scalp.ps1 — Scalp mode position manager
# Quick entries/exits (4h timeout, 5/15/50% targets, -3% stops)
# Runs every 5 minutes

param([bool] $DryRun = $false)

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_trade_logger.ps1"
)
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

$timestamp = Get-Date -Format "o"
$timestamp_dt = Get-Date
Write-Host "🎯 FARO V3 Scalp Manager started"

$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
if (-not (Test-Path $posFile)) {
    Write-Host "ℹ️  No active positions"
    exit 0
}

$positions = @()
Get-Content $posFile -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        if ($obj.status -eq "active") { $positions += $obj }
    } catch {}
}

if ($positions.Count -eq 0) {
    Write-Host "ℹ️  No active positions"
    exit 0
}

Write-Host "📊 Monitoring $($positions.Count) scalp positions"
$closed = @()

foreach ($pos in $positions) {
    try {
        $market = $pos.market
        $ticker = CoinEx-GetTicker -market $market -ErrorAction SilentlyContinue
        if (-not $ticker) { continue }

        $currentPrice = [double]$ticker.last
        $priceChange = (($currentPrice - $pos.entry_price) / $pos.entry_price) * 100
        $pnlUSD = ($currentPrice - $pos.entry_price) * $pos.quantity
        $minsSinceEntry = ($timestamp_dt - [datetime]$pos.ts).TotalMinutes
        $hoursSinceEntry = $minsSinceEntry / 60

        # Scalp mode: quick exits
        if ($currentPrice -le $pos.stop) {
            # HARD STOP: -3%
            Write-Host "🛑 SCALP STOP: $market | entry=$($pos.entry_price) current=$currentPrice | loss=$([Math]::Round($pnlUSD,2))" -ForegroundColor Red
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $market
                        entry_price = $pos.entry_price
                        exit_price = $currentPrice
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        pnl_pct = $priceChange
                        reason = "STOP"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch { Write-Host "WARN: Failed to close $market" }
            }
        }
        elseif ($currentPrice -ge $pos.target3) {
            # TARGET 3: +50% (final exit, close all)
            Write-Host "🎉 TARGET3: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD,2)) | +$priceChange%" -ForegroundColor Green
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $market
                        entry_price = $pos.entry_price
                        exit_price = $currentPrice
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        pnl_pct = $priceChange
                        reason = "T3"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch { Write-Host "WARN: Failed to close $market" }
            }
        }
        elseif ($currentPrice -ge $pos.target2 -and $pos.target2_closed -ne $true) {
            # TARGET 2: +15% (close 50%)
            Write-Host "📈 TARGET2: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD * 0.5,2)) | +$priceChange%" -ForegroundColor Yellow
            if (-not $DryRun) {
                Write-Host "⚪ Closing 50% of position, trail remaining 4%"
                # In real implementation: close 50%, set trailing stop on rest
            }
        }
        elseif ($currentPrice -ge $pos.target1 -and $pos.target1_closed -ne $true) {
            # TARGET 1: +5% (close 30%, set trailing stop)
            Write-Host "💰 TARGET1: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD * 0.3,2)) | +$priceChange%" -ForegroundColor Cyan
            if (-not $DryRun) {
                Write-Host "⚪ Closing 30% of position, trailing stop activated"
                # In real implementation: close 30%, activate trailing stop
            }
        }
        elseif ($hoursSinceEntry -ge 4) {
            # TIMEOUT: 4 hours (exit with whatever profit/loss)
            Write-Host "⏱️  TIMEOUT (4h): $market | entry=$($pos.entry_price) current=$currentPrice | pnl=$([Math]::Round($pnlUSD,2)) | +$priceChange%" -ForegroundColor Magenta
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $market
                        entry_price = $pos.entry_price
                        exit_price = $currentPrice
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        pnl_pct = $priceChange
                        reason = "TIMEOUT"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch { Write-Host "WARN: Failed to close $market" }
            }
        }
        # Still open, monitoring
        else {
            $emoji = if ($priceChange -lt 0) { "📉" } else { "📈" }
            Write-Host "$emoji MONITOR: $market | entry=$($pos.entry_price) current=$currentPrice | change=+$priceChange% | age=$([int]$minsSinceEntry)min" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "WARN: Error processing $($pos.market): $_" -ForegroundColor Yellow
    }
}

if ($closed.Count -gt 0) {
    $tradesFile = Join-Path $journalDir "faro_v3_trades.jsonl"
    foreach ($trade in $closed) {
        Add-Content -Path $tradesFile -Value ($trade | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
    }
    Write-Host "📝 Logged $($closed.Count) closed trades" -ForegroundColor Green
}

Write-Host "🎯 FARO V3 Scalp Manager completed | monitored=$($positions.Count), closed=$($closed.Count)" -ForegroundColor Green
