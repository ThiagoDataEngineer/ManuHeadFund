# faro_v3_entry.ps1 — Auto-entry on ENTRA/URGENTE signals
# Runs after faro_v3_engine to place orders on confirmed candidates

param([bool] $DryRun = $false, [double] $CapitalPercent = 0.01, [int] $MaxPositions = 5)

$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_order_idempotency.ps1"
)
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

$timestamp = Get-Date -Format "o"
$timestamp_dt = Get-Date
Write-Host "🟢 FARO V3 Entry started — auto-entry mode" -ForegroundColor Cyan

# Get current capital
try {
    $totalCap = CoinEx-GetTotalCapitalUSDT
    if ($totalCap -le 0) {
        Write-Warning "WARN: Capital is 0 or negative; skipping entries"
        exit 0
    }
} catch {
    Write-Warning "WARN: Failed to get capital: $_"
    exit 1
}

$positionSize = $totalCap * $CapitalPercent
Write-Host "📊 Capital: \$$totalCap | Position size: \$$positionSize" -ForegroundColor Yellow

# Check active position count
$posFile = Join-Path $journalDir "faro_v3_positions.jsonl"
$activePositions = @()
if (Test-Path $posFile) {
    Get-Content $posFile | ForEach-Object {
        try {
            $obj = $_ | ConvertFrom-Json
            if ($obj.status -eq "active") { $activePositions += $obj }
        } catch {}
    }
}

if ($activePositions.Count -ge $MaxPositions) {
    Write-Host "WARN: Max positions ($MaxPositions) reached; skipping new entries" -ForegroundColor Yellow
    exit 0
}

# Read recent candidates (last 10 minutes)
$candFile = Join-Path $journalDir "faro_v3_candidates.jsonl"
if (-not (Test-Path $candFile)) {
    Write-Host "ℹ️  No candidates found"
    exit 0
}

$entries = @()
Get-Content $candFile | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        $candTs = [datetime]$obj.ts
        $age = ($timestamp_dt - $candTs).TotalMinutes
        if ($age -le 30 -and $obj.decision -in "ENTRA","URGENTE") {
            $entries += $obj
        }
    } catch {}
} | Sort-Object -Property score -Descending

if ($entries.Count -eq 0) {
    Write-Host "ℹ️  No entry signals in last 30 minutes"
    exit 0
}

Write-Host "🎯 Found $($entries.Count) entry signals" -ForegroundColor Green

$entered = @()
foreach ($entry in $entries) {
    if ($activePositions.Count + $entered.Count -ge $MaxPositions) { break }

    $market = $entry.market
    try {
        # Fetch current price + volatility
        $ticker = CoinEx-GetTicker -market $market
        $currentPrice = [double]$ticker.last
        if (-not $currentPrice) { continue }

        # Calculate volatility (simple 24h range)
        $volatility = [double](($ticker.high24h - $ticker.low24h) / $ticker.last)
        $vol_pct = $volatility * 100

        # Dynamic position sizing: lower vol = larger position
        $sizeMultiplier = if ($vol_pct -gt 20) { 0.8 } elseif ($vol_pct -gt 15) { 1.0 } else { 1.2 }
        $quantity = ($positionSize * $sizeMultiplier) / $currentPrice

        # Calculate stops + targets
        $stop = $currentPrice * 0.92  # -8% stop
        $target1 = $currentPrice * 1.50  # +50%
        $target2 = $currentPrice * 2.50  # +150%

        # Check idempotency (no duplicate entry for this market today)
        if (Test-Path $posFile) {
            $existing = Get-Content $posFile |
                Where-Object { $_ | ConvertFrom-Json | Where-Object { $_.market -eq $market -and $_.status -eq "active" } }
            if ($existing) {
                Write-Host "⏭️  $market already has active position; skipping" -ForegroundColor Gray
                continue
            }
        }

        # Place order
        Write-Host "📍 Entering $market | price=$([Math]::Round($currentPrice,6)) | size=$([Math]::Round($quantity,4)) | stop=$([Math]::Round($stop,6)) | t1=$([Math]::Round($target1,6)) | t2=$([Math]::Round($target2,6))" -ForegroundColor Cyan

        if (-not $DryRun) {
            try {
                $result = CoinEx-PlaceOrder -market $market -side "buy" -type "market" -amount $quantity -stopLoss $stop -takeProfit $target2
                if ($result) {
                    $position = [PSCustomObject]@{
                        ts = $timestamp
                        market = $market
                        entry_price = $currentPrice
                        quantity = $quantity
                        stop = $stop
                        target1 = $target1
                        target1_closed = $false
                        target2 = $target2
                        volatility = $vol_pct
                        signal_score = $entry.score
                        signal_count = $entry.signal_count
                        reason = $entry.decision
                        status = "active"
                        order_id = $(if ($null -ne $result.order_id) { $result.order_id } else { "unknown" })
                    }
                    Add-Content -Path $posFile -Value ($position | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
                    $entered += $position
                    Write-Host "✅ Order placed: $market" -ForegroundColor Green
                } else {
                    Write-Warning "WARN: PlaceOrder failed for $market"
                }
            } catch {
                Write-Warning "WARN: Exception in ${market}: $_"
            }
        } else {
            Write-Host "✅ [DRY RUN] Would enter $market" -ForegroundColor Cyan
        }
    } catch {
        Write-Warning "WARN: Error processing ${market}: $_"
    }
}

Write-Host "🟢 FARO V3 Entry completed | $($entered.Count) new positions opened" -ForegroundColor Green
