# FQS hallucination detector TDD 2026-05-21 PM6+870min.
# Detecta Mentor alucinando "FQS indisponivel" quando FullContext tinha FQS valido.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_mentor_hallucination_detector.ps1")

Describe "FQS hallucination detector" {
    It "Mentor cita 'FQS indisponivel' MAS context tinha FQS != null: HALLUCINATION" {
        $r = Test-MentorFqsHallucination -MentorReason "FQS indisponivel sem entry no registry; nao posso aprovar" `
                                          -FullContextFqsScore 4 `
                                          -FullContextFqsCategory "QUALITY"
        $r.is_hallucination | Should Be $true
        $r.evidence | Should Match "fqs_was_in_context"
    }
    It "Mentor cita 'FQS indisponivel' AND context REAL nao tinha FQS: NOT hallucination (legit)" {
        $r = Test-MentorFqsHallucination -MentorReason "FQS indisponivel; market sem entry" `
                                          -FullContextFqsScore $null `
                                          -FullContextFqsCategory "N/A_no_registry"
        $r.is_hallucination | Should Be $false
    }
    It "Mentor nao cita FQS missing: passa direto (no detection)" {
        $r = Test-MentorFqsHallucination -MentorReason "Beta de -0.5 fora do modelo de risco" `
                                          -FullContextFqsScore 4 `
                                          -FullContextFqsCategory "QUALITY"
        $r.is_hallucination | Should Be $false
    }
    It "Variantes de 'FQS missing': pega todas" {
        foreach ($variant in @(
            "FQS indisponivel",
            "FQS nao declarado",
            "FQS sem entry no registry",
            "FQS missing",
            "FQS=N/A no contexto"
        )) {
            $r = Test-MentorFqsHallucination -MentorReason $variant -FullContextFqsScore 4 -FullContextFqsCategory "QUALITY"
            $r.is_hallucination | Should Be $true
        }
    }
    It "FQS=0 (registry no_entry path): NAO eh hallucination" {
        $r = Test-MentorFqsHallucination -MentorReason "FQS indisponivel" -FullContextFqsScore 0 -FullContextFqsCategory "AVOID"
        $r.is_hallucination | Should Be $false   # FQS=0 = legitimamente missing
    }
}

Describe "Add-HallucinationEvent - persistencia pra audit" {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP "fqs_halluc_$([guid]::NewGuid()).jsonl"
    }
    AfterEach {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    It "Registra hallucination event em JSONL" {
        Add-HallucinationEvent -Path $tmp -Market "TAOUSDT" -Type "fqs_missing" `
                                -MentorReason "FQS indisponivel sem entry no registry" `
                                -ContextValue "FQS=4/7 QUALITY"
        $line = Get-Content $tmp -Encoding UTF8 | Select-Object -First 1
        $obj = $line | ConvertFrom-Json
        $obj.market | Should Be "TAOUSDT"
        $obj.type | Should Be "fqs_missing"
    }
}
