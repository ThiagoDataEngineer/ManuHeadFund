# TDD: SHORT Pipeline + DSR Confidence (ADVANCED)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "SHORT Pipeline & DSR Confidence" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_short_dsr_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        . (Join-Path $projectRoot "agents\lib_short_pipeline_advanced.ps1")
        . (Join-Path $projectRoot "agents\lib_dsr_confidence_advanced.ps1")
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    # === SHORT PIPELINE ===

    It "Get-ShortPhase fase 0: BLOCKED em BEAR" {
        $phase = Get-ShortPhase -Regime "BEAR" -JournalDir $journalDir

        ($phase.phase) | Should Be 0
        ($phase.status) | Should Be "BLOCKED"
    }

    It "Get-ShortPhase fase 1: PILOT (< 3 wins)" {
        $trades = @(
            @{ direction="SHORT"; win=$true },
            @{ direction="SHORT"; win=$false }
        )

        $phase = Get-ShortPhase -Regime "BULL" -ShortTradeHistory $trades -JournalDir $journalDir

        ($phase.phase) | Should Be 1
        ($phase.name) | Should Be "PILOT"
        ($phase.max_loss_pct) | Should Be 2.0
    }

    It "Get-ShortPhase fase 2: RAMP (3-7 wins)" {
        $trades = @(
            @{ direction="SHORT"; win=$true },
            @{ direction="SHORT"; win=$true },
            @{ direction="SHORT"; win=$true },
            @{ direction="SHORT"; win=$false }
        )

        $phase = Get-ShortPhase -Regime "SIDEWAYS" -ShortTradeHistory $trades -JournalDir $journalDir

        ($phase.phase) | Should Be 2
        ($phase.name) | Should Be "RAMP"
        ($phase.max_loss_pct) | Should Be 4.0
    }

    It "Test-ShortApproval bloqueia regime BEAR" {
        $result = Test-ShortApproval -Market "TEST" -Regime "BEAR" `
            -MentorConviction 90 -ConfluenceCount 5 `
            -ProposedSizeUsd 100 -MaxPositionUsd 1000 -JournalDir $journalDir

        ($result.approved) | Should Be $false
        ($result.reason) | Should Match "Regime"
    }

    It "Test-ShortApproval aprova confluência 5/5 + conviction 80" {
        $result = Test-ShortApproval -Market "BTC" -Regime "BULL" `
            -MentorConviction 80 -ConfluenceCount 5 `
            -ProposedSizeUsd 50 -MaxPositionUsd 1000 -JournalDir $journalDir

        ($result.approved) | Should Be $true
    }

    It "short_pipeline_audit.jsonl é gerado" {
        $logPath = Join-Path $journalDir "short_pipeline_audit.jsonl"
        (Test-Path $logPath) | Should Be $true
    }

    # === DSR CONFIDENCE ===

    It "Get-DsrConfidenceLevel LOW (< 10 trades)" {
        $history = @(
            @{ win=$true },
            @{ win=$false },
            @{ win=$true }
        )

        $dsr = Get-DsrConfidenceLevel -TradeHistory $history -JournalDir $journalDir

        ($dsr.level) | Should Be "LOW"
        ($dsr.confidence_pct -lt 30) | Should Be $true
    }

    It "Get-DsrConfidenceLevel MEDIUM (10-30 trades)" {
        $history = @()
        1..20 | ForEach-Object { $history += @{ win=(Get-Random -Maximum 2) } }

        $dsr = Get-DsrConfidenceLevel -TradeHistory $history -JournalDir $journalDir

        ($dsr.level) | Should Be "MEDIUM"
        ($dsr.confidence_pct -ge 30 -and $dsr.confidence_pct -lt 70) | Should Be $true
    }

    It "Get-DsrConfidenceLevel HIGH (30+ trades)" {
        $history = @()
        1..50 | ForEach-Object { $history += @{ win=(Get-Random -Maximum 2) } }

        $dsr = Get-DsrConfidenceLevel -TradeHistory $history -JournalDir $journalDir

        ($dsr.level) | Should Be "HIGH"
        ($dsr.confidence_pct -ge 70) | Should Be $true
    }

    It "Test-WalkForwardValidation: backtest 8.0, forward 7.5 = ROBUST (error < 30%)" {
        $result = Test-WalkForwardValidation -Signal "FARO_V3" `
            -BacktestSharpe 8.0 -ForwardSharpe 7.5 -JournalDir $journalDir

        ($result.passes) | Should Be $true
        ($result.verdict) | Should Match "ROBUST"
    }

    It "Test-WalkForwardValidation: backtest 5.0, forward 1.0 = OVERFITTED (error > 30%)" {
        $result = Test-WalkForwardValidation -Signal "TORI" `
            -BacktestSharpe 5.0 -ForwardSharpe 1.0 -JournalDir $journalDir

        ($result.passes) | Should Be $false
        ($result.verdict) | Should Match "OVERFITTED"
    }

    It "Get-DsrRecommendedSize: LOW=0.5x, MEDIUM=0.8x, HIGH=1.0x" {
        $low = Get-DsrRecommendedSize -DsrLevel "LOW" -BasePositionUsd 100
        $med = Get-DsrRecommendedSize -DsrLevel "MEDIUM" -BasePositionUsd 100
        $high = Get-DsrRecommendedSize -DsrLevel "HIGH" -BasePositionUsd 100

        ($low.final_size_usd) | Should Be 50
        ($med.final_size_usd) | Should Be 80
        ($high.final_size_usd) | Should Be 100
    }

    It "dsr_validation_audit.jsonl gerado" {
        $logPath = Join-Path $journalDir "dsr_validation_audit.jsonl"
        (Test-Path $logPath) | Should Be $true
    }
}
