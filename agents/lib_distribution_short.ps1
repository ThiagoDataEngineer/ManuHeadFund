# lib_distribution_short.ps1 — DISTRIBUTION_SHORT Pattern Detection
# Detecta distribuição → reversão → dump setup (SHORT)
# TDD: 10 funções, cada uma testada
# 2026-06-08

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:DistributionConfig = @{
    min_ath_retests = 2
    min_red_vs_green_ratio = 1.0
    min_volume_spike_ratio = 2.0
    min_confidence_threshold = 0.50
    position_size_pct = 0.002  # 0.2%
    stop_loss_margin_pct = 3.0
    target_drop_pct = 50.0
    max_hold_days = 5
}

# ════════════════════════════════════════════════════════════
# TEST 1: Detecta ATH retests 2-3x
# ════════════════════════════════════════════════════════════

function Test-ATHRetestPattern {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [Parameter(Mandatory=$true)][double] $ATHPrice,
        [double] $TolerancePct = 2.0
    )

    $tolerance = $ATHPrice * ($TolerancePct / 100)
    $retest_zone_min = $ATHPrice - $tolerance
    $retest_zone_max = $ATHPrice + $tolerance

    $retests = $Candles | Where-Object { $_.close -ge $retest_zone_min -and $_.close -le $retest_zone_max }
    $retest_count = @($retests).Count

    # Volume declining on retests (sign of weakness)
    $avg_vol_early = ($Candles | Select-Object -First 3 | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average)
    $avg_vol_late = ($retests | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average)
    $volume_declining = ($avg_vol_late -lt $avg_vol_early)

    return @{
        detected = ($retest_count -ge 2)
        retest_count = $retest_count
        volume_declining = $volume_declining
        ath_price = $ATHPrice
        retest_zone = @{ min = $retest_zone_min; max = $retest_zone_max }
    }
}

# ════════════════════════════════════════════════════════════
# TEST 2: Red vs Green structure (distribution)
# ════════════════════════════════════════════════════════════

function Test-RedVsGreenStructure {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [int] $WindowSize = 4
    )

    $recent = $Candles | Select-Object -Last $WindowSize

    $red_candles = $recent | Where-Object { $_.close -lt $_.open }
    $green_candles = $recent | Where-Object { $_.close -ge $_.open }

    $red_avg_size = if (@($red_candles).Count -gt 0) {
        $red_candles | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average
    } else { 0 }

    $green_avg_size = if (@($green_candles).Count -gt 0) {
        $green_candles | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average
    } else { 0 }

    $red_count = @($red_candles).Count
    $green_count = @($green_candles).Count

    return @{
        detected = ($red_count -ge $green_count -and $red_avg_size -ge $green_avg_size)
        red_count = $red_count
        green_count = $green_count
        red_avg_size = $red_avg_size
        green_avg_size = $green_avg_size
        ratio = if ($green_avg_size -gt 0) { $red_avg_size / $green_avg_size } else { 1.0 }
    }
}

# ════════════════════════════════════════════════════════════
# TEST 3: High volume confirmation
# ════════════════════════════════════════════════════════════

function Test-HighVolume {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [int] $WindowSize = 3,
        [double] $MinSpikeRatio = 2.0
    )

    $avg_vol_20 = $Candles | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average
    $recent = $Candles | Select-Object -Last $WindowSize
    $recent_avg = $recent | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average

    $spike_ratio = if ($avg_vol_20 -gt 0) { $recent_avg / $avg_vol_20 } else { 0 }

    return @{
        detected = ($spike_ratio -ge $MinSpikeRatio)
        vol_spike_ratio = $spike_ratio
        recent_avg_vol = $recent_avg
        historical_avg_vol = $avg_vol_20
    }
}

# ════════════════════════════════════════════════════════════
# TEST 4: Support level identification
# ════════════════════════════════════════════════════════════

function Get-SupportLevel {
    param(
        [Parameter(Mandatory=$true)][array] $Candles
    )

    $lows = $Candles | Select-Object -ExpandProperty low -Unique

    # Find price level that was tested multiple times (within 1% tolerance)
    $support_candidates = @()
    foreach ($price in $lows) {
        $touches = @($Candles | Where-Object { [Math]::Abs($_.low - $price) / $price -lt 0.01 }).Count
        if ($touches -ge 2) {
            $support_candidates += @{ price = $price; touches = $touches }
        }
    }

    if ($support_candidates) {
        $support = $support_candidates | Sort-Object -Property touches -Descending | Select-Object -First 1
        return @{
            identified = $true
            support_price = $support.price
            touches = $support.touches
        }
    }

    # Fallback: lowest low
    $lowest = $Candles | Measure-Object -Property low -Minimum | Select-Object -ExpandProperty Minimum
    return @{
        identified = $true
        support_price = $lowest
        touches = 1
    }
}

# ════════════════════════════════════════════════════════════
# TEST 5: Entry on support break
# ════════════════════════════════════════════════════════════

function Test-SupportBreakEntry {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [Parameter(Mandatory=$true)][double] $SupportLevel
    )

    $recent = $Candles | Select-Object -Last 3
    $break_candle = $recent | Where-Object { $_.close -lt $SupportLevel } | Select-Object -First 1

    if (-not $break_candle) {
        return @{ triggered = $false; reason = "NO_SUPPORT_BREAK" }
    }

    # Check if volume confirms (volume > avg)
    $avg_vol = $recent | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average
    $vol_confirmed = ($break_candle.vol -ge $avg_vol * 1.5)

    return @{
        triggered = $vol_confirmed
        entry_price = $break_candle.close
        entry_confirmation = $vol_confirmed
        entry_volume = $break_candle.vol
        avg_volume = $avg_vol
    }
}

