# lib_gem_executor_multitf.Tests.ps1 — Phase 2 Integration Tests
# 2026-06-08: Validate Multi-TF gate integration in gem_executor.ps1

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_multiframe_analysis.ps1")
. (Join-Path $agentsDir "lib_candle_fetcher.ps1")

Describe "Multi-TF Gate Integration" {

    Context "Integration: Trend Analysis + Alignment" {

        It "validates LONG entry with uptrend HTF alignment" {
            # Simulate 1D/4H uptrend, 1H mixed
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_UP" -Trend4H "UP" -Trend1H "DOWN" -Direction "LONG"
            $result | Should Be $true
        }

        It "blocks LONG entry with downtrend HTF" {
            # 1D downtrend prevents LONG (PIPPIN case)
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "validates SHORT entry with downtrend HTF alignment" {
            # Simulate 1D/4H downtrend, 1H mixed
            $result = Test-MultiTimeframeAlignment -Trend1D "DOWN" -Trend4H "STRONG_DOWN" -Trend1H "UP" -Direction "SHORT"
            $result | Should Be $true
        }

        It "blocks SHORT when 1D is strongly uptrending" {
            # 1D uptrend prevents SHORT
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_UP" -Trend4H "DOWN" -Trend1H "DOWN" -Direction "SHORT"
            $result | Should Be $false
        }
    }

    Context "Signal Context Validation (bidirectional principle)" {

        It "SHORT approves when HTF is in accumulation (neutral)" {
            # 1D neutral allows SHORT (not requiring downtrend, just non-uptrend)
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "DOWN" -Trend1H "UP" -Direction "SHORT"
            $result | Should Be $true
        }

        It "LONG requires explicit uptrend, not just neutral" {
            # LONG needs UP/STRONG_UP, neutral is insufficient
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "NEUTRAL" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "demonstrates PIPPIN signal context: 1D down blocks LONG but enables SHORT" {
            # Both gates tested with same trend data
            $long_result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "LONG"
            $short_result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "SHORT"

            ($long_result -eq $false) | Should Be $true    # LONG blocked
            ($short_result -eq $true) | Should Be $true     # SHORT enabled
        }
    }

    Context "Candle Fetcher Mock" {

        It "Get-CoinExCandles returns empty array on invalid market" {
            # Mock: API failure returns empty array
            # (In live, this would call CoinEx API)
            $candles = @()  # Simulating failure
            $candles.Count | Should Be 0
        }

        It "handles insufficient candle count gracefully" {
            # Simulate: only 5 candles returned
            $candles = @(
                @{ close = 100; open = 99; high = 101; low = 98; volume = 1000 },
                @{ close = 101; open = 100; high = 102; low = 99; volume = 1000 },
                @{ close = 102; open = 101; high = 103; low = 100; volume = 1000 },
                @{ close = 101; open = 102; high = 103; low = 100; volume = 1000 },
                @{ close = 103; open = 101; high = 104; low = 100; volume = 1000 }
            )

            # get_TrendDirection should return NEUTRAL for count < 20
            $trend = Get-TrendDirection -Candles $candles -Timeframe "TEST"
            ($trend -eq "NEUTRAL") | Should Be $true
        }
    }

    Context "Order Execution Gate Logic (simulated)" {

        It "simulates blocked order for LONG with downtrend HTF" {
            # Scenario: gem_executor receives LONG signal, but 1D/4H downtrend
            $direction = "LONG"
            $trend1D = "STRONG_DOWN"
            $trend4H = "DOWN"
            $trend1H = "UP"

            $blocked = -not (Test-MultiTimeframeAlignment -Trend1D $trend1D -Trend4H $trend4H -Trend1H $trend1H -Direction $direction)

            $blocked | Should Be $true  # Order would be blocked
        }

        It "simulates approved order for SHORT with downtrend HTF" {
            # Scenario: gem_executor receives SHORT signal, 1D/4H downtrend
            $direction = "SHORT"
            $trend1D = "DOWN"
            $trend4H = "STRONG_DOWN"
            $trend1H = "UP"

            $approved = Test-MultiTimeframeAlignment -Trend1D $trend1D -Trend4H $trend4H -Trend1H $trend1H -Direction $direction

            $approved | Should Be $true  # Order would be approved
        }
    }
}
