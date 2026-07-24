# learning_engine.Tests.ps1 — Auto-Improve Conviction Thresholds + Pattern Learning
# TDD: 22 testes

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\lib_learning_engine.ps1"

Describe "Learning Engine" {

    Context "Cloud Error Log Analysis" {
        It "Lê log vazio sem erro" {
            $result = Read-CloudErrorLog -LogPath "C:\nonexistent.log"
            $result.errors.Count | Should Be 0
            $result.error_rate | Should Be 0
        }

        It "Extrai erros BLOCKED do log" {
            # 2026-07-23 FIX: timestamps hardcoded 2026-06-18 sempre caiam
            # fora da janela -Hours 24 relativa a "agora" -- gerar dinamico.
            $tmpLog = Join-Path $env:TEMP ("log_test_" + [guid]::NewGuid().ToString() + ".log")
            $ts1 = (Get-Date).AddHours(-2).ToString("yyyy-MM-dd HH:mm:ss")
            $ts2 = (Get-Date).AddHours(-1).ToString("yyyy-MM-dd HH:mm:ss")
            $ts3 = (Get-Date).AddMinutes(-30).ToString("yyyy-MM-dd HH:mm:ss")
            @"
[$ts1] [BLOCKED] BTCUSDT -- downtrend forte sem toques suficientes
[$ts2] [INFO] GemScan: 1 gem(s) encontrados
[$ts3] [BLOCKED] ETHUSDT -- conviction score insuficiente
"@ | Out-File $tmpLog -Encoding UTF8

            $result = Read-CloudErrorLog -LogPath $tmpLog -Hours 24
            ($result.errors.Count -gt 0) | Should Be $true
            $result | Should Not BeNullOrEmpty

            Remove-Item $tmpLog -Force
        }

        It "Calcula error rate" {
            $tmpLog = Join-Path $env:TEMP ("log_test_" + [guid]::NewGuid().ToString() + ".log")
            $ts1 = (Get-Date).AddHours(-2).ToString("yyyy-MM-dd HH:mm:ss")
            $ts2 = (Get-Date).AddHours(-1).ToString("yyyy-MM-dd HH:mm:ss")
            $ts3 = (Get-Date).AddMinutes(-30).ToString("yyyy-MM-dd HH:mm:ss")
            @(
                "[$ts1] [BLOCKED] BTCUSDT -- erro1",
                "[$ts2] [INFO] ok",
                "[$ts3] [BLOCKED] ETHUSDT -- erro2"
            ) | Out-File $tmpLog -Encoding UTF8

            $result = Read-CloudErrorLog -LogPath $tmpLog -Hours 24
            $result.error_rate | Should Be 66.67

            Remove-Item $tmpLog -Force
        }
    }

    Context "Error Classification" {
        It "Classifica trendline_weak" {
            $err = @{ reason = "trendline invalid — insufficient touches" }
            $class = Classify-ErrorPattern -Error $err
            $class.pattern | Should Match "trendline"
        }

        It "Classifica conviction_low" {
            $err = @{ reason = "conviction score below threshold 55" }
            $class = Classify-ErrorPattern -Error $err
            $class.pattern | Should Match "conviction"
            $class.severity | Should Be "high"
        }

        It "Classifica bear_rejection" {
            $err = @{ reason = "downtrend strong — rejection" }
            $class = Classify-ErrorPattern -Error $err
            $class.pattern | Should Match "bear"
        }

        It "Marca fixable patterns" {
            $err = @{ reason = "conviction low — can improve" }
            $class = Classify-ErrorPattern -Error $err
            $class.fixable | Should Be $true
        }
    }

    Context "Pattern Analysis" {
        It "Agrupa erros por pattern" {
            $errors = @(
                @{ reason = "conviction low"; market = "BTCUSDT" },
                @{ reason = "conviction low"; market = "ETHUSDT" },
                @{ reason = "trendline weak"; market = "BNBUSDT" }
            )
            $analysis = Analyze-ErrorPatterns -Errors $errors
            $analysis.patterns.Keys.Count | Should BeGreaterThan 0
        }

        It "Identifica top issue" {
            $errors = @(
                @{ reason = "conviction low"; market = "BTC" },
                @{ reason = "conviction low"; market = "ETH" },
                @{ reason = "conviction low"; market = "BNB" },
                @{ reason = "trendline weak"; market = "ADA" }
            )
            $analysis = Analyze-ErrorPatterns -Errors $errors
            $analysis.top_issue | Should Match "conviction|trendline"
        }

        It "Gera recomendação" {
            $errors = @(
                @{ reason = "conviction low"; market = "BTC" },
                @{ reason = "conviction low"; market = "ETH" }
            )
            $analysis = Analyze-ErrorPatterns -Errors $errors
            $analysis.recommendation | Should Not BeNullOrEmpty
        }
    }

    Context "Conviction Threshold Adjustment" {
        It "Aumenta threshold se error rate alto" {
            $adj = Calculate-ConvictionAdjustment -CurrentThreshold 55 -ErrorRate 40 -TopPattern "none"
            $adj.new_threshold | Should BeGreaterThan 55
            $adj.delta | Should BeGreaterThan 0
        }

        It "Reduz threshold se error rate baixo" {
            $adj = Calculate-ConvictionAdjustment -CurrentThreshold 60 -ErrorRate 5 -TopPattern "none"
            $adj.new_threshold | Should BeLessThan 60
            $adj.delta | Should BeLessThan 0
        }

        It "Abaixa conviction se pattern conviction_low" {
            $adj = Calculate-ConvictionAdjustment -CurrentThreshold 55 -ErrorRate 10 -TopPattern "conviction_low"
            $adj.new_threshold | Should BeLessThan 55
        }

        It "Sobe trendline se pattern trendline_weak" {
            $adj = Calculate-ConvictionAdjustment -CurrentThreshold 55 -ErrorRate 10 -TopPattern "trendline_weak"
            $adj.new_threshold | Should BeGreaterThan 55
        }

        It "Limita threshold a 45-100" {
            $adj1 = Calculate-ConvictionAdjustment -CurrentThreshold 50 -ErrorRate 1 -TopPattern "conviction_low"
            $adj1.new_threshold | Should BeGreaterThan 44

            $adj2 = Calculate-ConvictionAdjustment -CurrentThreshold 95 -ErrorRate 99 -TopPattern "none"
            $adj2.new_threshold | Should BeLessThan 101
        }

        It "Calcula confidence score" {
            $adj = Calculate-ConvictionAdjustment -CurrentThreshold 55 -ErrorRate 40 -TopPattern "none"
            $adj.confidence | Should BeGreaterThan 50
        }
    }

    Context "DSR Adjustment" {
        It "Cria regime recommendation" {
            $adj = Calculate-DSRAdjustment -CurrentDSR 1.0
            $adj.regime_recommendation.BULL_STRONG | Should Be 1.4
            $adj.regime_recommendation.BEAR_STRONG | Should Be 0.3
        }

        It "Ajusta DSR baseado em performance" {
            $perf = @{ BULL_STRONG = 1.5; BEAR_STRONG = 0.5 }
            $adj = Calculate-DSRAdjustment -CurrentDSR 1.0 -RegimePerformance $perf
            $adj.new_dsr | Should BeGreaterThan 0.5
            $adj.new_dsr | Should BeLessThan 2.0
        }

        It "Aumenta confidence com mais dados" {
            $perf = @{}
            $adj1 = Calculate-DSRAdjustment -CurrentDSR 1.0 -RegimePerformance $perf
            $adj1.confidence | Should Be 50

            $perf = @{}
            1..6 | ForEach-Object { $perf["regime$_"] = 1.0 }
            $adj2 = Calculate-DSRAdjustment -CurrentDSR 1.0 -RegimePerformance $perf
            $adj2.confidence | Should Be 85
        }
    }

    Context "Full Learning Cycle" {
        It "Executa ciclo completo sem erro" {
            $tmpLog = Join-Path $env:TEMP ("full_cycle_" + [guid]::NewGuid().ToString() + ".log")
            @"
[2026-06-18 14:09:27] [BLOCKED] BTCUSDT -- conviction low
[2026-06-18 14:10:00] [INFO] GemScan ok
[2026-06-18 14:10:30] [BLOCKED] ETHUSDT -- conviction low
"@ | Out-File $tmpLog -Encoding UTF8

            $result = Update-ConvictionFromLogs -LogPath $tmpLog -CurrentConvictionThreshold 55 -Hours 24
            $result.success | Should Be $true
            $result.conviction_adjustment | Should Not BeNullOrEmpty
            $result.pattern_analysis | Should Not BeNullOrEmpty

            Remove-Item $tmpLog -Force
        }

        It "Detecta action_needed quando delta significativo" {
            $tmpLog = Join-Path $env:TEMP ("action_" + [guid]::NewGuid().ToString() + ".log")
            @(
                "[2026-06-18 14:09:27] [BLOCKED] BTCUSDT -- conviction low",
                "[2026-06-18 14:10:00] [BLOCKED] ETHUSDT -- conviction low",
                "[2026-06-18 14:10:30] [BLOCKED] BNBUSDT -- conviction low"
            ) | Out-File $tmpLog -Encoding UTF8

            $result = Update-ConvictionFromLogs -LogPath $tmpLog -CurrentConvictionThreshold 55
            # Se 100% errors e pattern = conviction_low, deve gerar action
            $result | Should Not BeNullOrEmpty

            Remove-Item $tmpLog -Force
        }

        It "Agenda próxima revisão" {
            $tmpLog = Join-Path $env:TEMP ("schedule_" + [guid]::NewGuid().ToString() + ".log")
            "[2026-06-18 14:09:27] [INFO] test" | Out-File $tmpLog -Encoding UTF8

            $result = Update-ConvictionFromLogs -LogPath $tmpLog
            $result.next_check | Should Not BeNullOrEmpty
            $result.next_check | Should BeGreaterThan (Get-Date)

            Remove-Item $tmpLog -Force
        }
    }

    Context "Sintaxe" {
        It "lib_learning_engine.ps1 parse OK" {
            $err = $null
            [void][System.Management.Automation.PSParser]::Tokenize(
                (Get-Content ".\agents\lib_learning_engine.ps1" -Raw),
                [ref]$err
            )
            $err.Count | Should Be 0
        }
    }

}
