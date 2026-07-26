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

    Context "Threshold dinamico por momentum (2026-07-26)" {

        It "sem StrongAxesCount (default -1): comportamento identico ao fixo (regressao)" {
            # Caso real: SOLUSDT conviction=60.7, sem avaliar eixos -> continua bloqueado em 75
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 60.7 -DataAbsent $false -FlagOn $true -Threshold 75
            $r.allow | Should Be $false
        }

        It "2+ eixos fortes reduz threshold 75->60: conviction 60.7 agora passa" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 60.7 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 2
            $r.allow | Should Be $true
            $r.reason | Should Match "momentum"
        }

        It "so 1 eixo forte (abaixo do minimo 2): threshold continua 75, conviction 60.7 bloqueada" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 60.7 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 1
            $r.allow | Should Be $false
        }

        It "3 eixos fortes tambem reduz (minimo e piso, nao teto exato)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 62 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 3
            $r.allow | Should Be $true
        }

        It "conviction abaixo mesmo do threshold reduzido continua bloqueada" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 39.3 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 2
            $r.allow | Should Be $false
        }

        It "StrongAxesMinCount customizavel (exigir 3 em vez de 2)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 60.7 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 2 -StrongAxesMinCount 3
            $r.allow | Should Be $false
        }

        It "StrongAxesReducedThreshold customizavel" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 65 -DataAbsent $false -FlagOn $true -Threshold 75 -StrongAxesCount 2 -StrongAxesReducedThreshold 65
            $r.allow | Should Be $true
        }

        It "flag OFF ainda bloqueia mesmo com momentum forte (fail-safe preservado)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 90 -DataAbsent $false -FlagOn $false -Threshold 75 -StrongAxesCount 3
            $r.allow | Should Be $false
        }

        It "dados ausentes ainda bloqueia mesmo com momentum forte (fail-safe preservado)" {
            $r = Resolve-ConvictionOverride -ToriSignal "SKIP" -Conviction 90 -DataAbsent $true -FlagOn $true -Threshold 75 -StrongAxesCount 3
            $r.allow | Should Be $false
        }
    }
}
