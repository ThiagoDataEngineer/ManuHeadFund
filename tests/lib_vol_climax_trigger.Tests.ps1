# lib_vol_climax_trigger.Tests.ps1 -- TDD da conviccao do vol_climax producer.
#
# Get-VolClimaxConviction: SO Tier S (paper-trade eligible) e nao cluster-suprimido
# dispara trigger; conviccao = WSS (0-100). Tier A/B = observatorio (0).
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_chart_patterns.ps1")


Describe "Get-VolClimaxConviction" {
    It "Tier S nao suprimido -> conviccao = WSS" {
        Get-VolClimaxConviction -Tier "S" -Wss 75 | Should Be 75
    }
    It "Tier A (observatorio) -> 0 (nao dispara)" {
        Get-VolClimaxConviction -Tier "A" -Wss 90 | Should Be 0
    }
    It "Tier B -> 0" {
        Get-VolClimaxConviction -Tier "B" -Wss 80 | Should Be 0
    }
    It "Tier S mas cluster-suprimido -> 0" {
        Get-VolClimaxConviction -Tier "S" -Wss 88 -ClusterSuppressed $true | Should Be 0
    }
    It "WSS acima de 100 satura em 100" {
        Get-VolClimaxConviction -Tier "S" -Wss 130 | Should Be 100
    }
}
