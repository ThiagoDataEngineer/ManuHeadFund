# faro_v3_entry_scalp.ps1 — Scalp mode auto-entry
# Quick entries on 5+ signals, smaller position size, micro-caps only
# Runs every 15 minutes (or immediately after engine scan)

param([bool] $DryRun = $false, [double] $CapitalPercent = 0.002, [int] $MaxPositions = 10)

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
Write-Host "🚀 FARO V3 Scalp Entry started — aggressive micro-cap mode"

# Get capital
try {
    $totalCap = CoinEx-GetTotalCapitalUSDT
    if ($totalCap -le 0) {
        Write-Host "WARN: Capital is 0; skipping entries"
        exit 0
    }
} catch {
    Write-Host "WARN: Failed to get capital: $_"
    exit 1
}

$positionSize = $totalCap * $CapitalPercent
Write-Host "💰 Capital: \$$totalCap | Position size: \$$positionSize (0.2% each)"

# Check active positions
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
    Write-Host "⚠️  Max positions ($MaxPositions) reached"
    exit 0
}

# Read recent candidates (last 20 minutes)
$candFile = Join-Path $journalDir "faro_v3_candidates.jsonl"
if (-not (Test-Path $candFile)) {
    Write-Host "ℹ️  No candidates"
    exit 0
}

$entries = @()
Get-Content $candFile | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        $candTs = [datetime]$obj.ts
        $age = ($timestamp_dt - $candTs).TotalMinutes
        # Scalp mode: enter FAST (within 20 minutes of signal)
        if ($age -le 20 -and $obj.decision -in "ENTRA","URGENTE" -and $obj.signal_count -ge 5) {
            $entries += $obj
        }
    } catch {}
} | Sort-Object -Property score -Descending

if ($entries.Count -eq 0) {
    Write-Host "ℹ️  No hot signals"
    exit 0
}

Write-Host "🔥 Found $($entries.Count) hot signals (5/7 signals)"

$entered = @()
foreach ($entry in $entries) {
    if ($activePositions.Count + $entered.Count -ge $MaxPositions) { break }

    $market = $entry.market
    try {
        # Get current price
        $ticker = CoinEx-GetTicker -market $market -ErrorAction Stop
        $currentPrice = [double]$ticker.last
        if (-not $currentPrice) { continue }

        # Volatility (simpler: just daily range)
        $vol_pct = (([double]$ticker.high24h - [double]$ticker.low24h) / [double]$ticker.last) * 100

        # SCALP SIZING: smaller positions, higher vol = smaller size
        $sizeMultiplier = if ($vol_pct -gt 30) { 0.5 } elseif ($vol_pct -gt 15) { 0.8 } else { 1.0 }
        $quantity = ($positionSize * $sizeMultiplier) / $currentPrice

        # SCALP TARGETS: quick exits
        $stop = $currentPrice * 0.97      # -3% (not -8%)
        $target1 = $currentPrice * 1.05   # +5% (close 30%)
        $target2 = $currentPrice * 1.15   # +15% (close 50%)
        $target3 = $currentPrice * 1.50   # +50% (close rest)

        # Check if already in this market
        if (Test-Path $posFile) {
            $existing = Get-Content $posFile |
                Where-Object { $_ | ConvertFrom-Json | Where-Object { $_.market -eq $market -and $_.status -eq "active" } }
            if ($existing) {
                Write-Host "⏭️  $market already active"
                continue
            }
        }

        Write-Host "🎯 ENTER: $market | price=$([Math]::Round($currentPrice,6)) | qty=$([Math]::Round($quantity,4)) | T1=$([Math]::Round($target1,6)) T2=$([Math]::Round($target2,6)) T3=$([Math]::Round($target3,6))" -ForegroundColor Green

        if (-not $DryRun) {
            try {
                $result = CoinEx-PlaceOrder -market $market -side "buy" -type "market" -amount $quantity -stopLoss $stop -takeProfit $target3
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
                        target2_closed = $false
                        target3 = $target3
                        volatility = $vol_pct
                        signal_score = $entry.score
                        signal_count = $entry.signal_count
                        reason = $entry.decision
                        status = "active"
                        order_id = $result.order_id ?? "unknown"
                        mode = "SCALP"
                    }
                    Add-Content -Path $posFile -Value ($position | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
                    $entered += $position
                    Write-Host "✅ Scalp position opened: $market" -ForegroundColor Green
                } else {
                    Write-Host "WARN: PlaceOrder failed for $market"
                }
            } catch {
                Write-Host "WARN: Exception in $market: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✅ [DRY] Would enter $market" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "WARN: Error in $market: $_" -ForegroundColor Yellow
    }
}

Write-Host "✨ FARO V3 Scalp Entry done | opened=$($entered.Count), total_active=$($activePositions.Count + $entered.Count)/$MaxPositions" -ForegroundColor Green
