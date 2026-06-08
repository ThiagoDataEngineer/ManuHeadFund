# lib_gem_discovery.ps1 — GEM DISCOVERY SCANNER
# Escaneia 1800 pares CoinEx, detecta PULL_BACK + DISTRIBUTION patterns
# Real-time, 5-minute cycles
# 2026-06-09

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:DiscoveryConfig = @{
    scan_universe = "TOP_200_GEMS"  # Start with top 200, expand to 1800
    min_volume_usd = 50000
    confidence_threshold_pull_back = 0.70
    confidence_threshold_short = 0.60
    output_file = "journal/gem_discovery_live.jsonl"
    max_discoveries_per_cycle = 10
}

# ════════════════════════════════════════════════════════════
# MAIN: Scan all gems and detect patterns
# ════════════════════════════════════════════════════════════

function Start-GemDiscoveryScanner {
    [CmdletBinding()]
    param(
        [int] $MaxResults = 10,
        [string] $OutputFile = "journal/gem_discovery_live.jsonl"
    )

    Write-Host "`n🔍 GEM DISCOVERY SCANNER — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

    # Load pattern detection libraries
    . (Join-Path $PSScriptRoot "lib_pullback_recovery.ps1") 2>$null
    . (Join-Path $PSScriptRoot "lib_distribution_short.ps1") 2>$null

    # Fetch CoinEx top gems (simplified: static list for MVP)
    $top_gems = @(
        "BTCUSDT", "ETHUSDT", "XRPUSDT", "SOLUSDT", "ADAUSDT",
        "LINKUSDT", "DOGEUSDT", "MATICUSDT", "LITUSDT", "AVAXUSDT",
        "PEPOUSDT", "BONKUSDT", "SHIUSDT", "FLOKIUSDT", "DOGMAUSDT"
    )

    $discoveries = @()

    foreach ($market in $top_gems) {
        try {
            # Fetch 100 1h candles (last ~4 days)
            $candles = Get-CoinExCandles -Market $market -Timeframe "1h" -Limit 100

            if (-not $candles -or $candles.Count -lt 20) {
                continue
            }

            # Test PULL_BACK_RECOVERY pattern
            $pullback_result = Detect-PullbackRecoveryPattern -Market $market -Candles $candles
            if ($pullback_result.detected -and $pullback_result.confidence -ge $script:DiscoveryConfig.confidence_threshold_pull_back) {
                $discoveries += @{
                    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    market = $market
                    strategy = "PULL_BACK_RECOVERY"
                    confidence = $pullback_result.confidence
                    entry_price = $pullback_result.entry_price
                    stop_loss = $pullback_result.stop_loss
                    target = $pullback_result.target
                    position_size_pct = 0.003
                    action = "BUY_ON_BREAK"
                }

                Write-Host "✅ PULL_BACK detected in $market (conf: $([Math]::Round($pullback_result.confidence, 2)))" -ForegroundColor Green
            }

            # Test DISTRIBUTION_SHORT pattern
            $short_result = Detect-DistributionShortPattern -Market $market -Candles $candles
            if ($short_result.detected -and $short_result.confidence -ge $script:DiscoveryConfig.confidence_threshold_short) {
                $discoveries += @{
                    timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    market = $market
                    strategy = "DISTRIBUTION_SHORT"
                    confidence = $short_result.confidence
                    entry_price = $short_result.entry_price
                    stop_loss = $short_result.stop_loss
                    target = $short_result.target
                    position_size_pct = 0.002
                    action = "SHORT_ON_BREAK"
                    timing_critical = $short_result.timing_critical
                }

                Write-Host "⚠️ SHORT pattern detected in $market (conf: $([Math]::Round($short_result.confidence, 2))) [TIMING CRITICAL]" -ForegroundColor Yellow
            }

            if ($discoveries.Count -ge $MaxResults) {
                break
            }

        } catch {
            Write-Host "⚠️ Error scanning $market : $_" -ForegroundColor Gray
        }
    }

    # Save discoveries
    if ($discoveries) {
        foreach ($discovery in $discoveries) {
            $discovery | ConvertTo-Json | Add-Content -Path $OutputFile
        }

        Write-Host "`n📊 Found $($discoveries.Count) opportunity(ies)" -ForegroundColor Green
        Write-Host "   Saved to: $OutputFile`n" -ForegroundColor Gray

        return $discoveries
    } else {
        Write-Host "`n⭕ No high-confidence patterns detected this cycle`n" -ForegroundColor Gray
        return @()
    }
}

# ════════════════════════════════════════════════════════════
# HELPER: Fetch CoinEx candles
# ════════════════════════════════════════════════════════════

function Get-CoinExCandles {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [ValidateSet("1m", "5m", "15m", "1h", "4h", "1d")][string] $Timeframe = "1h",
        [int] $Limit = 100
    )

    try {
        # MVP: Use CoinEx V2 API
        $endpoint = "https://api.coinex.com/v2/spot/candlestick?market=$Market&timeframe=$Timeframe&limit=$Limit"

        $response = Invoke-RestMethod -Uri $endpoint -Method GET -TimeoutSec 5 -ErrorAction Stop

        if ($response.code -eq 0 -and $response.data) {
            # Convert to simple candle objects
            $candles = $response.data | ForEach-Object {
                @{
                    timestamp = $_[0]
                    open = [double]$_[1]
                    high = [double]$_[2]
                    low = [double]$_[3]
                    close = [double]$_[4]
                    vol = [double]$_[5]
                }
            }

            return $candles
        }
    } catch {
        Write-Host "API Error fetching $Market : $_" -ForegroundColor Gray
        return $null
    }
}

# ════════════════════════════════════════════════════════════
# Helper: Format output
# ════════════════════════════════════════════════════════════

function Format-DiscoveryAlert {
    param(
        [Parameter(Mandatory=$true)][PSCustomObject] $Discovery
    )

    $icon = if ($Discovery.action -eq "BUY_ON_BREAK") { "📈" } else { "📉" }
    $message = @"
$icon $($Discovery.market) — $($Discovery.strategy)

Entry: $($Discovery.entry_price | Get-CurrencyFormat)
Target: $($Discovery.target | Get-CurrencyFormat)
Stop: $($Discovery.stop_loss | Get-CurrencyFormat)
Risk: $($Discovery.position_size_pct * 100)%
Confidence: $($Discovery.confidence * 100 | Round)%
"@

    return $message
}

function Get-CurrencyFormat {
    param([double] $Value)
    if ($Value -lt 0.01) {
        return "`$$($Value.ToString('0.00000000'))"
    } else {
        return "`$$($Value.ToString('0.00'))"
    }
}
