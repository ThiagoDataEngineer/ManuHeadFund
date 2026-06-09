# lib_mentor_audit_simple.Tests.ps1 — 11 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_mentor_audit_simple.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $global:JOURNAL_DIR)) { mkdir $global:JOURNAL_DIR | Out-Null }

Describe "MentorAudit: Get-MentorDecisionsRecent" {
    It "retorna lista vazia se arquivo não existe" {
        $result = Get-MentorDecisionsRecent -JournalDir $global:JOURNAL_DIR
        $result.Count | Should Be 0
    }

    It "retorna últimas N decisões" {
        $file = Join-Path $global:JOURNAL_DIR "decisions_text.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        1..50 | ForEach-Object {
            @{ decision="APROVAR"; market="TEST$_"; score=75 } | ConvertTo-Json | Add-Content $file
        }

        $recent = Get-MentorDecisionsRecent -Limit 10 -JournalDir $global:JOURNAL_DIR
        $recent.Count | Should Be 10

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "limita por padrão a 100" {
        $file = Join-Path $global:JOURNAL_DIR "decisions_text.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        1..200 | ForEach-Object {
            @{ decision="APROVAR"; market="TEST$_" } | ConvertTo-Json | Add-Content $file
        }

        $recent = Get-MentorDecisionsRecent -JournalDir $global:JOURNAL_DIR
        $recent.Count | Should Be 100

        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

Describe "MentorAudit: Sample-MentorDecisions" {
    It "retorna amostra aleatória" {
        $decisions = 1..100 | ForEach-Object { @{ market="TEST$_"; decision="APROVAR" } }
        $sample = Sample-MentorDecisions -Decisions $decisions -SampleSize 20
        $sample.Count | Should Be 20
    }

    It "retorna todas se SampleSize > Count" {
        $decisions = 1..10 | ForEach-Object { @{ market="TEST$_" } }
        $sample = Sample-MentorDecisions -Decisions $decisions -SampleSize 50
        $sample.Count | Should Be 10
    }

    It "amostra é diversificada" {
        $decisions = 1..100 | ForEach-Object { @{ market="TEST$_"; id=$_ } }
        $sample = Sample-MentorDecisions -Decisions $decisions -SampleSize 30

        # Verifica que não são todos iguais
        $unique = @($sample.id | Select-Object -Unique).Count
        $unique | Should BeGreaterThan 1
    }
}

Describe "MentorAudit: Export-MentorAuditSample" {
    It "cria arquivo CSV" {
        $outFile = Join-Path $global:JOURNAL_DIR "audit_sample.csv"
        Remove-Item $outFile -ErrorAction SilentlyContinue

        $decisions = @(
            @{ timestamp="2026-06-09 10:00"; market="BTCUSDT"; decision="APROVAR"; direction="LONG"; score=85; gates_passed=@("G1","G2"); notes="vol spike confirmado" }
        )

        Export-MentorAuditSample -Decisions $decisions -OutputFile $outFile

        Test-Path $outFile | Should Be $true
        Remove-Item $outFile
    }

    It "exporta formato correto" {
        $outFile = Join-Path $global:JOURNAL_DIR "audit_sample.csv"
        Remove-Item $outFile -ErrorAction SilentlyContinue

        $decisions = @(
            @{ timestamp="2026-06-09 10:00"; market="TEST1"; decision="APROVAR"; direction="LONG"; score=80; gates_passed=@("G1"); notes="test" }
            @{ timestamp="2026-06-09 11:00"; market="TEST2"; decision="VETAR"; direction="SHORT"; score=40; gates_passed=@(); notes="blocked" }
        )

        $result = Export-MentorAuditSample -Decisions $decisions -OutputFile $outFile
        $result.count | Should Be 2

        Remove-Item $outFile
    }
}

Describe "MentorAudit: Get-MentorAccuracy" {
    It "retorna 0% se arquivo não existe" {
        $result = Get-MentorAccuracy -AuditFile (Join-Path $global:JOURNAL_DIR "nonexistent.csv")
        $result.accuracy | Should Be 0
        $result.total | Should Be 0
    }

    It "calcula accuracy corretamente" {
        $file = Join-Path $global:JOURNAL_DIR "audit_accuracy.csv"

        @"
market,decision,was_correct_yn,reason
BTCUSDT,APROVAR,Y,vol spike real
ETHUSDT,VETAR,N,deveria ter aprovado
SOLUSDT,APROVAR,Y,score 85
"@ | Set-Content $file

        $result = Get-MentorAccuracy -AuditFile $file
        $result.accuracy | Should Be 66.7
        $result.correct | Should Be 2
        $result.total | Should Be 3

        Remove-Item $file
    }

    It "trata CSV vazio" {
        $file = Join-Path $global:JOURNAL_DIR "empty_audit.csv"
        "market,decision,was_correct_yn" | Set-Content $file

        $result = Get-MentorAccuracy -AuditFile $file
        $result.accuracy | Should Be 0
        $result.total | Should Be 0

        Remove-Item $file
    }
}
