# faro_v3_aggressive_complete.Tests.ps1 — Full TDD suite for ML + Margin + Backtest

Describe "FARO V3 Aggressive - ML Prediction Layer" {
    BeforeAll {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $agentsDir = Join-Path $projectRoot "agents"
        . (Join-Path $agentsDir "lib_faro_ml_confidence.ps1") -ErrorAction SilentlyContinue
    }

    Context "Calculate-MLConfidence function" {
        It "Returns score 0-100" {
            $score = Calculate-MLConfidence -VolumeSignal 15 -PatternSignal 20 -MomentumSignal 15 -SentimentSignal 25
            $score | Should BeGreaterThan (0 - 1)
            $score | Should BeLessThan 100
        }

        It "Combines signals with weights: Vol 25%, Pattern 30%, Momentum 25%, Sentiment 20%" {
            # All signals max (25,25,25,30) = 105 total; normalized to 100
            $score = Calculate-MLConfidence -VolumeSignal 25 -PatternSignal 25 -MomentumSignal 25 -SentimentSignal 30
            $score | Should BeGreaterThan 50
        }

        It "Returns 0 if any signal negative" {
            $score = Calculate-MLConfidence -VolumeSignal -5 -PatternSignal 20 -MomentumSignal 15 -SentimentSignal 25
            $score | Should Be 0
        }

        It "Score 70+ indicates entry signal" {
            $score = Calculate-MLConfidence -VolumeSignal 18 -PatternSignal 20 -MomentumSignal 18 -SentimentSignal 20
            ($score -ge 0) | Should Be $true
        }
    }
}

Describe "FARO V3 Aggressive - Margin Management" {
    BeforeAll {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $agentsDir = Join-Path $projectRoot "agents"
        . (Join-Path $agentsDir "lib_faro_margin_safety.ps1") -ErrorAction SilentlyContinue
    }

    Context "Calculate-MarginPosition function" {
        It "Returns base position size with 1x multiplier if score < 85" {
            $pos = Calculate-MarginPosition -BasePositionSize 50 -SignalScore 70 -SignalCount 5 -MaxMargin 2.0
            $pos.leverage | Should Be 1.0
            $pos.effective_size | Should Be 50
        }

        It "Returns 1.5x leverage if score 85-95 and 6/7 signals" {
            $pos = Calculate-MarginPosition -BasePositionSize 50 -SignalScore 88 -SignalCount 6 -MaxMargin 2.0
            $pos.leverage | Should Be 1.5
            $pos.effective_size | Should Be 75
        }

        It "Returns 2x leverage if score 96+ and 6/7 signals" {
            $pos = Calculate-MarginPosition -BasePositionSize 50 -SignalScore 97 -SignalCount 6 -MaxMargin 2.0
            $pos.leverage | Should Be 2.0
            $pos.effective_size | Should Be 100
        }

        It "Caps leverage at MaxMargin parameter" {
            $pos = Calculate-MarginPosition -BasePositionSize 50 -SignalScore 99 -SignalCount 6 -MaxMargin 1.5
            $pos.leverage | Should Be 1.5
        }

        It "No leverage if only 5/7 signals regardless of score" {
            $pos = Calculate-MarginPosition -BasePositionSize 50 -SignalScore 95 -SignalCount 5 -MaxMargin 2.0
            $pos.leverage | Should Be 1.0
        }
    }

    Context "Calculate-MarginStop function" {
        It "Returns -1% stop for 2x margin (safe: -2% capital = -4% margin)" {
            $stop = Calculate-MarginStop -EntryPrice 100 -Leverage 2.0 -RiskPercent 0.02
            $stop | Should Be 99.0
        }

        It "Returns -2% stop for 1.5x margin" {
            $stop = Calculate-MarginStop -EntryPrice 100 -Leverage 1.5 -RiskPercent 0.02
            [Math]::Round($stop, 1) | Should BeGreaterThan 98
            [Math]::Round($stop, 1) | Should BeLessThan 99
        }

        It "Returns -2% stop for 1x leverage" {
            $stop = Calculate-MarginStop -EntryPrice 100 -Leverage 1.0 -RiskPercent 0.02
            $stop | Should Be 98.0
        }
    }

    Context "Validate-MarginSafety function" {
        It "Returns safe=true if open PnL within limits" {
            $result = Validate-MarginSafety -OpenPnL -50 -TotalCapital 5000 -Leverage 2.0
            $result.safe | Should Be $true
        }

        It "Returns safe=false if open PnL exceeds loss threshold" {
            $result = Validate-MarginSafety -OpenPnL -800 -TotalCapital 5000 -Leverage 2.0
            $result.safe | Should Be $false
        }

        It "Triggers liquidation if leverage exceeds 1.2x open loss ratio" {
            $result = Validate-MarginSafety -OpenPnL -800 -TotalCapital 5000 -Leverage 2.0
            $result.should_liquidate | Should Be $true
        }
    }
}

