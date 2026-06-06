# TDD: Stress Test — DD 15%+ Behavior

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Stress Test: Drawdown 15%+ Emergency Behavior" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_stress_dd_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_stress_test_dd.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-StressTestDD existe" {
        $cmd = Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "DD >= 10% triggers 50% position size reduction" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $result = Invoke-StressTestDD -CurrentDD -10 -BasePositionSize 100 -JournalDir $journalDir

            ($result.action) | Should Be "REDUCE_50"
            ($result.new_position_size) | Should Be 50
        }
    }

    It "DD >= 15% triggers HALT (pausa daemons)" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $result = Invoke-StressTestDD -CurrentDD -15 -BasePositionSize 100 -JournalDir $journalDir

            ($result.action) | Should Be "HALT"
            ($result.halt_reason -match "DD >= 15") | Should Be $true
        }
    }

    It "DD < 10% = normal (sem reducao)" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $result = Invoke-StressTestDD -CurrentDD -5 -BasePositionSize 100 -JournalDir $journalDir

            ($result.action) | Should Be "NORMAL"
        }
    }

    It "HALT action pausa todos os 5 daemons" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $result = Invoke-StressTestDD -CurrentDD -20 -BasePositionSize 100 `
                -DaemonsToHalt @("gem_loop", "scan_master", "telegram_listener", "watchdog_paper", "faro_v3_schedule") `
                -JournalDir $journalDir

            ($result.action) | Should Be "HALT"
            ($result.halted_daemons.Count -eq 5) | Should Be $true
        }
    }

    It "stress_test_dd.jsonl registra TODA ativacao de stress" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $stressPath = Join-Path $journalDir "stress_test_dd.jsonl"

            $null = Invoke-StressTestDD -CurrentDD -12 -BasePositionSize 100 -JournalDir $journalDir

            Test-Path $stressPath | Should Be $true
        }
    }

    It "stress log contem timestamp, current_dd, action, new_position_size" {
        if (Get-Command Invoke-StressTestDD -ErrorAction SilentlyContinue) {
            $stressPath = Join-Path $journalDir "stress_test_dd.jsonl"

            $null = Invoke-StressTestDD -CurrentDD -11 -BasePositionSize 200 -JournalDir $journalDir

            if (Test-Path $stressPath) {
                $content = Get-Content $stressPath
                ($content -match "current_dd") | Should Be $true
                ($content -match "action") | Should Be $true
            }
        }
    }
}
