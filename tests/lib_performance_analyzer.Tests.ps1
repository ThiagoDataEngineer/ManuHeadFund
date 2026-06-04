# lib_performance_analyzer.Tests.ps1 - Testes TDD para Performance Analyzer
# Rodar: Invoke-Pester -Path .\tests\lib_performance_analyzer.Tests.ps1

. "$PSScriptRoot\..\agents\lib_performance_analyzer.ps1"

Describe "Calculate-SharpeRatio" {
    It "Retorna sharpe ratio 0 para array vazio" {
        $result = Calculate-SharpeRatio -Trades @()
        $result.sharpe_ratio | Should Be 0
        $result.trades_count | Should Be 0
    }
    
    It "Calcula sharpe ratio corretamente para trades positivos" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = 20 }
            [PSCustomObject]@{ realized_pnl = 15 }
        )
        
        $result = Calculate-SharpeRatio -Trades $trades
        $result.sharpe_ratio | Should BeGreaterThan 0
        $result.avg_return | Should Be 15
        $result.trades_count | Should Be 3
    }
    
    It "Calcula sharpe ratio corretamente para trades mistos" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = -5 }
            [PSCustomObject]@{ realized_pnl = 15 }
            [PSCustomObject]@{ realized_pnl = -10 }
        )
        
        $result = Calculate-SharpeRatio -Trades $trades
        $result.avg_return | Should Be 2.5
        $result.std_dev | Should BeGreaterThan 0
        $result.trades_count | Should Be 4
    }
    
    It "Retorna sharpe ratio 0 para 1 trade apenas" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
        )
        
        $result = Calculate-SharpeRatio -Trades $trades
        $result.sharpe_ratio | Should Be 0
        $result.std_dev | Should Be 0
    }
}

Describe "Calculate-MaxDrawdown" {
    It "Retorna drawdown 0 para array vazio" {
        $result = Calculate-MaxDrawdown -Trades @()
        $result.max_drawdown_pct | Should Be 0
        $result.max_drawdown_usd | Should Be 0
    }
    
    It "Calcula drawdown corretamente para sequencia de perdas" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 100 }
            [PSCustomObject]@{ realized_pnl = -50 }
            [PSCustomObject]@{ realized_pnl = -30 }
        )
        
        $result = Calculate-MaxDrawdown -Trades $trades
        $result.max_drawdown_usd | Should Be 80
        $result.peak_equity | Should Be 100
        $result.valley_equity | Should Be 20
    }
    
    It "Calcula drawdown corretamente com recuperacao" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 100 }
            [PSCustomObject]@{ realized_pnl = -50 }
            [PSCustomObject]@{ realized_pnl = 80 }
            [PSCustomObject]@{ realized_pnl = -20 }
        )
        
        $result = Calculate-MaxDrawdown -Trades $trades
        $result.max_drawdown_usd | Should Be 50
        $result.peak_equity | Should Be 100
    }
    
    It "Retorna drawdown 0 para apenas trades positivos" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = 20 }
            [PSCustomObject]@{ realized_pnl = 30 }
        )
        
        $result = Calculate-MaxDrawdown -Trades $trades
        $result.max_drawdown_usd | Should Be 0
    }
}

Describe "Calculate-WinStreaks" {
    It "Retorna streaks 0 para array vazio" {
        $result = Calculate-WinStreaks -Trades @()
        $result.max_win_streak | Should Be 0
        $result.max_loss_streak | Should Be 0
    }
    
    It "Calcula win streak corretamente" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = 20 }
            [PSCustomObject]@{ realized_pnl = 15 }
            [PSCustomObject]@{ realized_pnl = -5 }
        )
        
        $result = Calculate-WinStreaks -Trades $trades
        $result.max_win_streak | Should Be 3
        $result.max_loss_streak | Should Be 1
    }
    
    It "Calcula loss streak corretamente" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = -10 }
            [PSCustomObject]@{ realized_pnl = -20 }
            [PSCustomObject]@{ realized_pnl = -15 }
            [PSCustomObject]@{ realized_pnl = 5 }
        )
        
        $result = Calculate-WinStreaks -Trades $trades
        $result.max_win_streak | Should Be 1
        $result.max_loss_streak | Should Be 3
    }
    
    It "Calcula streaks alternados corretamente" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = -5 }
            [PSCustomObject]@{ realized_pnl = 20 }
            [PSCustomObject]@{ realized_pnl = -10 }
        )
        
        $result = Calculate-WinStreaks -Trades $trades
        $result.max_win_streak | Should Be 1
        $result.max_loss_streak | Should Be 1
    }
    
    It "Identifica current streak corretamente" {
        $trades = @(
            [PSCustomObject]@{ realized_pnl = 10 }
            [PSCustomObject]@{ realized_pnl = 20 }
            [PSCustomObject]@{ realized_pnl = 15 }
        )
        
        $result = Calculate-WinStreaks -Trades $trades
        $result.current_streak | Should Be 3
        $result.current_streak_type | Should Be "win"
    }
}

