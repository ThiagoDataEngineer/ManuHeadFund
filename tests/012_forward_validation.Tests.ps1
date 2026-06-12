# TDD: Semana 4 — Forward Validation (walk-forward + OOS testing)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Semana 4: Forward Validation 6-12 Months" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_forward_val_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_forward_validation.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-WalkForwardTest existe" {
        $cmd = Get-Command Invoke-WalkForwardTest -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "calcula walk-forward erro (backtest vs forward)" {
        if (Get-Command Invoke-WalkForwardTest -ErrorAction SilentlyContinue) {
            # Simula: backtest Sharpe 5.2, forward Sharpe 3.8 => error 27%
            $wf = Invoke-WalkForwardTest -BacktestMetric 5.2 -ForwardMetric 3.8 `
                -MetricName "Sharpe" -JournalDir $journalDir

            ($wf.forward_error_pct -gt 0) | Should Be $true
            ($wf.forward_error_pct -lt 50) | Should Be $true  # Realistic error
        }
    }

    It "rejeita edge se forward error > 30% (overfitting suspect)" {
        if (Get-Command Invoke-WalkForwardTest -ErrorAction SilentlyContinue) {
            # Backtest 5.0, forward 2.0 => 60% error => REJECT
            $wf = Invoke-WalkForwardTest -BacktestMetric 5.0 -ForwardMetric 2.0 `
                -MetricName "Sharpe" -OverfitThreshold 30 -JournalDir $journalDir

            ($wf.passes) | Should Be $false
            ($wf.reason -match "overfitting") | Should Be $true
        }
    }

    It "aceita edge se forward error <= 30%" {
        if (Get-Command Invoke-WalkForwardTest -ErrorAction SilentlyContinue) {
            # Backtest 4.0, forward 3.2 => 20% error => PASS
            $wf = Invoke-WalkForwardTest -BacktestMetric 4.0 -ForwardMetric 3.2 `
                -MetricName "Sharpe" -OverfitThreshold 30 -JournalDir $journalDir

            ($wf.passes) | Should Be $true
        }
    }

    It "forward_validation.jsonl registra cada teste" {
        if (Get-Command Invoke-WalkForwardTest -ErrorAction SilentlyContinue) {
            $valPath = Join-Path $journalDir "forward_validation.jsonl"

            $null = Invoke-WalkForwardTest -BacktestMetric 4.5 -ForwardMetric 4.0 `
                -MetricName "Sharpe" -JournalDir $journalDir

            Test-Path $valPath | Should Be $true
        }
    }
}
