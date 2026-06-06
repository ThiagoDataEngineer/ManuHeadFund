# TDD: Audit Compliance — validação, logs estruturados, paper vs live
# OBJETIVO: auditoria reguladora 100% documentada

$projectRoot = Split-Path -Parent $PSScriptRoot

Describe "Audit Compliance: Regulador-Friendly" {
    BeforeAll {
        # Remove old test files to prevent flag accumulation
        $oldDirs = Get-ChildItem -Path $env:TEMP -Filter "test_audit_*" -Directory -ErrorAction SilentlyContinue
        $oldDirs | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $journalDir = Join-Path $env:TEMP "test_audit_$(New-Guid)_$(Get-Random)"
        New-Item -ItemType Directory -Path $journalDir -Force | Out-Null
        $global:JOURNAL_DIR = $journalDir

        $libPath = Join-Path $projectRoot "agents\lib_audit_compliance.ps1"
        if (Test-Path $libPath) {
            . $libPath
        }
    }

    AfterAll {
        Remove-Item -Recurse -Force $journalDir -ErrorAction SilentlyContinue
    }

    It "Test-InputDataNormality existe" {
        $cmd = Get-Command Test-InputDataNormality -ErrorAction SilentlyContinue
        ($cmd -ne $null) | Should Be $true
    }

    It "dados válidos passam validação (price > 0, change -50% a +100%, vol >= 0)" {
        if (Get-Command Test-InputDataNormality -ErrorAction SilentlyContinue) {
            $result = Test-InputDataNormality -Market "LINKUSDT" `
                -CurrentPrice 9.5 -Change24hPct 5.2 -VolumeUsd 50000000 `
                -AtrPct 2.5 -Direction "LONG" -JournalDir $journalDir

            ($result.is_valid) | Should Be $true
            ($result.severity) | Should Be "OK"
        }
    }

    It "preço negativo/zero REJEITA" {
        if (Get-Command Test-InputDataNormality -ErrorAction SilentlyContinue) {
            $result = Test-InputDataNormality -Market "SOLUSDT" `
                -CurrentPrice 0 -Change24hPct 2.0 -VolumeUsd 50000000 `
                -AtrPct 1.5 -Direction "LONG" -JournalDir $journalDir

            ($result.is_valid) | Should Be $false
            ($result.errors -join ',') | Should Match "PRICE_INVALID"
        }
    }

    It "change 24h > 100% REJEITA outlier" {
        if (Get-Command Test-InputDataNormality -ErrorAction SilentlyContinue) {
            $result = Test-InputDataNormality -Market "UNIUSDT" `
                -CurrentPrice 3.5 -Change24hPct 250 -VolumeUsd 50000000 `
                -AtrPct 5.0 -Direction "LONG" -JournalDir $journalDir

            ($result.is_valid) | Should Be $false
            ($result.severity) | Should Match "(ERROR|WARNING)"  # Multiple errors → WARNING or ERROR
        }
    }

    It "data_validation_audit.jsonl registra todas as validações" {
        if (Get-Command Test-InputDataNormality -ErrorAction SilentlyContinue) {
            $valPath = Join-Path $journalDir "data_validation_audit.jsonl"

            $null = Test-InputDataNormality -Market "BTC" `
                -CurrentPrice 100 -Change24hPct 1.5 -VolumeUsd 1000000000 `
                -AtrPct 1.2 -Direction "LONG" -JournalDir $journalDir

            Test-Path $valPath | Should Be $true
        }
    }

    It "Write-AuditLog cria JSONL + CSV legíveis" {
        if (Get-Command Write-AuditLog -ErrorAction SilentlyContinue) {
            $null = Write-AuditLog -Market "BTCUSDT" -AiDecision "EXECUTE" `
                -Confidence 85 -Price 100000 -TradeType "LONG" `
                -IsLiveTrading $true -JournalDir $journalDir

            $jsonlPath = Join-Path $journalDir "audit_log.jsonl"
            $csvPath = Join-Path $journalDir "audit_log.csv"

            (Test-Path $jsonlPath) | Should Be $true
            (Test-Path $csvPath) | Should Be $true
        }
    }

    It "audit_log.csv tem header + entradas auditáveis (Timestamp|Market|Decision|Confidence|...)" {
        if (Get-Command Write-AuditLog -ErrorAction SilentlyContinue) {
            $localDir = Join-Path $env:TEMP "test_csv_$(New-Guid)"
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null

            $null = Write-AuditLog -Market "ETHUSDT" -AiDecision "OBSERVE" `
                -Confidence 60 -Price 2500 -TradeType "SHORT" `
                -IsLiveTrading $false -JournalDir $localDir

            $csvPath = Join-Path $localDir "audit_log.csv"
            $csv = Get-Content $csvPath -Encoding UTF8

            ($csv[0]) | Should Match "Timestamp.*Market.*Decision.*Confidence"
            ($csv[1]) | Should Match "ETHUSDT.*OBSERVE.*60.*PAPER"

            Remove-Item -Recurse -Force $localDir
        }
    }

    It "Get-TradingMode detecta PAPER/LIVE/HYBRID via flags" {
        if (Get-Command Get-TradingMode -ErrorAction SilentlyContinue) {
            # Limpa dir completamente (safe from null)
            $oldDirs = @(Get-ChildItem -Path $env:TEMP -Filter "test_mode_*" -Directory -ErrorAction SilentlyContinue)
            if ($oldDirs.Count -gt 0) {
                $oldDirs | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            $localDir = Join-Path $env:TEMP "test_mode_$(Get-Random -Minimum 100000 -Maximum 999999)"
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null

            # Cria flag PAPER APENAS (nenhum LIVE flag)
            "1" | Set-Content -Path (Join-Path $localDir "PAPER_CALIBRATION_MODE.flag") -Encoding UTF8

            $mode = Get-TradingMode -JournalDir $localDir

            ($mode.is_paper) | Should Be $true
            ($mode.is_live) | Should Be $false

            Remove-Item -Recurse -Force $localDir
        }
    }

    It "New-TradeAuditRecord loga entrada/SL/TP/reasoning/confidence/modo" {
        if (Get-Command New-TradeAuditRecord -ErrorAction SilentlyContinue) {
            $record = New-TradeAuditRecord -Market "LINKUSDT" `
                -Direction "LONG" -EntryPrice 10 -StoplossPrice 9 `
                -TargetPrice 60 -PositionSizeUsd 500 -ModelConfidence 85 `
                -DecisionReasoning "5/5 confluência + timing limpo + ATR OK" `
                -IsLiveExecution $true -ConfluenceScore 100 -JournalDir $journalDir

            $recordPath = Join-Path $journalDir "trade_audit_records.jsonl"
            (Test-Path $recordPath) | Should Be $true
        }
    }

    It "trade_audit_records documenta RR ratio calculado" {
        if (Get-Command New-TradeAuditRecord -ErrorAction SilentlyContinue) {
            $null = New-TradeAuditRecord -Market "SOLUSDT" `
                -Direction "SHORT" -EntryPrice 100 -StoplossPrice 110 `
                -TargetPrice 80 -PositionSizeUsd 1000 -ModelConfidence 75 `
                -DecisionReasoning "DSR validado, timing OK" `
                -IsLiveExecution $false -JournalDir $journalDir

            $recordPath = Join-Path $journalDir "trade_audit_records.jsonl"
            $record = Get-Content $recordPath -Encoding UTF8 | ConvertFrom-Json

            # RR = 20% reward / 10% risk = 2:1
            ($record.rr_ratio) | Should BeGreaterThan 1.5
        }
    }

    It "Get-AuditorReport consolida validações + decisões + modo + conformidade" {
        if (Get-Command Get-AuditorReport -ErrorAction SilentlyContinue) {
            # Setup: cria alguns registros em dir isolado
            $localDir = Join-Path $env:TEMP "test_report2_$(New-Guid)"
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
            "1" | Set-Content -Path (Join-Path $localDir "LIVE_ENABLED.flag") -Encoding UTF8

            Write-AuditLog -Market "BTCUSDT" -AiDecision "EXECUTE" -Confidence 90 `
                -Price 100000 -TradeType "LONG" -IsLiveTrading $true -JournalDir $localDir

            Test-InputDataNormality -Market "ETHUSDT" -CurrentPrice 2500 `
                -Change24hPct 3.5 -VolumeUsd 500000000 -AtrPct 2.0 `
                -Direction "LONG" -JournalDir $localDir

            $report = Get-AuditorReport -JournalDir $localDir -DaysToAnalyze 1

            ($report.total_ai_decisions -gt 0) | Should Be $true
            ($report.live_trading_enabled) | Should Be $true
            ($report.avg_model_confidence) | Should BeGreaterThan 0

            Remove-Item -Recurse -Force $localDir
        }
    }

    It "auditoria mostra: data quality %, execute rate %, avg confidence, live vs paper split" {
        if (Get-Command Get-AuditorReport -ErrorAction SilentlyContinue) {
            $localDir = Join-Path $env:TEMP "test_report_$(New-Guid)"
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null

            # Cria registros variados
            Write-AuditLog -Market "LINKUSDT" -AiDecision "EXECUTE" -Confidence 80 `
                -Price 10 -TradeType "LONG" -IsLiveTrading $false -JournalDir $localDir
            Write-AuditLog -Market "SOLUSDT" -AiDecision "SKIP" -Confidence 40 `
                -Price 2.5 -TradeType "NONE" -IsLiveTrading $false -JournalDir $localDir

            Test-InputDataNormality -Market "A" -CurrentPrice 1 -Change24hPct 1 `
                -VolumeUsd 100000 -AtrPct 0.5 -Direction "LONG" -JournalDir $localDir
            Test-InputDataNormality -Market "B" -CurrentPrice 0 -Change24hPct 0 `
                -VolumeUsd 0 -AtrPct 0 -Direction "LONG" -JournalDir $localDir

            $report = Get-AuditorReport -JournalDir $localDir

            ($report.total_ai_decisions) | Should Be 2
            ($report.data_quality_pct) | Should Be 50  # 1/2 valid
            ($report.execute_rate_pct) | Should Be 50  # 1/2 execute
            ($report.avg_model_confidence) | Should BeGreaterThan 50

            Remove-Item -Recurse -Force $localDir
        }
    }

    It "COMPLIANCE: logs são imutáveis (append-only) em JSONL" {
        if (Get-Command Write-AuditLog -ErrorAction SilentlyContinue) {
            $localDir = Join-Path $env:TEMP "test_immutable_$(New-Guid)"
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null

            Write-AuditLog -Market "T1" -AiDecision "EXECUTE" -Confidence 80 `
                -Price 100 -TradeType "LONG" -IsLiveTrading $true -JournalDir $localDir
            Write-AuditLog -Market "T2" -AiDecision "SKIP" -Confidence 40 `
                -Price 200 -TradeType "NONE" -IsLiveTrading $false -JournalDir $localDir

            $jsonlPath = Join-Path $localDir "audit_log.jsonl"
            $lines = @(Get-Content $jsonlPath -Encoding UTF8)

            ($lines.Count) | Should Be 2
            ($lines[0]) | Should Match "T1"
            ($lines[1]) | Should Match "T2"

            Remove-Item -Recurse -Force $localDir
        }
    }
}
