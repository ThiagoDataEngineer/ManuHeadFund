# TDD: Semana 6 — Self-Learning Loop Autônomo (aprende do próprio histórico)

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Semana 6: Self-Learning Autonomous Loop" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_self_learn_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_self_learning.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-SelfLearningCycle existe" {
        $cmd = Get-Command Invoke-SelfLearningCycle -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "lê históricos (JSONL) e detecta padrões de erro" {
        if (Get-Command Invoke-SelfLearningCycle -ErrorAction SilentlyContinue) {
            # Simula histórico: 20% alucinações (hallucinates=true)
            $historico = @(
                @{ market="BTC"; mentor_conviction=95; data_sources=0; hallucinates=$true },
                @{ market="ETH"; mentor_conviction=85; data_sources=1; hallucinates=$true },
                @{ market="SOL"; mentor_conviction=75; data_sources=2; hallucinates=$false },
                @{ market="LINK"; mentor_conviction=80; data_sources=2; hallucinates=$false }
            )

            $cycle = Invoke-SelfLearningCycle -History $historico -JournalDir $journalDir

            ($cycle.patterns_detected -gt 0) | Should Be $true
            ($cycle.refinements_suggested -gt 0) | Should Be $true
        }
    }

    It "refina parâmetros baseado em performance real" {
        if (Get-Command Invoke-SelfLearningCycle -ErrorAction SilentlyContinue) {
            # Histórico: conviction alto + data_sources baixo = alucinações
            $historico = @(
                @{ mentor_conviction=90; data_sources=0; hallucinates=$true },
                @{ mentor_conviction=88; data_sources=0; hallucinates=$true },
                @{ mentor_conviction=92; data_sources=0; hallucinates=$true },
                @{ mentor_conviction=70; data_sources=2; hallucinates=$false }
            )

            $refinement = Invoke-ParameterRefinement -History $historico -JournalDir $journalDir

            ($refinement.new_conviction_min -le 80) | Should Be $true
            ($refinement.new_data_sources_min -ge 2) | Should Be $true
        }
    }

    It "detecta anomalias em padrões não documentados" {
        if (Get-Command Invoke-AnomalyDetector -ErrorAction SilentlyContinue) {
            # Exemplo: capital_safety blocks aumentando (padrão novo)
            $historico = @(
                @{ date="2026-06-05"; capital_blocks=0 },
                @{ date="2026-06-06"; capital_blocks=2 },
                @{ date="2026-06-07"; capital_blocks=8 },
                @{ date="2026-06-08"; capital_blocks=15 }
            )

            $anomaly = Invoke-AnomalyDetector -History $historico

            ($anomaly.detected) | Should Be $true
            ($anomaly.anomaly_type -match "trend") | Should Be $true
        }
    }

    It "aplica refinamentos com guardrails (rollback se piora)" {
        if (Get-Command Invoke-GuardedRefinement -ErrorAction SilentlyContinue) {
            # Simula: refinamento melhora performance
            $before = @{ win_rate=0.33; total_trades=10 }
            $after = @{ win_rate=0.40; total_trades=10 }

            $result = Invoke-GuardedRefinement -BeforeMetrics $before -AfterMetrics $after `
                -RefinementType "conviction_min" -JournalDir $journalDir

            ($result.applied) | Should Be $true
            ($result.rolled_back) | Should Be $false
        }
    }

    It "rejeita refinamentos que pioram performance" {
        if (Get-Command Invoke-GuardedRefinement -ErrorAction SilentlyContinue) {
            # Simula: refinamento piora performance
            $before = @{ win_rate=0.40; total_trades=10 }
            $after = @{ win_rate=0.25; total_trades=10 }

            $result = Invoke-GuardedRefinement -BeforeMetrics $before -AfterMetrics $after `
                -RefinementType "rr_minimum" -JournalDir $journalDir

            ($result.rolled_back) | Should Be $true
            ($result.applied) | Should Be $false
        }
    }

    It "self_learning_audit.jsonl registra TODA mudança (transparência)" {
        if (Get-Command Invoke-SelfLearningCycle -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "self_learning_audit.jsonl"

            $historico = @(@{ conviction=80; sources=2; result="win" })
            $null = Invoke-SelfLearningCycle -History $historico -JournalDir $journalDir

            Test-Path $auditPath | Should Be $true
        }
    }

    It "aprende coisas não documentadas (anomalias → refinamentos)" {
        if (Get-Command Invoke-UndocumentedLearning -ErrorAction SilentlyContinue) {
            # 2026-07-24 FIX: Measure-Object -Property nao funciona com
            # Hashtable (so PSCustomObject) -- dados reais de producao vem
            # de ConvertFrom-Json (sempre PSCustomObject), entao o mock
            # deve refletir isso pra testar o caminho real corretamente.
            $historico = @(
                [PSCustomObject]@{ market="SOLUSDT"; volume_24h=50000000; blocks=0 },
                [PSCustomObject]@{ market="SOLUSDT"; volume_24h=50000000; blocks=0 },
                [PSCustomObject]@{ market="SMALL_CAP"; volume_24h=5000000; blocks=15 },
                [PSCustomObject]@{ market="SMALL_CAP"; volume_24h=5000000; blocks=18 }
            )

            $learning = Invoke-UndocumentedLearning -History $historico

            ($learning.discovered -eq $true) | Should Be $true
            ($learning.pattern -match "volume") | Should Be $true
        }
    }

    It "ciclo contínuo: 6h interval, self-healing" {
        if (Get-Command Invoke-SelfLearningCycle -ErrorAction SilentlyContinue) {
            # Simulação: sistema executa ciclo, refina, valida
            $cycle1 = Invoke-SelfLearningCycle -History @(@{result="loss"}) -JournalDir $journalDir

            # 6h depois
            $cycle2 = Invoke-SelfLearningCycle -History @(@{result="win"}) -JournalDir $journalDir

            ($cycle1.cycle_id -ne $cycle2.cycle_id) | Should Be $true
            ($cycle2.improvements_since_last -ge 0) | Should Be $true
        }
    }
}
