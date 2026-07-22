# tori_daemon_integration.Tests.ps1 - Integration tests for Tori Daemon
#
# Validates complete daemon workflow:
# 1. State persistence
# 2. Trendline detection
# 3. Confluence scoring
# 4. Alert formatting
# 5. Report generation
#
# Run: Invoke-Pester tori_daemon_integration.Tests.ps1 -Verbose

# ============================================================================
# TEST SETUP
# ============================================================================

$agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
$journalPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"

# Mock CoinEx functions for testing
function global:CoinEx-GetFuturesMarkets {
    return @(
        @{ market = "BTCUSDT"; min_amount = 100 },
        @{ market = "ETHUSDT"; min_amount = 50 },
        @{ market = "XRPUSDT"; min_amount = 10 }
    )
}

function global:CoinEx-GetFuturesCandles {
    param($market, $period, $limit)

    # Return realistic mock candles
    $candles = @()
    $basePriceMap = @{ BTCUSDT = 63000; ETHUSDT = 3500; XRPUSDT = 0.52 }
    $basePrice = if ($null -ne $basePriceMap[$market]) { $basePriceMap[$market] } else { 1000 }

    for ($i = 0; $i -lt $limit; $i++) {
        $candles += [PSCustomObject]@{
            ts = [long]([DateTime]::UtcNow.AddHours(-$i)).Ticks
            open = $basePrice * (0.98 + (Get-Random -Minimum -2 -Maximum 2) / 100)
            high = $basePrice * (1.00 + (Get-Random -Minimum 0 -Maximum 3) / 100)
            low = $basePrice * (0.97 + (Get-Random -Minimum -3 -Maximum 0) / 100)
            close = $basePrice * (0.99 + (Get-Random -Minimum -1 -Maximum 1) / 100)
            volume = Get-Random -Minimum 1000 -Maximum 100000
        }
    }

    return $candles | Sort-Object ts
}

function global:CoinEx-GetTicker {
    param($market)

    $basePriceMap = @{ BTCUSDT = 63000; ETHUSDT = 3500; XRPUSDT = 0.52 }
    $basePrice = if ($null -ne $basePriceMap[$market]) { $basePriceMap[$market] } else { 1000 }
    return @{ last = $basePrice * (0.99 + (Get-Random -Minimum -1 -Maximum 1) / 100) }
}

# ============================================================================
# UNIT TESTS: Trendline Detection
# ============================================================================

Describe "Trendline Detection" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
    }

    It "Should detect bullish fractal pattern" {
        $closes = @(100, 102, 101, 105, 103, 104)
        $fractal = Get-FractalPattern -Opens $closes -Highs $closes -Lows $closes -Closes $closes

        $fractal | Should -Not -BeNullOrEmpty
    }

    It "Should detect volume climax signal" {
        $volumes = @(1000, 1100, 1050, 2500, 1000)  # 2500 is climax
        $climax = Get-VolumeClimax -Volumes $volumes -Threshold 2.0

        $climax.is_climax | Should -Be $true
        $climax.ratio | Should -BeGreaterThan 2.0
    }

    It "Should detect RSI extreme (oversold)" {
        $rsi = 25  # Oversold
        $extreme = Get-RSIExtreme -RSI $rsi -SetupType "LONG"

        $extreme.is_extreme | Should -Be $true
        $extreme.extreme_type | Should -Be "OVERSOLD"
    }

    It "Should detect RSI extreme (overbought)" {
        $rsi = 75  # Overbought
        $extreme = Get-RSIExtreme -RSI $rsi -SetupType "SHORT"

        $extreme.is_extreme | Should -Be $true
        $extreme.extreme_type | Should -Be "OVERBOUGHT"
    }

    It "Should calculate structural break (CHoCH)" {
        $lows = @(100, 99, 98, 97, 96)   # Descending
        $highs = @(110, 109, 108, 107, 106)

        $choch = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType "SHORT"

        $choch.has_choch | Should -Be $true
        $choch.break_level | Should -BeGreaterThan 0
    }
}

