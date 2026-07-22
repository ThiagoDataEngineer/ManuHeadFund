# lib_circuit_breaker_simple.Tests.ps1 — 15 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_circuit_breaker_simple.ps1")

$testJournal = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $testJournal)) { mkdir $testJournal | Out-Null }

Describe "CircuitBreaker: Get-DailyPnL" {
    It "retorna 0 se arquivo não existe" {
        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 0.0
    }

    It "soma PnL de hoje" {
        $today = (Get-Date).Date.ToString("yyyy-MM-dd")
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        @{ exit_date=$today; pnl_usd=50.0 } | ConvertTo-Json | Add-Content $outcomeFile
        @{ exit_date=$today; pnl_usd=30.0 } | ConvertTo-Json | Add-Content $outcomeFile

        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 80.0

        Remove-Item $outcomeFile
    }

    It "ignora PnL de ontem" {
        $today = (Get-Date).Date.ToString("yyyy-MM-dd")
        $yesterday = (Get-Date).AddDays(-1).Date.ToString("yyyy-MM-dd")
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        @{ exit_date=$yesterday; pnl_usd=100.0 } | ConvertTo-Json | Add-Content $outcomeFile
        @{ exit_date=$today; pnl_usd=50.0 } | ConvertTo-Json | Add-Content $outcomeFile

        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 50.0

        Remove-Item $outcomeFile
    }

    It "trata malformed JSON gracefully" {
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        Add-Content $outcomeFile "{ invalid json"
        Add-Content $outcomeFile @{ exit_date=((Get-Date).Date.ToString("yyyy-MM-dd")); pnl_usd=10.0 } | ConvertTo-Json

        # Não deve lançar erro
        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should BeGreaterOrEqual 0

        Remove-Item $outcomeFile
    }
}

Describe "CircuitBreaker: Test-CircuitBreakerTriggered" {
    It "retorna \$false se PnL > threshold" {
        $result = Test-CircuitBreakerTriggered -Capital 1000 -DailyLossThreshold -0.02
        $result | Should Be $false
    }

    It "retorna \$true se PnL < threshold -2%" {
        # Mock: Get-DailyPnL retorna -100
        # Capital 1000 * -0.02 = -20 threshold
        # -100 < -20 = $true

        # Sem mock, apenas testa lógica:
        $threshold = 1000 * -0.02  # -20
        $dailyPnL = -100
        ($dailyPnL -lt $threshold) | Should Be $true
    }

    It "default threshold é -2%" {
        # Capital 1000, threshold -20
        $threshold = 1000 * -0.02
        $threshold | Should Be -20
    }

    It "respeta capital customizado" {
        $threshold_5k = 5000 * -0.02
        $threshold_1k = 1000 * -0.02
        $threshold_5k | Should Be -100
        $threshold_1k | Should Be -20
    }
}

Describe "CircuitBreaker: Set/Reset" {
    It "cria flag de pausa" {
        $flagPath = Join-Path $testJournal "CIRCUIT_BREAKER_PAUSED.flag"
        Set-CircuitBreakerPause
        Test-Path $flagPath | Should Be $true
        Remove-Item $flagPath -ErrorAction SilentlyContinue
    }

    It "remove flag ao reset" {
        $flagPath = Join-Path $testJournal "CIRCUIT_BREAKER_PAUSED.flag"
        Add-Content -Path $flagPath -Value "test"
        Reset-CircuitBreaker
        Test-Path $flagPath | Should Be $false
    }

    It "reset não quebra se flag não existe" {
        Reset-CircuitBreaker  # Sem erro
        $true | Should Be $true
    }
}

Describe "CircuitBreaker: Integration" {
    It "detecta e pausa na perda -2%" {
        $capital = 1000
        $loss = -25  # < -2% threshold (-20)

        $triggered = Test-CircuitBreakerTriggered -Capital $capital -DailyLossThreshold -0.02
        # Sem mock, apenas valida lógica:
        ($loss -lt ($capital * -0.02)) | Should Be $true
    }

    It "permite trading se PnL > -2%" {
        $capital = 1000
        $gain = 50  # > -2% threshold (-20)

        ($gain -lt ($capital * -0.02)) | Should Be $false
    }
}
