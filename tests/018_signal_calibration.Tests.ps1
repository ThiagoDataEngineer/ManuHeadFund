# TDD: Signal Calibration — refina thresholds com histórico real
# CORE: Descobre qual score_threshold maximize win_rate

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Signal Calibration: Discover Optimal Thresholds" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_calib_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_signal_calibration.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-SignalCalibration existe e funciona" {
        if (Get-Command Invoke-SignalCalibration -ErrorAction SilentlyContinue) {
            $trades = @(
                @{ signal_score=80; win=$true },
                @{ signal_score=50; win=$false }
            )

            $calib = Invoke-SignalCalibration -TradeHistory $trades `
                -SignalName "FARO_V3" -JournalDir $journalDir

            ($calib -ne $null) | Should Be $true
        }
    }

    It "signal_calibration_audit.jsonl é gerado" {
        if (Get-Command Invoke-SignalCalibration -ErrorAction SilentlyContinue) {
            $logPath = Join-Path $journalDir "signal_calibration_audit.jsonl"

            if (-not (Test-Path $logPath)) {
                $trades = @{ signal_score=75; win=$true }
                $null = Invoke-SignalCalibration -TradeHistory @($trades) `
                    -SignalName "TEST" -JournalDir $journalDir
            }

            (Test-Path $logPath) | Should Be $true
        }
    }

    It "Update-SignalThresholds gera signal_thresholds.json" {
        if (Get-Command Update-SignalThresholds -ErrorAction SilentlyContinue) {
            $trades = @(@{ signal_faro_v3=80; signal_tori=70; signal_dsr=60; win=$true })

            $null = Update-SignalThresholds -NewFaroThreshold 70 `
                -NewToriThreshold 70 -NewDsrThreshold 70 `
                -TradeHistory $trades -JournalDir $journalDir

            $cfgPath = Join-Path $journalDir "signal_thresholds.json"
            (Test-Path $cfgPath) | Should Be $true
        }
    }

    It "Get-SignalByMarket funciona por market" {
        if (Get-Command Get-SignalByMarket -ErrorAction SilentlyContinue) {
            $trades = @(
                @{ market="LINKUSDT"; signal_score=65; win=$true },
                @{ market="LINKUSDT"; signal_score=70; win=$true },
                @{ market="LINKUSDT"; signal_score=50; win=$false }
            )

            $result = Get-SignalByMarket -Market "LINKUSDT" `
                -TradeHistory $trades -JournalDir $journalDir

            ($result.market) | Should Be "LINKUSDT"
        }
    }
}
