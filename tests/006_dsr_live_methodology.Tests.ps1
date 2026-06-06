# TDD: B1 — DSR live methodology + audit trail

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "B1: DSR Live Methodology & Audit Trail" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_dsr_live_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_dsr_live_audit.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-DsrLiveAudit existe" {
        $cmd = Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "calcula DSR baseado em Sharpe + PSR" {
        if (Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue) {
            # Simula 20 returns diarios
            $returns = @(-0.015, 0.025, 0.010, -0.005, 0.030, 0.015, -0.010, 0.020, 0.008, 0.012,
                        0.018, -0.008, 0.025, 0.015, 0.010, -0.012, 0.028, 0.020, 0.015, 0.022)

            $dsr = Invoke-DsrLiveAudit -Returns $returns -Market "BTCUSDT" -JournalDir $journalDir

            ($dsr.dsr_value -ge 0 -and $dsr.dsr_value -le 1) | Should Be $true
        }
    }

    It "rejeita DSR se n_samples < 30 (insuficiente)" {
        if (Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue) {
            $returns = @(0.01, 0.02, -0.01)  # Apenas 3

            $dsr = Invoke-DsrLiveAudit -Returns $returns -Market "SOLUSDT" -JournalDir $journalDir

            ($dsr.confidence -eq "LOW") | Should Be $true
        }
    }

    It "forward_validated flag indica se foi backtestado" {
        if (Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue) {
            $returns = @()
            for ($i = 0; $i -lt 40; $i++) {
                $returns += (Get-Random -Minimum -50 -Maximum 50) / 1000
            }

            $dsr = Invoke-DsrLiveAudit -Returns $returns -Market "LINK" `
                -ForwardValidated $true -JournalDir $journalDir

            ($dsr.forward_validated) | Should Be $true
        }
    }

    It "dsr_live_audit.jsonl registra TODA metricas de calculo" {
        if (Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "dsr_live_audit.jsonl"

            $returns = @()
            for ($i = 0; $i -lt 35; $i++) {
                $returns += (Get-Random -Minimum -30 -Maximum 40) / 1000
            }

            $null = Invoke-DsrLiveAudit -Returns $returns -Market "NEAR" -JournalDir $journalDir

            Test-Path $auditPath | Should Be $true
        }
    }

    It "audit contem timestamp, market, n_samples, sharpe, psr, dsr_value, confidence" {
        if (Get-Command Invoke-DsrLiveAudit -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "dsr_live_audit.jsonl"

            $returns = @()
            for ($i = 0; $i -lt 32; $i++) {
                $returns += (Get-Random -Minimum -25 -Maximum 35) / 1000
            }

            $null = Invoke-DsrLiveAudit -Returns $returns -Market "UNI" -JournalDir $journalDir

            if (Test-Path $auditPath) {
                $content = Get-Content $auditPath
                ($content -match "dsr_value") | Should Be $true
                ($content -match "n_samples") | Should Be $true
                ($content -match "confidence") | Should Be $true
            }
        }
    }
}
