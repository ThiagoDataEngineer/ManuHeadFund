# lib_tori_trigger.Tests.ps1 -- TDD da conviccao do tori_ripe producer.
#
# Get-ToriConviction: SO setup_ripening dispara; mais perto da action_line + mais
# toques = maior conviccao (base 50). Threshold tori_ripe no bus = 50.
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_tori_proximity.ps1")


Describe "Get-ToriConviction" {
    It "nao-ripening -> 0 (nao dispara)" {
        Get-ToriConviction -Ripening $false -ProximityPct 0.2 -Touches 5 | Should Be 0
    }
    It "ripening colado na linha + muitos toques -> alta conviccao" {
        # prox 0% -> +30, touches 4 -> +20, base 50 = 100
        Get-ToriConviction -Ripening $true -ProximityPct 0.0 -Touches 4 | Should Be 100
    }
    It "ripening mais distante + poucos toques -> menor (mas >= base)" {
        # prox 2% -> +0, touches 1 -> +5, base 50 = 55
        Get-ToriConviction -Ripening $true -ProximityPct 2.0 -Touches 1 | Should Be 55
    }
    It "ripening sempre >= threshold 50" {
        (Get-ToriConviction -Ripening $true -ProximityPct 5.0 -Touches 0) -ge 50 | Should Be $true
    }
    It "satura em 100" {
        Get-ToriConviction -Ripening $true -ProximityPct 0.0 -Touches 99 | Should Be 100
    }
}
