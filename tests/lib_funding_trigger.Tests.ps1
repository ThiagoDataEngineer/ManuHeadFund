# lib_funding_trigger.Tests.ps1 -- TDD da conviccao do funding producer.
#
# Get-FundingConviction: funding rate (8h) -> conviccao 0-100 + direcao.
# Positivo extremo -> SHORT (longs lotados), negativo -> LONG. Abaixo de
# exhaustion (0.05%/8h) -> 0. Threshold funding no bus = 60.
#
# Pester 3.x. UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_funding_exhaustion_gate.ps1")


Describe "Get-FundingConviction" {
    It "funding no limiar (0.05%/8h) -> conviccao 60 SHORT" {
        $r = Get-FundingConviction -FundingRate 0.0005
        $r.conviction | Should Be 60
        $r.direction  | Should Be "short"
    }
    It "funding 0.10%/8h -> 80 SHORT" {
        (Get-FundingConviction -FundingRate 0.001).conviction | Should Be 80
    }
    It "funding negativo extremo -> LONG" {
        (Get-FundingConviction -FundingRate -0.001).direction | Should Be "long"
    }
    It "funding abaixo do limiar -> 0 (nao dispara)" {
        (Get-FundingConviction -FundingRate 0.0001).conviction | Should Be 0
    }
    It "funding muito extremo satura em 100" {
        (Get-FundingConviction -FundingRate 0.003).conviction | Should Be 100
    }
}
