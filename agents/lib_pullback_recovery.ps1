# lib_pullback_recovery.ps1 — PULL_BACK_RECOVERY Pattern Detection
# Detecta pump falso → pullback → recovery setup (LONG)
# TDD: 10 funções, cada uma testada
# 2026-06-08

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:PullbackConfig = @{
    min_pump_multiple = 5.0
    min_pullback_pct = 20.0
    min_recovery_vol_ratio = 1.5
    max_support_distance_pct = 2.0
    min_liquidity_usd = 50000
    min_confidence_threshold = 0.55
    position_size_pct = 0.003  # 0.3%
}

# ════════════════════════════════════════════════════════════
# TEST 1: Detecta pump (5x em 1-5 dias)
# ════════════════════════════════════════════════════════════

function Test-PumpDetected {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [double] $MinPumpMultiplier = 5.0
    )

    if ($Candles.Count -lt 2) { return @{ detected = $false } }

    $lowest = $Candles | Measure-Object -Property close -Minimum | Select-Object -ExpandProperty Minimum
    $highest = $Candles | Measure-Object -Property close -Maximum | Select-Object -ExpandProperty Maximum

    $pump_multiple = if ($lowest -gt 0) { $highest / $lowest } else { 0 }

    return @{
        detected = ($pump_multiple -ge $MinPumpMultiplier)
        pump_multiple = $pump_multiple
        lowest_price = $lowest
        highest_price = $highest
    }
}

# ════════════════════════════════════════════════════════════
# TEST 2: Detecta pullback testando suporte
# ════════════════════════════════════════════════════════════

function Test-PullbackDetected {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [Parameter(Mandatory=$true)][double] $SupportLevel,
        [double] $TolerancePct = 2.0
    )

    $tolerance_range = $SupportLevel * ($TolerancePct / 100)
    $min_price = $SupportLevel - $tolerance_range
    $max_price = $SupportLevel + $tolerance_range

    $tested_support = $Candles | Where-Object { $_.close -le $max_price -and $_.close -ge $min_price }

    if ($tested_support) {
        $closest_to_support = $tested_support | Sort-Object { [Math]::Abs($_.close - $SupportLevel) } | Select-Object -First 1
        $distance_pct = ([Math]::Abs($closest_to_support.close - $SupportLevel) / $SupportLevel) * 100

        return @{
            detected = $true
            support_tested = $true
            distance_from_support_pct = $distance_pct
            test_price = $closest_to_support.close
        }
    }

    return @{ detected = $false; support_tested = $false }
}

# ════════════════════════════════════════════════════════════
# TEST 3: Detecta volume recovery
# ════════════════════════════════════════════════════════════

function Test-VolumeRecovery {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [int] $PullbackIndex = 3,
        [double] $MinRecoveryRatio = 1.5
    )

    if ($Candles.Count -le $PullbackIndex) {
        return @{ detected = $false }
    }

    $pullback_vol = $Candles[$PullbackIndex].vol
    $recovery_candles = $Candles | Select-Object -Skip ($PullbackIndex + 1) -First 3

    if ($recovery_candles.Count -eq 0) {
        return @{ detected = $false }
    }

    $recovery_avg_vol = $recovery_candles | Measure-Object -Property vol -Average | Select-Object -ExpandProperty Average
    $recovery_ratio = if ($pullback_vol -gt 0) { $recovery_avg_vol / $pullback_vol } else { 0 }

    return @{
        detected = ($recovery_ratio -ge $MinRecoveryRatio)
        vol_recovery_ratio = $recovery_ratio
        pullback_vol = $pullback_vol
        recovery_avg_vol = $recovery_avg_vol
    }
}

# ════════════════════════════════════════════════════════════
# TEST 4: Valida entry zone (acima prior high)
# ════════════════════════════════════════════════════════════

function Get-EntryZone {
    param(
        [Parameter(Mandatory=$true)][array] $Candles,
        [Parameter(Mandatory=$true)][double] $PullbackHighPrice
    )

    $entry_min = $PullbackHighPrice * 1.01  # Acima por 1%
    $entry_max = $PullbackHighPrice * 1.05  # Até 5% acima

    return @{
        entry_min = $entry_min
        entry_max = $entry_max
        entry_range = $entry_max - $entry_min
        prior_high = $PullbackHighPrice
    }
}

# ════════════════════════════════════════════════════════════
# TEST 5: Calcula risco (SL no suporte)
# ════════════════════════════════════════════════════════════

function Get-RiskParameters {
    param(
        [Parameter(Mandatory=$true)][double] $SupportLevel,
        [Parameter(Mandatory=$true)][double] $EntryPrice
    )

    $loss_pct = (($EntryPrice - $SupportLevel) / $EntryPrice) * 100
    $loss_usd_per_dollar = ($EntryPrice - $SupportLevel)

    return @{
        stop_loss = $SupportLevel
        entry_price = $EntryPrice
        loss_pct = $loss_pct
        loss_usd_per_dollar = $loss_usd_per_dollar
    }
}

# ════════════════════════════════════════════════════════════
# TEST 6: Calcula target (30x gem math)
# ════════════════════════════════════════════════════════════

