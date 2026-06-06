# TDD: Performance Refiner — confluência multi-sinal + refinamento SL/TP
# OBJETIVO: elevar win rate de 33% para 60%+ via consenso robusto

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Performance Refiner: Confluência Multi-Sinal" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_perf_refine_$(New-Guid)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_performance_refiner.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-PerformanceRefiner existe" {
        $cmd = Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "confluência 5/5 = APROVADO (consenso total)" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            # Todos os sinais = green
            $result = Invoke-PerformanceRefiner -Market "LINKUSDT" `
                -FaroV3Score 80 `
                -ToriProximity 85 `
                -DsrConfidence 75 `
                -MentorConviction 90 `
                -MesaConsensus "FORTE_3" `
                -VolatilityChange5m 1.2 `
                -JournalDir $journalDir

            ($result.approved) | Should Be $true
            ($result.confluence_count) | Should Be 5
        }
    }

    It "confluência 2/5 = REJEITADO (consenso fraco)" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            # Apenas 2 sinais = RED
            $result = Invoke-PerformanceRefiner -Market "SOLUSDT" `
                -FaroV3Score 45 `
                -ToriProximity 40 `
                -DsrConfidence 55 `
                -MentorConviction 45 `
                -MesaConsensus "CAOS" `
                -VolatilityChange5m 2.1 `
                -JournalDir $journalDir

            ($result.approved) | Should Be $false
            ($result.reason) | Should Match "WEAK_CONFLUENCE"
        }
    }

    It "entrada barulhenta (vol 5m > 5%) = REJEITADA mesmo com confluência 5/5" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            $result = Invoke-PerformanceRefiner -Market "UNIUSDT" `
                -FaroV3Score 85 `
                -ToriProximity 80 `
                -DsrConfidence 75 `
                -MentorConviction 85 `
                -MesaConsensus "FORTE_3" `
                -VolatilityChange5m 6.5 `
                -JournalDir $journalDir

            ($result.approved) | Should Be $false
            ($result.is_good_timing) | Should Be $false
        }
    }

    It "confluência 5/5 recomenda R:R 10:1 vs confluência 3/5 recomenda 5:1" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            # Confluência 5/5
            $result5 = Invoke-PerformanceRefiner -Market "BTCUSDT" `
                -FaroV3Score 90 `
                -ToriProximity 90 `
                -DsrConfidence 85 `
                -MentorConviction 95 `
                -MesaConsensus "FORTE_3" `
                -VolatilityChange5m 0.5 `
                -JournalDir $journalDir

            # Confluência 3/5
            $result3 = Invoke-PerformanceRefiner -Market "ETHUSDT" `
                -FaroV3Score 65 `
                -ToriProximity 55 `
                -DsrConfidence 45 `
                -MentorConviction 70 `
                -MesaConsensus "CAOS" `
                -VolatilityChange5m 1.0 `
                -JournalDir $journalDir

            ($result5.recommended_rr_ratio) | Should Be 10
            ($result3.recommended_rr_ratio) | Should Be 5
        }
    }

    It "performance_refiner_audit.jsonl logs todas as entradas" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            $auditPath = Join-Path $journalDir "performance_refiner_audit.jsonl"

            $result = Invoke-PerformanceRefiner -Market "NEAR" `
                -FaroV3Score 70 `
                -ToriProximity 60 `
                -DsrConfidence 65 `
                -MentorConviction 75 `
                -MesaConsensus "MEDIO_2" `
                -VolatilityChange5m 1.5 `
                -JournalDir $journalDir

            Test-Path $auditPath | Should Be $true
            (Get-Content $auditPath | Measure-Object -Line).Lines | Should BeGreaterThan 0
        }
    }

    It "Invoke-ConfluentEntryFinder analisa histórico e recomenda confluence_min" {
        if (Get-Command Invoke-ConfluentEntryFinder -ErrorAction SilentlyContinue) {
            # Histórico: 5/5 confluence = 2/2 wins, 3/5 confluence = 1/5 losses
            $history = @(
                @{ confluence_count=5; win=$true },
                @{ confluence_count=5; win=$true },
                @{ confluence_count=3; win=$false },
                @{ confluence_count=3; win=$false },
                @{ confluence_count=3; win=$false }
            )

            $finder = Invoke-ConfluentEntryFinder -TradeHistory $history -JournalDir $journalDir

            # Deveria recomendar min confluence 5 (win_rate 100%)
            ($finder.recommended_min_confluence -ge 4) | Should Be $true
        }
    }

    It "Get-AtrEstimate calcula ATR via candles (preferred) ou fallback proxy" {
        if (Get-Command Get-AtrEstimate -ErrorAction SilentlyContinue) {
            # Com candles
            $candles = @(
                @{ high=100; low=95; close=98 },
                @{ high=102; low=96; close=101 },
                @{ high=99; low=94; close=97 }
            )

            $atr = Get-AtrEstimate -Market "LINKUSDT" -RecentCandles $candles

            ($atr.method) | Should Be "candles"
            ($atr.atr_pct) | Should BeGreaterThan 0
        }
    }

    It "Get-AtrEstimate fallback pra proxy (change 24h) se sem candles" {
        if (Get-Command Get-AtrEstimate -ErrorAction SilentlyContinue) {
            $atr = Get-AtrEstimate -Market "SOLUSDT" -Change24hPct 3.5

            ($atr.method) | Should Be "proxy"
            ($atr.atr_pct) | Should BeGreaterThan 0
        }
    }

    It "Invoke-RefinedStopLossTarget ajusta SL/Target por confluência + regime" {
        if (Get-Command Invoke-RefinedStopLossTarget -ErrorAction SilentlyContinue) {
            # Entrada forte (conf=1.0) em BULL
            $strong = Invoke-RefinedStopLossTarget -EntryPrice 100 -AtrPct 2.5 `
                -PositionConfidence 1.0 -Direction "LONG" -Regime "BULL"

            # Entrada fraca (conf=0.6) em BULL
            $weak = Invoke-RefinedStopLossTarget -EntryPrice 100 -AtrPct 2.5 `
                -PositionConfidence 0.6 -Direction "LONG" -Regime "BULL"

            # Entrada forte deveria ter R:R maior
            ($strong.rr_ratio) | Should BeGreaterThan ($weak.rr_ratio)
            # Entrada fraca deveria ter SL mais largo (menos reativo)
            ($weak.stop_pct) | Should BeGreaterThan ($strong.stop_pct)
        }
    }

    It "SHORT: SL acima de entry, target abaixo" {
        if (Get-Command Invoke-RefinedStopLossTarget -ErrorAction SilentlyContinue) {
            $short = Invoke-RefinedStopLossTarget -EntryPrice 100 -AtrPct 2.5 `
                -PositionConfidence 0.8 -Direction "SHORT" -Regime "BEAR"

            ($short.stop_loss) | Should BeGreaterThan ($short.entry)
            ($short.target) | Should BeLessThan ($short.entry)
        }
    }

    It "confluência 3/5 = borderline APROVADO (consenso minimo)" {
        if (Get-Command Invoke-PerformanceRefiner -ErrorAction SilentlyContinue) {
            # Exatamente 3 sinais
            $result = Invoke-PerformanceRefiner -Market "TONUSDT" `
                -FaroV3Score 60 `
                -ToriProximity 55 `
                -DsrConfidence 65 `
                -MentorConviction 45 `
                -MesaConsensus "CAOS" `
                -VolatilityChange5m 1.0 `
                -JournalDir $journalDir

            ($result.approved) | Should Be $true
            ($result.confluence_count) | Should Be 3
        }
    }
}