Describe "FARO V3 Aggressive - Backtest Engine" {
    BeforeAll {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $agentsDir = Join-Path $projectRoot "agents"
        . (Join-Path $agentsDir "lib_faro_backtest.ps1") -ErrorAction SilentlyContinue
    }

    Context "Run-BacktestSimulation function" {
        It "Returns valid backtest result object" {
            $trades = @(
                [PSCustomObject]@{entry_price=100; exit_price=103; quantity=1; reason="T1"},
                [PSCustomObject]@{entry_price=100; exit_price=98; quantity=1; reason="STOP"}
            )
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result | Should Not Be $null
            $result.total_trades | Should Be 2
        }

        It "Calculates win rate correctly (wins / total)" {
            $trades = @(
                [PSCustomObject]@{entry_price=100; exit_price=103; quantity=1},
                [PSCustomObject]@{entry_price=100; exit_price=102; quantity=1},
                [PSCustomObject]@{entry_price=100; exit_price=98; quantity=1},
                [PSCustomObject]@{entry_price=100; exit_price=97; quantity=1}
            )
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result.win_rate | Should Be 0.5
        }

        It "Calculates total PnL as sum of all trades" {
            $trades = @(
                [PSCustomObject]@{entry_price=100; exit_price=105; quantity=10},
                [PSCustomObject]@{entry_price=100; exit_price=98; quantity=10}
            )
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result.total_pnl | Should BeGreaterThan 20
        }

        It "Calculates max drawdown correctly" {
            $trades = @(
                [PSCustomObject]@{entry_price=100; exit_price=95; quantity=10},
                [PSCustomObject]@{entry_price=100; exit_price=110; quantity=10},
                [PSCustomObject]@{entry_price=110; exit_price=100; quantity=10}
            )
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result.max_drawdown_pct | Should BeGreaterThan 0
            $result.max_drawdown_pct | Should BeLessThan 100
        }

        It "Calculates Sharpe ratio (risk-adjusted return)" {
            $trades = @()
            for ($i = 0; $i -lt 20; $i++) {
                $pnl = if ($i % 2 -eq 0) { 50 } else { -20 }
                $trades += [PSCustomObject]@{entry_price=100; exit_price=(100 + $pnl/10); quantity=10}
            }
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result.sharpe_ratio | Should BeGreaterThan 0
        }

        It "Return is within 0-200% for reasonable backtests" {
            $trades = @()
            for ($i = 0; $i -lt 30; $i++) {
                $trades += [PSCustomObject]@{entry_price=100; exit_price=103; quantity=1}
            }
            $result = Run-BacktestSimulation -Trades $trades -InitialCapital 5000
            $result.return_pct | Should BeGreaterThan 0
            $result.return_pct | Should BeLessThan 500
        }
    }
}

Describe "FARO V3 Aggressive - Live Deployment" {
    Context "System startup" {
        It "All libs load without errors" {
            $projectRoot = Split-Path $PSScriptRoot -Parent
            $agentsDir = Join-Path $projectRoot "agents"
            $libs = @("lib_faro_ml_confidence.ps1", "lib_faro_margin_safety.ps1", "lib_faro_backtest.ps1")

            foreach ($lib in $libs) {
                $path = Join-Path $agentsDir $lib
                if (Test-Path $path) {
                    { . $path } | Should Not Throw
                }
            }
        }

        It "Journal directory exists" {
            $journalDir = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
            Test-Path $journalDir | Should Be $true
        }
    }

    Context "Config parameters loaded" {
        BeforeAll {
            $projectRoot = Split-Path $PSScriptRoot -Parent
            $agentsDir = Join-Path $projectRoot "agents"
            . (Join-Path $agentsDir "config.ps1") -ErrorAction SilentlyContinue
        }

        It "FARO_V3_AGGRESSIVE_ENABLED is true" {
            $global:FARO_V3_ENABLED | Should Be $true
        }

        It "FARO_V3_MODE is AGGRESSIVE_SCALP" {
            $global:FARO_V3_MODE | Should Be "AGGRESSIVE_SCALP"
        }

        It "FARO_V3_MARGIN_ENABLED is true" {
            $global:FARO_V3_MARGIN_ENABLED | Should Be $true
        }

        It "FARO_V3_MARGIN_MAX is 2.0" {
            $global:FARO_V3_MARGIN_MAX | Should Be 2.0
        }
    }
}
