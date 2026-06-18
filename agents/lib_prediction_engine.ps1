# lib_prediction_engine.ps1 — Predictive Learning Engine
# Forecast errors ANTES de acontecer, ajusta proativamente
# Temporal analysis + regime transition forecast
# Pure functions, TDD-driven

$ErrorActionPreference = "Stop"

# ============================================================================
# TEMPORAL ANALYSIS — Detect Trends + Forecast
# ============================================================================

function Analyze-ErrorTrend {
    <#
    .SYNOPSIS
    Linear regression: error_rate(t) = slope*t + intercept
    Predicts when error_rate hits critical threshold

    .PARAMETER ErrorHistory
    @(5, 6, 7, 9, 11, 13, 15) — % error por dia

    .PARAMETER CriticalThreshold
    Quando alertar (default 25%)

    .OUTPUTS
    @{
      slope = double (% per day)
      trend = "increasing"|"stable"|"decreasing"
      days_to_critical = int (-1 if won't reach)
      forecast_7d = @(current, +1day, +2day, ...)
      action = "raise_threshold"|"investigate"|"none"
    }
    #>
    param(
        [array]$ErrorHistory,
        [int]$CriticalThreshold = 25
    )

    if ($ErrorHistory.Count -lt 2) {
        return @{
            slope = 0
            trend = "insufficient_data"
            days_to_critical = -1
            forecast_7d = @()
            action = "none"
        }
    }

    # Linear regression: y = mx + b
    $n = $ErrorHistory.Count
    $xSum = 0
    $ySum = 0
    $xySum = 0
    $x2Sum = 0

    for ($i = 0; $i -lt $n; $i++) {
        $x = $i + 1
        $y = $ErrorHistory[$i]
        $xSum += $x
        $ySum += $y
        $xySum += $x * $y
        $x2Sum += $x * $x
    }

    $slope = ($n * $xySum - $xSum * $ySum) / ($n * $x2Sum - $xSum * $xSum)
    $intercept = ($ySum - $slope * $xSum) / $n

    # Classify trend
    $trend = if ($slope -gt 0.5) { "increasing_fast" }
    elseif ($slope -gt 0.1) { "increasing_slow" }
    elseif ($slope -lt -0.5) { "decreasing_fast" }
    elseif ($slope -lt -0.1) { "decreasing_slow" }
    else { "stable" }

    # Forecast next 5 days ahead (current + 5 = 6 total)
    $forecast = @($ErrorHistory[-1])  # Last known
    $daysTo = -1
    for ($i = 1; $i -le 5; $i++) {
        $predicted = $intercept + $slope * ($n + $i)
        $predicted = [math]::Max(0, [math]::Min(100, $predicted))  # Clamp 0-100
        $forecast += $predicted

        if ($predicted -ge $CriticalThreshold -and $daysTo -eq -1) {
            $daysTo = $i
        }
    }

    # Action
    $action = if ($daysTo -ge 0 -and $daysTo -le 3) { "raise_threshold_urgent" }
    elseif ($daysTo -ge 4 -and $daysTo -le 7) { "raise_threshold_planned" }
    elseif ($slope -gt 1.0) { "investigate_degradation" }
    else { "none" }

    @{
        slope = [math]::Round($slope, 3)
        trend = $trend
        days_to_critical = $daysTo
        forecast_7d = @($forecast | ForEach-Object { [math]::Round($_, 1) })
        action = $action
        intercept = [math]::Round($intercept, 2)
    }
}

function Analyze-SignalDegradation {
    <#
    .SYNOPSIS
    Detecta degradação de qualidade de sinal ao longo do tempo

    .PARAMETER SignalAccuracyHistory
    @(72, 70, 68, 65, 62) — % accuracy por período

    .PARAMETER Window
    Quantos períodos pra detectar trend (default 5)

    .OUTPUTS
    @{
      is_degrading = $true|$false
      degradation_rate = double (% per period)
      remaining_quality = int (0-100)
      recommendation = string
    }
    #>
    param(
        [array]$SignalAccuracyHistory,
        [int]$Window = 5
    )

    if ($SignalAccuracyHistory.Count -lt 2) {
        return @{
            is_degrading = $false
            degradation_rate = 0
            remaining_quality = 50
            recommendation = "insufficient_data"
        }
    }

    $startIdx = [math]::Max(0, $SignalAccuracyHistory.Count - $Window)
    $recent = $SignalAccuracyHistory[$startIdx..($SignalAccuracyHistory.Count-1)]
    $errors = @()
    foreach ($acc in $recent) {
        $errors += (100 - $acc)
    }
    $trend = Analyze-ErrorTrend -ErrorHistory $errors -CriticalThreshold 40

    $degrading = $trend.slope -gt 0.1
    $degradationRate = [math]::Abs($trend.slope)
    $lastAccuracy = $recent[$recent.Count-1]

    $recommendation = if ($lastAccuracy -lt 50) { "Signal broken — remove" }
    elseif ($degradationRate -gt 1.0) { "Rapid degradation — investigate" }
    elseif ($degrading) { "Gradual degradation — loosen threshold" }
    else { "Signal stable" }

    @{
        is_degrading = $degrading
        degradation_rate = [math]::Round($degradationRate, 2)
        remaining_quality = [math]::Round($lastAccuracy, 1)
        recommendation = $recommendation
    }
}

# ============================================================================
# REGIME TRANSITION FORECAST
# ============================================================================

function Forecast-RegimeTransition {
    <#
    .SYNOPSIS
    State machine: forecast próximo regime + dias até transition

    .PARAMETER CurrentDSR
    Valor atual de DSR (0-2, target 1.0)

    .PARAMETER DSRHistory
    Últimos 7 dias: @(1.05, 1.03, 1.01, 0.99, 0.97, 0.95, 0.93)

    .PARAMETER MomentumValue
    -1 (bearish) a +1 (bullish)

    .OUTPUTS
    @{
      current_regime = "BULL_STRONG"|"BULL_WEAK"|"BEAR_WEAK"|"BEAR_STRONG"
      forecast_regime = string
      days_to_transition = int
      confidence = 0-100
      pre_adjust = @{ leverage, sl_tightness, entry_aggression }
    }
    #>
    param(
        [double]$CurrentDSR = 1.0,
        [array]$DSRHistory = @(),
        [double]$MomentumValue = 0,
        [int]$LookAheadDays = 3
    )

    # Classify current regime
    $currentRegime = if ($CurrentDSR -ge 1.2) { "BULL_STRONG" }
    elseif ($CurrentDSR -ge 1.0 -and $CurrentDSR -lt 1.2) { "BULL_WEAK" }
    elseif ($CurrentDSR -ge 0.8 -and $CurrentDSR -lt 1.0) { "BEAR_WEAK" }
    else { "BEAR_STRONG" }

    # Forecast trend
    $daysTo = -1
    $forecastRegime = $currentRegime

    if ($DSRHistory.Count -ge 3) {
        # Simple linear regression on DSR values
        $n = $DSRHistory.Count
        $xSum = 0
        $ySum = 0
        $xySum = 0
        $x2Sum = 0

        for ($i = 0; $i -lt $n; $i++) {
            $x = $i + 1
            $y = $DSRHistory[$i]
            $xSum += $x
            $ySum += $y
            $xySum += $x * $y
            $x2Sum += $x * $x
        }

        $slope = ($n * $xySum - $xSum * $ySum) / ($n * $x2Sum - $xSum * $xSum)

        # Projeto 3 dias pra frente
        $lastDSR = $DSRHistory[-1]
        $forecastDSR = $lastDSR + $slope * $LookAheadDays

        # Qual regime será?
        $forecastRegime = if ($forecastDSR -ge 1.2) { "BULL_STRONG" }
        elseif ($forecastDSR -ge 1.0) { "BULL_WEAK" }
        elseif ($forecastDSR -ge 0.8) { "BEAR_WEAK" }
        else { "BEAR_STRONG" }

        # Dias até mudança
        if ($forecastRegime -ne $currentRegime) {
            $daysTo = [math]::Max(1, [int]($LookAheadDays / 2))
        }
    }

    # Pre-adjustment recomendações
    $preAdj = @{
        leverage = 1.0
        sl_tightness = 5  # % stop loss width
        entry_aggression = "normal"
    }

    if ($forecastRegime -eq "BEAR_STRONG") {
        $preAdj.leverage = 0.5
        $preAdj.sl_tightness = 3
        $preAdj.entry_aggression = "conservative"
    }
    elseif ($forecastRegime -eq "BULL_STRONG") {
        $preAdj.leverage = 1.4
        $preAdj.sl_tightness = 7
        $preAdj.entry_aggression = "aggressive"
    }

    $confidence = if ($DSRHistory.Count -ge 7) { 85 } else { 50 }

    @{
        current_regime = $currentRegime
        forecast_regime = $forecastRegime
        days_to_transition = $daysTo
        confidence = $confidence
        pre_adjust = $preAdj
    }
}

# ============================================================================
# ADAPTIVE CONVICTION THRESHOLD — Multi-Factor
# ============================================================================

function Calculate-AdaptiveConvictionThreshold {
    <#
    .SYNOPSIS
    Conviction threshold = base + time-of-day + regime + signal-quality + trend adjustments

    .PARAMETER BaseThreshold
    Default 55

    .PARAMETER TimeOfDay
    "asia"|"eu"|"us" (00-06/06-12/12-18 UTC)

    .PARAMETER Regime
    "BULL_STRONG"|"BEAR_STRONG"|etc

    .PARAMETER ErrorTrend
    @{ action = "raise_threshold_urgent"|"none" }

    .PARAMETER SignalQuality
    @{ remaining_quality = 70, is_degrading = $true }

    .OUTPUTS
    @{
      threshold = int (45-100)
      breakdown = @{ base, time_of_day, regime, error_trend, signal_quality }
      rationale = string
    }
    #>
    param(
        [int]$BaseThreshold = 55,
        [string]$TimeOfDay = "eu",
        [string]$Regime = "BULL_WEAK",
        [hashtable]$ErrorTrend = @{},
        [hashtable]$SignalQuality = @{}
    )

    $adjustments = @{}

    # Time-of-day adjustment
    $adjustments.time_of_day = switch ($TimeOfDay) {
        { $_ -eq "asia" } { 5 }
        { $_ -eq "us" } { 3 }
        { $_ -eq "eu" } { -3 }
        default { 0 }
    }

    # Regime adjustment
    $adjustments.regime = switch ($Regime) {
        { $_ -eq "BULL_STRONG" } { -5 }
        { $_ -eq "BULL_WEAK" } { 0 }
        { $_ -eq "BEAR_WEAK" } { 3 }
        { $_ -eq "BEAR_STRONG" } { 8 }
        default { 0 }
    }

    # Error trend adjustment
    $errAction = $ErrorTrend.action
    $adjustments.error_trend = switch ($errAction) {
        { $_ -eq "raise_threshold_urgent" } { 10 }
        { $_ -eq "raise_threshold_planned" } { 5 }
        { $_ -eq "investigate_degradation" } { 7 }
        default { 0 }
    }

    # Signal quality adjustment
    $quality = if ($SignalQuality.remaining_quality) { $SignalQuality.remaining_quality } else { 70 }
    $adjustments.signal_quality = if ($quality -lt 60) { 5 } else { 0 }

    # Calculate final
    $total = $BaseThreshold + ($adjustments.Values | Measure-Object -Sum).Sum
    $final = [math]::Max(45, [math]::Min(100, $total))

    $rationale = @(
        "base=$BaseThreshold"
        if ($adjustments.time_of_day -ne 0) { "time_of_day=$(+$($adjustments.time_of_day))" }
        if ($adjustments.regime -ne 0) { "regime=$(+$($adjustments.regime))" }
        if ($adjustments.error_trend -ne 0) { "error_trend=$(+$($adjustments.error_trend))" }
        if ($adjustments.signal_quality -ne 0) { "signal_quality=$(+$($adjustments.signal_quality))" }
    ) -join " "

    @{
        threshold = $final
        breakdown = $adjustments
        rationale = $rationale
    }
}

# Functions auto-exported (no Export-ModuleMember needed for tests)
