# mentor_multi_shot.Tests.ps1 -- B.7
# Get-MentorExamplesBlock retorna 1 APROVAR + 1 VETAR canonicos no formato JSON.

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\..\agents\lib_mentor_examples.ps1"

Describe "Get-MentorExamplesBlock" {

    It "retorna bloco com header e end" {
        $b = Get-MentorExamplesBlock
        $b | Should Match "=== EXAMPLES ==="
        $b | Should Match "=== END EXAMPLES ==="
    }

    It "contem exemplo APROVAR com veredicto_5tier=EXECUTAR" {
        $b = Get-MentorExamplesBlock
        $b | Should Match "EXECUTAR"
        $b | Should Match "APROVAR"
    }

    It "contem exemplo VETAR com veredicto_5tier ABORTAR ou HARD_VETO" {
        $b = Get-MentorExamplesBlock
        $b | Should Match "VETAR"
        ($b -match "ABORTAR" -or $b -match "HARD_VETO") | Should Be $true
    }

    It "tem 2 exemplos com 'decision' e 'veredicto_5tier'" {
        $b = Get-MentorExamplesBlock
        ([regex]::Matches($b, '"decision"')).Count | Should Be 2
        ([regex]::Matches($b, '"veredicto_5tier"')).Count | Should Be 2
        ([regex]::Matches($b, '"confianca"')).Count | Should Be 2
    }
}
