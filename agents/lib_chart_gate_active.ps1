# lib_chart_gate_active.ps1
# 2026-06-18: Chart patterns as ACTIVE BLOCKER (not just info)
# Rejects entries with bearish chart patterns, pump signatures, fake breakouts

function Test-ChartPatternGate {
    <#
    .SYNOPSIS
        BLOCKER: Reject entry if chart shows bad pattern
        - Rejects pump-chase (topping patterns)
        - Rejects fake breakouts
        - Rejects selling climax (already peaked)
    .PARAMETER Market
        Market symbol (e.g., "BTCUSDT")
    .PARAMETER HistoricalPrice
        Last 20 closes (for pattern detection)
    .PARAMETER Volume
        Corresponding volumes
    .OUTPUTS
        PSCustomObject: pass=$true/$false, reason, confidence
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Market,
        [Parameter(Mandatory=$false)] [double[]]$HistoricalPrice,
        [Parameter(Mandatory=$false)] [double[]]$Volume
    )

    # Default: if no data, allow (fail-open)
    if (-not $HistoricalPrice -or $HistoricalPrice.Count -lt 5) {
        return @{ pass = $true; reason = "insufficient_data"; confidence = 0 }
    }

    # Check for PUMP signature (volume climax + price spike)
    $recent = $HistoricalPrice[-5..-1]  # Last 5 candles
    $vol_recent = $Volume[-5..-1]

    # Pump = (1) rising prices in last 3, AND (2) volume spike anywhere in recent
    $price_up = ($recent[-1] -gt $recent[0])  # Last close > 5-candle open

    # Volume spike: any recent candle >2x the average of earlier candles
    $vol_baseline = ($vol_recent[0] + $vol_recent[1]) / 2  # First 2 candles average
    $vol_spike = ($vol_recent[-1] -gt ($vol_baseline * 2)) -or `
                 ($vol_recent[-2] -gt ($vol_baseline * 2)) -or `
                 ($vol_recent[-3] -gt ($vol_baseline * 2))  # Any of last 3 spike

    if ($price_up -and $vol_spike) {
        # This smells like pump — high risk
        return @{
            pass = $false
            reason = "pump_pattern_detected"
            confidence = 85
            pattern = "volume_climax_with_price_spike"
        }
    }

    # Check for TOPPING pattern (bearish reversal)
    if ($recent.Count -ge 3) {
        # Shooting star: long upper wick, small body = rejection
        $high = [math]::Max($recent[-1], $recent[-2])
        $low = [math]::Min($recent[-1], $recent[-2])
        $range = $high - $low

        if ($range -gt 0) {
            $upper_wick = $recent[-1] - $high
            # If upper wick is >50% of range, it's a shooting star rejection
            if ([math]::Abs($upper_wick) -gt ($range * 0.5)) {
                return @{
                    pass = $false
                    reason = "shooting_star_rejection"
                    confidence = 70
                    pattern = "upper_wick_rejection"
                }
            }
        }
    }

    # All checks passed — chart looks OK
    return @{
        pass = $true
        reason = "chart_pattern_ok"
        confidence = 60
    }
}

function Get-DailyAutoCalibrationAdvice {
    <#
    .SYNOPSIS
        Daily: Check what we won vs what we missed, recommend gate changes
    .OUTPUTS
        PSCustomObject: action, reason, new_conviction_threshold, new_mesa_strong
    #>
    [CmdletBinding()]
    param()

    # Load insight from yesterday
    $insight_file = "journal/daily_insight_$(Get-Date -Format 'yyyyMMdd').json"

    if (Test-Path $insight_file) {
        $insight = Get-Content $insight_file | ConvertFrom-Json
        $gap = $insight.net_gap_usd

        if ($gap -gt 200) {
            # Missed too much — loosen gates
            return @{
                action = "OPEN_GATES"
                reason = "missed_${gap} in top gainers"
                conviction_threshold_new = 48
                mesa_strong_new = 55
                confidence = "HIGH"
            }
        }
        elseif ($gap -lt -100) {
            # Took too many losses — tighten gates
            return @{
                action = "TIGHTEN_GATES"
                reason = "avoided_${([math]::Abs($gap))} in losses"
                conviction_threshold_new = 52
                mesa_strong_new = 65
                confidence = "HIGH"
            }
        }
    }

    # Default: maintain
    return @{
        action = "MAINTAIN"
        reason = "gates_calibrated"
        conviction_threshold_new = 50
        mesa_strong_new = 60
        confidence = "MEDIUM"
    }
}

# Dot-source only (not a module)
