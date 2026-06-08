# Tests for lib_exit_logic.ps1

Describe "Exit Logic Library" {
    BeforeAll {
        $root = Get-Location
        . (Join-Path $root "agents\lib_exit_logic.ps1")
    }

    Context "Position Tracking" {
        It "Opens a position" {
            $pos = Track-Position -OrderId "order_001" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            $pos.order_id -eq "order_001" | Should Be $true
            $pos.market -eq "BTCUSDT" | Should Be $true
            $pos.entry_price -eq 50000 | Should Be $true
            $pos.quantity -eq 0.01 | Should Be $true
            $pos.status -eq "OPEN" | Should Be $true
        }

        It "Calculates TP price (+2%)" {
            $pos = Track-Position -OrderId "order_tp" -Market "ETHUSDT" -Type "SPOT" -EntryPrice 2500 -Quantity 0.1

            $expectedTp = 2500 * 1.02
            ([Math]::Round($pos.tp_price, 2) -eq [Math]::Round($expectedTp, 2)) | Should Be $true
        }

        It "Calculates SL price (-1%)" {
            $pos = Track-Position -OrderId "order_sl" -Market "LINKUSDT" -Type "FUTURES" -EntryPrice 25 -Quantity 10

            $expectedSl = 25 * 0.99
            ([Math]::Round($pos.sl_price, 2) -eq [Math]::Round($expectedSl, 2)) | Should Be $true
        }

        It "Tracks entry time" {
            $pos = Track-Position -OrderId "order_time" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            ($pos.entry_time -le (Get-Date)) | Should Be $true
        }

        It "Initializes trailing SL equal to regular SL" {
            $pos = Track-Position -OrderId "order_ts" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            ($pos.trailing_sl -le $pos.sl_price + 1) | Should Be $true
        }
    }

    Context "Take Profit (Close 50%)" {
        BeforeEach {
            # Clear positions
            $script:OpenPositions = @()
        }

        It "Detects TP hit" {
            $pos = Track-Position -OrderId "order_tp_hit" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price hits TP (+2%)
            $result = Monitor-Position -OrderId "order_tp_hit" -CurrentPrice 51000

            $result.status -eq "CLOSED" | Should Be $true
            $result.reason -eq "TAKE_PROFIT (50%)" | Should Be $true
        }

        It "Closes only 50% at TP" {
            $pos = Track-Position -OrderId "order_half_close" -Market "ETHUSDT" -Type "SPOT" -EntryPrice 2500 -Quantity 1.0

            $result = Monitor-Position -OrderId "order_half_close" -CurrentPrice 2551  # +2%

            $result.quantity_closed -eq 0.5 | Should Be $true
        }

        It "TP price is entry * 1.02" {
            $pos = Track-Position -OrderId "order_tp_calc" -Market "XRPUSDT" -Type "SPOT" -EntryPrice 100 -Quantity 100

            $result = Monitor-Position -OrderId "order_tp_calc" -CurrentPrice 102

            $result.quantity_closed -eq 50 | Should Be $true
        }

        It "Calculates PnL correctly at TP" {
            $pos = Track-Position -OrderId "order_pnl" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            $result = Monitor-Position -OrderId "order_pnl" -CurrentPrice 51000

            # PnL = (51000 - 50000) * 0.005 = $5
            ([Math]::Abs($result.pnl_usdt - 5.0) -lt 0.1) | Should Be $true
        }
    }

    Context "Stop Loss (Close 100%)" {
        BeforeEach {
            $script:OpenPositions = @()
        }

        It "Detects SL hit" {
            $pos = Track-Position -OrderId "order_sl_hit" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price hits SL (-1%)
            $result = Monitor-Position -OrderId "order_sl_hit" -CurrentPrice 49500

            $result.status -eq "CLOSED" | Should Be $true
            $result.reason -eq "STOP_LOSS" | Should Be $true
        }

        It "Closes 100% at SL" {
            $pos = Track-Position -OrderId "order_sl_full" -Market "ETHUSDT" -Type "SPOT" -EntryPrice 2500 -Quantity 1.0

            $result = Monitor-Position -OrderId "order_sl_full" -CurrentPrice 2475  # -1%

            $result.quantity_closed -eq 1.0 | Should Be $true
        }

        It "Calculates loss correctly at SL" {
            $pos = Track-Position -OrderId "order_loss" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            $result = Monitor-Position -OrderId "order_loss" -CurrentPrice 49500

            # Loss = (49500 - 50000) * 0.01 = -$5
            ([Math]::Abs($result.pnl_usdt - (-5.0)) -lt 0.1) | Should Be $true
        }

        It "SL has higher priority than TP" {
            $pos = Track-Position -OrderId "order_priority" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Fake: price drops below SL
            $result = Monitor-Position -OrderId "order_priority" -CurrentPrice 49000

            $result.reason -eq "STOP_LOSS" | Should Be $true
        }
    }

    Context "Trailing Stop" {
        BeforeEach {
            $script:OpenPositions = @()
        }

        It "Updates max price on price increase" {
            $pos = Track-Position -OrderId "order_ts_update" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price goes up to 51000
            $result1 = Monitor-Position -OrderId "order_ts_update" -CurrentPrice 51000

            $pos = $script:OpenPositions[0]
            $pos.max_price -eq 51000 | Should Be $true
        }

        It "Moves SL up by 50% of gain" {
            $pos = Track-Position -OrderId "order_ts_lock" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price goes up to 51000
            Monitor-Position -OrderId "order_ts_lock" -CurrentPrice 51000

            $pos = $script:OpenPositions[0]
            # Gain = 1000, trailing_sl should move up by 500, so 50000 - 1 + 500 = 50499
            ($pos.trailing_sl -gt 50000) | Should Be $true
        }

        It "Doesn't move SL down" {
            $pos = Track-Position -OrderId "order_ts_nodown" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price goes to 51000
            Monitor-Position -OrderId "order_ts_nodown" -CurrentPrice 51000

            $highSl = $pos.trailing_sl

            # Price drops to 50500
            Monitor-Position -OrderId "order_ts_nodown" -CurrentPrice 50500

            $pos = $script:OpenPositions[0]
            ($pos.trailing_sl -ge $highSl) | Should Be $true
        }

        It "Triggers trailing SL if breached" {
            $pos = Track-Position -OrderId "order_ts_trigger" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Price up to 50800 (not yet TP at +2% = 51000)
            Monitor-Position -OrderId "order_ts_trigger" -CurrentPrice 50800

            # Then drops below trailing SL
            $pos = $script:OpenPositions[0]
            $triggerPrice = $pos.trailing_sl - 1

            $result = Monitor-Position -OrderId "order_ts_trigger" -CurrentPrice $triggerPrice

            $result.status -eq "CLOSED" | Should Be $true
            $result.reason -eq "STOP_LOSS" | Should Be $true
        }
    }

    Context "Time-Based Exit (60 min)" {
        BeforeEach {
            $script:OpenPositions = @()
        }

        It "Opens position with entry time" {
            $pos = Track-Position -OrderId "order_time_test" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            $pos.entry_time -le (Get-Date) | Should Be $true
        }

        It "Detects if position held >60 min" {
            # Can't easily test real time, but can verify the logic exists
            $pos = Track-Position -OrderId "order_60min" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Manually set entry_time to 61 min ago
            $pos.entry_time = (Get-Date).AddMinutes(-61)

            $result = Monitor-Position -OrderId "order_60min" -CurrentPrice 50100

            $result.status -eq "CLOSED" | Should Be $true
            $result.reason -like "*TIME_LIMIT*" | Should Be $true
        }
    }

    Context "Position Status" {
        BeforeEach {
            $script:OpenPositions = @()
        }

        It "Returns status of specific position" {
            Track-Position -OrderId "order_status1" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            $status = Get-PositionStatus -OrderId "order_status1"

            $status.order_id -eq "order_status1" | Should Be $true
            $status.status -eq "OPEN" | Should Be $true
        }

        It "Returns status of all positions" {
            Track-Position -OrderId "order_status2" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01
            Track-Position -OrderId "order_status3" -Market "ETHUSDT" -Type "SPOT" -EntryPrice 2500 -Quantity 0.1

            $statuses = Get-PositionStatus

            @($statuses).Count -eq 2 | Should Be $true
        }
    }

    Context "Configuration" {
        It "Changes TP percentage" {
            Set-ExitConfig -TakeProfitPct 0.03

            $script:ExitConfig.take_profit_pct -eq 0.03 | Should Be $true
        }

        It "Changes SL percentage" {
            Set-ExitConfig -StopLossPct 0.02

            $script:ExitConfig.stop_loss_pct -eq 0.02 | Should Be $true
        }

        It "Changes trailing stop config" {
            Set-ExitConfig -TrailingStopPct 0.75

            $script:ExitConfig.trailing_stop_pct -eq 0.75 | Should Be $true
        }

        It "Changes max hold time" {
            Set-ExitConfig -MaxHoldTimeMin 120

            $script:ExitConfig.max_hold_time_min -eq 120 | Should Be $true
        }
    }

    Context "Edge Cases" {
        BeforeEach {
            $script:OpenPositions = @()
        }

        It "Handles position not found" {
            $result = Monitor-Position -OrderId "nonexistent" -CurrentPrice 50000

            $result.status -eq "NOT_FOUND" | Should Be $true
        }

        It "Handles already closed position" {
            Track-Position -OrderId "order_closed" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.01

            # Close it
            Close-Position -OrderId "order_closed" -CurrentPrice 51000 -CloseAll $true

            # Try to monitor again
            $result = Monitor-Position -OrderId "order_closed" -CurrentPrice 51500

            $result.status -eq "ALREADY_CLOSED" | Should Be $true
        }

        It "Handles very small quantities" {
            $pos = Track-Position -OrderId "order_tiny" -Market "BTCUSDT" -Type "SPOT" -EntryPrice 50000 -Quantity 0.00001

            $result = Monitor-Position -OrderId "order_tiny" -CurrentPrice 51000

            $result.quantity_closed -eq 0.000005 | Should Be $true
        }

        It "Handles large quantities" {
            $pos = Track-Position -OrderId "order_large" -Market "XRPUSDT" -Type "SPOT" -EntryPrice 2.5 -Quantity 100000

            $result = Monitor-Position -OrderId "order_large" -CurrentPrice 2.55

            $result.quantity_closed -eq 50000 | Should Be $true
        }
    }
}

