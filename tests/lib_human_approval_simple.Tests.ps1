# lib_human_approval_simple.Tests.ps1 — 14 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_human_approval_simple.ps1")

$global:JOURNAL_DIR = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $global:JOURNAL_DIR)) { mkdir $global:JOURNAL_DIR | Out-Null }

Describe "HumanApproval: Request-HumanApproval" {
    It "aprova automatico se <\$100" {
        $result = Request-HumanApproval -Market "TESTUSDT" -SizeUsd 50
        $result.approved | Should Be $true
        $result.method | Should Be "auto_under_100"
    }

    It "pede aprovação se >=\$100" {
        $result = Request-HumanApproval -Market "TESTUSDT" -SizeUsd 150
        $result.approved | Should Be $null
        $result.method | Should Be "human_pending"
    }

    It "cria arquivo de aprovação pendente" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        Request-HumanApproval -Market "TESTUSDT" -SizeUsd 200 | Out-Null
        Test-Path $file | Should Be $true

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "registra detalhes da requisição" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        Request-HumanApproval -Market "BTCUSDT" -SizeUsd 500 | Out-Null

        $content = Get-Content $file | ConvertFrom-Json
        $content.market | Should Be "BTCUSDT"
        $content.size_usd | Should Be 500
        $content.status | Should Be "PENDING"

        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

Describe "HumanApproval: Get-PendingApprovals" {
    It "retorna lista vazia se arquivo não existe" {
        $result = Get-PendingApprovals -JournalDir $global:JOURNAL_DIR
        $result.Count | Should Be 0
    }

    It "retorna apenas PENDING" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        @{ market="TEST1"; status="PENDING" } | ConvertTo-Json | Add-Content $file
        @{ market="TEST2"; status="APPROVED" } | ConvertTo-Json | Add-Content $file
        @{ market="TEST3"; status="PENDING" } | ConvertTo-Json | Add-Content $file

        $pending = Get-PendingApprovals -JournalDir $global:JOURNAL_DIR
        $pending.Count | Should Be 2

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "trata arquivo vazio gracefully" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        $result = Get-PendingApprovals -JournalDir $global:JOURNAL_DIR
        $result | Should Be @()
    }
}

Describe "HumanApproval: Mark-ApprovalDone" {
    It "marca como APPROVED" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        @{ market="TESTUSDT"; status="PENDING"; size_usd=100 } | ConvertTo-Json | Add-Content $file

        Mark-ApprovalDone -MarketId "TESTUSDT" -Approved $true

        $updated = Get-Content $file | ConvertFrom-Json
        $updated.status | Should Be "APPROVED"

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "marca como REJECTED" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        @{ market="TESTUSDT"; status="PENDING" } | ConvertTo-Json | Add-Content $file

        Mark-ApprovalDone -MarketId "TESTUSDT" -Approved $false

        $updated = Get-Content $file | ConvertFrom-Json
        $updated.status | Should Be "REJECTED"

        Remove-Item $file -ErrorAction SilentlyContinue
    }

    It "adiciona timestamp de decisão" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        @{ market="TESTUSDT"; status="PENDING" } | ConvertTo-Json | Add-Content $file

        Mark-ApprovalDone -MarketId "TESTUSDT" -Approved $true

        $updated = Get-Content $file | ConvertFrom-Json
        $updated.decided_at | Should Not BeNullOrEmpty

        Remove-Item $file -ErrorAction SilentlyContinue
    }
}

Describe "HumanApproval: Integration" {
    It "workflow completo: request -> approve -> confirm" {
        $file = Join-Path $global:JOURNAL_DIR "human_approvals_pending.jsonl"
        Remove-Item $file -ErrorAction SilentlyContinue

        # 1. Request
        Request-HumanApproval -Market "GEMTEST" -SizeUsd 250 | Out-Null
        $pending = Get-PendingApprovals -JournalDir $global:JOURNAL_DIR
        $pending.Count | Should Be 1

        # 2. Mark approved
        Mark-ApprovalDone -MarketId "GEMTEST" -Approved $true

        # 3. Verify
        $updated = Get-Content $file | ConvertFrom-Json
        $updated.status | Should Be "APPROVED"

        Remove-Item $file -ErrorAction SilentlyContinue
    }
}
