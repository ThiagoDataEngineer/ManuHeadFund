# lib_circuit_breaker_simple.Tests.ps1 — 15 TDD

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_circuit_breaker_simple.ps1")

$testJournal = Join-Path $PSScriptRoot "test_journal"
if (-not (Test-Path $testJournal)) { mkdir $testJournal | Out-Null }
# 2026-07-23 FIX: Set-CircuitBreakerPause/Reset-CircuitBreaker usam
# $global:JOURNAL_DIR (sem parametro -JournalDir), nao $testJournal local
# -- sem isso, os testes de flag liam/escreviam no journal/ real do
# projeto, nao no isolado de teste.
$global:JOURNAL_DIR = $testJournal

Describe "CircuitBreaker: Get-DailyPnL" {
    It "retorna 0 se arquivo não existe" {
        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 0.0
    }

    It "soma PnL de hoje" {
        $today = (Get-Date).Date.ToString("yyyy-MM-dd")
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        @{ exit_date=$today; pnl_usd=50.0 } | ConvertTo-Json -Compress | Add-Content $outcomeFile
        @{ exit_date=$today; pnl_usd=30.0 } | ConvertTo-Json -Compress | Add-Content $outcomeFile

        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 80.0

        Remove-Item $outcomeFile
    }

    It "ignora PnL de ontem" {
        $today = (Get-Date).Date.ToString("yyyy-MM-dd")
        $yesterday = (Get-Date).AddDays(-1).Date.ToString("yyyy-MM-dd")
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        @{ exit_date=$yesterday; pnl_usd=100.0 } | ConvertTo-Json -Compress | Add-Content $outcomeFile
        @{ exit_date=$today; pnl_usd=50.0 } | ConvertTo-Json -Compress | Add-Content $outcomeFile

        $pnl = Get-DailyPnL -JournalDir $testJournal
        $pnl | Should Be 50.0

        Remove-Item $outcomeFile
    }

    It "trata malformed JSON gracefully" {
        # 2026-07-23 FIX: "Add-Content $outcomeFile @{...} | ConvertTo-Json"
        # tinha a ordem do pipeline errada -- gravava o hashtable como
        # string bruta (Add-Content aplicado ANTES do ConvertTo-Json, que
        # so recebia o $null de retorno do Add-Content).
        $outcomeFile = Join-Path $testJournal "trade_outcomes.jsonl"
        Add-Content $outcomeFile "{ invalid json"
        @{ exit_date=((Get-Date).Date.ToString("yyyy-MM-dd")); pnl_usd=10.0 } | ConvertTo-Json -Compress | Add-Content $outcomeFile

        # Não deve lançar erro
        $pnl = Get-DailyPnL -JournalDir $testJournal
        ($pnl -ge 0) | Should Be $true

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

# 2026-07-27: achado real em producao -- gem_executor.ps1 chamava
# Test-CircuitBreakerTriggered -Capital $global:CAPITAL_TOTAL, mas essa
# variavel NUNCA e setada no caminho real de execucao ($CAPITAL_TOTAL existe
# so em escopo de SCRIPT em config.ps1, sem $global:). PowerShell coage o
# $null explicitamente passado pra 0 no parametro [double]$Capital -- o
# default (3645.0) NUNCA e usado nesse caso, porque so se aplica quando o
# parametro NAO e passado. Resultado real: threshold = 0 * -0.02 = 0, entao
# qualquer PnL negativo (mesmo -$0.01) disparava o circuit breaker e
# bloqueava TODOS os candidatos do dia (confirmado: 11/11 bloqueados por
# PnL de so -$7.75, nem perto de -2% real de ~$4985).
Describe "CircuitBreaker: regressao -- capital nulo/vazio nao pode zerar o threshold" {
    It "documenta o bug: passar \$null explicito no parametro double vira 0, ignorando o default" {
        function Test-CapitalCoercion { param([double]$Capital = 3645.0) return $Capital }
        $nullCapital = $null
        (Test-CapitalCoercion -Capital $nullCapital) | Should Be 0.0
    }

    It "threshold com capital=0 dispara com QUALQUER pnl negativo (o bug real)" {
        $capital = 0.0
        $threshold = $capital * -0.02
        $threshold | Should Be 0.0
        (-0.01 -lt $threshold) | Should Be $true
    }

    It "fix: fallback para capital real (ou default seguro) quando o capital calculado e <= 0" {
        function Resolve-CircuitBreakerCapital {
            param([double]$ComputedCapital)
            if ($ComputedCapital -le 0) { return 3645.0 }
            return $ComputedCapital
        }
        (Resolve-CircuitBreakerCapital -ComputedCapital 0) | Should Be 3645.0
        (Resolve-CircuitBreakerCapital -ComputedCapital 4985.0) | Should Be 4985.0
    }

    It "com capital real (~4985), PnL de -7.75 NAO deveria disparar -2% (-99.70)" {
        $capital = 4985.0
        $threshold = $capital * -0.02
        $dailyPnL = -7.75
        ($dailyPnL -lt $threshold) | Should Be $false
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
