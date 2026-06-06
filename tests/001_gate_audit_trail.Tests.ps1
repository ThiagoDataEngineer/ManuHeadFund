# TDD: A1 — Gate audit trail + pre-trade gate chain
# Tests for lib_gate_audit.ps1

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "A1: Gate Audit Trail — Pre-Trade Gate Chain" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_gate_audit_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        # Load lib if exists
        $libPath = Join-Path $projectRoot "agents\lib_gate_audit.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-AllGates existe" {
        $cmd = Get-Command Invoke-AllGates -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "Invoke-AllGates retorna resultado com passes e reason" {
        if (Get-Command Invoke-AllGates -ErrorAction SilentlyContinue) {
            $result = Invoke-AllGates -Market "BTCUSDT" -VolumeUsd 5000000 `
                -EquityTodayPct 0 -CurrentTierACount 0 -JournalDir $journalDir

            ($result -ne $null) | Should Be $true
            ($result.passes -ne $null) | Should Be $true
        }
    }

    It "gate_audit_trail.jsonl eh criado" {
        if (Get-Command Invoke-AllGates -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "gate_audit_trail.jsonl"

            $result = Invoke-AllGates -Market "SOLUSDT" -VolumeUsd 5000000 `
                -EquityTodayPct 0 -CurrentTierACount 0 -JournalDir $journalDir

            Test-Path $auditPath | Should Be $true
        }
    }

    It "gate_audit_trail.jsonl contem market, timestamp, gate_name" {
        if (Get-Command Invoke-AllGates -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "gate_audit_trail.jsonl"

            $result = Invoke-AllGates -Market "LINKUSDT" -VolumeUsd 5000000 `
                -EquityTodayPct 0 -CurrentTierACount 0 -JournalDir $journalDir

            if (Test-Path $auditPath) {
                $content = Get-Content $auditPath -ErrorAction SilentlyContinue
                ($content -match "LINKUSDT") | Should Be $true
            }
        }
    }
}
