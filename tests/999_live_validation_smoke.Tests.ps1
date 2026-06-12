# LIVE VALIDATION: A1 (Gates) + A4 (Capital Safety)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "LIVE VALIDATION: Gate Chain + Capital Safety" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "live_validation_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        . (Join-Path $projectRoot "agents\lib_gate_audit.ps1")
        . (Join-Path $projectRoot "agents\lib_capital_safety_enforcer.ps1")
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    Context "Scenario 1: GOOD TRADE (all gates pass + capital ok)" {
        It "LINKUSDT entry 10, SL 9, target 60 (huge R:R), position 50 USD (<1% cap)" {
            $gateResult = Invoke-AllGates -Market "LINKUSDT" -VolumeUsd 5000000 `
                -EquityTodayPct 0 -CurrentTierACount 1 -JournalDir $journalDir

            ($gateResult.passes) | Should Be $true

            # Entry 10, SL 9 => risk = 1 per unit
            # Target 60 => reward = 50 => R:R = 50:1 (EXCELLENT)
            # Account 5000 => 1% = 50 USD
            # Position 50 USD is exactly at limit (passes)
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 10 -StoplossPrice 9 -TargetPrice 60 `
                -ProposedSizeUsd 50 -BetaCap 1.0 -JournalDir $journalDir

            ($check.passes) | Should Be $true
            ($check.rr_ratio -ge 5) | Should Be $true
        }
    }

    Context "Scenario 2: VOLUME FAIL (-gate blocks)" {
        It "SOLUSDT only 500k vol (need min 1M)" {
            $gateResult = Invoke-AllGates -Market "SOLUSDT" -VolumeUsd 500000 `
                -EquityTodayPct 0 -CurrentTierACount 1 -JournalDir $journalDir

            ($gateResult.passes) | Should Be $false
        }
    }

    Context "Scenario 3: OVERSIZED POSITION (capital safety blocks)" {
        It "entry 100, SL 95, proposed 5000 USD > 1% cap" {
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 100 -StoplossPrice 95 `
                -ProposedSizeUsd 5000 -BetaCap 1.0 -JournalDir $journalDir

            ($check.passes) | Should Be $false
        }
    }

    Context "Scenario 4: BAD RR (capital safety blocks)" {
        It "risk 5 pts, reward 3 pts = 1:0.6 ratio (need min 1:5)" {
            $check = Invoke-CapitalSafetyCheck -AccountBalanceUsd 5000 `
                -EntryPrice 100 -StoplossPrice 95 -TargetPrice 103 `
                -ProposedSizeUsd 100 -JournalDir $journalDir

            # Risk = 5, Reward = 3, RR = 0.6 (< 5 required)
            ($check.passes) | Should Be $false
        }
    }

    Context "Audit Trail Completeness" {
        It "gate_audit_trail.jsonl was created" {
            (Test-Path (Join-Path $journalDir "gate_audit_trail.jsonl")) | Should Be $true
        }

        It "capital_safety_checks.jsonl was created" {
            (Test-Path (Join-Path $journalDir "capital_safety_checks.jsonl")) | Should Be $true
        }

        It "logs are valid JSON" {
            $auditPath = Join-Path $journalDir "gate_audit_trail.jsonl"
            if (Test-Path $auditPath) {
                $lines = @(Get-Content $auditPath | Where-Object { $_.Trim() -ne "" })
                foreach ($line in $lines) {
                    { $line | ConvertFrom-Json -ErrorAction Stop } | Should Not Throw
                }
            }
        }
    }
}
