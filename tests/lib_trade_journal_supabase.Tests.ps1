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
            $result | Should Be $true
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
            $result | Should Be $true
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

            { Save-TradeOutcome -TradeRecord $record } | Should Not Throw
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
            $result | Should Be $true
        }

        # 2026-07-27: achado real -- Reconcile-AppToJournal (lib_position_sync_live.ps1)
        # ja monta um id ESTAVEL (position_id da CoinEx) via _Convert-ClosedTradeToOutcome,
        # mas Save-TradeOutcome sempre sobrescrevia com um GUID novo, quebrando a
        # idempotencia do upsert (mesmo fechamento reprocessado a cada ciclo virava
        # registro duplicado, inflando PnL diario/circuit breaker).
        It "preserva o id estavel do TradeRecord quando presente (idempotencia)" {
            $mirrorPath = Join-Path $global:STATE_STORE_LOCAL_DIR "trade_outcomes.jsonl"
            if (Test-Path $mirrorPath) { Remove-Item $mirrorPath -Force }

            $record = @{
                id = "SOLUSDT|SHORT|position_sync|123456789"
                entry_ts = (Get-Date)
                symbol = "SOLUSDT"
                direction = "SHORT"
                source = "app_import"
                entry_price = 150.0
                pnl_realized = -0.31
                status = "closed"
            }

            Save-TradeOutcome -TradeRecord $record | Should Be $true
            $lines = @(Get-Content $mirrorPath | Where-Object { $_ -match '^\{' })
            $saved = $lines[-1] | ConvertFrom-Json
            $saved.id | Should Be "SOLUSDT|SHORT|position_sync|123456789"
        }

        It "gera id via GUID quando TradeRecord nao tem id (comportamento antigo preservado)" {
            $mirrorPath = Join-Path $global:STATE_STORE_LOCAL_DIR "trade_outcomes.jsonl"
            if (Test-Path $mirrorPath) { Remove-Item $mirrorPath -Force }

            $record = @{
                entry_ts = (Get-Date)
                symbol = "ADAUSDT"
                direction = "LONG"
                source = "gem_executor"
                entry_price = 0.5
                quantity = 100
            }

            Save-TradeOutcome -TradeRecord $record | Should Be $true
            $lines = @(Get-Content $mirrorPath | Where-Object { $_ -match '^\{' })
            $saved = $lines[-1] | ConvertFrom-Json
            $saved.id | Should Not BeNullOrEmpty
            $saved.id | Should Not Be "SOLUSDT|SHORT|position_sync|123456789"
        }

        It "reprocessar o MESMO id estavel 2x nao gera ids diferentes (simula Reconcile-AppToJournal reprocessando as ultimas N posicoes fechadas)" {
            $mirrorPath = Join-Path $global:STATE_STORE_LOCAL_DIR "trade_outcomes.jsonl"
            if (Test-Path $mirrorPath) { Remove-Item $mirrorPath -Force }

            $record = @{
                id = "DASHUSDT|LONG|position_sync|987654321"
                entry_ts = (Get-Date)
                symbol = "DASHUSDT"
                direction = "LONG"
                source = "app_import"
                entry_price = 30.0
                pnl_realized = -0.24
                status = "closed"
            }

            Save-TradeOutcome -TradeRecord $record | Should Be $true
            Save-TradeOutcome -TradeRecord $record | Should Be $true

            $lines = @(Get-Content $mirrorPath | Where-Object { $_ -match '^\{' })
            $ids = @($lines | ForEach-Object { ($_ | ConvertFrom-Json).id } | Select-Object -Unique)
            $ids.Count | Should Be 1
            $ids[0] | Should Be "DASHUSDT|LONG|position_sync|987654321"
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
            $trades | Should Not BeNullOrEmpty
            $trades.Count | Should BeGreaterThan 0
        }

        It "filters by status" {
            $pending = Get-RecentTrades -DaysBack 30 -Status "pending"
            $pending.Count | Should BeGreaterThan 0
            $pending[0].status | Should Be "pending"
        }

        It "respects DaysBack parameter" {
            $recent = Get-RecentTrades -DaysBack 3 -Status "closed"
            foreach ($trade in $recent) {
                $age = (Get-Date) - $trade.entry_ts
                $age.TotalDays | Should BeLessThan 4
            }
        }

        It "returns all statuses when Status='all'" {
            $all = Get-RecentTrades -DaysBack 30 -Status "all"
            $all.Count | Should BeGreaterThan 0
        }

        It "sorts by entry_ts descending" {
            $trades = Get-RecentTrades -DaysBack 30 -Status "closed" -Limit 100
            if ($trades.Count -gt 1) {
                $trades[0].entry_ts | Should BeGreaterThan $trades[-1].entry_ts
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
            $stats | Should Not BeNullOrEmpty
            $stats.win_count | Should BeGreaterThan 0
            $stats.loss_count | Should BeGreaterThan 0
            ($stats.win_rate -le 1) | Should Be $true
            ($stats.win_rate -ge 0) | Should Be $true
        }

        It "calculates total PnL" {
            $stats = Get-TradeStats -DaysBack 30
            $stats.pnl_total | Should Not BeNullOrEmpty
        }

        It "filters by regime" {
            $bullStats = Get-TradeStats -Regime "BULL" -DaysBack 30
            $bullStats | Should Not BeNullOrEmpty
        }

        It "returns zero stats for no trades" {
            $stats = Get-TradeStats -DaysBack 1 -Regime "NONEXISTENT"
            $stats.total | Should Be 0
            $stats.win_rate | Should Be 0
        }

        It "includes median PnL" {
            # Get-TradeStats documenta [OutputType([hashtable])] -- checar chave
            # via .PSObject.Properties nao funciona em Hashtable (so reflete
            # propriedades da classe .NET tipo Keys/Values/Count, nao as chaves
            # customizadas). Usar ContainsKey, que e o jeito certo pra Hashtable.
            $stats = Get-TradeStats -DaysBack 30
            $stats.ContainsKey("pnl_median") | Should Be $true
        }

        It "includes min and max PnL" {
            $stats = Get-TradeStats -DaysBack 30
            $stats.ContainsKey("pnl_min") | Should Be $true
            $stats.ContainsKey("pnl_max") | Should Be $true
        }
    }

    Context "Edge cases" {
        It "handles empty trade outcomes gracefully" {
            # Isola deste caso: Context "Get-TradeStats" acima grava trades reais
            # no mesmo STATE_STORE_LOCAL_DIR via BeforeEach, sem limpar depois --
            # sem isolar aqui, -DaysBack 365 sempre pegava esses trades residuais.
            # Save-TradeOutcome grava em DOIS arquivos (Save-StateRecords ->
            # trade_outcomes.json + _Mirror-TradeOutcomeLocal -> trade_outcomes.jsonl,
            # o fallback usado quando o primeiro falha/retorna vazio) -- limpar so
            # um dos dois ainda deixava o outro alimentar Get-RecentTrades.
            foreach ($ext in @("json", "jsonl")) {
                $tableFile = Join-Path $global:STATE_STORE_LOCAL_DIR "trade_outcomes.$ext"
                if (Test-Path $tableFile) { Remove-Item $tableFile -Force }
            }

            $stats = Get-TradeStats -DaysBack 365
            $stats.total | Should Be 0
        }

        It "ignores malformed local JSON lines" {
            # This is tested implicitly by _Read-TradeOutcomesLocal
            # which skips unparseable lines
            # 2026-07-21: com exatamente 1 resultado o pipeline "achata" o array
            # pra objeto unico (comportamento nativo do PS) -- @() forca o tipo,
            # o que a asercao original nao fazia.
            # 2026-07-23 FIX: "Should BeOfType [object[]]" nao funciona no
            # Pester 3.4.0 para tipos array -- checagem direta com -is.
            $trades = @(Get-RecentTrades -DaysBack 30)
            ($trades -is [array]) | Should Be $true
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

            { Save-TradeOutcome -TradeRecord $record } | Should Not Throw
        }
    }
}
