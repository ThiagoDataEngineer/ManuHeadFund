# B4 mode-conflict prevention: invariante pre-mentor.
# Defesa em profundidade — mesmo apos 4-mode mapping fix, payload corrompido
# (tier=A + mode=TIER_B_PAPER) deve falhar fast SEM custar 1 LLM call.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_mentor_invariants.ps1")

Describe "B4 Test-MentorPayloadInvariant" {
    It "tier=A + mode=TIER_A_LIVE: passa (mode coerente)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "A" -MentorMode "TIER_A_LIVE"
        $r.valid | Should Be $true
    }
    It "tier=A + mode=TIER_A_PAPER: passa (4-mode ortogonal correto)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "A" -MentorMode "TIER_A_PAPER"
        $r.valid | Should Be $true
    }
    It "tier=A + mode=TIER_B_PAPER: REJEITA (conflito mutual exclusion)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "A" -MentorMode "TIER_B_PAPER"
        $r.valid | Should Be $false
        $r.reason | Should Match "conflito|conflict|tier.*A.*TIER_B"
    }
    It "tier=B + mode=TIER_B_PAPER: passa (coerente)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "B" -MentorMode "TIER_B_PAPER"
        $r.valid | Should Be $true
    }
    It "tier=C + mode=TIER_A_LIVE: REJEITA (qualidade insuficiente)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "C" -MentorMode "TIER_A_LIVE"
        $r.valid | Should Be $false
    }
    It "GEM mode: sempre passa (path separado)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "B" -MentorMode "GEM"
        $r.valid | Should Be $true
    }
    It "tier vazio: REJEITA (payload incompleto)" {
        $r = Test-MentorPayloadInvariant -TriagemTier "" -MentorMode "TIER_A_LIVE"
        $r.valid | Should Be $false
    }
}
