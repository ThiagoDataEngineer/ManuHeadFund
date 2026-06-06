# TDD: B2 — SHORT pipeline ramp-up strategy

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "B2: SHORT Pipeline Ramp-Up Strategy" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_short_rampup_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_short_rampup.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-ShortRampupCheck existe" {
        $cmd = Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "fase 0: SHORT bloqueado (regime BEAR_WEAK)" {
        if (Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-ShortRampupCheck -Market "BTCUSDT" `
                -Regime "BEAR_WEAK" -Phase 0 -JournalDir $journalDir

            ($check.short_enabled) | Should Be $false
            ($check.reason -match "regime") | Should Be $true
        }
    }

    It "fase 1: SHORT tight stops (2% max loss per trade)" {
        if (Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-ShortRampupCheck -Market "SOLUSDT" `
                -Regime "BULL_WEAK" -Phase 1 -JournalDir $journalDir

            ($check.short_enabled) | Should Be $true
            ($check.max_loss_pct -eq 2) | Should Be $true
            ($check.position_size_pct -eq 0.5) | Should Be $true  # 50% of 1%
        }
    }

    It "fase 2: SHORT expanded (4% max loss, full position)" {
        if (Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue) {
            $check = Invoke-ShortRampupCheck -Market "LINKUSDT" `
                -Regime "BULL" -Phase 2 -JournalDir $journalDir

            ($check.short_enabled) | Should Be $true
            ($check.max_loss_pct -eq 4) | Should Be $true
            ($check.position_size_pct -eq 1.0) | Should Be $true
        }
    }

    It "valida ensemble (2/3 mentores concordam com SHORT)" {
        if (Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue) {
            $mentorVotes = @("SHORT", "SKIP", "SHORT")  # 2/3 SHORT
            $consensus = Invoke-ShortEnsemble -MentorVotes $mentorVotes

            ($consensus.consensus) | Should Be "SHORT"
            ($consensus.confidence -ge 0.66) | Should Be $true
        }
    }

    It "short_rampup.jsonl registra tentativas com fase/regime/loss_pct" {
        if (Get-Command Invoke-ShortRampupCheck -ErrorAction SilentlyContinue) {
            $rampupPath = Join-Path $journalDir "short_rampup.jsonl"

            $null = Invoke-ShortRampupCheck -Market "NEAR" `
                -Regime "BULL_WEAK" -Phase 1 -JournalDir $journalDir

            Test-Path $rampupPath | Should Be $true
        }
    }
}
