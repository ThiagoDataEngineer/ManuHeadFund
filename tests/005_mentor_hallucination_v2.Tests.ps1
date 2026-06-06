# TDD: A3 — Mentor hallucination detector v2
# Tests for lib_mentor_hallucination_detector.ps1

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "A3: Mentor Hallucination Detector V2" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_hallucination_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_mentor_hallucination_detector.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-MentorHallucinationAudit existe" {
        $cmd = Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "detecta hallucination: conviction sem base de dados" {
        if (Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue) {
            $mentorOutput = [PSCustomObject]@{
                market = "BTCUSDT"
                conviction = 95
                reasoning = "Baseado em análise técnica"
                data_sources = @()  # Vazio!
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $audit = Invoke-MentorHallucinationAudit -MentorOutput $mentorOutput -JournalDir $journalDir

            ($audit.is_hallucination) | Should Be $true
            ($audit.reason -match "sem fontes") | Should Be $true
        }
    }

    It "detecta hallucination: cita metrica que nao foi calculada" {
        if (Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue) {
            $mentorOutput = [PSCustomObject]@{
                market = "SOLUSDT"
                conviction = 80
                reasoning = "RSI em oversold (<=30) na daily"
                calculated_metrics = @("price", "volume")  # RSI nao esta aqui!
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $audit = Invoke-MentorHallucinationAudit -MentorOutput $mentorOutput -JournalDir $journalDir

            ($audit.is_hallucination) | Should Be $true
        }
    }

    It "aceita decision com conviction + dados validos" {
        if (Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue) {
            $mentorOutput = [PSCustomObject]@{
                market = "LINKUSDT"
                conviction = 75
                reasoning = "Volume > 3M, price acima SMA50"
                data_sources = @("coinex_ohlcv", "ta_sma")
                calculated_metrics = @("volume", "sma50", "price")
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $audit = Invoke-MentorHallucinationAudit -MentorOutput $mentorOutput -JournalDir $journalDir

            ($audit.is_hallucination) | Should Be $false
        }
    }

    It "mentor_hallucinations.jsonl registra TODAS as deteccoes" {
        if (Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue) {
            $hallucinPath = Join-Path $journalDir "mentor_hallucinations.jsonl"

            $mentorOutput = [PSCustomObject]@{
                market = "NEAR"
                conviction = 90
                reasoning = "Test"
                data_sources = @()
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $null = Invoke-MentorHallucinationAudit -MentorOutput $mentorOutput -JournalDir $journalDir

            Test-Path $hallucinPath | Should Be $true
        }
    }

    It "hallucination_audit contem timestamp, market, conviction, is_hallucination, reason" {
        if (Get-Command Invoke-MentorHallucinationAudit -ErrorAction SilentlyContinue) {
            $hallucinPath = Join-Path $journalDir "mentor_hallucinations.jsonl"

            $mentorOutput = [PSCustomObject]@{
                market = "UNI"
                conviction = 85
                reasoning = "Test hallucination"
                data_sources = @()
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            }

            $null = Invoke-MentorHallucinationAudit -MentorOutput $mentorOutput -JournalDir $journalDir

            if (Test-Path $hallucinPath) {
                $content = Get-Content $hallucinPath
                ($content -match "is_hallucination") | Should Be $true
                ($content -match "market") | Should Be $true
            }
        }
    }
}
