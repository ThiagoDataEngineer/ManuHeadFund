# lib_tori_confluence_detector.Tests.ps1 - Pester test suite for confluence detection
#
# Tests: Volume Climax, RSI Extremes, Fractal, CHoCH, Volume Profile
#
# PS 5.1, UTF-8 BOM

Describe "lib_tori_confluence_detector" {
    BeforeAll {
        $libPath = Join-Path $PSScriptRoot "..\agents\lib_tori_confluence_detector.ps1"
        . $libPath
    }

    Context "Get-VolumeClimax" {
        It "detects volume climax when current volume is 2.5x average" {
            $volumes = @(100, 95, 105, 98, 102, 250)  # Last is 2.5x average
            $result = Get-VolumeClimax -Volumes $volumes -Threshold 2.0

            $result.is_climax | Should -Be $true
            $result.ratio | Should -BeGreaterThan 2.0
        }

        It "returns false when volume is not spiked" {
            $volumes = @(100, 95, 105, 98, 102, 105)
            $result = Get-VolumeClimax -Volumes $volumes -Threshold 2.0

            $result.is_climax | Should -Be $false
        }

        It "handles insufficient data gracefully" {
            $volumes = @(100, 200)
            $result = Get-VolumeClimax -Volumes $volumes

            $result.is_climax | Should -Be $false
            $result.ratio | Should -Be 0.0
        }

        It "handles zero volume gracefully" {
            $volumes = @(0, 0, 0, 0, 0)
            $result = Get-VolumeClimax -Volumes $volumes

            $result.is_climax | Should -Be $false
            $result.ratio | Should -Be 0.0
        }
    }

    Context "Get-RSIExtreme" {
        It "detects oversold for LONG setup (RSI < 30)" {
            $result = Get-RSIExtreme -RSI 25 -SetupType "LONG"

            $result.is_extreme | Should -Be $true
            $result.extreme_type | Should -Be "OVERSOLD"
            $result.points | Should -Be 20
        }

        It "detects overbought for SHORT setup (RSI > 70)" {
            $result = Get-RSIExtreme -RSI 75 -SetupType "SHORT"

            $result.is_extreme | Should -Be $true
            $result.extreme_type | Should -Be "OVERBOUGHT"
            $result.points | Should -Be 20
        }

        It "returns false for LONG when RSI is not oversold" {
            $result = Get-RSIExtreme -RSI 50 -SetupType "LONG"

            $result.is_extreme | Should -Be $false
            $result.points | Should -Be 0
        }

        It "returns false for SHORT when RSI is not overbought" {
            $result = Get-RSIExtreme -RSI 50 -SetupType "SHORT"

            $result.is_extreme | Should -Be $false
            $result.points | Should -Be 0
        }
    }

    Context "Get-FractalPattern" {
        It "detects bearish fractal (peak with lower highs on sides)" {
            $opens = @(100, 102, 104, 103, 101)
            $highs = @(100, 103, 110, 105, 102)  # Index 2 is peak
            $lows = @(99, 101, 108, 102, 100)
            $closes = @(99, 102, 109, 104, 101)

            $result = Get-FractalPattern -Opens $opens -Highs $highs -Lows $lows -Closes $closes

            $result.fractal_type | Should -Be "BEARISH"
            $result.points | Should -Be 15
        }

        It "detects bullish fractal (trough with higher lows on sides)" {
            $opens = @(100, 102, 100, 103, 101)
            $highs = @(100, 103, 102, 105, 102)
            $lows = @(99, 101, 90, 102, 100)  # Index 2 is trough
            $closes = @(99, 102, 91, 104, 101)

            $result = Get-FractalPattern -Opens $opens -Highs $highs -Lows $lows -Closes $closes

            $result.fractal_type | Should -Be "BULLISH"
            $result.points | Should -Be 15
        }

        It "returns no fractal when pattern insufficient" {
            $opens = @(100, 101)
            $highs = @(100, 101)
            $lows = @(99, 100)
            $closes = @(100, 100)

            $result = Get-FractalPattern -Opens $opens -Highs $highs -Lows $lows -Closes $closes

            $result.fractal_type | Should -Be ""
            $result.points | Should -Be 0
        }
    }

    Context "Get-StructuralBreak" {
        It "detects LONG CHoCH when new low breaks below prior support" {
            $lows = @(100, 101, 102, 99, 97)  # Last 2 avg (98) < prior 2 avg (101.5)
            $highs = @(105, 106, 107, 104, 102)

            $result = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType "LONG"

            $result.has_choch | Should -Be $true
            $result.points | Should -Be 15
        }

        It "detects SHORT CHoCH when new high breaks above prior resistance" {
            $lows = @(95, 94, 93, 96, 98)
            $highs = @(100, 101, 102, 105, 107)  # Last 2 avg (106) > prior 2 avg (101.5)

            $result = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType "SHORT"

            $result.has_choch | Should -Be $true
            $result.points | Should -Be 15
        }

        It "returns false when no structural break" {
            $lows = @(100, 101, 102, 101, 100)  # No new low
            $highs = @(105, 106, 107, 106, 105)

            $result = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType "LONG"

            $result.has_choch | Should -Be $false
            $result.points | Should -Be 0
        }

        It "handles insufficient data" {
            $lows = @(100, 101)
            $highs = @(105, 106)

            $result = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType "LONG"

            $result.has_choch | Should -Be $false
        }
    }

    Context "Get-VolumeProfile" {
        It "identifies peak volume level" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000 },
                [PSCustomObject]@{ close = 102; volume = 5000 },  # Peak volume
                [PSCustomObject]@{ close = 101; volume = 2000 },
                [PSCustomObject]@{ close = 103; volume = 1500 }
            )

            $result = Get-VolumeProfile -Candles $candles

            $result.peak_volume_level | Should -BeGreaterThan 0
            $result.total_volume | Should -Be 9500
        }

        It "handles single candle" {
            $candles = @(
                [PSCustomObject]@{ close = 100; volume = 1000 }
            )

            $result = Get-VolumeProfile -Candles $candles

            $result.peak_volume_level | Should -Be 100
        }

        It "returns empty for no candles" {
            $candles = @()

            $result = Get-VolumeProfile -Candles $candles

            $result.peak_volume_level | Should -Be 0.0
        }
    }

    Context "Get-ConfluenceScoreEnhanced" {
        It "returns baseline 50 for insufficient data" {
            $candles = @(
                [PSCustomObject]@{ open = 100; high = 101; low = 99; close = 100; volume = 1000 }
            )

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 100 -TrendlineTouches 2

            $result.total_score | Should -Be 0
            $result.signals_fired.Count | Should -Be 0
        }

        It "calculates score with multiple signals fired" {
            # Build 20-candle history with signals
            $candles = @()
            for ($i = 0; $i -lt 20; $i++) {
                $candles += [PSCustomObject]@{
                    open = 100 + $i
                    high = 102 + $i
                    low = 98 + $i
                    close = 100 + $i
                    volume = if ($i -eq 19) { 500 } else { 100 }  # Volume spike at end
                }
            }

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 99 -TrendlineTouches 3

            $result.total_score | Should -BeGreaterThan 0
            $result.total_score | Should -BeLessOrEqual 100
            $result.breakdown | Should -Not -BeNullOrEmpty
        }

        It "includes trendline touch bonus" {
            $candles = @()
            for ($i = 0; $i -lt 15; $i++) {
                $candles += [PSCustomObject]@{
                    open = 100
                    high = 101
                    low = 99
                    close = 100
                    volume = 100
                }
            }

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 100 -TrendlineTouches 4  # 4 touches = +10 points

            $result.breakdown["trendline_touches"] | Should -Be 10
        }

        It "caps score at 100" {
            $candles = @()
            for ($i = 0; $i -lt 30; $i++) {
                $candles += [PSCustomObject]@{
                    open = 100
                    high = 101
                    low = 99
                    close = 100
                    volume = 1000  # Huge volume spike
                }
            }

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 100 -TrendlineTouches 5

            $result.total_score | Should -BeLessOrEqual 100
        }

        it "returns correct properties" {
            $candles = @()
            for ($i = 0; $i -lt 20; $i++) {
                $candles += [PSCustomObject]@{
                    open = 100
                    high = 101
                    low = 99
                    close = 100
                    volume = 100
                }
            }

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 99 -TrendlineTouches 2

            $result | Should -HaveProperty "total_score"
            $result | Should -HaveProperty "breakdown"
            $result | Should -HaveProperty "signals_fired"
            $result | Should -HaveProperty "rsi"
            $result | Should -HaveProperty "volume_climax_ratio"
            $result | Should -HaveProperty "peak_volume_level"
            $result | Should -HaveProperty "trendline_touches"
        }
    }

    Context "Integration: Full Confluence Flow" {
        It "processes complete candle history and returns comprehensive score" {
            # Generate 30-candle history
            $candles = @()
            for ($i = 0; $i -lt 30; $i++) {
                $basePrice = 100 + ($i * 0.5)
                $candles += [PSCustomObject]@{
                    open = $basePrice
                    high = $basePrice + 1
                    low = $basePrice - 1
                    close = $basePrice
                    volume = if ($i -gt 25) { 500 } else { 100 }
                }
            }

            $result = Get-ConfluenceScoreEnhanced -Candles $candles -SetupType "LONG" `
                -TrendlineStartPrice 100 -TrendlineTouches 3

            # Verify complete output structure
            $result.total_score | Should -BeGreaterThan 0
            $result.total_score | Should -BeLessOrEqual 100
            $result.breakdown.Keys.Count | Should -BeGreaterThan 0
            $result.rsi | Should -BeGreaterThan 0
            $result.rsi | Should -BeLessOrEqual 100
        }
    }
}
