# TDD: Dynamic Position Sizing — Beta * Confluence dinâmico (CORE)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Dynamic Position Sizing" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_sizing_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_position_sizing_dynamic.ps1"
        if (Test-Path $libPath) { . $libPath }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-DynamicPositionSize existe" {
        Get-Command Invoke-DynamicPositionSize -ErrorAction SilentlyContinue | Should Not Be $null
    }

    It "confluence 5/5 → 1.0x, 3/5 → 0.6x multiplier" {
        $r5 = Invoke-DynamicPositionSize -Market "M1" `
            -AccountEquityUsd 5000 -BetaVsBtc 1.0 `
            -ConfluenceCount 5 -Regime "SIDEWAYS" -JournalDir $journalDir

        $r3 = Invoke-DynamicPositionSize -Market "M2" `
            -AccountEquityUsd 5000 -BetaVsBtc 1.0 `
            -ConfluenceCount 3 -Regime "SIDEWAYS" -JournalDir $journalDir

        ($r5.confluence_multiplier) | Should Be 1.0
        ($r3.confluence_multiplier) | Should Be 0.6
    }

    It "position_sizing_audit.jsonl log gerado" {
        $logPath = Join-Path $journalDir "position_sizing_audit.jsonl"
        (Test-Path $logPath) | Should Be $true
    }
}
