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
        # 2026-07-23 FIX: Sync-ExchangePositionsLive foi reativada usando
        # CoinEx-GetOpenOrders (lib_coinex.ps1) como fonte -- schema real
        # confirmado por uso em producao (lib_trailing_adaptive.ps1,
        # trailing_stop_monitor.ps1), em vez de CoinEx-GetPendingPositions
        # direto com campos camelCase especulativos nunca validados.
        function CoinEx-GetOpenOrders {
            param([double]$MinValueUSD = 3.0)
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
        # 2026-07-23 FIX: dados de teste no schema real de CoinEx-GetOpenOrders
        # (position_type, side "buy"/"sell", price, amount, stop_price,
        # take_profit_price, order_id, market) -- nao mais o shape camelCase
        # especulativo (entryPrice/markPrice/stopLossPrice/orderId) que
        # nunca existiu na API real.
        BeforeEach {
            $global:TEST_POSITIONS = @(
                [PSCustomObject]@{
                    order_id = "pos_001"; market = "BTCUSDT"; position_type = "FUTURES"
                    side = "buy"; price = 43500.00; amount = 0.5; last_price = 44000.00
                    stop_price = 43000.00; take_profit_price = 45000.00
                },
                [PSCustomObject]@{
                    order_id = "pos_002"; market = "WLDUSDT"; position_type = "FUTURES"
                    side = "sell"; price = 0.3897; amount = 100; last_price = 0.3900
                    stop_price = $null; take_profit_price = $null
                }
            )
        }

        It "syncs Futures positions" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced | Should Not BeNullOrEmpty
            $synced.Count | Should Be 2
        }

        It "normalizes position fields" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced[0].symbol | Should Be "BTCUSDT"
            $synced[0].direction | Should Be "LONG"
            $synced[0].stop_loss | Should Be 43000.00
            $synced[0].take_profit | Should Be 45000.00
        }

        It "detects orphaned positions (missing SL or TP)" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $orphan = $synced | Where-Object { $_.symbol -eq "WLDUSDT" }
            $orphan | Should Not BeNullOrEmpty
            $orphan.stop_loss | Should Be 0
            $orphan.take_profit | Should Be 0
        }

        It "sets source to 'app_sync'" {
            $synced = Sync-ExchangePositionsLive -IsFutures $true
            $synced[0].source | Should Be "app_sync"
        }

        It "respects MaxPositions limit" {
            $global:TEST_POSITIONS = @(1..150 | ForEach-Object {
                [PSCustomObject]@{
                    order_id = "pos_$_"; market = "TEST$_"; position_type = "FUTURES"
                    side = "buy"; price = 100; amount = 1; last_price = 101
                    stop_price = 99; take_profit_price = 102
                }
            })

            $synced = Sync-ExchangePositionsLive -IsFutures $true -MaxPositions 100
            $synced.Count | Should Be 100
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
            $orphans | Should Not BeNullOrEmpty
            $nosl = $orphans | Where-Object { [double]$_.stop_loss -eq 0 }
            $nosl.Count | Should BeGreaterThan 0
        }

        It "identifies positions without take_profit" {
            $orphans = Get-AdoptableOrphans
            $notp = $orphans | Where-Object { [double]$_.take_profit -eq 0 }
            $notp.Count | Should BeGreaterThan 0
        }

        It "returns objects with all required fields" {
            $orphans = Get-AdoptableOrphans
            if ($orphans.Count -gt 0) {
                $orphans[0].PSObject.Properties["id"] | Should Not BeNullOrEmpty
                $orphans[0].PSObject.Properties["symbol"] | Should Not BeNullOrEmpty
                $orphans[0].PSObject.Properties["status"] | Should Not BeNullOrEmpty
            }
        }
    }

    Context "Sync-PositionsPeriodic" {
        BeforeEach {
            $global:TEST_POSITIONS = @(
                [PSCustomObject]@{
                    order_id = "pos_fut_001"; market = "BTCUSDT"; position_type = "FUTURES"
                    side = "buy"; price = 43500; amount = 0.5; last_price = 44000
                    stop_price = 43000; take_profit_price = 45000
                }
            )
            $global:TEST_CLOSED_POSITIONS = @(
                [PSCustomObject]@{
                    position_id = 9001; market = "ETHUSDT"; side = "long"
                    realized_pnl = "50"; avg_entry_price = "2300"
                    ath_margin_size = "460"; leverage = "5"
                    created_at = [DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds()
                    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    finished_type = "take_profit"
                }
            )
        }

        It "orchestrates complete sync cycle" {
            # 2026-07-23 FIX: Sync-PositionsPeriodic retorna Hashtable, nao
            # PSCustomObject -- .PSObject.Properties[] so reflete
            # propriedades .NET (Keys/Values/Count), nao as chaves
            # customizadas. ContainsKey() e o jeito certo pra Hashtable.
            $result = Sync-PositionsPeriodic
            $result | Should Not BeNullOrEmpty
            $result.ContainsKey("futures_synced") | Should Be $true
            $result.ContainsKey("spot_synced") | Should Be $true
            $result.ContainsKey("closed_outcomes") | Should Be $true
            $result.ContainsKey("orphans_count") | Should Be $true
        }

        It "returns sync counts" {
            $result = Sync-PositionsPeriodic
            $result.futures_synced | Should BeGreaterThan -1  # >= 0
            $result.spot_synced | Should BeGreaterThan -1     # >= 0
        }
    }

    Context "Edge cases" {
        It "handles null position gracefully" {
            # 2026-07-23 FIX: "Should Be @()" compara array vazio via -eq,
            # que no Pester 3 sempre falha (mesmo com ambos os lados vazios,
            # a mensagem de erro mostra "{}" == "{}" mas o teste falha) --
            # checar Count -eq 0 e o jeito correto de validar array vazio.
            $global:TEST_POSITIONS = $null
            $synced = @(Sync-ExchangePositionsLive -IsFutures $true)
            $synced.Count | Should Be 0
        }

        It "handles empty closed positions" {
            $global:TEST_CLOSED_POSITIONS = @()
            $outcomes = @(Reconcile-AppToJournal -Limit 20)
            $outcomes.Count | Should Be 0
        }

        It "coerces string prices to double" {
            $global:TEST_POSITIONS = @(
                [PSCustomObject]@{
                    order_id = "pos_string"; market = "TEST"; position_type = "FUTURES"
                    side = "buy"; price = "100.50"; amount = "0.5"; last_price = "101.00"
                    stop_price = "99.00"; take_profit_price = "102.00"
                }
            )

            { Sync-ExchangePositionsLive -IsFutures $true } | Should Not Throw
        }

        It "handles datetime as string in closed position" {
            $global:TEST_CLOSED_POSITIONS = @(
                [PSCustomObject]@{
                    position_id = 9002; market = "TEST"; side = "long"
                    realized_pnl = "1"; avg_entry_price = "100"
                    ath_margin_size = "100"; leverage = "1"
                    created_at = [DateTimeOffset]::Parse("2026-07-07T10:30:00Z").ToUnixTimeMilliseconds()
                    updated_at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
                    finished_type = "manual"
                }
            )

            { Reconcile-AppToJournal -Limit 10 } | Should Not Throw
        }
    }
}
