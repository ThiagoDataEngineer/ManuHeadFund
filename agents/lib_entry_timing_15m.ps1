# lib_entry_timing_15m.ps1 -- Trendline 15M + RSI entry timing gate
# 2026-07-15: Gate #2 — refina entry timing em setups daily ja confirmados
# Evita entry em overbought, captura breaking points com volume

param()

$script:__entryCache = @{}
$script:__entryCacheAt = @{}

function _CalculateRSI {
    <#
    .SYNOPSIS
        Calcula RSI 14-period (Wilder's smoothing).
        Formula: RSI = 100 - (100 / (1 + RS)), onde RS = avg_gain / avg_loss
    #>
    param(
        [double[]] $Closes,
        [int] $Period = 14
    )

    if ($Closes.Count -lt $Period + 1) {
        return 50  # Fallback: neutral
    }

    $gains = 0.0
    $losses = 0.0

    # Calculate gains/losses over last $Period candles
    for ($i = $Closes.Count - $Period; $i -lt $Closes.Count; $i++) {
        $change = $Closes[$i] - $Closes[$i - 1]
        if ($change -gt 0) {
            $gains += $change
        } else {
            $losses += [Math]::Abs($change)
        }
    }

    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period

    if ($avgLoss -eq 0) {
        return if ($avgGain -gt 0) { 100 } else { 0 }
    }

    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}

function _CalculateVolumeRatio {
    <#
    .SYNOPSIS
        Calcula vol_ratio: volume recente vs histórico.
        vol_ratio = avg(last 3 candles) / avg(previous 7)
    #>
    param([double[]] $Volumes)

    if ($Volumes.Count -lt 10) {
        return 1.0
    }

    $vol3 = ($Volumes[($Volumes.Count - 3)..($Volumes.Count - 1)] | Measure-Object -Average).Average
    $vol7 = ($Volumes[($Volumes.Count - 10)..($Volumes.Count - 4)] | Measure-Object -Average).Average

    if ($vol7 -eq 0) { return 1.0 }
    return $vol3 / $vol7
}

function Get-TrendlineEntrySignal {
    <#
    .SYNOPSIS
        Usa daily trendline score + 15M RSI/volume para TIMING de entry.
        Retorna: signal {ENTER|WAIT|SKIP}, confidence, RSI, vol_ratio.
    .PARAMETER Market
        Symbol (ex: DODOUSDT)
    .PARAMETER DailyTrendlineScore
        Score daily trendline (de Get-TrendlineScore). Se <70, retorna SKIP.
    .PARAMETER UseCache
        Se $true, cache 15min (15M velas nao mudam rapido).
    .EXAMPLE
        $sig = Get-TrendlineEntrySignal -Market DODOUSDT -DailyTrendlineScore 75
        $sig.signal  # "ENTER" | "WAIT" | "SKIP"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $DailyTrendlineScore,
        [bool] $UseCache = $true,
        [int] $CacheMinutes = 15,
        [int] $Limit15m = 30
    )

    # === Check cache ===
    if ($UseCache -and $script:__entryCache.ContainsKey($Market)) {
        $cacheTime = $script:__entryCacheAt[$Market]
        if ($cacheTime -and ((Get-Date) - $cacheTime).TotalMinutes -lt $CacheMinutes) {
            return $script:__entryCache[$Market]
        }
    }

    try {
        # === Validate daily trendline ===
        if ($DailyTrendlineScore -lt 70) {
            return @{
                signal = "skip"
                confidence = 0
                reason = "daily_trendline_weak_score_$DailyTrendlineScore"
                rsi_15m = 0
                vol_ratio = 0
                daily_trendline_score = $DailyTrendlineScore
                ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        # === Fetch 15M candles ===
        $candles15m = @(Get-CoinExCandles -Market $Market -Period "15min" -Limit $Limit15m -ErrorAction Stop)
        if ($candles15m.Count -lt 10) {
            return @{
                signal = "wait"
                confidence = 0.40
                reason = "insufficient_15m_data"
                rsi_15m = 0
                vol_ratio = 0
                daily_trendline_score = $DailyTrendlineScore
                ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        # === Extract OHLCV ===
        $closes = @($candles15m | ForEach-Object { [double]$_.close })
        $volumes = @($candles15m | ForEach-Object { [double]$_.volume })

        # === Calculate RSI 14 ===
        $rsi = _CalculateRSI -Closes $closes -Period 14
        $rsi = [Math]::Round($rsi, 1)

        # === Calculate volume ratio ===
        $volRatio = _CalculateVolumeRatio -Volumes $volumes
        $volRatio = [Math]::Round($volRatio, 2)

        # === Decision tree ===
        $signal = "wait"
        $confidence = 0.50
        $reason = ""

        if ($rsi -lt 70) {
            # Good: not overbought
            $signal = "enter"
            $confidence = 0.85
            $reason = "rsi_not_overbought_$rsi"

            # Boost confidence if volume confirms
            if ($volRatio -gt 1.5) {
                $confidence = 0.95
                $reason += "_vol_spike_$volRatio"
            }
        } elseif ($rsi -le 80) {
            # Marginal: could wait for pullback
            $signal = "wait"
            $confidence = 0.60
            $reason = "rsi_elevated_$rsi`_wait_pullback"
        } else {
            # Bad: overbought (like DODO case)
            $signal = "skip"
            $confidence = 0.75
            $reason = "rsi_overbought_$rsi`_skip_cycle"
        }

        $result = @{
            signal = $signal
            confidence = [Math]::Round($confidence, 3)
            reason = $reason
            rsi_15m = $rsi
            vol_ratio = $volRatio
            daily_trendline_score = $DailyTrendlineScore
            details = @{
                rsi_threshold_overbought = 70
                rsi_threshold_very_overbought = 80
                vol_ratio_threshold_spike = 1.5
            }
            ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        # === Cache result ===
        $script:__entryCache[$Market] = $result
        $script:__entryCacheAt[$Market] = Get-Date

        return $result

    } catch {
        return @{
            signal = "error"
            confidence = 0
            reason = "exception: $_"
            rsi_15m = 0
            vol_ratio = 0
            daily_trendline_score = $DailyTrendlineScore
            ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

function Test-EntryTimingGate {
    <#
    .SYNOPSIS
        Aplica entry timing como gate.
        Aplica desconto no score Tori baseado em entry_signal.
    .PARAMETER Market
        Symbol
    .PARAMETER DailyTrendlineScore
        Score daily trendline
    .PARAMETER ToriScore
        Score Tori (de mesa). Sera ajustado por entry_signal_discount.
    .EXAMPLE
        $gate = Test-EntryTimingGate -Market DODOUSDT -DailyTrendlineScore 75 -ToriScore 60
        $gate.effective_tori_score  # 60 - discount
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $DailyTrendlineScore,
        [Parameter(Mandatory)] [int] $ToriScore
    )

    $entrySignal = Get-TrendlineEntrySignal -Market $Market -DailyTrendlineScore $DailyTrendlineScore

    # === Discount logic ===
    # ENTER: no discount (confidence high)
    # WAIT: -10 discount (wait for better signal)
    # SKIP: -25 discount (overbought, skip this cycle)
    # ERROR: -50 discount (fail safe)

    $discount = switch ($entrySignal.signal) {
        "enter" { 0 }
        "wait" { 10 }
        "skip" { 25 }
        "error" { 50 }
        default { 20 }
    }

    $effectiveScore = $ToriScore - $discount

    return [PSCustomObject]@{
        signal = $entrySignal.signal
        confidence = $entrySignal.confidence
        rsi_15m = $entrySignal.rsi_15m
        vol_ratio = $entrySignal.vol_ratio
        tori_score_original = $ToriScore
        entry_signal_discount = $discount
        effective_tori_score = $effectiveScore
        passes_gate = $effectiveScore -ge 60  # Default gate threshold
        reason = $entrySignal.reason
        source = "entry_timing_gate"
    }
}

function Format-EntryTimingReport {
    <#
    .SYNOPSIS
        Formata entry timing para logging/Telegram.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $Signal,
        [bool] $Verbose = $false
    )

    $icon = switch ($Signal.signal) {
        "enter" { "[ENTER]" }
        "wait" { "[WAIT]" }
        "skip" { "[SKIP]" }
        default { "[?]" }
    }

    $line1 = "$icon $Market`: RSI=$($Signal.rsi_15m) VolRatio=$($Signal.vol_ratio) Conf=$($Signal.confidence)"

    if ($Verbose) {
        $line2 = "  Tori: $($Signal.tori_score_original) - $($Signal.entry_signal_discount) discount = $($Signal.effective_tori_score) (passes: $($Signal.passes_gate))"
        $line3 = "  Reason: $($Signal.reason)"
        return @($line1, $line2, $line3) -join "`n"
    }

    return $line1
}
