<#
VOL_CLIMAX INTEGRATION LAYER
Adapta Detect-VolumeClimax (backtest) pra workflow de trading live.
Wire em gem_agent para boost score quando vol climax detectado.

Status: TDD Phase 1 - Function exists + tests defined
#>

function Test-VolClimaxSignal {
    param(
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [double] $ClimaxMultiplier = 2.5,  # Refined (backtest +8.6pp)
        [int]    $Lookback = 20,
        [nullable[double]] $RsiOversoldMax = 30  # Confluence RSI<30 (LONG)
    )
    <#
    .SYNOPSIS
    Detecta volume climax SEM chamar Detect-VolumeClimax (evita circular dep).
    Retorna score 0-100 para uso em gem_agent scoring.

    .PARAMETER Volumes, Closes, Highs, Lows
    Arrays de OHLCV (últimas N barras; current = last element)

    .PARAMETER ClimaxMultiplier
    Vol deve ser >= 2.5x média (refined backtest calibration 2026-05-22)

    .PARAMETER RsiOversoldMax
    Confluence: RSI < 30 (bearish) ou > 70 (bullish) confirma signal.
    Se null, ignora confluence (modo lenient).

    .OUTPUTS
    @{
        detected = $true | $false
        score = 0-100  # 0=no signal, 100=perfect climax
        direction = "LONG" | "SHORT" | "NONE"
        reason = "volume spike + RSI extreme"
    }
    #>

    $result = @{
        detected = $false
        score = 0
        direction = "NONE"
        reason = ""
    }

    # Validation
    if ($Volumes.Count -lt $Lookback -or $Closes.Count -lt $Lookback) {
        $result.reason = "Insufficient history"
        return $result
    }

    # Current bar
    $currVol = $Volumes[-1]
    $currClose = $Closes[-1]
    $currHigh = $Highs[-1]
    $currLow = $Lows[-1]

    # Average volume (excluding current)
    $histVol = $Volumes[0..($Volumes.Count - 2)]
    $avgVol = ($histVol | Measure-Object -Average).Average
    if ($avgVol -le 0) {
        $result.reason = "Invalid average volume"
        return $result
    }

    # Test 1: Volume spike
    $volRatio = $currVol / $avgVol
    if ($volRatio -lt $ClimaxMultiplier) {
        $result.reason = "Vol spike $volRatio`x < $ClimaxMultiplier`x threshold"
        return $result
    }

    # Test 2: Price extremity (near recent high or low)
    $high20 = ($Highs[-$Lookback..-1] | Measure-Object -Maximum).Maximum
    $low20 = ($Lows[-$Lookback..-1] | Measure-Object -Minimum).Minimum
    $range20 = $high20 - $low20

    $isNearHigh = ($high20 - $currClose) -le ($range20 * 0.05)  # Top 5%
    $isNearLow = ($currClose - $low20) -le ($range20 * 0.05)   # Bottom 5%

    if (-not ($isNearHigh -or $isNearLow)) {
        $result.reason = "Price not at extremes"
        return $result
    }

    # Test 3: RSI confluence (if requested)
    $rsiScore = 50  # Neutral
    if ($RsiOversoldMax -and $RsiOversoldMax -gt 0) {
        # Simple RSI calculation (14-period)
        $period = [Math]::Min(14, $Closes.Count)
        if ($period -ge 2) {
            $gains = @(); $losses = @()
            for ($i = $Closes.Count - $period; $i -lt $Closes.Count; $i++) {
                $delta = $Closes[$i] - $Closes[$i - 1]
                if ($delta -gt 0) { $gains += $delta } else { $losses += [Math]::Abs($delta) }
            }

            $avgGain = if ($gains.Count -gt 0) { ($gains | Measure-Object -Average).Average } else { 0 }
            $avgLoss = if ($losses.Count -gt 0) { ($losses | Measure-Object -Average).Average } else { 0 }

            $rsi = if ($avgLoss -gt 0) {
                100 - (100 / (1 + ($avgGain / $avgLoss)))
            } else {
                if ($avgGain -gt 0) { 100 } else { 50 }
            }

            # Score boost if RSI extreme
            if ($rsi -lt $RsiOversoldMax) {
                $rsiScore = 30 + (($RsiOversoldMax - $rsi) / $RsiOversoldMax) * 70
                $result.direction = "LONG"
            } elseif ($rsi -gt (100 - $RsiOversoldMax)) {
                $rsiScore = 30 + ((($rsi - (100 - $RsiOversoldMax)) / $RsiOversoldMax) * 70)
                $result.direction = "SHORT"
            } else {
                $rsiScore = 40
            }
        }
    } else {
        # No RSI confluence, just direction from price
        $result.direction = if ($isNearLow) { "LONG" } else { "SHORT" }
        $rsiScore = 60
    }

    # Calculate final score
    $volSpikeFactor = [Math]::Min(100, 40 + (($volRatio - $ClimaxMultiplier) / $ClimaxMultiplier) * 60)
    $result.score = [Math]::Round(($volSpikeFactor * 0.5) + ($rsiScore * 0.5), 2)
    $result.detected = $result.score -ge 65
    $result.reason = "Vol ${volRatio}x + RSI $rsiScore -> Direction=$($result.direction)"

    return $result
}

function Get-VolClimaxBoost {
    param(
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [int] $CurrentScore = 0
    )
    <#
    .SYNOPSIS
    Returns boost points (0-30) to add to gem_agent base score if vol climax detected.
    #>

    $signal = Test-VolClimaxSignal -Volumes $Volumes -Closes $Closes -Highs $Highs -Lows $Lows

    if ($signal.detected) {
        # Boost 15-30 points based on signal strength
        $boost = [Math]::Round(15 + ($signal.score - 65) / 35 * 15)
        return [Math]::Min(30, [Math]::Max(15, $boost))
    }

    return 0
}

# Note: Export-ModuleMember not needed for dot-sourcing in PowerShell scripts
# Functions are automatically available after . .\lib_vol_climax_integration.ps1
