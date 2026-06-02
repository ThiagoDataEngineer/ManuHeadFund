# faro_v3_entry_aggressive.ps1 — Ultra-aggressive micro-scalp
# 6/7 signals ONLY + 1.5x margin on high-confidence + 0.5% capital per position
# Target: $300/day on $5k capital = 6% daily ROI

param([bool] $DryRun = $false, [double] $CapitalPercent = 0.005, [int] $MaxPositions = 20, [bool] $UseMargin = $true)

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
Write-Host "🔥 FARO V3 AGGRESSIVE started — 6/7 signals + margin mode"

# Get capital
try {
    $totalCap = CoinEx-GetTotalCapitalUSDT
    if ($totalCap -le 0) {
        Write-Host "WARN: Capital is 0"
        exit 0
    }
} catch {
    Write-Host "WARN: Failed to get capital"
    exit 1
}

$positionSize = $totalCap * $CapitalPercent
if ($UseMargin) {
    $positionSize = $positionSize * 1.5  # 1.5x margin
}

Write-Host "💰 Capital: \$$totalCap | Position: \$$positionSize (0.5% × 1.5x margin)"
Write-Host "📊 Max $MaxPositions concurrent positions = $(($MaxPositions * $CapitalPercent * 100))% exposure"

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

# Read recent candidates (last 15 minutes for freshness)
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
        # STRICT: only 6/7 signals, score 70+, fresh (<15min)
        if ($age -le 15 -and $obj.signal_count -eq 6 -and $obj.score -ge 70 -and $obj.decision -eq "URGENTE") {
            $entries += $obj
        }
    } catch {}
} | Sort-Object -Property score -Descending

if ($entries.Count -eq 0) {
    Write-Host "ℹ️  No 6/7 URGENTE signals found"
    exit 0
}

Write-Host "🔥 Found $($entries.Count) HIGH-CONFIDENCE signals (6/7 + score 70+)"

$entered = @()
foreach ($entry in $entries) {
    if ($activePositions.Count + $entered.Count -ge $MaxPositions) { break }

    $market = $entry.market
    try {
        $ticker = CoinEx-GetTicker -market $market -ErrorAction Stop
        $currentPrice = [double]$ticker.last
        if (-not $currentPrice) { continue }

        # Volatility
        $vol_pct = (([double]$ticker.high24h - [double]$ticker.low24h) / [double]$ticker.last) * 100

        # AGGRESSIVE sizing: smaller position on high vol
        $sizeMultiplier = if ($vol_pct -gt 30) { 0.6 } elseif ($vol_pct -gt 15) { 0.9 } else { 1.1 }
        $quantity = ($positionSize * $sizeMultiplier) / $currentPrice

        # AGGRESSIVE targets: tighter stops, faster exits
        $stop = $currentPrice * 0.98       # -2% (super tight)
        $target1 = $currentPrice * 1.03    # +3% (close 20% fast)
        $target2 = $currentPrice * 1.08    # +8% (close 30%)
        $target3 = $currentPrice * 1.20    # +20% (close 50%)

        # Check if already trading this market
        if (Test-Path $posFile) {
            $existing = Get-Content $posFile |
                Where-Object { $_ | ConvertFrom-Json | Where-Object { $_.market -eq $market -and $_.status -eq "active" } }
            if ($existing) {
                Write-Host "⏭️  $market already active"
                continue
            }
        }

        $marginNote = if ($UseMargin) { " (1.5x margin)" } else { "" }
        Write-Host "🚀 AGGRESSIVE ENTRY: $market | price=$([Math]::Round($currentPrice,6)) | qty=$([Math]::Round($quantity,6))$marginNote" -ForegroundColor Green
        Write-Host "   Stops: $([Math]::Round($stop,6)) | T1: $([Math]::Round($target1,6)) T2: $([Math]::Round($target2,6)) T3: $([Math]::Round($target3,6))"

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
                        reason = "URGENTE_6/7"
                        status = "active"
                        order_id = $result.order_id ?? "unknown"
                        mode = "AGGRESSIVE"
                        margin_used = $UseMargin
                        margin_multiplier = 1.5
                    }
                    Add-Content -Path $posFile -Value ($position | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
                    $entered += $position
                    Write-Host "✅ ENTERED: $market (6/7 signals)" -ForegroundColor Green
                } else {
                    Write-Host "WARN: PlaceOrder failed for $market"
                }
            } catch {
                Write-Host "WARN: Exception in ${market}: $_" -ForegroundColor Yellow
            }
        } else {
            Write-Host "✅ [DRY] Would enter ${market} with 1.5x margin" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "WARN: Error in ${market}: $_" -ForegroundColor Yellow
    }
}

Write-Host "✨ FARO V3 AGGRESSIVE done | opened=$($entered.Count), total=$($activePositions.Count + $entered.Count)/$MaxPositions" -ForegroundColor Green