function Get-TargetPrice {
    param(
        [Parameter(Mandatory=$true)][double] $EntryPrice,
        [int] $R_Multiple = 30
    )

    $target = $EntryPrice * $R_Multiple

    return @{
        target = $target
        entry = $EntryPrice
        r_multiple = $R_Multiple
        profit_usd_per_dollar = ($target - $EntryPrice)
    }
}

# ════════════════════════════════════════════════════════════
# TEST 7: Valida liquidity
# ════════════════════════════════════════════════════════════

function Test-LiquidityAdequate {
    param(
        [Parameter(Mandatory=$true)][double] $Volume24hUSD,
        [Parameter(Mandatory=$true)][double] $EntryUSD,
        [double] $MinVolumeUSD = 50000
    )

    $adequate = ($Volume24hUSD -ge $MinVolumeUSD)
    $slippage_risk = if ($Volume24hUSD -gt 0) { ($EntryUSD / $Volume24hUSD) * 100 } else { 100 }

    return @{
        adequate = $adequate
        volume_24h_usd = $Volume24hUSD
        entry_usd = $EntryUSD
        slippage_risk = $slippage_risk / 100  # Convert to 0-1
        recommendation = if ($adequate) { "OK" } else { "SKIP_LOW_LIQUIDITY" }
    }
}

# ════════════════════════════════════════════════════════════
# TEST 8: Confidence score
# ════════════════════════════════════════════════════════════

function Get-ConfidenceScore {
    param(
        [Parameter(Mandatory=$true)][hashtable] $Factors
    )

    $score = 0.0
    $max_score = 5.0

    if ($Factors.pump_detected) { $score += 1.0 }
    if ($Factors.pullback_detected) { $score += 1.0 }
    if ($Factors.volume_recovery) { $score += 1.0 }
    if ($Factors.liquidity_adequate) { $score += 1.0 }
    if ($Factors.support_clear) { $score += 1.0 }

    $confidence = $score / $max_score
    $action = if ($confidence -ge 0.70) { "EXECUTE" } elseif ($confidence -ge 0.55) { "CONSIDER" } else { "SKIP" }

    return @{
        confidence = $confidence
        score = $score
        max_score = $max_score
        action = $action
        recommendation = @{
            EXECUTE = "High confidence, proceed with entry"
            CONSIDER = "Medium confidence, monitor for confirmation"
            SKIP = "Low confidence, skip this setup"
        }[$action]
    }
}

# ════════════════════════════════════════════════════════════
# TEST 9: Real data pattern PEPE
# ════════════════════════════════════════════════════════════

function Detect-PullbackRecoveryPattern {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][array] $Candles
    )

    # Step 1: Detect pump
    $pump_result = Test-PumpDetected -Candles $Candles -MinPumpMultiplier 5.0
    if (-not $pump_result.detected) {
        return @{ detected = $false; reason = "PUMP_NOT_DETECTED" }
    }

    # Step 2: Identify support (first candle is base)
    $support_level = $Candles[0].close

    # Step 3: Detect pullback
    $pullback_result = Test-PullbackDetected -Candles $Candles -SupportLevel $support_level
    if (-not $pullback_result.detected) {
        return @{ detected = $false; reason = "PULLBACK_NOT_DETECTED" }
    }

    # Step 4: Detect volume recovery
    $volume_result = Test-VolumeRecovery -Candles $Candles -PullbackIndex 3
    if (-not $volume_result.detected) {
        return @{ detected = $false; reason = "VOLUME_RECOVERY_NOT_DETECTED" }
    }

    # Step 5: Calculate entry zone
    $max_price = $Candles | Measure-Object -Property close -Maximum | Select-Object -ExpandProperty Minimum
    $pullback_high = ($Candles | Where-Object { $_.close -le $support_level * 2 } | Measure-Object -Property close -Maximum | Select-Object -ExpandProperty Maximum)

    $entry_zone = Get-EntryZone -Candles $Candles -PullbackHighPrice ($pullback_high ?? $support_level * 2)

    # Step 6: Calculate risk
    $risk = Get-RiskParameters -SupportLevel $support_level -EntryPrice $entry_zone.entry_min

    # Step 7: Calculate target
    $target = Get-TargetPrice -EntryPrice $entry_zone.entry_min -R_Multiple 30

    # Step 8: Check liquidity
    $liquidity = Test-LiquidityAdequate -Volume24hUSD ($Candles[-1].vol * 10) -EntryUSD 500

    # Step 9: Confidence
    $factors = @{
        pump_detected = $pump_result.detected
        pullback_detected = $pullback_result.detected
        volume_recovery = $volume_result.detected
        liquidity_adequate = $liquidity.adequate
        support_clear = $true
    }
    $confidence_result = Get-ConfidenceScore -Factors $factors

    return @{
        detected = $true
        market = $Market
        phase = "PULLBACK"
        confidence = $confidence_result.confidence
        action = $confidence_result.action
        entry_price = $entry_zone.entry_min
        stop_loss = $risk.stop_loss
        target = $target.target
        r_multiple = 30
        position_size_pct = $script:PullbackConfig.position_size_pct
        risk_pct = $risk.loss_pct
        pump_multiple = $pump_result.pump_multiple
        volume_ratio = $volume_result.vol_recovery_ratio
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}
