# TDD: A4 — Capital Safety enforcement

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "A4: Capital Safety Enforcement" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_capital_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_capital_safety_enforcer.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-CapitalSafetyCheck existe" {
        $cmd = Get-Command Invoke-CapitalSafetyCheck -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "calcula max position size" {
        if (Get-Command Invoke-CapitalSafetyCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 100 -StoplossPrice 95 -BetaCap 1.2 -JournalDir $journalDir

            ($check.max_position_usd -gt 0) | Should Be $true
        }
    }

    It "rejeita posicao que ultrapassa 1% capital" {
        if (Get-Command Invoke-CapitalSafetyCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 2700 `
                -EntryPrice 100 -StoplossPrice 95 -ProposedSizeUsd 5000 `
                -BetaCap 1.0 -JournalDir $journalDir

            if ($check.max_position_usd -lt 5000) {
                $check.passes | Should Be $false
            }
        }
    }

    It "valida R:R ratio" {
        if (Get-Command Invoke-CapitalSafetyCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 100 -StoplossPrice 95 -TargetPrice 125 -JournalDir $journalDir

            ($check.rr_ratio -ne $null) | Should Be $true
            ($check.rr_ratio -ge 5) | Should Be $true
        }
    }

    It "capital_safety_checks.jsonl registra checagens" {
        if (Get-Command Invoke-CapitalSafetyCheck -ErrorAction SilentlyContinue) {
            $checksPath = Join-Path $journalDir "capital_safety_checks.jsonl"

            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 100 -StoplossPrice 95 -Market "SOLUSDT" -JournalDir $journalDir

            Test-Path $checksPath | Should Be $true
        }
    }
}
