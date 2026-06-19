Describe "Leverage Cap (Blocker #3 Fix)" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_leverage_cap.ps1")
    }

    Context "Get-SafeLeverage Hard Cap" {
        It "Should never return > 5x leverage" {
            $result = Get-SafeLeverage -RequestedLeverage 50  # Request 50x (BNB bug)
            $result | Should -BeLessThanOrEqual 5.0
        }

        It "Should return 2x for STANDARD mode default" {
            $result = Get-SafeLeverage -Mode "STANDARD"
            $result | Should -Be 2.0
        }

        It "Should return 1x for SCALP mode default" {
            $result = Get-SafeLeverage -Mode "SCALP"
            $result | Should -Be 1.0
        }

        It "Should return 3x for PUMP_RIDE mode default" {
            $result = Get-SafeLeverage -Mode "PUMP_RIDE"
            $result | Should -Be 3.0
        }

        It "Should bump leverage for elite conviction (>75)" {
            $result = Get-SafeLeverage -Mode "STANDARD" -ConvictionPercent 90
            $result | Should -BeGreaterThan 2.0
            $result | Should -BeLessThanOrEqual 5.0
        }

        It "Should reduce leverage for low conviction (<40)" {
            $result = Get-SafeLeverage -Mode "STANDARD" -ConvictionPercent 30
            $result | Should -BeLessThan 2.0
            $result | Should -BeGreaterThanOrEqual 1.0
        }
    }

    Context "Test-LeverageSafe Validation" {
        It "Should FAIL for leverage > 5x" {
            $result = Test-LeverageSafe -Leverage 50 -Capital 3645 -PositionSize 18225
            $result.safe | Should -Be $false
            $result.reason | Should -Match "exceeds_cap"
        }

        It "Should PASS for leverage 5x" {
            $result = Test-LeverageSafe -Leverage 5.0 -Capital 3645 -PositionSize 18225
            $result.safe | Should -Be $true
        }

        It "Should PASS for leverage 2x" {
            $result = Test-LeverageSafe -Leverage 2.0 -Capital 3645 -PositionSize 7290
            $result.safe | Should -Be $true
        }

        It "Should calculate liquidation buffer for 5x" {
            # 5x leverage: liquidation at 20% below entry
            $result = Test-LeverageSafe -Leverage 5.0 -Capital 3645 -PositionSize 18225
            $result.liquidation_buffer_pct | Should -BeCloseTo 20 -Precision 1
        }

        It "Should FAIL if liquidation buffer too tight (>15% required)" {
            # 10x leverage: liquidation at 10% (below safe threshold)
            $result = Test-LeverageSafe -Leverage 10 -Capital 3645 -PositionSize 36450
            $result.safe | Should -Be $false
        }
    }

    Context "Blocker #3 Evidence: 50x BNB No More" {
        It "Should reject BNB 50x trade from earlier" {
            # BNBUSDT was 50x, should be capped now
            $result = Get-SafeLeverage -RequestedLeverage 50

            $result | Should -BeLessThanOrEqual 5.0
            $result | Should -BeGreaterThan 1.0
        }

        It "Should reject XMR 20x trade from earlier" {
            $result = Get-SafeLeverage -RequestedLeverage 20

            $result | Should -BeLessThanOrEqual 5.0
        }

        It "Should enforce cap on ALL requests" {
            @(1, 5, 10, 50, 100, 1000) | ForEach-Object {
                $result = Get-SafeLeverage -RequestedLeverage $_
                $result | Should -BeLessThanOrEqual 5.0
                $result | Should -BeGreaterThanOrEqual 1.0
            }
        }
    }
}