# ════════════════════════════════════════════════════════════
# TEST 6: Stop loss (above ATH +3%)
# ════════════════════════════════════════════════════════════

function Get-ShortStopLoss {
    param(
        [Parameter(Mandatory=$true)][double] $EntryPrice,
        [Parameter(Mandatory=$true)][double] $ATHPrice,
        [double] $Margin_pct = 3.0
    )

    $stop_loss = $ATHPrice * (1.0 + $Margin_pct / 100)
    $risk_pct = (($stop_loss - $EntryPrice) / $EntryPrice) * 100

    return @{
        stop_loss = $stop_loss
        entry_price = $EntryPrice
        ath_price = $ATHPrice
        margin_pct = $Margin_pct
        risk_pct = $risk_pct
    }
}

# ════════════════════════════════════════════════════════════
# TEST 7: Target (-50% ATH)
# ════════════════════════════════════════════════════════════

function Get-ShortTarget {
    param(
        [Parameter(Mandatory=$true)][double] $ATHPrice,
        [double] $TargetDrop_pct = 50.0
    )

    $target = $ATHPrice * (1.0 - $TargetDrop_pct / 100)

    return @{
        target = $target
        ath_price = $ATHPrice
        drop_pct = $TargetDrop_pct
        profit_pct = $TargetDrop_pct
    }
}

# ════════════════════════════════════════════════════════════
# TEST 8: Timing critical warning
# ════════════════════════════════════════════════════════════

function Get-TimingCritical {
    param(
        [Parameter(Mandatory=$true)][hashtable] $Factors
    )

    $factors_met = @($Factors.Values | Where-Object { $_ -eq $true }).Count

    $critical = ($factors_met -ge 2)

    return @{
        timing_critical = $critical
        entry_window_bars = 2
        factors_met = $factors_met
        warning = if ($critical) { "Tight timing window (1-2 bars), be ready" } else { "More time available" }
    }
}

# ════════════════════════════════════════════════════════════
# TEST 9: Real data BONK dump
# ════════════════════════════════════════════════════════════

function Detect-DistributionShortPattern {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][array] $Candles
    )

    # Step 1: Identify ATH
    $ath = $Candles | Measure-Object -Property close -Maximum | Select-Object -ExpandProperty Maximum

    # Step 2: Detect ATH retest pattern
    $ath_result = Test-ATHRetestPattern -Candles $Candles -ATHPrice $ath
    if (-not $ath_result.detected) {
        return @{ detected = $false; reason = "ATH_RETESTS_NOT_FOUND" }
    }

    # Step 3: Detect red vs green structure
    $red_green = Test-RedVsGreenStructure -Candles $Candles -WindowSize 4
    if (-not $red_green.detected) {
        return @{ detected = $false; reason = "RED_GREEN_PATTERN_NOT_FOUND" }
    }

    # Step 4: Check high volume
    $vol_result = Test-HighVolume -Candles $Candles -WindowSize 3
    if (-not $vol_result.detected) {
        return @{ detected = $false; reason = "VOLUME_SPIKE_NOT_FOUND" }
    }

    # Step 5: Identify support
    $support = Get-SupportLevel -Candles $Candles
    if (-not $support.identified) {
        return @{ detected = $false; reason = "SUPPORT_NOT_IDENTIFIED" }
    }

    # Step 6: Check for entry trigger
    $entry = Test-SupportBreakEntry -Candles $Candles -SupportLevel $support.support_price
    if (-not $entry.triggered) {
        return @{ detected = $false; reason = "SUPPORT_BREAK_NOT_TRIGGERED" }
    }

    # Step 7: Calculate SL and target
    $stop_loss = Get-ShortStopLoss -EntryPrice $entry.entry_price -ATHPrice $ath
    $target = Get-ShortTarget -ATHPrice $ath

    # Step 8: Timing critical
    $timing_factors = @{
        support_break_confirmed = $entry.entry_confirmation
        high_volume = $vol_result.detected
        red_structure = $red_green.detected
    }
    $timing = Get-TimingCritical -Factors $timing_factors

    # Step 9: Calculate confidence
    $confidence_factors = @{
        ath_retests = $ath_result.detected
        red_structure = $red_green.detected
        volume_confirmed = $vol_result.detected
        support_identified = $support.identified
        entry_triggered = $entry.triggered
    }
    $confidence = (@($confidence_factors.Values | Where-Object { $_ -eq $true }).Count / $confidence_factors.Count)

    return @{
        detected = $true
        market = $Market
        phase = "DISTRIBUTION"
        confidence = $confidence
        action = if ($confidence -ge 0.70) { "EXECUTE" } else { "CONSIDER" }
        entry_price = $entry.entry_price
        entry_type = "SUPPORT_BREAK"
        stop_loss = $stop_loss.stop_loss
        target = $target.target
        r_multiple = [Math]::Round(($entry.entry_price - $target.target) / ($stop_loss.stop_loss - $entry.entry_price), 2)
        position_size_pct = $script:DistributionConfig.position_size_pct
        risk_pct = $stop_loss.risk_pct
        timing_critical = $timing.timing_critical
        ath_price = $ath
        support_price = $support.support_price
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}
