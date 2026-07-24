# dashboard_phase2.Tests.ps1 — WebSocket Real-Time + Control Buttons
# TDD: 18 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\scripts\dashboard_phase2_websocket.ps1"

Describe "Dashboard Phase 2 — WebSocket + Controls" {

    Context "Realtime Sync Initialization" {
        It "Inicia stream com credentials válidas" {
            $sync = Start-DashboardRealtimeSync -SupabaseUrl "https://test.supabase.co" -SupabaseKey "test_key"
            $sync.stream_id | Should Not BeNullOrEmpty
            $sync.tables.Count | Should BeGreaterThan 0
        }

        It "Retorna erro sem credentials" {
            $sync = Start-DashboardRealtimeSync -SupabaseUrl $null -SupabaseKey $null
            $sync.stream_id | Should BeNullOrEmpty
            $sync.error | Should Match "Missing"
        }

        It "Inscreve em múltiplas tabelas" {
            $tables = @("trailing_positions", "trade_outcomes", "conviction_observations")
            $sync = Start-DashboardRealtimeSync -SupabaseUrl "https://test.supabase.co" -SupabaseKey "key" -Tables $tables
            $sync.tables | Should Be $tables
        }
    }

    Context "Subscription Management" {
        It "Cria subscription sem filtro" {
            $sub = New-RealtimeSubscription -Table "trailing_positions"
            $sub.table | Should Be "trailing_positions"
            $sub.filter | Should BeNullOrEmpty
            $sub.event_count | Should Be 0
        }

        It "Cria subscription com filtro SQL" {
            $sub = New-RealtimeSubscription -Table "trade_outcomes" -Filter "win=eq.true"
            $sub.filter | Should Be "win=eq.true"
        }

        It "Atualiza dados na subscription" {
            $sub = New-RealtimeSubscription -Table "trailing_positions"
            $data = @(
                @{ market = "BTCUSDT"; active = $true; peak = 100 },
                @{ market = "ETHUSDT"; active = $false; peak = 200 }
            )
            $result = Update-SubscriptionData -Subscription $sub -NewData $data
            $result.success | Should Be $true
            $result.cached_rows | Should Be 2
            $sub.event_count | Should Be 1
        }
    }

    Context "Control Buttons" {
        It "Cria botão HALT" {
            $btn = New-ControlButton -Command "/halt" -Label "HALT Trading" -Color "red"
            $btn.command | Should Be "/halt"
            $btn.label | Should Be "HALT Trading"
            $btn.enabled | Should Be $true
        }

        It "Cria botão RESUME" {
            $btn = New-ControlButton -Command "/resume" -Label "RESUME Trading"
            $btn.command | Should Be "/resume"
        }

        It "Cria botão BALANCE" {
            $btn = New-ControlButton -Command "/balance" -Label "Show Capital"
            $btn.command | Should Be "/balance"
        }

        It "Invoca botão com sucesso" {
            $btn = New-ControlButton -Command "/halt" -Label "HALT"
            $result = Invoke-ControlButton -Button $btn -TelegramToken "token" -ChatId "123" -MarketState @{}
            $result.success | Should Be $true
            $btn.click_count | Should Be 1
        }

        It "Bloqueado se desabilitado" {
            $btn = New-ControlButton -Command "/halt" -Label "HALT"
            $btn.enabled = $false
            $result = Invoke-ControlButton -Button $btn -TelegramToken "token" -ChatId "123" -MarketState @{}
            $result.success | Should Be $false
        }

        It "Rastreia cliques" {
            $btn = New-ControlButton -Command "/scan" -Label "SCAN"
            Invoke-ControlButton -Button $btn -TelegramToken "t" -ChatId "c" -MarketState @{}
            Invoke-ControlButton -Button $btn -TelegramToken "t" -ChatId "c" -MarketState @{}
            $btn.click_count | Should Be 2
        }
    }

    Context "Dashboard State" {
        It "Cria state inicial" {
            $state = New-DashboardState
            $state.capital_total | Should Be 0
            $state.positions_open | Should Be 0
            $state.pnl_total | Should Be 0
        }

        It "Atualiza com posições abertas" {
            $state = New-DashboardState
            $positions = @(
                [PSCustomObject]@{ capital = 1000; unrealized_pnl = 50 },
                [PSCustomObject]@{ capital = 2000; unrealized_pnl = -100 }
            )
            $state = Update-DashboardState -State $state -Positions $positions -TradeOutcomes @() -DaemonStatus @{}
            $state.capital_total | Should Be 3000
            $state.positions_open | Should Be 2
            $state.pnl_total | Should Be -50
        }

        It "Calcula PnL percentage" {
            $state = New-DashboardState
            $positions = @([PSCustomObject]@{ capital = 1000; unrealized_pnl = 100 })
            $state = Update-DashboardState -State $state -Positions $positions -TradeOutcomes @() -DaemonStatus @{}
            $state.pnl_percentage | Should BeGreaterThan 0
        }

        It "Conta trades últimas 24h" {
            $state = New-DashboardState
            $now = Get-Date
            $trades = @(
                @{ exit_date = $now.AddHours(-2).ToString(); win = $true },
                @{ exit_date = $now.AddDays(-2).ToString(); win = $false }
            )
            $state = Update-DashboardState -State $state -Positions @() -TradeOutcomes $trades -DaemonStatus @{}
            $state.trades_24h | Should Be 1
            $state.trades_7d | Should Be 2
        }

        It "Calcula win rate" {
            $state = New-DashboardState
            $trades = @(
                @{ exit_date = (Get-Date).ToString(); win = $true },
                @{ exit_date = (Get-Date).ToString(); win = $true },
                @{ exit_date = (Get-Date).ToString(); win = $false }
            )
            $state = Update-DashboardState -State $state -Positions @() -TradeOutcomes $trades -DaemonStatus @{}
            [math]::Round($state.win_rate) | Should Be 67
        }
    }

    Context "Dashboard HTML Generation" {
        It "Gera HTML com estado" {
            $state = New-DashboardState
            $buttons = @(
                (New-ControlButton -Command "/halt" -Label "HALT"),
                (New-ControlButton -Command "/resume" -Label "RESUME")
            )
            $html = New-DashboardHtmlWithControls -State $state -Buttons $buttons
            $html | Should Match "<!DOCTYPE html>"
            $html | Should Match "ManuHeadFund"
            $html | Should Match "/halt"
            $html | Should Match "/resume"
        }

        It "Inclui capital total" {
            $state = New-DashboardState
            $state.capital_total = 5000
            $html = New-DashboardHtmlWithControls -State $state -Buttons @()
            $html | Should Match "5000"
        }

        It "Inclui PnL com cor apropriada" {
            $state = New-DashboardState
            $state.pnl_total = 250
            $html = New-DashboardHtmlWithControls -State $state -Buttons @()
            $html | Should Match "positive"
        }

        It "Mostra status dos daemons" {
            $state = New-DashboardState
            $state.daemon_status = @{ gem_loop = "ok"; trailing = "ok"; telegram = "ok" }
            $html = New-DashboardHtmlWithControls -State $state -Buttons @()
            $html | Should Match "gem_loop"
            $html | Should Match "trailing"
        }
    }

    Context "Sintaxe" {
        It "dashboard_phase2_websocket.ps1 parse OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize(
                (Get-Content ".\scripts\dashboard_phase2_websocket.ps1" -Raw),
                [ref]$err
            )
            $err.Count | Should Be 0
        }
    }

}
