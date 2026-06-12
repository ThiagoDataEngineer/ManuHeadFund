# mentor_5tier_mandatory.Tests.ps1 -- B.2
# Test-MentorOutputV2 (extended) requer veredicto_5tier alem dos campos legacy.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\agents\lib_mentor_schema.ps1"

Describe "Test-MentorOutputV2 5-tier mandatory" {

    It "valid quando veredicto_5tier presente" {
        $obj = [PSCustomObject]@{
            decision = "APROVAR"; confianca = 80
            veredicto_5tier = "EXECUTAR"
            mentor_mensagem = "Setup ok"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $true
        $r.violations.Count | Should Be 0
    }

    It "invalid quando veredicto_5tier ausente" {
        $obj = [PSCustomObject]@{
            decision = "APROVAR"; confianca = 80
            mentor_mensagem = "msg"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $false
        ($r.violations -join ',') | Should Match "veredicto_5tier"
    }

    It "invalid quando veredicto_5tier nao reconhecido" {
        $obj = [PSCustomObject]@{
            decision = "VETAR"; confianca = 30
            veredicto_5tier = "QUASE_EXECUTAR"
            mentor_mensagem = "x"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $false
        ($r.violations -join ',') | Should Match "5tier_invalid"
    }

    It "tier coerente: STRONG_EXECUTAR/EXECUTAR mapeia decision=APROVAR" {
        $obj = [PSCustomObject]@{
            decision = "VETAR"  # conflict
            confianca = 80
            veredicto_5tier = "EXECUTAR"
            mentor_mensagem = "x"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $false
        ($r.violations -join ',') | Should Match "5tier_decision_inconsistent"
    }

    It "tier ABORTAR/HARD_VETO coerente com decision=VETAR" {
        $obj = [PSCustomObject]@{
            decision = "VETAR"; confianca = 20
            veredicto_5tier = "HARD_VETO"
            mentor_mensagem = "extreme red flag"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $true
    }

    It "REVISAR mapeia pra qualquer decision (paper-only intermedio)" {
        $obj = [PSCustomObject]@{
            decision = "APROVAR"; confianca = 50
            veredicto_5tier = "REVISAR"
            mentor_mensagem = "doubt"
        }
        $r = Test-MentorOutputV2 -Response $obj
        $r.valid | Should Be $true
    }
}
