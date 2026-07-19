Describe "lib_position_sync_live" {
    BeforeAll {
        . "$PSScriptRoot/../agents/lib_state_store.ps1"
        . "$PSScriptRoot/../agents/lib_position_sync_live.ps1"
        . "$PSScriptRoot/../agents/lib_trade_journal_supabase.ps1"

        # Mock backend
        $global:STATE_STORE_BACKEND = "local"
        $global:STATE_STORE_LOCAL_DIR = Join-Path $PSScriptRoot ".test_positions"

        if (-not (Test-Path $global:STATE_STORE_LOCAL_DIR)) {
            New-Item -ItemType Directory -Path $global:STATE_STORE_LOCAL_DIR -Force | Out-Null
        }

        # Mock CoinEx functions
        function CoinEx-GetPendingPositions {
            param([bool]$IsFutures = $true)
            if ($global:TEST_POSITIONS) {
                return @($global:TEST_POSITIONS)
            }
            return @()
        }

        function CoinEx-GetClosedPositions {
            param([int]$Limit = 20)
            if ($global:TEST_CLOSED_POSITIONS) {
                return @($global:TEST_CLOSED_POSITIONS | Select-Object -First $Limit)
            }
            return @()
        }

        function Get-CurrentRegime {
            return "BEAR_WEAK"
        }
    }

    AfterAll {
        if (Test-Path $global:STATE_STORE_LOCAL_DIR) {
            Remove-Item -Path $global:STATE_STORE_LOCAL_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        $global:STATE_STORE_BACKEND = $null
        $global:STATE_STORE_LOCAL_DIR = $null
        $global:TEST_POSITIONS = $null
        $global:TEST_CLOSED_POSITIONS = $null
    }

    Context "Sync-ExchangePositionsLive" {
        BeforeEach {
            $global:TEST_POSITIONS = @(
                @{
                    orderId = "pos_001"
                    symbol = "BTCUSDT"
                    side = "LONG"
                    entryPrice = 43500.00
                    quantity = 0.5
                    markPrice = 44000.00
                    stopLossPrice = 43000.00
                    takeProfitPrice = 45000.00
                    created_at = (Get-Date).AddHours(-2)
                },
                @{
                    orderId = "pos_002"
                    symbol = "WLDUSDT"
                    side = "SHORT"
                    entryPrice = 0.3897
                    quantity = 100
                    markPrice = 0.3900
                    stopLossPrice = 0
                    takeProfitPrice = 0
                    created_at = (Get-Date).AddDays(-1)
                }
            )
        }

        It "syncs Futures positions" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced | Should -Not -BeNullOrEmpty
            $synced.Count | Should -Be 2
        }

        It "normalizes position fields" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced[0].symbol | Should -Be "BTCUSDT"
            $synced[0].direction | Should -Be "LONG"
            $synced[0].stop_loss | Should -Be 43000.00
            $synced[0].take_profit | Should -Be 45000.00
        }

        It "detects orphaned positions (missing SL or TP)" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $orphan = $synced | Where-Object { $_.symbol -eq "WLDUSDT" }
            $orphan | Should -Not -BeNullOrEmpty
            $orphan.stop_loss | Should -Be 0
            $orphan.take_profit | Should -Be 0
        }

        It "sets source to 'app_sync'" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced[0].source | Should -Be "app_sync"
        }

        It "respects MaxPositions limit" {
            $global:TEST_POSITIONS = @(1..150 | ForEach-Object {
                @{
                    orderId = "pos_$_"
                    symbol = "TEST$_"
                    side = "LONG"
                    entryPrice = 100
                    quantity = 1
                    markPrice = 101
                    stopLossPrice = 99
                    takeProfitPrice = 102
                    created_at = (Get-Date)
                }
            })

            $synced = Sync-ExchangePositionsLive -IsFutures $true -MaxPositions 100
            $synced.Count | Should -Be 100
        }
    }

    Context "Reconcile-AppToJournal" {
        # 2026-07-19: dados de teste atualizados pro shape REAL de
        # /v2/futures/finished-position, confirmado via job one-shot
        # (diag_closed_position_shape_readonly_2026_07_19.ps1) contra a API
        # real. Shape anterior (orderId/entryPrice/exitPrice/quantity) era
        # especulativo, nunca existiu na resposta real da CoinEx.
        BeforeEach {
            $global:TEST_CLOSED_POSITIONS = @(
                [PSCustomObject]@{
                    position_id = 1001; market = "ETHUSDT"; side = "long"
                    realized_pnl = "50"; avg_entry_price = "2300.00"
                    ath_margin_size = "460"; leverage = "5"
                    created_at = [DateTimeOffset]::UtcNow.AddHours(-5).ToUnixTimeMilliseconds()
                    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    finished_type = "take_profit"
                },
                [PSCustomObject]@{
                    position_id = 1002; market = "XRPUSDT"; side = "short"
                    realized_pnl = "10"; avg_entry_price = "2.50"
                    ath_margin_size = "50"; leverage = "5"
                    created_at = [DateTimeOffset]::UtcNow.AddHours(-3).ToUnixTimeMilliseconds()
                    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    finished_type = "stop_loss"
                }
            )
        }

        It "converts closed trades to outcomes" {
            $outcomes = Reconcile-AppToJournal -Limit 20
            $outcomes | Should Not BeNullOrEmpty
            $outcomes.Count | Should Be 2
        }

        It "calculates LONG PnL correctly" {
            $outcomes = Reconcile-AppToJournal -Limit 20
            $long = $outcomes | Where-Object { $_.direction -eq "LONG" }
            $long | Should Not BeNullOrEmpty
            # realized_pnl vem pronto da API (nao recalcula de entry/exit)
            $long.pnl_realized | Should Be 50
        }

        It "calculates SHORT PnL correctly" {
            $outcomes = Reconcile-AppToJournal -Limit 20
            $short = $outcomes | Where-Object { $_.direction -eq "SHORT" }
            $short | Should Not BeNullOrEmpty
            $short.pnl_realized | Should Be 10
        }

        It "sets source to 'app_import'" {
            $outcomes = Reconcile-AppToJournal -Limit 20
            $outcomes[0].source | Should Be "app_import"
        }

        It "sets status to 'closed'" {
            $outcomes = Reconcile-AppToJournal -Limit 20
            $outcomes[0].status | Should Be "closed"
        }

        It "respects Limit parameter" {
            $global:TEST_CLOSED_POSITIONS = @(1..50 | ForEach-Object {
                [PSCustomObject]@{
                    position_id = $_; market = "TESTUSDT"; side = "long"
                    realized_pnl = "1"; avg_entry_price = "100"
                    ath_margin_size = "100"; leverage = "1"
                    created_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    finished_type = "manual"
                }
            })

            $outcomes = Reconcile-AppToJournal -Limit 10
            $outcomes.Count | Should Not BeGreaterThan 10
        }
    }

    Context "Get-AdoptableOrphans" {
        BeforeEach {
            # Manually insert test positions into state store
            $orphans = @(
                @{
                    id = "orphan_1"
                    symbol = "BTCUSDT"
                    direction = "LONG"
                    entry_price = 43500
                    quantity = 0.5
                    stop_loss = 0
                    take_profit = 45000
                    current_price = 44000
                    status = "active"
                    source = "app_sync"
                    regime = "BEAR_WEAK"
                    entered_at = (Get-Date)
                },
                @{
                    id = "orphan_2"
                    symbol = "WLDUSDT"
                    direction = "SHORT"
                    entry_price = 0.3897
                    quantity = 100
                    stop_loss = 0
                    take_profit = 0
                    current_price = 0.39
                    status = "active"
                    source = "app_sync"
                    regime = "BEAR_WEAK"
                    entered_at = (Get-Date)
                }
            )

            Save-StateRecords -Table "open_positions" -Records $orphans -PrimaryKey "id"
        }

        It "identifies positions without stop_loss" {
            $orphans = Get-AdoptableOrphans
            $orphans | Should -Not -BeNullOrEmpty
            $nosl = $orphans | Where-Object { [double]$_.stop_loss -eq 0 }
            $nosl.Count | Should -Be -GreaterThan 0
        }

        It "identifies positions without take_profit" {
            $orphans = Get-AdoptableOrphans
            $notp = $orphans | Where-Object { [double]$_.take_profit -eq 0 }
            $notp.Count | Should -Be -GreaterThan 0
        }

        It "returns objects with all required fields" {
            $orphans = Get-AdoptableOrphans
            if ($orphans.Count -gt 0) {
                $orphans[0] | Should -HaveProperty "id"
                $orphans[0] | Should -HaveProperty "symbol"
                $orphans[0] | Should -HaveProperty "status"
            }
        }
    }

    Context "Sync-PositionsPeriodic" {
        BeforeEach {
            $global:TEST_POSITIONS = @(
                @{
                    orderId = "pos_fut_001"
                    symbol = "BTCUSDT"
                    side = "LONG"
                    entryPrice = 43500
                    quantity = 0.5
                    markPrice = 44000
                    stopLossPrice = 43000
                    takeProfitPrice = 45000
                    created_at = (Get-Date)
                }
            )
            $global:TEST_CLOSED_POSITIONS = @(
                @{
                    orderId = "closed_perf"
                    symbol = "ETHUSDT"
                    side = "LONG"
                    entryPrice = 2300
                    exitPrice = 2350
                    quantity = 1.0
                    entered_at = (Get-Date).AddHours(-1)
                }
            )
        }

        It "orchestrates complete sync cycle" {
            $result = Sync-PositionsPeriodic
            $result | Should -Not -BeNullOrEmpty
            $result | Should -HaveProperty "futures_synced"
            $result | Should -HaveProperty "spot_synced"
            $result | Should -HaveProperty "closed_outcomes"
            $result | Should -HaveProperty "orphans_count"
        }

        It "returns sync counts" {
            $result = Sync-PositionsPeriodic
            $result.futures_synced | Should -BeGreaterThan -1  # >= 0
            $result.spot_synced | Should -BeGreaterThan -1     # >= 0
        }
    }

    Context "Edge cases" {
        It "handles null position gracefully" {
            $global:TEST_POSITIONS = $null
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced | Should -Be @()
        }

        It "handles empty closed positions" {
            $global:TEST_CLOSED_POSITIONS = @()
            $outcomes = Reconcile-AppToJournal -Limit 20
            $outcomes | Should -Be @()
        }

        It "coerces string prices to double" {
            $global:TEST_POSITIONS = @(
                @{
                    orderId = "pos_string"
                    symbol = "TEST"
                    side = "LONG"
                    entryPrice = "100.50"  # string
                    quantity = "0.5"       # string
                    markPrice = "101.00"   # string
                    stopLossPrice = "99.00"
                    takeProfitPrice = "102.00"
                    created_at = (Get-Date)
                }
            )

            { Sync-ExchangePositionsLive -IsFutures $true } | Should -Not -Throw
        }

        It "handles datetime as string in closed position" {
            $global:TEST_CLOSED_POSITIONS = @(
                @{
                    orderId = "closed_str_date"
                    symbol = "TEST"
                    side = "LONG"
                    entryPrice = 100
                    exitPrice = 101
                    quantity = 1
                    entered_at = "2026-07-07T10:30:00Z"  # ISO string
                }
            )

            { Reconcile-AppToJournal -Limit 10 } | Should -Not -Throw
        }
    }
}
