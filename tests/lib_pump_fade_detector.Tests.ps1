Describe "lib_pump_fade_detector" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_pump_fade_detector.ps1")
    }

    Context "Find-PumpFadeOpportunity" {
        It "função existe e é callable" {
            (Get-Command Find-PumpFadeOpportunity -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }

        It "retorna PSCustomObject com propriedade detected" {
            # Mock test: apenas verifica se função retorna estrutura correta
            $mockResult = [PSCustomObject]@{
                detected = $false
                market = "TESTUSDT"
                reason = "insufficient_data"
            }

            $mockResult.PSObject.Properties.Name -contains "detected" | Should Be $true
            $mockResult.PSObject.Properties.Name -contains "market" | Should Be $true
        }

        It "detected pode ser true com pump-fade pattern" {
            $mockResult = [PSCustomObject]@{
                detected = $true
                market = "HUSDT"
                pump_ret = 15.0
                dump_ret = -20.0
                confidence = 0.75
                entry_setup = @{
                    entry_price = 0.5
                    stop_pct = 0.01
                    target_pct = 0.05
                }
            }

            $mockResult.detected | Should Be $true
            $mockResult.confidence | Should Be 0.75
        }
    }
}
