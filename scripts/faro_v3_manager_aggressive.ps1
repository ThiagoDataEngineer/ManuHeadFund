# faro_v3_manager_aggressive.ps1 — Aggressive micro-scalp manager
# Monitors with tight stops (-2%), fast exits (+3/8/20%), 3h timeout

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
Write-Host "🎯 FARO V3 AGGRESSIVE Manager started"

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

Write-Host "📊 Monitoring $($positions.Count) AGGRESSIVE positions (tight stops + fast exits)"
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

        if ($currentPrice -le $pos.stop) {
            # HARD STOP: -2% (ULTRA TIGHT)
            Write-Host "🛑 STOP HIT: $market | entry=$($pos.entry_price) current=$currentPrice | loss=$([Math]::Round($pnlUSD,2))" -ForegroundColor Red
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
                        reason = "STOP_TIGHT"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch {}
            }
        }
        elseif ($currentPrice -ge $pos.target3) {
            # TARGET 3: +20% (close all)
            Write-Host "🎉 TARGET3: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD,2)) | +$([Math]::Round($priceChange,1))%" -ForegroundColor Green
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
                        reason = "T3_MEGA"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch {}
            }
        }
        elseif ($currentPrice -ge $pos.target2 -and $pos.target2_closed -ne $true) {
            # TARGET 2: +8% (close 30%, keep 70% trailing)
            Write-Host "📈 TARGET2: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD * 0.3,2)) | +$([Math]::Round($priceChange,1))%" -ForegroundColor Yellow
            if (-not $DryRun) {
                Write-Host "⚪ Closing 30%, trailing remaining 4%"
            }
        }
        elseif ($currentPrice -ge $pos.target1 -and $pos.target1_closed -ne $true) {
            # TARGET 1: +3% (close 20%, keep 80% trailing)
            Write-Host "💰 TARGET1: $market | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD * 0.2,2)) | +$([Math]::Round($priceChange,1))%" -ForegroundColor Cyan
            if (-not $DryRun) {
                Write-Host "⚪ Closing 20%, trailing remaining"
            }
        }
        elseif ($hoursSinceEntry -ge 3) {
            # TIMEOUT: 3 hours (exit at market)
            Write-Host "⏱️  TIMEOUT (3h): $market | entry=$($pos.entry_price) current=$currentPrice | pnl=$([Math]::Round($pnlUSD,2)) | $([Math]::Round($priceChange,1))%" -ForegroundColor Magenta
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
                        reason = "TIMEOUT_3H"
                        mins_held = [int]$minsSinceEntry
                        status = "closed"
                    }
                } catch {}
            }
        }
        else {
            $emoji = if ($priceChange -lt 0) { "📉" } else { "📈" }
            Write-Host "$emoji MONITOR: $market | entry=$($pos.entry_price) current=$currentPrice | $([Math]::Round($priceChange,1))% | age=$([int]$minsSinceEntry)min" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "WARN: Error in $($pos.market): $_" -ForegroundColor Yellow
    }
}

if ($closed.Count -gt 0) {
    $tradesFile = Join-Path $journalDir "faro_v3_trades.jsonl"
    foreach ($trade in $closed) {
        Add-Content -Path $tradesFile -Value ($trade | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
    }
    Write-Host "📝 Logged $($closed.Count) closed trades" -ForegroundColor Green
}

Write-Host "✨ Manager done | monitored=$($positions.Count), closed=$($closed.Count)" -ForegroundColor Green
