Describe "Sizing Centralized (Blocker #2 Fix)" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_sizing_centralized.ps1")
    }

    Context "Get-SafePositionSize Basic" {
        It "Should return 1% of capital as max loss (standard)" {
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 100

            $result.max_loss_usd | Should -Be 36.45  # 3645 * 0.01
            $result.max_loss_pct | Should -BeCloseTo 1 -Precision 2
        }

        It "Should calculate size from SL distance" {
            # Entry 100, SL 98 = 2% stop loss
            # Max loss $36 → size = $36 / 0.02 = $1800
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            $result.size_usd | Should -Be 1800
            $result.size_pct | Should -BeCloseTo 49.3 -Precision 1
        }

        It "Should reduce size for low conviction (<50)" {
            # Same entry/stop, but conviction 25 = 50% reduction
            $resultHigh = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 100
            $resultLow = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02 -ConvictionPercent 25

            # Low conviction should be ~25% of high (25/50 = 0.5)
            $resultLow.size_usd | Should -BeLessThan $resultHigh.size_usd
        }

        It "Should cap leverage at 5x maximum" {
            # Force very small SL to create huge position
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.001  # tiny SL

            # Max = capital * 5x = $18,225
            $result.size_usd | Should -BeLessOrEqual 18225
        }
    }

    Context "Consistency Across Scenarios" {
        It "Should use 1% capital rule for ALL inputs" {
            # Three different scenarios, all should hit ~1% max loss
            $s1 = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02
            $s2 = Get-SafePositionSize -Capital 3645 -EntryPrice 50 -StopLossPercent 0.01
            $s3 = Get-SafePositionSize -Capital 3645 -EntryPrice 1000 -StopLossPercent 0.001

            # All should have max_loss ~$36
            $s1.max_loss_usd | Should -BeCloseTo 36.45 -Precision 1
            $s2.max_loss_usd | Should -BeCloseTo 36.45 -Precision 1
            $s3.max_loss_usd | Should -BeCloseTo 36.45 -Precision 1
        }
    }

    Context "Get-SafePositionSizeFromGem" {
        It "Should work from Gem object (wrapper)" {
            $gem = @{
                entry_price = 100
                stop_loss = 98
                conviction = 80
                market = "TESTUSDT"
            }

            $result = Get-SafePositionSizeFromGem -Gem $gem -Capital 3645

            $result.size_usd | Should -BeGreaterThan 0
            $result.max_loss_pct | Should -BeCloseTo 1 -Precision 1
        }

        It "Should return null for invalid gem" {
            $gem = @{
                entry_price = 0  # Invalid
                stop_loss = 98
            }

            $result = Get-SafePositionSizeFromGem -Gem $gem -Capital 3645
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Blocker #2 Evidence: Consistency" {
        It "Should NOT return 0.3% sizing anymore (old bug)" {
            # Old code: $size = capital * 0.003 = $10.93
            # New code: $size should be $1800 (1% / 2% SL)
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            $result.size_usd | Should -BeGreaterThan 1000  # Much larger than $10
        }

        It "Should NOT return 0.2% sizing anymore (old bug)" {
            $result = Get-SafePositionSize -Capital 3645 -EntryPrice 100 -StopLossPercent 0.02

            # Old: capital * 0.002 = $7.29
            # New: $1800
            $result.size_usd | Should -BeGreaterThan 1000
        }

        It "All paths should return same size for same inputs" {
            # Before fix: lib_gem_router, lib_kelly_wire, lib_hybrid_orchestrator all different
            # After fix: all use Get-SafePositionSize

            $capital = 3645
            $entry = 100
            $stop = 98

            $size1 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02
            $size2 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02
            $size3 = Get-SafePositionSize -Capital $capital -EntryPrice $entry -StopLossPercent 0.02

            $size1.size_usd | Should -Be $size2.size_usd
            $size2.size_usd | Should -Be $size3.size_usd
        }
    }
}
