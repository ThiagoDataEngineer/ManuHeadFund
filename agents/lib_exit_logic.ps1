# lib_exit_logic.ps1 — Exit management (TP, SL, Trailing, Time-based)
# Position monitoring + auto-close logic

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:ExitConfig = @{
    take_profit_pct = 0.02      # +2%
    stop_loss_pct = 0.01        # -1%
    take_profit_close_pct = 0.5 # Close 50% at TP
    trailing_stop_pct = 0.5     # Move SL up 50% of gain
    max_hold_time_min = 60      # Close after 60 min
    check_interval_sec = 5      # Check every 5 sec
}

# In-memory position tracking
$script:OpenPositions = @()

# ════════════════════════════════════════════════════════════
# OPEN POSITION (track after PlaceOrder)
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Track-Position -OrderId "xxx" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

.DESCRIPTION
    Store position data for monitoring. Called after successful PlaceOrder.
#>

function Track-Position {
    param(
        [Parameter(Mandatory=$true)][string] $OrderId,
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][ValidateSet("SPOT", "FUTURES")] $Type,
        [Parameter(Mandatory=$true)][double] $EntryPrice,
        [Parameter(Mandatory=$true)][double] $Quantity,
        [string] $ClientId = ""
    )

    $position = @{
        order_id = $OrderId
        market = $Market
        type = $Type
        entry_price = $EntryPrice
        quantity = $Quantity
        quantity_remaining = $Quantity
        entry_time = Get-Date
        client_id = $ClientId
        status = "OPEN"

        # Exit prices
        tp_price = $EntryPrice * (1 + $script:ExitConfig.take_profit_pct)
        sl_price = $EntryPrice * (1 - $script:ExitConfig.stop_loss_pct)

        # Trailing stop (initially = SL)
        trailing_sl = $EntryPrice * (1 - $script:ExitConfig.stop_loss_pct)
        max_price = $EntryPrice  # Track highest price for trailing

        # Execution tracking
        tp_executed = $false
        sl_executed = $false
        partial_closed = 0  # Quantity closed at TP
        close_price = $null
        close_reason = $null
    }

    $script:OpenPositions += $position

    Write-Host "📍 Position opened: $Market | Entry: $EntryPrice | TP: $($position.tp_price) | SL: $($position.sl_price)" -ForegroundColor Green

    return $position
}

# ════════════════════════════════════════════════════════════
# MONITOR POSITION (check for exit triggers)
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Monitor-Position -OrderId "xxx" -CurrentPrice 51000

.DESCRIPTION
    Check if TP/SL/time/trailing is hit. Auto-close if triggered.
    Returns: @{ action, reason, quantity_closed, price }
#>

function Monitor-Position {
    param(
        [Parameter(Mandatory=$true)][string] $OrderId,
        [Parameter(Mandatory=$true)][double] $CurrentPrice
    )

    $position = $script:OpenPositions | Where-Object { $_.order_id -eq $OrderId }
    if (-not $position) {
        return @{ status = "NOT_FOUND"; order_id = $OrderId }
    }

    if ($position.status -ne "OPEN") {
        return @{ status = "ALREADY_CLOSED"; reason = $position.close_reason }
    }

    # Update trailing stop (lock gains)
    if ($CurrentPrice -gt $position.max_price) {
        $position.max_price = $CurrentPrice
        $profit = $CurrentPrice - $position.entry_price
        if ($profit -gt 0) {
            $position.trailing_sl = $CurrentPrice - ($profit * $script:ExitConfig.trailing_stop_pct)
        }
    }

    # Check time-based exit (60 min)
    $holdTime = (Get-Date) - $position.entry_time
    if ($holdTime.TotalMinutes -ge $script:ExitConfig.max_hold_time_min) {
        return Close-Position -OrderId $OrderId -CurrentPrice $CurrentPrice -Reason "TIME_LIMIT (60min)"
    }

    # Check stop loss (CRITICAL - highest priority)
    if ($CurrentPrice -le $position.sl_price -or $CurrentPrice -le $position.trailing_sl) {
        return Close-Position -OrderId $OrderId -CurrentPrice $CurrentPrice -Reason "STOP_LOSS" -CloseAll $true
    }

    # Check take profit (close 50%)
    if ($CurrentPrice -ge $position.tp_price -and -not $position.tp_executed) {
        $qtyToClose = $position.quantity_remaining * $script:ExitConfig.take_profit_close_pct
        return Close-Position -OrderId $OrderId -CurrentPrice $CurrentPrice -Quantity $qtyToClose -Reason "TAKE_PROFIT (50%)"
    }

    # No action needed
    $pnl = (($CurrentPrice - $position.entry_price) / $position.entry_price) * 100
    return @{
        status = "MONITORING"
        order_id = $OrderId
        current_price = $CurrentPrice
        pnl_pct = [Math]::Round($pnl, 2)
        tp_price = $position.tp_price
        sl_price = $position.sl_price
        trailing_sl = [Math]::Round($position.trailing_sl, 4)
        time_held_min = [Math]::Round($holdTime.TotalMinutes, 1)
    }
}

# ════════════════════════════════════════════════════════════
# CLOSE POSITION (partial or full)
# ════════════════════════════════════════════════════════════

