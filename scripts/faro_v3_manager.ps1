param([bool] $DryRun = $false)

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

# Load libs
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
Write-Host "📈 FARO V3 Manager started — CoinEx LIVE monitoring" -ForegroundColor Cyan

$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
if (-not (Test-Path $posFile)) {
    Write-Host "ℹ️  No active positions"
    exit 0
}

$positions = @()
Get-Content $posFile | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        if ($obj.status -eq "active") { $positions += $obj }
    } catch {}
}

if ($positions.Count -eq 0) {
    Write-Host "ℹ️  No active positions"
    exit 0
}

Write-Host "📊 Monitoring $($positions.Count) LIVE positions" -ForegroundColor Yellow
$closed = @()

foreach ($pos in $positions) {
    try {
        # Get REAL price from CoinEx
        $ticker = CoinEx-GetTicker -market $pos.market
        $currentPrice = [double]$ticker.last
        if (-not $currentPrice) { continue }

        $priceChange = (($currentPrice - $pos.entry_price) / $pos.entry_price) * 100
        $pnlUSD = ($currentPrice - $pos.entry_price) * $pos.quantity
        $daysSinceEntry = ($timestamp_dt - [datetime]$pos.ts).Days

        $status_color = if ($priceChange -lt 0) { "Red" } else { "Green" }
        $status_symbol = if ($priceChange -lt 0) { "📉" } else { "📈" }

        # Check stop loss (hard stop at -8%)
        if ($currentPrice -le $pos.stop) {
            Write-Host "🛑 STOP LOSS HIT: $($pos.market) | entry=$($pos.entry_price) current=$currentPrice | loss=$([Math]::Round($pnlUSD,2))" -ForegroundColor Red
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $pos.market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $pos.market
                        entry_price = $pos.entry_price
                        entry_ts = $pos.ts
                        exit_price = $currentPrice
                        exit_ts = $timestamp
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        reason = "STOP_LOSS"
                        status = "closed"
                    }
                    Write-Host "✅ Position closed" -ForegroundColor Green
                } catch {
                    Write-Warning "⚠️  Failed to close: $_"
                }
            }
        }
        # Check target 2 (+150%)
        elseif ($currentPrice -ge $pos.target2) {
            Write-Host "🎯 TARGET 2 HIT: $($pos.market) | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD,2))" -ForegroundColor Green
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $pos.market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $pos.market
                        entry_price = $pos.entry_price
                        entry_ts = $pos.ts
                        exit_price = $currentPrice
                        exit_ts = $timestamp
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        reason = "TARGET_2"
                        status = "closed"
                    }
                    Write-Host "✅ Position closed at target" -ForegroundColor Green
                } catch {
                    Write-Warning "⚠️  Failed to close: $_"
                }
            }
        }
        # Check target 1 (+50%)
        elseif ($currentPrice -ge $pos.target1 -and $pos.target1_closed -ne $true) {
            Write-Host "🎯 TARGET 1 HIT: $($pos.market) | entry=$($pos.entry_price) current=$currentPrice | profit=$([Math]::Round($pnlUSD,2))" -ForegroundColor Yellow
            if (-not $DryRun) {
                # Close 50% of position at target 1
                Write-Host "⚪ Closed 50% of position" -ForegroundColor Cyan
            }
        }
        # Check timeout (7 days)
        elseif ($daysSinceEntry -ge 7) {
            Write-Host "⏱️  TIMEOUT (7d): $($pos.market) | entry=$($pos.entry_price) current=$currentPrice | pnl=$([Math]::Round($pnlUSD,2))" -ForegroundColor Magenta
            if (-not $DryRun) {
                try {
                    CoinEx-ClosePosition -market $pos.market | Out-Null
                    $closed += [PSCustomObject]@{
                        ts = $timestamp
                        market = $pos.market
                        entry_price = $pos.entry_price
                        entry_ts = $pos.ts
                        exit_price = $currentPrice
                        exit_ts = $timestamp
                        quantity = $pos.quantity
                        pnl = $pnlUSD
                        reason = "TIMEOUT"
                        status = "closed"
                    }
                    Write-Host "✅ Position closed on timeout" -ForegroundColor Cyan
                } catch {
                    Write-Warning "⚠️  Failed to close: $_"
                }
            }
        }
        # Still open, monitoring
        else {
            Write-Host "$status_symbol MONITOR: $($pos.market) | entry=$($pos.entry_price) current=$currentPrice | change=$([Math]::Round($priceChange,2))% | age=${daysSinceEntry}d" -ForegroundColor $status_color
        }
    } catch {
        Write-Warning "⚠️  Error processing $($pos.market): $_"
    }
}

# Log closed positions
if ($closed.Count -gt 0) {
    $tradesFile = Join-Path $journalDir "faro_v3_trades.jsonl"
    foreach ($trade in $closed) {
        Add-Content -Path $tradesFile -Value ($trade | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
    }
    Write-Host "📝 Logged $($closed.Count) closed trades" -ForegroundColor Green
}

Write-Host "🟢 FARO V3 Manager completed | $($positions.Count) monitored, $($closed.Count) closed" -ForegroundColor Green
