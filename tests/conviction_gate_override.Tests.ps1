# conviction_gate_override.Tests.ps1 -- TDD do override do Tori pelo ensemble
# Destrava o "Tori veta tudo": se conviccao do ensemble e alta, override o SKIP.
# FAIL-SAFE: so com flag; nunca overrida dados-ausentes nem gates de seguranca.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_entry_conviction_ensemble.ps1"

Describe "Resolve-ConvictionOverride" {

    Context "Override valido (destrava Tori)" {

        It "tori SKIP + conviccao alta + flag ON = ALLOW (override)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 85 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.allow | Should Be $true
        }

        It "tori WAIT + conviccao alta + flag ON = ALLOW" {
            $r = Resolve-ConvictionOverride -ToriSignal "WAIT" -Conviction 80 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.allow | Should Be $true
        }
    }

    Context "Respeita o veto (NAO override)" {

        It "conviccao abaixo do threshold = BLOCK" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 60 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.allow | Should Be $false
        }

        It "flag OFF = nunca override" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 95 -DataAbsent $false -FlagOn $false -Threshold 75
            $r.allow | Should Be $false
        }

        It "dados ausentes = nunca override (nao temos base)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 95 -DataAbsent $true -FlagOn $true -Threshold 75
            $r.allow | Should Be $false
        }

        It "tori ENTER = nao aplica (ja passa, sem override)" {
            $r = Resolve-ConvictionOverride -ToriSignal "ENTER" -Conviction 95 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.allow | Should Be $false
            $r.reason | Should Match "not_applicable|enter"
        }
    }

    Context "Retorna razao auditavel" {

        It "allow tem reason com conviccao" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 88 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.reason | Should Match "88|conviction|override"
        }
    }
}
