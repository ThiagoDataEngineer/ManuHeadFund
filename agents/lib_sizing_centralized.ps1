# lib_sizing_centralized.ps1
# BLOCKER #2 FIX: Single source of truth for position sizing
# 2026-06-18: Consolidate 0.01, 0.003, 0.002 into one function

function Get-SafePositionSize {
    <#
    .SYNOPSIS
        Calculate safe position size (central source of truth)
        - 1% of capital is max loss
        - Adjusts by conviction/risk
    .PARAMETER Capital
        Available capital (USD)
    .PARAMETER EntryPrice
        Entry price (to calculate position amount)
    .PARAMETER StopLossPercent
        SL distance from entry (e.g., 0.02 = 2%)
    .PARAMETER ConvictionPercent
        Confidence 0-100 (can reduce size for low conviction)
    .OUTPUTS
        PSCustomObject with:
          size_usd: position size in USD
          size_pct: percentage of capital
          max_loss_usd: actual max loss if SL hit
          leverage: if using margin (default 1x)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [double]$Capital,
        [Parameter(Mandatory=$true)] [double]$EntryPrice,
        [Parameter(Mandatory=$false)] [double]$StopLossPercent = 0.02,
        [Parameter(Mandatory=$false)] [int]$ConvictionPercent = 50,
        [Parameter(Mandatory=$false)] [double]$MaxLossPercent = 0.01  # 1% capital = max risk
    )

    # Base: 1% of capital
    $maxLossUsd = $Capital * $MaxLossPercent

    # Adjust by conviction (conservative: below 50 conviction = reduce size)
    if ($ConvictionPercent -lt 50) {
        $convictionFactor = [double]$ConvictionPercent / 50.0  # 0-1 scale
        $maxLossUsd = $maxLossUsd * $convictionFactor
    }

    # Calculate position size from SL distance
    $sizeUsd = if ($StopLossPercent -gt 0) {
        [Math]::Round($maxLossUsd / $StopLossPercent, 2)
    } else {
        $maxLossUsd  # Fallback if SL not set
    }

    # Cap size at reasonable leverage (no 50x)
    $maxSizeUsd = $Capital * 5  # Max 5x leverage
    $sizeUsd = [Math]::Min($sizeUsd, $maxSizeUsd)

    # Actual loss if SL hit
    $actualMaxLoss = $sizeUsd * $StopLossPercent
    $sizePercent = ($sizeUsd / $Capital) * 100

    return @{
        size_usd = $sizeUsd
        size_pct = $sizePercent
        max_loss_usd = $actualMaxLoss
        max_loss_pct = ($actualMaxLoss / $Capital) * 100
        entry_price = $EntryPrice
        sl_pct = $StopLossPercent
        conviction = $ConvictionPercent
        capital = $Capital
        valid = $sizeUsd -gt 0
    }
}

function Get-SafePositionSizeFromGem {
    <#
    .SYNOPSIS
        Get position size from Gem object (wrapper)
    .PARAMETER Gem
        Gem object with market, conviction, entry, stop_loss
    .PARAMETER Capital
        Available capital
    .OUTPUTS
        Same as Get-SafePositionSize
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Gem,
        [Parameter(Mandatory=$true)] [double]$Capital
    )

    $entry = [double]$(if ($null -ne $Gem.entry_price) { $Gem.entry_price } elseif ($null -ne $Gem.entry) { $Gem.entry } else { 0 })
    $stop = [double]($(if ($null -ne $Gem.stop_loss) { $Gem.stop_loss } else { 0 }))
    $conviction = [int]($(if ($null -ne $Gem.conviction) { $Gem.conviction } else { 50 }))

    if ($entry -le 0 -or $stop -le 0) {
        Write-Warning "Invalid entry/stop: entry=$entry stop=$stop"
        return $null
    }

    $slPct = [Math]::Abs(($entry - $stop) / $entry)

    return Get-SafePositionSize -Capital $Capital `
                                -EntryPrice $entry `
                                -StopLossPercent $slPct `
                                -ConvictionPercent $conviction
}