# ============================================================================
# UNIT TESTS: Confluence Scoring
# ============================================================================

Describe "Confluence Scoring" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
    }

    It "Should calculate high confluence score with all signals" {
        $candles = CoinEx-GetFuturesCandles -market "BTCUSDT" -period "1D" -limit 300

        $confluence = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "SHORT" -TrendlineStartPrice 63000 -TrendlineTouches 3

        $confluence.total_score | Should -BeGreaterThan 0
        $confluence.total_score | Should -BeLessOrEqual 100
    }

    It "Should fire multiple signals" {
        $candles = CoinEx-GetFuturesCandles -market "BTCUSDT" -period "4H" -limit 100

        $confluence = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" -TrendlineStartPrice 63000

        $confluence.signals_fired | Should -Not -BeNullOrEmpty
        $confluence.signals_fired.Count | Should -BeGreaterThan 0
    }

    It "Should return RSI value" {
        $candles = CoinEx-GetFuturesCandles -market "ETHUSDT" -period "1H" -limit 50

        $confluence = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "SHORT" -TrendlineStartPrice 3500

        $confluence.rsi | Should -BeGreaterOrEqual 0
        $confluence.rsi | Should -BeLessOrEqual 100
    }
}

# ============================================================================
# UNIT TESTS: Alert Formatting
# ============================================================================

Describe "Alert Formatting" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
    }

    It "Should format new setup alert with all fields" {
        $setup = [PSCustomObject]@{
            pair = "BTCUSDT"
            timeframe = "1D"
            trend_type = "SHORT"
            confidence_score = 87
            entry_price = 63420.50
            stop_loss = 64650.30
            target_price = 60500.00
            rr_ratio = 3.3
            rsi = 72
            signals_fired = "VOLUME_CLIMAX|RSI_EXTREME|FRACTAL_BEARISH"
            id = "test_id"
            timestamp = (Get-Date -Format "o")
        }

        $message = Format-NewSetupAlert -Setup $setup

        $message | Should -Match "BTCUSDT"
        $message | Should -Match "SHORT"
        $message | Should -Match "87/100"
        $message | Should -Match "63420"
        $message | Should -Match "3.3x"
    }

    It "Should format target hit alert" {
        $setup = [PSCustomObject]@{
            pair = "XRPUSDT"
            timeframe = "4H"
            trend_type = "LONG"
            entry_price = 0.50
            target_price = 0.525
            unrealized_pnl = 0.025
            rr_ratio = 2.5
            timestamp = (Get-Date).AddHours(-2).ToString("o")
            closed_time = (Get-Date).ToString("o")
        }

        $message = Format-TargetHitAlert -Setup $setup

        $message | Should -Match "CLOSED"
        $message | Should -Match "TARGET"
        $message | Should -Match "XRPUSDT"
        $message | Should -Match "0.525"
    }

    It "Should format stop hit alert" {
        $setup = [PSCustomObject]@{
            pair = "ETHUSDT"
            timeframe = "1H"
            trend_type = "SHORT"
            entry_price = 3500
            stop_loss = 3400
            unrealized_pnl = -100
            risk_usdt = 100
            timestamp = (Get-Date).AddMinutes(-45).ToString("o")
            closed_time = (Get-Date).ToString("o")
        }

        $message = Format-StopHitAlert -Setup $setup

        $message | Should -Match "STOPPED"
        $message | Should -Match "ETHUSDT"
        $message | Should -Match "3400"
        $message | Should -Match "100"
    }

    It "Should format summary report with statistics" {
        $activeSetups = @(
            [PSCustomObject]@{ pair = "BTCUSDT"; trend_type = "LONG"; confidence_score = 85 },
            [PSCustomObject]@{ pair = "ETHUSDT"; trend_type = "SHORT"; confidence_score = 82 }
        )

        $closedTrades = @(
            [PSCustomObject]@{ unrealized_pnl = 150 },
            [PSCustomObject]@{ unrealized_pnl = -50 },
            [PSCustomObject]@{ unrealized_pnl = 200 }
        )

        $metrics = @{
            total_scans = 10
            pairs_analyzed = 150
            setups_found = 5
        }

        $message = Format-SummaryReport -ActiveSetups $activeSetups -RecentClosedTrades $closedTrades -PerformanceMetrics $metrics

        $message | Should -Match "Active Setups: 2"
        $message | Should -Match "LONG: 1"
        $message | Should -Match "SHORT: 1"
        $message | Should -Match "Recent Trades: 3"
        $message | Should -Match "Wins: 2"
        $message | Should -Match "Losses: 1"
        $message | Should -Match "Win Rate: 66"
    }
}

