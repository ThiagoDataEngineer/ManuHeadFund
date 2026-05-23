# cost_tracker_alarm.Tests.ps1 — TDD strict: hard-stop alarm para custos
# 8 tests: validar limites per-trade e daily, métricas
# UTF-8 BOM, Pester 3.x

Describe "Cost Tracker Alarm" {
    # Load lib sob teste
    . "$PSScriptRoot\..\agents\lib_cost_tracker.ps1"

    # Mock CSV para testes
    $testCostFile = Join-Path $env:TEMP "test_claude_usage_$$_$((Get-Random)).csv"

    BeforeEach {
        "timestamp,agent,model,input_tokens,output_tokens,cost_usd,latency_ms" |
            Out-File -FilePath $testCostFile -Encoding utf8 -Force
    }

    AfterEach {
        if (Test-Path $testCostFile) {
            Remove-Item $testCostFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Test-CostAlarmThreshold" {
        It "retorna alarm_triggered=false quando custos < limites" {
            $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "$ts,mesa,claude-haiku-4-5,1000,500,0.0050,100" |
                Add-Content -Path $testCostFile -Encoding utf8

            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 0.10 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.alarm_triggered | Should Be $false
            $result.reason | Should Be "ok"
        }

        It "retorna estrutura com current_metrics" {
            $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "$ts,triagem,claude-sonnet-4-5,5000,2000,0.0200,500" |
                Add-Content -Path $testCostFile -Encoding utf8

            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 0.10 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.current_metrics | Should Not Be $null
            $result.current_metrics.daily_cost | Should Be 0.02
        }

        It "trigera alarme quando daily_cost > MaxDailyCostUsd" {
            $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            for ($i = 1; $i -le 6; $i++) {
                "$ts,mesa,claude-sonnet-4-5,100000,50000,1.0000,1000" |
                    Add-Content -Path $testCostFile -Encoding utf8
            }

            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 0.10 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.alarm_triggered | Should Be $true
            $result.reason | Should Be "daily_high"
        }

        It "calcula daily_cost acumulado" {
            $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "$ts,mesa,claude-sonnet-4-5,100000,50000,0.5000,1000" |
                Add-Content -Path $testCostFile -Encoding utf8
            "$ts,mentor,claude-opus-4-7,50000,30000,0.7500,2000" |
                Add-Content -Path $testCostFile -Encoding utf8

            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 1.0 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.current_metrics.daily_cost | Should Be 1.25
        }

        It "gracefully retorna OK quando CSV vazio" {
            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 0.10 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.alarm_triggered | Should Be $false
            $result.reason | Should Be "ok"
        }

        It "trata CSV com cost_usd vazio como 0" {
            $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            "$ts,mesa,claude-sonnet-4-5,100000,50000,,1000" |
                Add-Content -Path $testCostFile -Encoding utf8

            $result = Test-CostAlarmThreshold -MaxCostPerTradeUsd 0.10 -MaxDailyCostUsd 5.00 -CostFile $testCostFile
            $result.alarm_triggered | Should Be $false
        }
    }
}

# Cleanup ja eh feito no AfterEach dentro do Describe
