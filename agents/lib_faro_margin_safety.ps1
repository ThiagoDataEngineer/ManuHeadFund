# lib_faro_margin_safety.ps1 — Intelligent 2x margin with auto-liquidation safety

function Calculate-MarginPosition {
    param(
        [decimal] $BasePositionSize = 50,
        [int] $SignalScore = 70,
        [int] $SignalCount = 5,
        [decimal] $MaxMargin = 2.0
    )

    # Margin only activated on 6/7 signals (5/7 = no margin)
    if ($SignalCount -lt 6) {
        return [PSCustomObject]@{
            base_size = $BasePositionSize
            leverage = 1.0
            effective_size = $BasePositionSize
            margin_used = $false
            reason = "Insufficient signals ($SignalCount/7)"
        }
    }

    # Score-based leverage tiers (6/7+ signals required)
    $leverage = 1.0
    $reason = "Default 1x (below threshold)"

    if ($SignalScore -ge 96) {
        $leverage = [Math]::Min(2.0, $MaxMargin)
        $reason = "Score $SignalScore >= 96: 2x margin"
    }
    elseif ($SignalScore -ge 85) {
        $leverage = [Math]::Min(1.5, $MaxMargin)
        $reason = "Score $SignalScore >= 85: 1.5x margin"
    }
    elseif ($SignalScore -ge 75) {
        $leverage = 1.0
        $reason = "Score $SignalScore >= 75: No margin (safety)"
    }

    return [PSCustomObject]@{
        base_size = $BasePositionSize
        leverage = $leverage
        effective_size = [decimal]($BasePositionSize * $leverage)
        margin_used = ($leverage -gt 1.0)
        reason = $reason
        signal_score = $SignalScore
        signal_count = $SignalCount
    }
}

function Calculate-MarginStop {
    param(
        [decimal] $EntryPrice = 100,
        [decimal] $Leverage = 1.0,
        [decimal] $RiskPercent = 0.02  # -2% capital risk
    )

    # For 2x margin: -2% capital = -4% margin loss
    # So stop must be at: -2% * (1 / 2x) = -1% price
    # Formula: stop = entry * (1 - RiskPercent / Leverage)

    if ($Leverage -le 0) { return $EntryPrice }

    $riskAdjusted = $RiskPercent / $Leverage
    $stopPrice = $EntryPrice * (1 - $riskAdjusted)

    # For leverage 1.5x: -2% / 1.5 = -1.333% → rounds to 98.67, display as 98.0
    return [decimal]([Math]::Round($stopPrice, 1))
}

function Validate-MarginSafety {
    param(
        [decimal] $OpenPnL = 0,
        [decimal] $TotalCapital = 5000,
        [decimal] $Leverage = 1.0,
        [int] $OpenPositions = 1
    )

    # Safety thresholds
    $maxDrawdownPercent = 0.15  # 15% max drawdown before warning
    $liquidationThreshold = 0.20  # 20% loss triggers auto-liquidation

    $maxDrawdown = $TotalCapital * $maxDrawdownPercent
    $liquidationLevel = $TotalCapital * $liquidationThreshold

    $drawdownPercent = if ($OpenPnL -lt 0) { [Math]::Abs($OpenPnL) / $TotalCapital } else { 0 }
    $leverageRisk = $drawdownPercent * $Leverage

    # Safe if within max drawdown threshold
    $isSafe = ($OpenPnL -gt -$maxDrawdown)

    # Should liquidate if loss exceeds threshold OR leverage risk too high
    $shouldLiquidate = ($OpenPnL -lt -$liquidationLevel) -or ($leverageRisk -gt 0.30)

    return [PSCustomObject]@{
        open_pnl = $OpenPnL
        total_capital = $TotalCapital
        leverage = $Leverage
        open_positions = $OpenPositions
        drawdown_pct = [Math]::Round($drawdownPercent * 100, 2)
        leverage_risk_pct = [Math]::Round($leverageRisk * 100, 2)
        safe = $isSafe
        should_liquidate = $shouldLiquidate
        warning = if ($drawdownPercent -gt 0.10) { "HIGH DRAWDOWN: $([Math]::Round($drawdownPercent * 100, 1))%" } else { $null }
        margin_health = if ($leverageRisk -lt 0.2) { "GOOD" } elseif ($leverageRisk -lt 0.3) { "CAUTION" } else { "DANGER" }
    }
}

function Get-EffectiveStopForLeverage {
    param(
        [decimal] $EntryPrice,
        [decimal] $DesiredCapitalStop = 0.02,  # -2% capital
        [decimal] $Leverage = 1.0
    )

    # What price stop protects us for the given leverage?
    # Example: 2x margin @ $100 entry, 2% capital risk
    # = -1% price stop (because -1% at 2x = -2% capital)

    $priceStop = $DesiredCapitalStop / $Leverage
    return [Math]::Round($EntryPrice * (1 - $priceStop), 2)
}

function Estimate-LiquidationPrice {
    param(
        [decimal] $EntryPrice,
        [decimal] $Leverage,
        [decimal] $MaintenanceMargin = 0.05  # Typically 5% for crypto
    )

    # At what price does margin call happen?
    # Liquidation = Entry - (Entry × MaintenanceMargin × Leverage)

    if ($Leverage -le 1) { return 0 }

    $liquidationPrice = $EntryPrice - ($EntryPrice * $MaintenanceMargin * $Leverage)
    return [Math]::Max(0, [Math]::Round($liquidationPrice, 2))
}
