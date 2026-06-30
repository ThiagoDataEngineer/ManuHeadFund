# Engulfing Pattern - Simplified
# Returns engulfing signal if: current body > previous body AND color reversal

function Detect-EngulfingPattern {
    param([array] $Candles, [int] $LookbackPeriod = 20, [bool] $Verbose = $false)

    if ($Candles.Count -lt 2) { return @() }

    $curr = $Candles[-1]
    $prev = $Candles[-2]

    $co = [double]$curr.open
    $cc = [double]$curr.close
    $po = [double]$prev.open
    $pc = [double]$prev.close

    $currBody = [Math]::Abs($cc - $co)
    $prevBody = [Math]::Abs($pc - $po)

    # Bullish: current green, prev red, current body larger
    if (($cc -gt $co) -and ($pc -lt $po) -and ($currBody -gt $prevBody)) {
        return @(@{
            type = "engulfing"
            direction = "bullish"
            confidence = 0.32
            current_candle = @{ open = $co; close = $cc; high = [double]$curr.high; low = [double]$curr.low }
            previous_candle = @{ open = $po; close = $pc; high = [double]$prev.high; low = [double]$prev.low }
            timestamp = $curr.timestamp
        })
    }

    # Bearish: current red, prev green, current body larger
    if (($cc -lt $co) -and ($pc -gt $po) -and ($currBody -gt $prevBody)) {
        return @(@{
            type = "engulfing"
            direction = "bearish"
            confidence = 0.32
            current_candle = @{ open = $co; close = $cc; high = [double]$curr.high; low = [double]$curr.low }
            previous_candle = @{ open = $po; close = $pc; high = [double]$prev.high; low = [double]$prev.low }
            timestamp = $curr.timestamp
        })
    }

    return @()
}

function Validate-EngulfingStrength {
    param([hashtable] $EngulfingPattern, [double] $MinEnvelopmentPct = 50)

    if (-not $EngulfingPattern) { return $false }

    # Caminho 1: pattern ja traz envelopment_pct calculado
    if ($null -ne $EngulfingPattern.envelopment_pct) {
        return ([double]$EngulfingPattern.envelopment_pct -ge $MinEnvelopmentPct)
    }

    # Caminho 2: deriva envelopment dos corpos das velas (output do Detect)
    if (-not $EngulfingPattern.current_candle) { return $false }

    $cb = [Math]::Abs($EngulfingPattern.current_candle.close - $EngulfingPattern.current_candle.open)
    $pb = [Math]::Abs($EngulfingPattern.previous_candle.close - $EngulfingPattern.previous_candle.open)

    if ($pb -eq 0) { return $false }

    return (($cb / $pb * 100) -ge $MinEnvelopmentPct)
}

function Get-EngulfingContext {
    param([array] $Candles, [int] $CurrentIndex)

    # index < 1: nao ha vela anterior p/ comparar (insuficiente)
    if ($CurrentIndex -lt 1) { return $null }

    $greenCount = 0
    for ($i = [Math]::Max(0, $CurrentIndex - 3); $i -lt $CurrentIndex; $i++) {
        if ([double]$Candles[$i].close -gt [double]$Candles[$i].open) { $greenCount++ }
    }

    $currVol = [double]($Candles[$CurrentIndex].volume ?? 0)
    $prevVol = [double]($Candles[$CurrentIndex - 1].volume ?? 0)

    return @{
        trend_before = if ($greenCount -ge 2) { "uptrend" } else { "downtrend" }
        momentum = if ($currVol -gt $prevVol) { "accelerating" } elseif ($prevVol -gt 0) { "decelerating" } else { "unknown" }
    }
}