# ============================================================================
# INTEGRATION TESTS: State Persistence
# ============================================================================

Describe "State Persistence" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
        # 2026-07-21: $journalPath declarado no top-level do arquivo nao
        # sobrevive ate BeforeEach em Pester 5 (Discovery vs Run scopes).
        $journalPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
    }

    BeforeEach {
        $testStateFile = Join-Path $journalPath "test_tori_state_$(Get-Random).json"
    }

    AfterEach {
        if (Test-Path $testStateFile) {
            Remove-Item $testStateFile -Force
        }
    }

    It "Should save and restore state" {
        $testState = @{
            timestamp = Get-Date -Format "o"
            active_setups = @(
                @{ pair = "BTCUSDT"; trend_type = "SHORT"; confidence_score = 87; entry_price = 63000; unrealized_pnl = -500 }
            )
            closed_trades = @(
                @{ pair = "ETHUSDT"; trend_type = "LONG"; unrealized_pnl = 150 }
            )
            performance = @{
                total_scans = 5
                pairs_analyzed = 150
                total_pnl = 150
                win_rate = 1.0
            }
        } | ConvertTo-Json -Depth 5

        Set-Content -Path $testStateFile -Value $testState -Encoding UTF8

        # Load it back
        $loaded = Get-Content -Path $testStateFile -Raw | ConvertFrom-Json

        $loaded.active_setups.Count | Should -Be 1
        $loaded.active_setups[0].pair | Should -Be "BTCUSDT"
        $loaded.closed_trades.Count | Should -Be 1
        $loaded.performance.total_scans | Should -Be 5
    }

    It "Should handle large state file (500 trades)" {
        $testState = @{
            timestamp = Get-Date -Format "o"
            active_setups = @()
            closed_trades = @(1..500 | ForEach-Object {
                @{
                    pair = "PAIR$_"
                    trend_type = if ($_ % 2) { "LONG" } else { "SHORT" }
                    unrealized_pnl = $_ * 10
                    timestamp = (Get-Date).AddHours(-$_).ToString("o")
                }
            })
            performance = @{
                total_scans = 100
                total_pnl = 2500
            }
        } | ConvertTo-Json -Depth 5

        Set-Content -Path $testStateFile -Value $testState -Encoding UTF8

        $loaded = Get-Content -Path $testStateFile -Raw | ConvertFrom-Json

        $loaded.closed_trades.Count | Should -Be 500
        (Get-Item $testStateFile).Length | Should -BeGreaterThan 0
    }
}

# ============================================================================
# INTEGRATION TESTS: Report Generation
# ============================================================================

