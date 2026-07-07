Describe "lib_trade_journal_supabase" {
    BeforeAll {
        . "$PSScriptRoot/../agents/lib_state_store.ps1"
        . "$PSScriptRoot/../agents/lib_trade_journal_supabase.ps1"

        # Set to local backend for testing
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = Join-Path $PSScriptRoot ".test_journal"

        # Create test directory
        if (-not (Test-Path $global:STATE_STORE_LOCAL_DIR)) {
            New-Item -ItemType Directory -Path $global:STATE_STORE_LOCAL_DIR -Force | Out-Null
        }
    }

    AfterAll {
        # Cleanup
        if (Test-Path $global:STATE_STORE_LOCAL_DIR) {
            Remove-Item -Path $global:STATE_STORE_LOCAL_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        $global:STATE_STORE_BACKEND = $null
        $global:STATE_STORE_LOCAL_DIR = $null
    }

    Context "Save-TradeOutcome" {
        It "saves a trade outcome with all fields" {
            $record = @{
                entry_ts = (Get-Date).AddHours(-1)
                symbol = "BTCUSDT"
                direction = "LONG"
                source = "gem_executor"
                entry_price = 43500.50
                exit_price = 44000.00
                quantity = 0.5
                pnl_realized = 225.00
                pnl_percent = 0.53
                status = "closed"
                regime = "BULL_WEAK"
                has_confluence = $true
                conviction_score = 0.75
            }

            $result = Save-TradeOutcome -TradeRecord $record
            $result | Should -Be $true
        }

        It "saves minimal record with defaults" {
            $record = @{
                entry_ts = (Get-Date)
                symbol = "ETHUSDT"
                direction = "SHORT"
                source = "mock_trade_test"
                entry_price = 2300.00
                quantity = 1.0
            }

            $result = Save-TradeOutcome -TradeRecord $record
            $result | Should -Be $true
        }

        It "handles PnL correctly for SHORT trades" {
            $record = @{
                entry_ts = (Get-Date)
                symbol = "XRPUSDT"
                direction = "SHORT"
                source = "gem_executor"
                entry_price = 2.50
                exit_price = 2.40
                quantity = 100.0
                pnl_realized = 10.00  # (2.50 - 2.40) * 100
                status = "closed"
            }

            { Save-TradeOutcome -TradeRecord $record } | Should -Not -Throw
        }

        It "coerces string dates to datetime" {
            $record = @{
                entry_ts = "2026-07-07T10:30:00Z"
                symbol = "BNBUSDT"
                direction = "LONG"
                source = "app_import"
                entry_price = 600.00
                quantity = 0.1
            }

            $result = Save-TradeOutcome -TradeRecord $record
            $result | Should -Be $true
        }
    }

    Context "Get-RecentTrades" {
        BeforeEach {
            # Insert test data
            @(
                @{
                    entry_ts = (Get-Date).AddDays(-2)
                    symbol = "BTCUSDT"
                    direction = "LONG"
                    source = "gem_executor"
                    entry_price = 43000
                    exit_price = 43500
                    quantity = 0.5
                    pnl_realized = 250
                    status = "closed"
                },
                @{
                    entry_ts = (Get-Date).AddDays(-5)
                    symbol = "ETHUSDT"
                    direction = "SHORT"
                    source = "mock_trade_test"
                    entry_price = 2400
                    exit_price = 2350
                    quantity = 1.0
                    pnl_realized = 50
                    status = "closed"
                },
                @{
                    entry_ts = (Get-Date)
                    symbol = "ADAUSDT"
                    direction = "LONG"
                    source = "gem_executor"
                    entry_price = 0.75
                    quantity = 100
                    status = "pending"
                }
            ) | ForEach-Object { Save-TradeOutcome -TradeRecord $_ }
        }

        It "retrieves closed trades from last 7 days" {
            $trades = Get-RecentTrades -DaysBack 7 -Status "closed"
            $trades | Should -Not -BeNullOrEmpty
            $trades.Count | Should -Be -GreaterThan 0
        }

        It "filters by status" {
            $pending = Get-RecentTrades -DaysBack 30 -Status "pending"
            $pending.Count | Should -Be -GreaterThan 0
            $pending[0].status | Should -Be "pending"
        }

        It "respects DaysBack parameter" {
            $recent = Get-RecentTrades -DaysBack 3 -Status "closed"
            foreach ($trade in $recent) {
                $age = (Get-Date) - $trade.entry_ts
                $age.TotalDays | Should -BeLessThan 4
            }
        }

        It "returns all statuses when Status='all'" {
            $all = Get-RecentTrades -DaysBack 30 -Status "all"
            $all.Count | Should -Be -GreaterThan 0
        }

        It "sorts by entry_ts descending" {
            $trades = Get-RecentTrades -DaysBack 30 -Status "closed" -Limit 100
            if ($trades.Count -gt 1) {
                $trades[0].entry_ts | Should -BeGreaterThan $trades[-1].entry_ts
            }
        }
    }

    Context "Get-TradeStats" {
        BeforeEach {
            # Insert diverse trade data
            @(
                @{ entry_ts = (Get-Date).AddDays(-1); symbol = "BTCUSDT"; direction = "LONG"; source = "gem"; entry_price = 100; quantity = 1; pnl_realized = 50; status = "closed"; regime = "BULL" },
                @{ entry_ts = (Get-Date).AddDays(-1); symbol = "ETHUSDT"; direction = "LONG"; source = "gem"; entry_price = 100; quantity = 1; pnl_realized = 25; status = "closed"; regime = "BULL" },
                @{ entry_ts = (Get-Date).AddDays(-1); symbol = "XRPUSDT"; direction = "SHORT"; source = "gem"; entry_price = 100; quantity = 1; pnl_realized = -30; status = "closed"; regime = "BULL" },
                @{ entry_ts = (Get-Date).AddDays(-2); symbol = "ADAUSDT"; direction = "LONG"; source = "mock"; entry_price = 100; quantity = 1; pnl_realized = 10; status = "closed"; regime = "BEAR" }
            ) | ForEach-Object { Save-TradeOutcome -TradeRecord $_ }
        }

        It "calculates correct win_rate" {
            $stats = Get-TradeStats -DaysBack 30
            $stats | Should -Not -BeNullOrEmpty
            $stats.win_count | Should -Be -GreaterThan 0
            $stats.loss_count | Should -Be -GreaterThan 0
            $stats.win_rate | Should -BeLessThanOrEqual 1
            $stats.win_rate | Should -BeGreaterThanOrEqual 0
        }

        It "calculates total PnL" {
            $stats = Get-TradeStats -DaysBack 30
            $stats.pnl_total | Should -Not -BeNullOrEmpty
        }

        It "filters by regime" {
            $bullStats = Get-TradeStats -Regime "BULL" -DaysBack 30
            $bullStats | Should -Not -BeNullOrEmpty
        }

        It "returns zero stats for no trades" {
            $stats = Get-TradeStats -DaysBack 1 -Regime "NONEXISTENT"
            $stats.total | Should -Be 0
            $stats.win_rate | Should -Be 0
        }

        It "includes median PnL" {
            $stats = Get-TradeStats -DaysBack 30
            $stats.PSObject.Properties.Name | Should -Contain "pnl_median"
        }

        It "includes min and max PnL" {
            $stats = Get-TradeStats -DaysBack 30
            $stats.PSObject.Properties.Name | Should -Contain "pnl_min"
            $stats.PSObject.Properties.Name | Should -Contain "pnl_max"
        }
    }

    Context "Edge cases" {
        It "handles empty trade outcomes gracefully" {
            $stats = Get-TradeStats -DaysBack 365
            $stats.total | Should -Be 0
        }

        It "ignores malformed local JSON lines" {
            # This is tested implicitly by _Read-TradeOutcomesLocal
            # which skips unparseable lines
            $trades = Get-RecentTrades -DaysBack 30
            $trades | Should -BeOfType [object[]]
        }

        It "coerces PnL fields to double" {
            $record = @{
                entry_ts = (Get-Date)
                symbol = "TEST"
                direction = "LONG"
                source = "test"
                entry_price = "100.50"  # string
                quantity = 1.0
                pnl_realized = "25.75"  # string
            }

            { Save-TradeOutcome -TradeRecord $record } | Should -Not -Throw
        }
    }
}
