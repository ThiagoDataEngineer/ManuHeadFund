param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "lib_correlation_rolling — Beta rolling correlation (1h)" {
    . "$ModulePath\lib_correlation_rolling.ps1"

    Context "Get-RollingCorrelation (Pearson)" {
        It "Two identical series (perfect correlation = 1.0)" {
            $s1 = @(10, 20, 30, 40, 50)
            $s2 = @(10, 20, 30, 40, 50)
            $corr = Get-RollingCorrelation -Series1 $s1 -Series2 $s2
            $corr | Should Be 1.0
        }

        It "Two opposite series (perfect negative = -1.0)" {
            $s1 = @(10, 20, 30, 40, 50)
            $s2 = @(50, 40, 30, 20, 10)
            $corr = Get-RollingCorrelation -Series1 $s1 -Series2 $s2
            [math]::Abs($corr) | Should Be 1.0
        }

        It "Independent series (near-zero correlation)" {
            $s1 = @(1, 2, 3, 4, 5)
            $s2 = @(5, 1, 4, 2, 3)
            $corr = Get-RollingCorrelation -Series1 $s1 -Series2 $s2
            [math]::Abs($corr) | Should BeLessThan 0.35
        }

        It "Insufficient data (n < 2): return null (fail-soft)" {
            $s1 = @(10)
            $s2 = @(10)
            $corr = Get-RollingCorrelation -Series1 $s1 -Series2 $s2
            $corr | Should Be $null
        }

        It "One series all zeros: return null (fail-soft)" {
            $s1 = @(0, 0, 0, 0)
            $s2 = @(1, 2, 3, 4)
            $corr = Get-RollingCorrelation -Series1 $s1 -Series2 $s2
            $corr | Should Be $null
        }
    }

    Context "Test-CorrelationThreshold" {
        It "Low correlation (0.3): below 0.75 → pass=true" {
            $result = Test-CorrelationThreshold -Correlation 0.3 -Threshold 0.75
            $result.pass | Should Be $true
        }

        It "Moderate correlation (0.75): equals threshold → pass=false (boundary)" {
            $result = Test-CorrelationThreshold -Correlation 0.75 -Threshold 0.75
            $result.pass | Should Be $false
        }

        It "High correlation (0.85): above 0.75 → pass=false" {
            $result = Test-CorrelationThreshold -Correlation 0.85 -Threshold 0.75
            $result.pass | Should Be $false
        }

        It "Perfect correlation (1.0): pass=false, alert=true" {
            $result = Test-CorrelationThreshold -Correlation 1.0 -Threshold 0.75
            $result.pass | Should Be $false
            $result.alert_demote | Should Be $true
        }

        It "Custom threshold respected" {
            $result = Test-CorrelationThreshold -Correlation 0.7 -Threshold 0.8
            $result.pass | Should Be $true
        }
    }

    Context "Test-CorrelationTrend" {
        It "Trending UP (0.5 → 0.8): trend=UP" {
            $trend = Test-CorrelationTrend -Previous 0.5 -Current 0.8
            $trend.direction | Should Be "UP"
            $trend.delta | Should Be 0.3
        }

        It "Trending DOWN (0.8 → 0.5): trend=DOWN" {
            $trend = Test-CorrelationTrend -Previous 0.8 -Current 0.5
            $trend.direction | Should Be "DOWN"
            $trend.delta | Should Be -0.3
        }

        It "Flat (0.75 → 0.76): trend=FLAT" {
            $trend = Test-CorrelationTrend -Previous 0.75 -Current 0.76
            $trend.direction | Should Be "FLAT"
        }

        It "First measurement (previous null): trend=INIT" {
            $trend = Test-CorrelationTrend -Previous $null -Current 0.65
            $trend.direction | Should Be "INIT"
        }
    }

    Context "Integration: Full Alpha Demote Logic" {
        BeforeEach {
            $testPath = "$env:TEMP\corr_cache_test_$(Get-Random).json"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Low corr + BEAR_WEAK: pass gate (no demote)" {
            # Asset: ETHUSDT, correlation 0.45 (low)
            $result = Test-AlphaCorrelationGate `
                -AssetMarket "ETHUSDT" `
                -Correlation 0.45 `
                -Regime "BEAR_WEAK" `
                -CachePath $testPath

            $result.pass | Should Be $true
        }

        It "High corr (0.82) + trending UP + BEAR_WEAK: demote" {
            # Asset losing alpha (following BTC)
            $trend = @{ direction = "UP"; delta = 0.15; trending_up = $true }
            $result = Test-AlphaCorrelationGate `
                -AssetMarket "BTCBTC" `
                -Correlation 0.82 `
                -Trend $trend `
                -Regime "BEAR_WEAK" `
                -CachePath $testPath

            $result.pass | Should Be $false
            $result.action | Should Be "DEMOTE_TO_OBSERVE"
        }

        It "High corr (0.80) but trending DOWN: no demote (improving)" {
            # Asset decorrelating from BTC (good)
            $trend = @{ direction = "DOWN"; delta = -0.12; trending_up = $false }
            $result = Test-AlphaCorrelationGate `
                -AssetMarket "PENDLE" `
                -Correlation 0.80 `
                -Trend $trend `
                -Regime "BEAR_WEAK" `
                -CachePath $testPath

            $result.pass | Should Be $true
            $result.reason | Should Match "decorrelating"
        }

        It "High corr + non-BEAR_WEAK regime: pass (not applicable)" {
            $result = Test-AlphaCorrelationGate `
                -AssetMarket "ETHUSDT" `
                -Correlation 0.88 `
                -Regime "BULL_WEAK" `
                -CachePath $testPath

            $result.pass | Should Be $true
        }
    }

    Context "Cache: Correlation history" {
        BeforeEach {
            $testPath = "$env:TEMP\corr_history_$(Get-Random).json"
        }

        AfterEach {
            if (Test-Path $testPath) { Remove-Item $testPath -Force }
        }

        It "Saves correlation snapshot" {
            Save-CorrelationSnapshot -Path $testPath `
                -Market "ETHUSDT" `
                -Correlation 0.65 `
                -Trend "FLAT" `
                -Timestamp (Get-Date)

            (Test-Path $testPath) | Should Be $true
        }

        It "Retrieves last correlation" {
            Save-CorrelationSnapshot -Path $testPath -Market "ETHUSDT" -Correlation 0.50 -Trend "FLAT" -Timestamp (Get-Date)
            Save-CorrelationSnapshot -Path $testPath -Market "ETHUSDT" -Correlation 0.65 -Trend "UP" -Timestamp (Get-Date)

            $last = Get-LastCorrelationSnapshot -Path $testPath -Market "ETHUSDT"
            $last.correlation | Should Be 0.65
            $last.trend | Should Be "UP"
        }

        It "Appends multiple markets" {
            Save-CorrelationSnapshot -Path $testPath -Market "ETHUSDT" -Correlation 0.50 -Trend "FLAT" -Timestamp (Get-Date)
            Save-CorrelationSnapshot -Path $testPath -Market "PENDLE" -Correlation 0.72 -Trend "UP" -Timestamp (Get-Date)

            $lines = @(Get-Content $testPath | ConvertFrom-Json)
            $lines.Count | Should Be 2
        }
    }
}
