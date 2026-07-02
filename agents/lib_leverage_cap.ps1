# lib_leverage_cap.ps1
# BLOCKER #3 FIX: Hard leverage cap enforcement
# 2026-06-18: Found 50x BNB, 20x XMR - need universal cap

function Get-SafeLeverage {
    <#
    .SYNOPSIS
        Get safe leverage (hard cap at 5x maximum)
    .PARAMETER RequestedLeverage
        Requested leverage (may be high, e.g., 50x)
    .PARAMETER ConvictionPercent
        Conviction 0-100 (higher = can use more leverage)
    .PARAMETER Mode
        Trade mode: "STANDARD" (default 2x), "SCALP" (1x), "PUMP_RIDE" (3x)
    .OUTPUTS
        Safe leverage value (1-5x)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [double]$RequestedLeverage = 2.0,
        [Parameter(Mandatory=$false)] [int]$ConvictionPercent = 50,
        [Parameter(Mandatory=$false)] [string]$Mode = "STANDARD"
    )

    # Base defaults by mode
    $baseDefault = switch ($Mode) {
        "SCALP"      { 1.0 }
        "PUMP_RIDE"  { 3.0 }
        "STANDARD"   { 2.0 }
        default      { 2.0 }
    }

    # Start with base default
    $leverage = $baseDefault

    # Adjust for conviction (higher conviction = can use more)
    if ($ConvictionPercent -gt 75) {
        # Elite conviction: can bump up leverage
        $leverage = [Math]::Min($baseDefault * 1.5, 5.0)  # Max 1.5x base, capped at 5x
    }
    elseif ($ConvictionPercent -lt 40) {
        # Low conviction: reduce leverage
        $leverage = [Math]::Max($baseDefault * 0.5, 1.0)  # Min 1x
    }

    # Hard cap: NEVER exceed 5x
    $leverage = [Math]::Min($leverage, 5.0)

    # Verify requested doesn't override cap
    if ($RequestedLeverage -gt $leverage) {
        Write-Warning "[LEVERAGE CAP] Requested $RequestedLeverage capped to $leverage"
    }

    return [Math]::Max($leverage, 1.0)  # Minimum 1x (no deleveraging)
}

function Test-LeverageSafe {
    <#
    .SYNOPSIS
        Test if leverage is within safe bounds
    .PARAMETER Leverage
        Leverage value to test
    .PARAMETER Capital
        Account capital
    .PARAMETER PositionSize
        Position size (USD)
    .OUTPUTS
        PSCustomObject with safe=true/false and reason
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [double]$Leverage,
        [Parameter(Mandatory=$true)] [double]$Capital,
        [Parameter(Mandatory=$true)] [double]$PositionSize
    )

    # Hard cap: never allow > 5x
    if ($Leverage -gt 5.0) {
        return @{
            safe = $false
            reason = "leverage_exceeds_cap_5x ($Leverage)"
            leverage = $Leverage
            max_allowed = 5.0
        }
    }

    # Liquidation check: position at 2% loss = liquidation if leverage too high
    # Formula: max_liq_price = entry * (1 - 1/leverage)
    # For 50x: liq = 1 - 1/50 = 2%
    # For 5x: liq = 1 - 1/5 = 20%
    $minSafeStop = 0.20  # 20% minimum before liquidation (for 5x)
    $actualLiquidationBuffer = 1.0 / $Leverage

    if ($actualLiquidationBuffer -lt 0.15) {  # Less than 15% buffer
        return @{
            safe = $false
            reason = "liquidation_buffer_too_tight_${[Math]::Round($actualLiquidationBuffer * 100)}pct"
            leverage = $Leverage
            liquidation_buffer_pct = $actualLiquidationBuffer * 100
            recommended_max_leverage = 5
        }
    }

    return @{
        safe = $true
        leverage = $Leverage
        liquidation_buffer_pct = $actualLiquidationBuffer * 100
    }
}
