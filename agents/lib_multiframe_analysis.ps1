# lib_multiframe_analysis.ps1 — Multi-Timeframe Trend Analysis + Alignment Gate
# 2026-06-08: Automated HTF confirmation before trade execution
# Purpose: Analyze trend direction across 1D/4H/1H and enforce alignment rules

# ─────────────────────────────────────────────────────────────────────────────
# Get-SimpleMovingAverage — Calculate SMA for trend detection
# ─────────────────────────────────────────────────────────────────────────────
function Get-SimpleMovingAverage {
    param([double[]]$Closes, [int]$Period = 20)

    if ($Closes.Count -lt $Period) { return $Closes[-1] }

    $sum = 0
    for ($i = $Closes.Count - $Period; $i -lt $Closes.Count; $i++) {
        $sum += $Closes[$i]
    }
    return $sum / $Period
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-RSI — Relative Strength Index for momentum/overbought detection
# ─────────────────────────────────────────────────────────────────────────────
function Get-RSI {
    param([double[]]$Closes, [int]$Period = 14)

    if ($Closes.Count -lt $Period + 1) { return 50 }

    $gains = 0; $losses = 0
    for ($i = $Closes.Count - $Period; $i -lt $Closes.Count; $i++) {
        $change = $Closes[$i] - $Closes[$i - 1]
        if ($change -gt 0) { $gains += $change } else { $losses += [math]::Abs($change) }
    }

    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period

    if ($avgLoss -eq 0) { return 100 }
    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-TrendDirection — Classify trend as STRONG_UP/UP/NEUTRAL/DOWN/STRONG_DOWN
# ─────────────────────────────────────────────────────────────────────────────
function Get-TrendDirection {
    param(
        [object[]]$Candles,      # OHLCV array
        [string]$Timeframe = ""  # "1D", "4H", "1H" etc (informational)
    )

    if ($Candles.Count -lt 20) {
        Write-Host "      [TREND] Insufficient candles for $Timeframe (need 20+, have $($Candles.Count))" -ForegroundColor DarkGray
        return "NEUTRAL"
    }

    # Extract closes
    $closes = @()
    foreach ($c in $Candles) {
        $closes += [double]$c.close
    }

    # Calculate indicators
    $sma20 = Get-SimpleMovingAverage $closes 20
    $rsi14 = Get-RSI $closes 14
    $currentClose = $closes[-1]
    $prevClose = $closes[-2]

    # Trend direction: compare current vs SMA
    $aboveSMA = $currentClose -gt $sma20
    $closingUp = $currentClose -gt $prevClose

    # Classify
    if ($aboveSMA) {
        # Uptrend
        if ($rsi14 -gt 60) {
            $trend = "STRONG_UP"
        } else {
            $trend = "UP"
        }
    } else {
        # Downtrend
        if ($rsi14 -lt 40) {
            $trend = "STRONG_DOWN"
        } else {
            $trend = "DOWN"
        }
    }

    Write-Host "      [TREND] $Timeframe=$trend (close=$([math]::Round($currentClose, 6)) sma=$([math]::Round($sma20, 6)) rsi=$([math]::Round($rsi14, 1)))" -ForegroundColor DarkCyan
    return $trend
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-MultiTimeframeAlignment — Validate LONG/SHORT against HTF trends
# ─────────────────────────────────────────────────────────────────────────────
function Test-MultiTimeframeAlignment {
    param(
        [string]$Trend1D,
        [string]$Trend4H,
        [string]$Trend1H,
        [string]$Direction  # "LONG" or "SHORT"
    )

    <#
    LONG rules:
      - 1D must be UP or STRONG_UP (not DOWN/STRONG_DOWN)
      - 4H must be UP or STRONG_UP (confirmation)
      - 1H can be anything (local confirmation within sweep)

    SHORT rules:
      - 1D must NOT be UP/STRONG_UP (neutral or downtrend)
      - 4H must NOT be UP/STRONG_UP
      - 1H can be anything
    #>

    if ($Direction -eq "LONG") {
        $ok1D = $Trend1D -in @("STRONG_UP", "UP")
        $ok4H = $Trend4H -in @("STRONG_UP", "UP")
        $aligned = $ok1D -and $ok4H
    } else {
        # SHORT
        $ok1D = $Trend1D -in @("STRONG_DOWN", "DOWN", "NEUTRAL")
        $ok4H = $Trend4H -in @("STRONG_DOWN", "DOWN", "NEUTRAL")
        $aligned = $ok1D -and $ok4H
    }

    return $aligned
}

# Functions automatically available after dot-sourcing
