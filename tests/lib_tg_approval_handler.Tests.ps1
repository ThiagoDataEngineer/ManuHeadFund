# lib_tg_approval_handler.Tests.ps1 — 12 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_tg_approval_handler.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $global:JOURNAL_DIR)) { mkdir $global:JOURNAL_DIR | Out-Null }

Describe "TgApprovalHandler: Process-ApprovalCommand" {
    It "/approve market seta status APPROVED" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue
        @{ market="TESTUSDT"; status="PENDING"; size_usd=150 } | ConvertTo-Json | Add-Content $file

        $result = Process-ApprovalCommand -Command "/approve" -Market "TESTUSDT" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "ok"

        $updated = Get-Content $file | ConvertFrom-Json
        $updated.status | Should Be "APPROVED"

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "/reject market seta status REJECTED" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue
        @{ market="TESTUSDT"; status="PENDING"; size_usd=150 } | ConvertTo-Json | Add-Content $file

        $result = Process-ApprovalCommand -Command "/reject" -Market "TESTUSDT" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "ok"

        $updated = Get-Content $file | ConvertFrom-Json
        $updated.status | Should Be "REJECTED"

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "/resume remove circuit breaker flag" {
        $flagPath = Join-Path $global:JOURNAL_DIR "CIRCUIT_BREAKER_PAUSED.flag"
        Add-Content -Path $flagPath -Value "test" -Encoding UTF8

        $result = Process-ApprovalCommand -Command "/resume" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "ok"

        Test-Path $flagPath | Should Be $false
    }

    It "/pause seta circuit breaker flag" {
        $flagPath = Join-Path $global:JOURNAL_DIR "CIRCUIT_BREAKER_PAUSED.flag"
        Remove-Item $flagPath -ErrorAction SilentlyContinue

        $result = Process-ApprovalCommand -Command "/pause" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "ok"

        Test-Path $flagPath | Should Be $true

        Remove-Item $flagPath -ErrorAction SilentlyContinue
    }

    It "retorna error se market faltando em /approve" {
        $result = Process-ApprovalCommand -Command "/approve" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "error"
        $result.message | Should Match "Uso:"
    }

    It "case insensitive commands" {
        $flagPath = Join-Path $global:JOURNAL_DIR "CIRCUIT_BREAKER_PAUSED.flag"
        Add-Content -Path $flagPath -Value "test" -Encoding UTF8

        $result = Process-ApprovalCommand -Command "/RESUME" -JournalDir $global:JOURNAL_DIR
        $result.status | Should Be "ok"

        Test-Path $flagPath | Should Be $false
    }
}

Describe "TgApprovalHandler: Get-PendingApprovalStatus" {
    It "retorna sem pendentes se arquivo vazio" {
        Remove-Item (Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl") -ErrorAction SilentlyContinue

        $status = Get-PendingApprovalStatus -JournalDir $global:JOURNAL_DIR
        $status | Should Match "Nenhuma"
    }

    It "lista pending approvals" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue
        @{ market="TEST1"; status="PENDING"; size_usd=100 } | ConvertTo-Json | Add-Content $file
        @{ market="TEST2"; status="PENDING"; size_usd=200 } | ConvertTo-Json | Add-Content $file

        $status = Get-PendingApprovalStatus -JournalDir $global:JOURNAL_DIR
        $status | Should Match "TEST1"
        $status | Should Match "TEST2"

        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

Describe "TgApprovalHandler: Test-CircuitBreakerActive" {
    It "retorna \$true se flag existe" {
        $flagPath = Join-Path $global:JOURNAL_DIR "CIRCUIT_BREAKER_PAUSED.flag"
        Add-Content -Path $flagPath -Value "test" -Encoding UTF8

        Test-CircuitBreakerActive -JournalDir $global:JOURNAL_DIR | Should Be $true

        Remove-Item $flagPath
    }

    It "retorna \$false se flag não existe" {
        $flagPath = Join-Path $global:JOURNAL_DIR "CIRCUIT_BREAKER_PAUSED.flag"
        Remove-Item $flagPath -ErrorAction SilentlyContinue

        Test-CircuitBreakerActive -JournalDir $global:JOURNAL_DIR | Should Be $false
    }
}
