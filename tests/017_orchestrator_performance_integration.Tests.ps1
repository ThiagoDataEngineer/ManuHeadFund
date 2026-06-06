# TDD: Orchestrator Performance Integration
# POSIÇÃO: Após Mentor APROVAR, antes telegram fire
# IMPACTO: Bloqueia entradas fracas mesmo com Mentor OK

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Orchestrator Performance Integration" {
    BeforeAll {
        $journalDir = Join-Path $env:TEMP "test_orch_perf_$(New-Guid)_$(Get-Random)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_orchestrator_performance_integration.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Invoke-PerformanceGate existe" {
        $cmd = Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "PASSA: confluência 5/5 + timing limpo → full size 1.0x" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            $triagem = @{ score_faro=80; score_tori=85; dsr_confidence=75 }
            $mesa = @{ consensus="FORTE_3" }
            $mentor = @{ conviction_pct=90 }

            $result = Invoke-PerformanceGate -Market "LINKUSDT" `
                -TriagemResult $triagem -MesaResult $mesa -MentorResult $mentor `
                -CurrentPrice 10 -Change24hPct 2 -VolumeUsd 50000000 -AtrPct 2.5 `
                -Volatility5mPct 1.5 -JournalDir $journalDir

            ($result.passes) | Should Be $true
            ($result.confluence_count) | Should Be 5
            ($result.size_multiplier) | Should Be 1.0
        }
    }

    It "BLOQUEIA: confluência 2/5 mesmo com Mentor OK → size 0.0x" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            $triagem = @{ score_faro=40; score_tori=45 }  # < 50 cada
            $mesa = @{ consensus="CAOS" }                 # Não FORTE_3
            $mentor = @{ conviction_pct=85 }              # Mentor OK

            $result = Invoke-PerformanceGate -Market "SOLUSDT" `
                -TriagemResult $triagem -MesaResult $mesa -MentorResult $mentor `
                -CurrentPrice 2.5 -Change24hPct 1 -VolumeUsd 50000000 -AtrPct 2 `
                -Volatility5mPct 0.5 -JournalDir $journalDir

            ($result.passes) | Should Be $false
            ($result.confluence_count) | Should Be 1  # Apenas mentor
            ($result.reason) | Should Match "CONFLUENCE_LOW"
            ($result.size_multiplier) | Should Be 0.0
        }
    }

    It "BLOQUEIA: entrada barulhenta (vol 5m > 5%) mesmo confluência 5/5" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            $triagem = @{ score_faro=90; score_tori=90 }
            $mesa = @{ consensus="FORTE_3" }
            $mentor = @{ conviction_pct=95 }

            $result = Invoke-PerformanceGate -Market "UNIUSDT" `
                -TriagemResult $triagem -MesaResult $mesa -MentorResult $mentor `
                -CurrentPrice 3.5 -Change24hPct 0.5 -VolumeUsd 50000000 -AtrPct 1.5 `
                -Volatility5mPct 6.2 -JournalDir $journalDir

            ($result.passes) | Should Be $false
            ($result.reason) | Should Match "NOISY_ENTRY"
        }
    }

    It "size multiplier: 5/5=1.0, 4/5=0.8, 3/5=0.5" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            # 5/5: Faro + Tori + DSR + Mentor + Mesa
            $r5 = Invoke-PerformanceGate -Market "M1" `
                -TriagemResult @{score_faro=80; score_tori=80; dsr_confidence=75} `
                -MesaResult @{consensus="FORTE_3"} `
                -MentorResult @{conviction_pct=90} `
                -Volatility5mPct 1.0 -JournalDir $journalDir
            ($r5.size_multiplier) | Should Be 1.0

            # 4/5: Faro + Tori + DSR + Mentor (sem Mesa)
            $r4 = Invoke-PerformanceGate -Market "M2" `
                -TriagemResult @{score_faro=80; score_tori=80; dsr_confidence=75} `
                -MesaResult @{consensus="CAOS"} `
                -MentorResult @{conviction_pct=90} `
                -Volatility5mPct 1.0 -JournalDir $journalDir
            ($r4.size_multiplier) | Should Be 0.8

            # 3/5: Faro + Tori + Mentor (sem DSR, sem Mesa)
            $r3 = Invoke-PerformanceGate -Market "M3" `
                -TriagemResult @{score_faro=80; score_tori=80} `
                -MesaResult @{consensus="CAOS"} `
                -MentorResult @{conviction_pct=90} `
                -Volatility5mPct 1.0 -JournalDir $journalDir
            ($r3.size_multiplier) | Should Be 0.5
        }
    }

    It "performance_gate_audit.jsonl logs confluência + timing + size" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            $null = Invoke-PerformanceGate -Market "BTCUSDT" `
                -TriagemResult @{score_faro=75; score_tori=70} `
                -MesaResult @{consensus="FORTE_3"} `
                -MentorResult @{conviction_pct=80} `
                -Volatility5mPct 0.8 -JournalDir $journalDir

            $logPath = Join-Path $journalDir "performance_gate_audit.jsonl"
            (Test-Path $logPath) | Should Be $true
        }
    }

    It "Get-EntrySignalsForConfluence retorna scores 0-100 por sinal" {
        if (Get-Command Get-EntrySignalsForConfluence -ErrorAction SilentlyContinue) {
            # Setup cache
            Update-SignalScoresCache -Market "LINKUSDT" `
                -FaroV3Score 75 -ToriScore 80 -DsrConfidence 70 `
                -MentorConviction 85 -MesaConsensus "FORTE_3" -JournalDir $journalDir

            $scores = Get-EntrySignalsForConfluence -Market "LINKUSDT" -JournalDir $journalDir

            ($scores.faro_v3_score) | Should Be 75
            ($scores.tori_proximity_score) | Should Be 80
            ($scores.dsr_confidence) | Should Be 70
            ($scores.mentor_conviction) | Should Be 85
            ($scores.mesa_consensus) | Should Be "FORTE_3"
        }
    }

    It "Update-SignalScoresCache armazena scores por market" {
        if (Get-Command Update-SignalScoresCache -ErrorAction SilentlyContinue) {
            Update-SignalScoresCache -Market "SOLUSDT" `
                -FaroV3Score 60 -ToriScore 55 -DsrConfidence 65 `
                -MentorConviction 75 -JournalDir $journalDir

            $cacheFile = Join-Path $journalDir "signal_scores_cache.json"
            (Test-Path $cacheFile) | Should Be $true

            $cache = Get-Content $cacheFile | ConvertFrom-Json
            ($cache.SOLUSDT.faro_v3) | Should Be 60
        }
    }

    It "confluência 3/5 borderline PASSA com timing limpo" {
        if (Get-Command Invoke-PerformanceGate -ErrorAction SilentlyContinue) {
            # 3/5: Faro + Tori + Mentor (sem DSR, sem Mesa)
            $result = Invoke-PerformanceGate -Market "NEAR" `
                -TriagemResult @{score_faro=65; score_tori=60} `
                -MesaResult @{consensus="CAOS"} `
                -MentorResult @{conviction_pct=70} `
                -Volatility5mPct 0.5 -JournalDir $journalDir

            ($result.passes) | Should Be $true
            ($result.confluence_count) | Should Be 3
            ($result.size_multiplier) | Should Be 0.5
        }
    }
}
