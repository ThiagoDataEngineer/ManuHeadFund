# leverage_cap.Tests.ps1 -- 2026-07-17: convertido pra sintaxe Pester 3.4.0
# (ambiente local so tem Pester 3.4.0 instalado; -BeLessThanOrEqual/-BeCloseTo
# nao existem nessa versao -- comparacoes booleanas manuais via Should Be $true)

Describe "Leverage Cap (Blocker #3 Fix)" {

    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_leverage_cap.ps1")
    }

    Context "Get-SafeLeverage Hard Cap" {
        It "Should never return > 5x leverage" {
            $result = Get-SafeLeverage -RequestedLeverage 50  # Request 50x (BNB bug)
            ($result -le 5.0) | Should Be $true
        }

        It "Should return 2x for STANDARD mode default" {
            $result = Get-SafeLeverage -Mode "STANDARD"
            $result | Should Be 2.0
        }

        It "Should return 1x for SCALP mode default" {
            $result = Get-SafeLeverage -Mode "SCALP"
            $result | Should Be 1.0
        }

        It "Should return 3x for PUMP_RIDE mode default" {
            $result = Get-SafeLeverage -Mode "PUMP_RIDE"
            $result | Should Be 3.0
        }

        It "Should bump leverage for elite conviction (>75)" {
            $result = Get-SafeLeverage -Mode "STANDARD" -ConvictionPercent 90
            ($result -gt 2.0) | Should Be $true
            ($result -le 5.0) | Should Be $true
        }

        It "Should reduce leverage for low conviction (<40)" {
            $result = Get-SafeLeverage -Mode "STANDARD" -ConvictionPercent 30
            ($result -lt 2.0) | Should Be $true
            ($result -ge 1.0) | Should Be $true
        }
    }

    Context "Test-LeverageSafe Validation" {
        It "Should FAIL for leverage > 5x" {
            $result = Test-LeverageSafe -Leverage 50 -Capital 3645 -PositionSize 18225
            $result.safe | Should Be $false
            $result.reason | Should Match "exceeds_cap"
        }

        It "Should PASS for leverage 5x" {
            $result = Test-LeverageSafe -Leverage 5.0 -Capital 3645 -PositionSize 18225
            $result.safe | Should Be $true
        }

        It "Should PASS for leverage 2x" {
            $result = Test-LeverageSafe -Leverage 2.0 -Capital 3645 -PositionSize 7290
            $result.safe | Should Be $true
        }

        It "Should calculate liquidation buffer for 5x" {
            # 5x leverage: liquidation at 20% below entry
            $result = Test-LeverageSafe -Leverage 5.0 -Capital 3645 -PositionSize 18225
            ([Math]::Abs($result.liquidation_buffer_pct - 20) -lt 1) | Should Be $true
        }

        It "Should FAIL if liquidation buffer too tight (>15% required)" {
            # 10x leverage: liquidation at 10% (below safe threshold)
            $result = Test-LeverageSafe -Leverage 10 -Capital 3645 -PositionSize 36450
            $result.safe | Should Be $false
        }
    }

    Context "Blocker #3 Evidence: 50x BNB No More" {
        It "Should reject BNB 50x trade from earlier" {
            # BNBUSDT was 50x, should be capped now
            $result = Get-SafeLeverage -RequestedLeverage 50

            ($result -le 5.0) | Should Be $true
            ($result -gt 1.0) | Should Be $true
        }

        It "Should reject XMR 20x trade from earlier" {
            $result = Get-SafeLeverage -RequestedLeverage 20

            ($result -le 5.0) | Should Be $true
        }

        It "Should enforce cap on ALL requests" {
            @(1, 5, 10, 50, 100, 1000) | ForEach-Object {
                $result = Get-SafeLeverage -RequestedLeverage $_
                ($result -le 5.0) | Should Be $true
                ($result -ge 1.0) | Should Be $true
            }
        }
    }
}
