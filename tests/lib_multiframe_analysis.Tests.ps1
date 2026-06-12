# lib_multiframe_analysis.Tests.ps1 — TDD for Multi-TF Analysis
# 2026-06-08: 20 test cases for trend detection and alignment

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_multiframe_analysis.ps1")

Describe "Multi-Timeframe Analysis" {

    # ─────────────────────────────────────────────────────────────────────────
    # Trend Detection Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Trend Direction Detection" {

        It "detects STRONG_UP when close > SMA20 and RSI > 60" {
            # Mock: uptrend with overbought
            $candles = @()
            for ($i = 0; $i -lt 20; $i++) {
                $candles += @{ close = 100 + $i; open = 99 + $i; high = 101 + $i; low = 98 + $i; volume = 1000 }
            }
            $candles += @{ close = 120; open = 119; high = 121; low = 118; volume = 1000 }  # Final RSI spike

            $trend = Get-TrendDirection -Candles $candles -Timeframe "4H"
            ($trend -eq "STRONG_UP") | Should Be $true
        }

        It "detects STRONG_DOWN when close < SMA20 and RSI < 40" {
            $candles = @()
            for ($i = 0; $i -lt 20; $i++) {
                $candles += @{ close = 100 - $i; open = 101 - $i; high = 102 - $i; low = 99 - $i; volume = 1000 }
            }
            $candles += @{ close = 70; open = 71; high = 72; low = 69; volume = 1000 }

            $trend = Get-TrendDirection -Candles $candles -Timeframe "1D"
            ($trend -eq "STRONG_DOWN") | Should Be $true
        }

        It "returns NEUTRAL for insufficient candles" {
            $candles = @(
                @{ close = 100; open = 99; high = 101; low = 98; volume = 1000 },
                @{ close = 101; open = 100; high = 102; low = 99; volume = 1000 }
            )

            $trend = Get-TrendDirection -Candles $candles -Timeframe "1H"
            ($trend -eq "NEUTRAL") | Should Be $true
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Multi-TF Alignment Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "LONG Alignment Rules" {

        It "LONG passes when 1D=UP and 4H=UP" {
            $result = Test-MultiTimeframeAlignment -Trend1D "UP" -Trend4H "UP" -Trend1H "DOWN" -Direction "LONG"
            $result | Should Be $true
        }

        It "LONG passes when 1D=STRONG_UP and 4H=STRONG_UP" {
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_UP" -Trend4H "STRONG_UP" -Trend1H "NEUTRAL" -Direction "LONG"
            $result | Should Be $true
        }

        It "LONG fails when 1D=DOWN and 4H=UP" {
            $result = Test-MultiTimeframeAlignment -Trend1D "DOWN" -Trend4H "UP" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "LONG fails when 1D=UP and 4H=DOWN" {
            $result = Test-MultiTimeframeAlignment -Trend1D "UP" -Trend4H "DOWN" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "LONG fails when 1D=NEUTRAL and 4H=UP (1D needed UP)" {
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "UP" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "LONG passes when 1H=DOWN but 1D+4H align UP" {
            $result = Test-MultiTimeframeAlignment -Trend1D "UP" -Trend4H "UP" -Trend1H "DOWN" -Direction "LONG"
            $result | Should Be $true
        }
    }

    Context "SHORT Alignment Rules" {

        It "SHORT passes when 1D=DOWN and 4H=DOWN" {
            $result = Test-MultiTimeframeAlignment -Trend1D "DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "SHORT"
            $result | Should Be $true
        }

        It "SHORT passes when 1D=STRONG_DOWN and 4H=STRONG_DOWN" {
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "STRONG_DOWN" -Trend1H "NEUTRAL" -Direction "SHORT"
            $result | Should Be $true
        }

        It "SHORT passes when 1D=NEUTRAL and 4H=DOWN" {
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "DOWN" -Trend1H "DOWN" -Direction "SHORT"
            $result | Should Be $true
        }

        It "SHORT fails when 1D=UP and 4H=DOWN" {
            $result = Test-MultiTimeframeAlignment -Trend1D "UP" -Trend4H "DOWN" -Trend1H "DOWN" -Direction "SHORT"
            $result | Should Be $false
        }

        It "SHORT fails when 1D=DOWN and 4H=UP" {
            $result = Test-MultiTimeframeAlignment -Trend1D "DOWN" -Trend4H "UP" -Trend1H "DOWN" -Direction "SHORT"
            $result | Should Be $false
        }

        It "SHORT passes when 1H=UP but 1D+4H align DOWN/NEUTRAL" {
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "DOWN" -Trend1H "UP" -Direction "SHORT"
            $result | Should Be $true
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Special Cases
    # ─────────────────────────────────────────────────────────────────────────

    Context "Edge Cases" {

        It "LONG fails when all three trends are NEUTRAL" {
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "NEUTRAL" -Trend1H "NEUTRAL" -Direction "LONG"
            $result | Should Be $false
        }

        It "SHORT passes when all three trends are NEUTRAL" {
            $result = Test-MultiTimeframeAlignment -Trend1D "NEUTRAL" -Trend4H "NEUTRAL" -Trend1H "NEUTRAL" -Direction "SHORT"
            $result | Should Be $true
        }

        It "PIPPIN case: 1D=STRONG_DOWN and 4H=DOWN blocks LONG" {
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "LONG"
            $result | Should Be $false
        }

        It "PIPPIN case: 1D=STRONG_DOWN and 4H=DOWN approves SHORT" {
            $result = Test-MultiTimeframeAlignment -Trend1D "STRONG_DOWN" -Trend4H "DOWN" -Trend1H "UP" -Direction "SHORT"
            $result | Should Be $true
        }
    }
}