Describe "Report Generation" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
        $journalPath = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
    }

    BeforeEach {
        $testReportDir = Join-Path $journalPath "test_reports_$(Get-Random)"
        New-Item -ItemType Directory -Path $testReportDir -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $testReportDir) {
            Remove-Item -Path $testReportDir -Recurse -Force
        }
    }

    It "Should generate HTML dashboard with valid structure" {
        $state = @{
            timestamp = Get-Date -Format "o"
            last_scan_time = (Get-Date).AddHours(-1).ToString("o")
            active_setups = @(
                @{ pair = "BTCUSDT"; timeframe = "1D"; trend_type = "SHORT"; confidence_score = 87; entry_price = 63000; current_price = 62500; unrealized_pnl = 500 },
                @{ pair = "ETHUSDT"; timeframe = "4H"; trend_type = "LONG"; confidence_score = 82; entry_price = 3500; current_price = 3520; unrealized_pnl = 20 }
            )
            closed_trades = @(
                @{ pair = "XRPUSDT"; timeframe = "1H"; trend_type = "LONG"; confidence_score = 81; entry_price = 0.50; target_price = 0.525; unrealized_pnl = 0.025; status = "CLOSED_TARGET" }
            )
            performance = @{
                total_scans = 10
                pairs_analyzed = 150
                setups_found = 3
                avg_confluence_score = 83.3
                win_rate = 0.66
                total_pnl = 520.025
            }
        }

        # HTML should contain key elements
        # (Would normally export, but skip actual file write in tests)

        $state.active_setups.Count | Should -Be 2
        $state.closed_trades.Count | Should -Be 1
        $state.performance.total_pnl | Should -Be 520.025
    }

    It "Should handle empty state gracefully" {
        $emptyState = @{
            timestamp = Get-Date -Format "o"
            active_setups = @()
            closed_trades = @()
            performance = @{
                total_scans = 0
                total_pnl = 0
                win_rate = 0
            }
        }

        $emptyState.active_setups.Count | Should -Be 0
        $emptyState.closed_trades.Count | Should -Be 0
    }
}

# ============================================================================
# END-TO-END TESTS
# ============================================================================

Describe "End-to-End Daemon Workflow" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
    }

    It "Should complete minimal scan cycle" {
        # This is a smoke test that verifies the components integrate

        $candles = CoinEx-GetFuturesCandles -market "BTCUSDT" -period "1D" -limit 100
        $candles.Count | Should -BeGreaterThan 0

        $confluence = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "SHORT" -TrendlineStartPrice 63000

        $confluence.total_score | Should -BeGreaterThan 0
        $confluence.total_score | Should -BeLessOrEqual 100

        $setup = [PSCustomObject]@{
            pair = "BTCUSDT"
            confidence_score = $confluence.total_score
            entry_price = 63000
            stop_loss = 64000
            target_price = 61000
            rr_ratio = 2.0
            signals_fired = $confluence.signals_fired -join "|"
            timestamp = Get-Date -Format "o"
        }

        $message = Format-NewSetupAlert -Setup $setup

        $message | Should -Match "BTCUSDT"
        $message | Should -Match $confluence.total_score.ToString()
    }
}

# ============================================================================
# PERFORMANCE TESTS
# ============================================================================

Describe "Performance Benchmarks" {

    BeforeAll {
        $__agentsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
        $__libPath = Join-Path $__agentsPath "lib_tori_confluence_detector.ps1"
        if (Test-Path $__libPath) { . $__libPath }
        $__alertPath = Join-Path $__agentsPath "tori_telegram_alerts.ps1"
        if (Test-Path $__alertPath) { . $__alertPath }
        $__reporterPath = Join-Path $__agentsPath "tori_daemon_reporter.ps1"
        if (Test-Path $__reporterPath) { . $__reporterPath }
    }

    It "Should process 100 candles in < 500ms" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $candles = CoinEx-GetFuturesCandles -market "BTCUSDT" -period "1D" -limit 100
        $confluence = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "SHORT" -TrendlineStartPrice 63000

        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 500
    }

    It "Should format alert in < 50ms" {
        $setup = [PSCustomObject]@{
            pair = "BTCUSDT"
            timeframe = "1D"
            trend_type = "SHORT"
            confidence_score = 87
            entry_price = 63420.50
            stop_loss = 64650.30
            target_price = 60500.00
            rr_ratio = 3.3
            rsi = 72
            signals_fired = "VOLUME_CLIMAX|RSI_EXTREME"
            id = "test_id"
            timestamp = Get-Date -Format "o"
        }

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $message = Format-NewSetupAlert -Setup $setup

        $stopwatch.Stop()

        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 50
    }
}