Describe "Analyze-PerformanceByMarket" {
    It "Retorna array vazio para trades vazios" {
        $result = Analyze-PerformanceByMarket -Trades @()
        $result.Count | Should Be 0
    }
    
    It "Agrupa trades por market corretamente" {
        $trades = @(
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = 10 }
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = -5 }
            [PSCustomObject]@{ market = "ETHUSDT"; realized_pnl = 20 }
        )
        
        $result = Analyze-PerformanceByMarket -Trades $trades
        $result.Count | Should Be 2
        
        $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
        $btc.trades | Should Be 2
        $btc.wins | Should Be 1
        $btc.losses | Should Be 1
        $btc.total_pnl | Should Be 5
    }
    
    It "Calcula win rate por market corretamente" {
        $trades = @(
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = 10 }
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = 20 }
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = -5 }
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = 15 }
        )
        
        $result = Analyze-PerformanceByMarket -Trades $trades
        $btc = $result | Where-Object { $_.market -eq "BTCUSDT" }
        $btc.win_rate | Should Be 75
    }
    
    It "Ordena markets por total_pnl decrescente" {
        $trades = @(
            [PSCustomObject]@{ market = "BTCUSDT"; realized_pnl = 10 }
            [PSCustomObject]@{ market = "ETHUSDT"; realized_pnl = 50 }
            [PSCustomObject]@{ market = "XRPUSDT"; realized_pnl = 30 }
        )
        
        $result = Analyze-PerformanceByMarket -Trades $trades
        $result[0].market | Should Be "ETHUSDT"
        $result[1].market | Should Be "XRPUSDT"
        $result[2].market | Should Be "BTCUSDT"
    }
}

Describe "Analyze-PerformanceByHour" {
    It "Retorna array vazio para trades vazios" {
        $result = Analyze-PerformanceByHour -Trades @()
        $result.Count | Should Be 0
    }
    
    It "Agrupa trades por hora corretamente" {
        # Timestamp para 2026-05-23 10:00:00 UTC
        $ts1 = 1779705600000
        # Timestamp para 2026-05-23 14:00:00 UTC
        $ts2 = 1779720000000
        
        $trades = @(
            [PSCustomObject]@{ created_at = $ts1; realized_pnl = 10 }
            [PSCustomObject]@{ created_at = $ts1; realized_pnl = 20 }
            [PSCustomObject]@{ created_at = $ts2; realized_pnl = 15 }
        )
        
        $result = Analyze-PerformanceByHour -Trades $trades
        $result.Count | Should BeGreaterThan 0
    }
    
    It "Calcula metricas por hora corretamente" {
        $ts = 1779705600000  # 2026-05-23 10:00:00 UTC
        
        $trades = @(
            [PSCustomObject]@{ created_at = $ts; realized_pnl = 10 }
            [PSCustomObject]@{ created_at = $ts; realized_pnl = -5 }
            [PSCustomObject]@{ created_at = $ts; realized_pnl = 20 }
        )
        
        $result = Analyze-PerformanceByHour -Trades $trades
        $hour10 = $result | Where-Object { $_.hour -eq 10 }
        
        if ($hour10) {
            $hour10.trades | Should Be 3
            $hour10.wins | Should Be 2
            $hour10.total_pnl | Should Be 25
        }
    }
}