function Close-Position {
    param(
        [Parameter(Mandatory=$true)][string] $OrderId,
        [Parameter(Mandatory=$true)][double] $CurrentPrice,
        [double] $Quantity = 0,  # 0 = close all
        [string] $Reason = "MANUAL",
        [bool] $CloseAll = $false
    )

    $position = $script:OpenPositions | Where-Object { $_.order_id -eq $OrderId }
    if (-not $position) {
        return @{ status = "NOT_FOUND" }
    }

    $qtyToClose = if ($CloseAll -or $Quantity -le 0) { $position.quantity_remaining } else { [Math]::Min($Quantity, $position.quantity_remaining) }

    $pnl = ($CurrentPrice - $position.entry_price) * $qtyToClose
    $pnl_pct = (($CurrentPrice - $position.entry_price) / $position.entry_price) * 100

    Write-Host "🔴 Close-Position: $($position.market) | Qty: $qtyToClose | Price: $CurrentPrice | Reason: $Reason | PnL: $([Math]::Round($pnl, 2)) USDT ($([Math]::Round($pnl_pct, 2))%)" -ForegroundColor Yellow

    # Update position
    $position.quantity_remaining -= $qtyToClose
    $position.partial_closed += $qtyToClose
    $position.close_price = $CurrentPrice
    $position.close_reason = $Reason

    if ($position.quantity_remaining -le 0.00001) {
        # Fully closed
        $position.status = "CLOSED"
        $position.quantity_remaining = 0
    } else {
        # Partially closed, still monitoring
        $position.status = "PARTIAL"
    }

    return @{
        status = "CLOSED"
        order_id = $OrderId
        reason = $Reason
        quantity_closed = $qtyToClose
        close_price = $CurrentPrice
        pnl_usdt = [Math]::Round($pnl, 4)
        pnl_pct = [Math]::Round($pnl_pct, 2)
        time_held_min = [Math]::Round(((Get-Date) - $position.entry_time).TotalMinutes, 1)
    }
}

# ════════════════════════════════════════════════════════════
# AUTO-MONITOR LOOP (background worker)
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Start-ExitMonitor -UpdateFunc { param($OrderId, $Price) Get-LivePrice $OrderId }

.DESCRIPTION
    Run monitoring loop in background, call UpdateFunc to get live prices.
    UpdateFunc returns @{ order_id, price } for each open position.
#>

function Start-ExitMonitor {
    param(
        [Parameter(Mandatory=$true)][scriptblock] $UpdateFunc
    )

    Write-Host "🔄 ExitMonitor started (checking every $($script:ExitConfig.check_interval_sec)s)" -ForegroundColor Cyan

    while ($true) {
        try {
            # Get live prices for all open positions
            $positions = @($script:OpenPositions | Where-Object { $_.status -in @("OPEN", "PARTIAL") })

            if ($positions.Count -eq 0) {
                Start-Sleep -Seconds $script:ExitConfig.check_interval_sec
                continue
            }

            foreach ($pos in $positions) {
                try {
                    # Call update function to get current price
                    $priceData = & $UpdateFunc -OrderId $pos.order_id
                    if ($priceData -and $priceData.price) {
                        $result = Monitor-Position -OrderId $pos.order_id -CurrentPrice $priceData.price
                        if ($result.status -eq "CLOSED") {
                            Write-Host "✅ Position closed: $($result.reason)" -ForegroundColor Green
                        }
                    }
                } catch {
                    Write-Host "❌ Error monitoring $($pos.order_id): $($_.Exception.Message)" -ForegroundColor Red
                }
            }

            Start-Sleep -Seconds $script:ExitConfig.check_interval_sec
        } catch {
            Write-Host "❌ Monitor error: $($_.Exception.Message)" -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
    }
}

# ════════════════════════════════════════════════════════════
# POSITION SUMMARY
# ════════════════════════════════════════════════════════════

function Get-PositionStatus {
    param(
        [string] $OrderId = ""
    )

    if ($OrderId) {
        $pos = $script:OpenPositions | Where-Object { $_.order_id -eq $OrderId }
        if ($pos) {
            return @{
                order_id = $pos.order_id
                market = $pos.market
                status = $pos.status
                entry_price = $pos.entry_price
                quantity_remaining = $pos.quantity_remaining
                tp_price = $pos.tp_price
                sl_price = $pos.sl_price
                trailing_sl = $pos.trailing_sl
                time_held_min = [Math]::Round(((Get-Date) - $pos.entry_time).TotalMinutes, 1)
            }
        }
        return $null
    } else {
        # Return all positions
        return @($script:OpenPositions | ForEach-Object {
            @{
                order_id = $_.order_id
                market = $_.market
                status = $_.status
                entry_price = $_.entry_price
                qty_remaining = $_.quantity_remaining
                qty_closed = $_.partial_closed
                time_held_min = [Math]::Round(((Get-Date) - $_.entry_time).TotalMinutes, 1)
            }
        })
    }
}

# ════════════════════════════════════════════════════════════
# CONFIGURATION
# ════════════════════════════════════════════════════════════

function Set-ExitConfig {
    param(
        [double] $TakeProfitPct = 0.02,
        [double] $StopLossPct = 0.01,
        [double] $TakeProfitClosePct = 0.5,
        [double] $TrailingStopPct = 0.5,
        [int] $MaxHoldTimeMin = 60
    )

    $script:ExitConfig.take_profit_pct = $TakeProfitPct
    $script:ExitConfig.stop_loss_pct = $StopLossPct
    $script:ExitConfig.take_profit_close_pct = $TakeProfitClosePct
    $script:ExitConfig.trailing_stop_pct = $TrailingStopPct
    $script:ExitConfig.max_hold_time_min = $MaxHoldTimeMin

    Write-Host "⚙️ Exit config updated: TP=+$([Math]::Round($TakeProfitPct*100,1))% SL=-$([Math]::Round($StopLossPct*100,1))% TS=$([Math]::Round($TrailingStopPct*100,0))%" -ForegroundColor Cyan
}

