# mentor_self_consistency.Tests.ps1 -- C.8
# Test-SelfConsistency: compara 2 respostas Mentor. Critical tiers (STRONG/HARD)
# precisam acordo; divergir -> downgrade EXECUTAR/ABORTAR.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\agents\lib_mentor_self_consistency.ps1"

function MakeResp { param($Tier5, $Decision) [PSCustomObject]@{ decision = $Decision; veredicto_5tier = $Tier5; confianca = 80 } }

Describe "Test-MentorCriticalTier" {

    It "STRONG_EXECUTAR eh critical" {
        Test-MentorCriticalTier -Veredicto5tier "STRONG_EXECUTAR" | Should Be $true
    }

    It "HARD_VETO eh critical" {
        Test-MentorCriticalTier -Veredicto5tier "HARD_VETO" | Should Be $true
    }

    It "EXECUTAR NAO eh critical" {
        Test-MentorCriticalTier -Veredicto5tier "EXECUTAR" | Should Be $false
    }

    It "REVISAR NAO eh critical" {
        Test-MentorCriticalTier -Veredicto5tier "REVISAR" | Should Be $false
    }
}

Describe "Resolve-SelfConsistency" {

    It "concordancia STRONG x STRONG -> mantem STRONG_EXECUTAR" {
        $r = Resolve-SelfConsistency -First (MakeResp "STRONG_EXECUTAR" "APROVAR") -Second (MakeResp "STRONG_EXECUTAR" "APROVAR")
        $r.final.veredicto_5tier | Should Be "STRONG_EXECUTAR"
        $r.consistent | Should Be $true
    }

    It "discordancia STRONG x EXECUTAR -> downgrade pra EXECUTAR" {
        $r = Resolve-SelfConsistency -First (MakeResp "STRONG_EXECUTAR" "APROVAR") -Second (MakeResp "EXECUTAR" "APROVAR")
        $r.final.veredicto_5tier | Should Be "EXECUTAR"
        $r.consistent | Should Be $false
        $r.reason | Should Match "downgrade"
    }

    It "discordancia HARD_VETO x ABORTAR -> downgrade pra ABORTAR" {
        $r = Resolve-SelfConsistency -First (MakeResp "HARD_VETO" "VETAR") -Second (MakeResp "ABORTAR" "VETAR")
        $r.final.veredicto_5tier | Should Be "ABORTAR"
        $r.consistent | Should Be $false
    }

    It "discordancia STRONG x VETAR -> downgrade pra REVISAR (max safe)" {
        $r = Resolve-SelfConsistency -First (MakeResp "STRONG_EXECUTAR" "APROVAR") -Second (MakeResp "ABORTAR" "VETAR")
        $r.final.veredicto_5tier | Should Be "REVISAR"
        $r.consistent | Should Be $false
    }
}

Describe "Test-SelfConsistencyRequired" {

    It "STRONG retorna true" {
        Test-SelfConsistencyRequired -Veredicto5tier "STRONG_EXECUTAR" | Should Be $true
    }
    It "HARD_VETO retorna true" {
        Test-SelfConsistencyRequired -Veredicto5tier "HARD_VETO" | Should Be $true
    }
    It "EXECUTAR/ABORTAR retorna false (saving cost)" {
        Test-SelfConsistencyRequired -Veredicto5tier "EXECUTAR" | Should Be $false
        Test-SelfConsistencyRequired -Veredicto5tier "ABORTAR" | Should Be $false
    }
}
