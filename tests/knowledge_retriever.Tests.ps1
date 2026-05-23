# knowledge_retriever.Tests.ps1 -- Pester 3.x -- Get-RelevantKnowledge
# TDD: testes escritos antes da implementacao
# Sem acentos. Sem em-dash. Sem operadores pipeline '&&'.

$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir  = Join-Path (Split-Path $here -Parent) "agents"

. (Join-Path $agentsDir "knowledge_retriever.ps1")


Describe "Get-RelevantKnowledge - contrato basico" {
    It "Retorna array vazio para zero tags" {
        $r = Get-RelevantKnowledge -Tags @()
        $r.Count | Should Be 0
    }

    It "Retorna array vazio para tag desconhecida" {
        $r = Get-RelevantKnowledge -Tags @("xyz_inexistente_zzz_999")
        $r.Count | Should Be 0
    }

    It "Cada chunk tem os campos source/tag/text" {
        $r = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks 1
        if ($r.Count -gt 0) {
            $r[0].source | Should Not BeNullOrEmpty
            $r[0].tag    | Should Not BeNullOrEmpty
            $r[0].text   | Should Not BeNullOrEmpty
        }
    }

    It "Respeita MaxChunks=1" {
        $r = Get-RelevantKnowledge -Tags @("bear","fase","distribui","macro") -MaxChunks 1
        ($r.Count -le 1) | Should Be $true
    }

    It "Respeita MaxChunks=3" {
        $r = Get-RelevantKnowledge -Tags @("bear","fase","distribui","macro","trend","stop") -MaxChunks 3
        ($r.Count -le 3) | Should Be $true
    }
}


Describe "Get-RelevantKnowledge - tag matching" {
    It "Encontra tag 'livermore' em algum arquivo de knowledge" {
        $r = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks 1
        $r.Count | Should BeGreaterThan 0
        # Esperamos achar em MENTOR.md ou similar
        ($r[0].source -match "\.md$") | Should Be $true
    }

    It "Encontra tag 'bear' em algum arquivo (BEAR_MARKET.md provavelmente)" {
        $r = Get-RelevantKnowledge -Tags @("bear") -MaxChunks 1
        $r.Count | Should BeGreaterThan 0
    }

    It "Tag case-insensitive: 'LIVERMORE' funciona igual a 'livermore'" {
        $rLower = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks 1
        $rUpper = Get-RelevantKnowledge -Tags @("LIVERMORE") -MaxChunks 1
        $rLower.Count | Should Be $rUpper.Count
    }

    It "Multiplas tags retornam ate MaxChunks chunks" {
        $r = Get-RelevantKnowledge -Tags @("livermore","wyckoff","bear") -MaxChunks 3
        ($r.Count -gt 0) | Should Be $true
        ($r.Count -le 3) | Should Be $true
    }
}


Describe "Get-RelevantKnowledge - robustez" {
    It "Nao quebra com Tags=$null (retorna vazio)" {
        $r = Get-RelevantKnowledge -Tags $null
        $r.Count | Should Be 0
    }

    It "Nao quebra com MaxChunks=0 (retorna vazio)" {
        $r = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks 0
        $r.Count | Should Be 0
    }

    It "Nao quebra com MaxChunks negativo (retorna vazio)" {
        $r = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks -5
        $r.Count | Should Be 0
    }

    It "Text do chunk e truncado para ser razoavel (< 2000 chars)" {
        $r = Get-RelevantKnowledge -Tags @("livermore","bear") -MaxChunks 3
        foreach ($chunk in $r) {
            ($chunk.text.Length -le 2000) | Should Be $true
        }
    }
}


Describe "Get-RelevantKnowledge - formato citation" {
    It "source retorna apenas nome do arquivo (sem path)" {
        $r = Get-RelevantKnowledge -Tags @("livermore") -MaxChunks 1
        if ($r.Count -gt 0) {
            ($r[0].source -notmatch '[\\/]') | Should Be $true
            $r[0].source | Should Match "\.md$"
        }
    }

    It "tag retornada e a tag que casou (lowercase preservada)" {
        $r = Get-RelevantKnowledge -Tags @("LIVERMORE") -MaxChunks 1
        if ($r.Count -gt 0) {
            # tag de output deve ser uma das fornecidas (case-insensitive)
            ($r[0].tag.ToLower()) | Should Be "livermore"
        }
    }
}
