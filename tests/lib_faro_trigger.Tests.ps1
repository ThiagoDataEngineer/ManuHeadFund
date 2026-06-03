# lib_faro_trigger.Tests.ps1 -- TDD da conviccao do faro producer.
#
# Get-FaroConviction: SO ENTRA (5/7) / URGENTE (6+/7) disparam; conviccao = score.
# WATCH/SKIP = 0. (FARO V3 e subsistema PS7 -- rodar sob pwsh + Pester 3.4.)
#
# UTF-8 BOM. Sem acentos.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_faro_v3_scoring.ps1")


Describe "Get-FaroConviction" {
    It "ENTRA score 71 -> 71" {
        Get-FaroConviction -Score 71 -Decision "ENTRA" | Should Be 71
    }
    It "URGENTE score 90 -> 90" {
        Get-FaroConviction -Score 90 -Decision "URGENTE" | Should Be 90
    }
    It "WATCH (4/7) -> 0 (nao dispara)" {
        Get-FaroConviction -Score 60 -Decision "WATCH" | Should Be 0
    }
    It "SKIP -> 0" {
        Get-FaroConviction -Score 30 -Decision "SKIP" | Should Be 0
    }
    It "score acima de 100 satura" {
        Get-FaroConviction -Score 130 -Decision "URGENTE" | Should Be 100
    }
}
