# Regime Position Sizing Library
# Adjust position sizes based on market regime for optimal risk management
# BULL_STRONG/BULL_WEAK/BEAR_WEAK: 1.0x
# BEAR_STRONG: 0.5x (risk reduction in capitulation)

function Get-RegimePositionSize {
    param(
        [decimal] $Capital,
        [string] $Regime = "BULL_STRONG",
        [double] $BasePercentage = 0.01,  # 1% default
        [switch] $Verbose
    )

    $multipliers = Get-RegimeMultipliers

    if (-not $multipliers.ContainsKey($Regime)) {
        if ($Verbose) { Write-Host "⚠️ Unknown regime '$Regime', using base position" -ForegroundColor Yellow }
        $Regime = "BULL_STRONG"  # Safety default
    }

    $multiplier = $multipliers[$Regime]
    $position = $Capital * $BasePercentage * $multiplier

    if ($Verbose) {
        Write-Host "Position for $($Regime): $([Math]::Round($position, 2)) (multiplier: $multiplier)" -ForegroundColor Cyan
    }

    return $position
}

function Get-RegimeMultipliers {
    return @{
        "BULL_STRONG" = 1.0
        "BULL_WEAK" = 1.0
        "BEAR_WEAK" = 1.0
        "BEAR_STRONG" = 0.5    # 50% reduction in extreme stress
    }
}

function Test-RegimePositionValid {
    param(
        [hashtable] $Position,
        [double] $HardCapPercent = 0.01
    )

    $capital = $Position.capital
    $size = $Position.size
    $regime = $Position.regime ?? "BULL_STRONG"

    # Hard cap: never exceed 1% of capital
    $hardCap = $capital * $HardCapPercent
    if ($size -gt $hardCap) {
        return $false
    }

    # Regime-specific cap
    $multipliers = Get-RegimeMultipliers
    $mult = $multipliers[$regime] ?? 1.0
    $regimeCap = $capital * $HardCapPercent * $mult

    if ($size -gt $regimeCap) {
        return $false
    }

    return $true
}

function Adjust-PositionForRegime {
    param(
        [hashtable] $Position,
        [string] $NewRegime,
        [double] $HardCapPercent = 0.01
    )

    $capital = $Position.capital
    $currentSize = $Position.size
    $currentRegime = $Position.regime ?? "BULL_STRONG"

    if ($currentRegime -eq $NewRegime) {
        return @{
            size = $currentSize
            regime = $NewRegime
            adjusted = $false
            reason = "no change"
        }
    }

    # Calculate new size based on new regime multiplier
    $multipliers = Get-RegimeMultipliers
    $baseSize = $capital * $HardCapPercent
    $newMultiplier = $multipliers[$NewRegime] ?? 1.0
    $newSize = [Math]::Min($baseSize * $newMultiplier, $baseSize)

    return @{
        size = $newSize
        regime = $NewRegime
        adjusted = $true
        previous_size = $currentSize
        reason = "regime_change: $currentRegime → $NewRegime"
        multiplier_change = "$($multipliers[$currentRegime])x → $newMultiplier`x"
    }
}

function Get-RegimePositionLabel {
    param(
        [string] $Regime,
        [double] $Multiplier = 1.0
    )

    $labels = @{
        "BULL_STRONG" = "🚀 BULL_STRONG (pump) — Full position"
        "BULL_WEAK" = "📈 BULL_WEAK (recovery) — Full position"
        "BEAR_WEAK" = "📉 BEAR_WEAK (decline) — Full position"
        "BEAR_STRONG" = "🔴 BEAR_STRONG (capitulation) — CAUTION: 50% reduced"
    }

    $base = $labels[$Regime] ?? "UNKNOWN REGIME"
    $multStr = "$([Math]::Round($Multiplier, 1))x"

    return "$base [$multStr]"
}

function Get-RegimeContext {
    param(
        [string] $Regime
    )

    $contexts = @{
        "BULL_STRONG" = @{
            name = "Pump Phase"
            description = "Prices rising strong, volume elevated"
            stress = "LOW"
            volatility = "HIGH"
            trend_bias = "LONG"
            vol_climax_wr = 0.65
            combo_wr = 0.714
            position_size = 1.0
        }
        "BULL_WEAK" = @{
            name = "Recovery"
            description = "Prices rising slowly, low volatility"
            stress = "LOW"
            volatility = "LOW"
            trend_bias = "LONG"
            vol_climax_wr = 0.54
            combo_wr = 0.646
            position_size = 1.0
        }
        "BEAR_WEAK" = @{
            name = "Decline"
            description = "Prices falling slowly, low volatility"
            stress = "MEDIUM"
            volatility = "LOW"
            trend_bias = "SHORT"
            vol_climax_wr = 0.56
            combo_wr = 0.626
            position_size = 1.0
        }
        "BEAR_STRONG" = @{
            name = "Capitulation"
            description = "Prices falling fast, extreme volatility"
            stress = "CRITICAL"
            volatility = "EXTREME"
            trend_bias = "SHORT"
            vol_climax_wr = 0.52
            combo_wr = 0.616
            position_size = 0.5
        }
    }

    return $contexts[$Regime] ?? $contexts["BULL_STRONG"]
}

