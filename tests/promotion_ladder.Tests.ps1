# promotion_ladder.Tests.ps1 -- TDD lib_promotion_ladder.ps1
# Pester 3.x, sem acentos. PS 5.1.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_promotion_gates.ps1")

# Working dir temporario por test run
$testDir = Join-Path $env:TEMP ("pl_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$testJsonl = Join-Path $testDir "promotion_pipeline.jsonl"

Describe "Add-PromotionEvent" {

    It "cria jsonl novo e append primeira linha" {
        $r = Add-PromotionEvent -Path $testJsonl -Market "PENDLEUSDT" -Event "discovered" -Source "user_manual"
        $r.success | Should Be $true
        Test-Path $testJsonl | Should Be $true
        (Get-Content $testJsonl).Count | Should Be 1
    }

    It "append segunda linha mantem primeira" {
        Add-PromotionEvent -Path $testJsonl -Market "PENDLEUSDT" -Event "evaluated" -Metrics @{ n_trades = 5; sharpe_30d = 1.2 } | Out-Null
        (Get-Content $testJsonl).Count | Should Be 2
    }
}

Describe "Get-PromotionState" {

    It "retorna state 0 (DESCOBERTA) apos discovered" {
        $s = Get-PromotionState -Path $testJsonl -Market "PENDLEUSDT"
        $s.tier_state | Should Be 0
        $s.tier_label | Should Be "DESCOBERTA"
    }

    It "retorna null pra market nao registrado" {
        $s = Get-PromotionState -Path $testJsonl -Market "NEVERSEEN"
        $s | Should Be $null
    }

    It "reflete promote pra OBSERVATION" {
        Add-PromotionEvent -Path $testJsonl -Market "PENDLEUSDT" -Event "promoted" -TierState 1 | Out-Null
        $s = Get-PromotionState -Path $testJsonl -Market "PENDLEUSDT"
        $s.tier_state | Should Be 1
        $s.tier_label | Should Be "OBSERVATION"
    }
}

Describe "Test-GateObservationToC" {

    It "passa quando todos criterios atendidos (Versao C + regime iii)" {
        $m = @{
            sharpe_30d = 1.2
            mom_20d = 0.05
            n_trades = 6
            max_dd = 0.10
            regime_asset = "BULL_WEAK"
            regime_btc = "BEAR_WEAK"
        }
        $r = Test-GateObservationToC -Metrics $m
        $r.passed | Should Be $true
    }

    It "falha quando n_trades < 5" {
        $m = @{
            sharpe_30d = 1.5
            mom_20d = 0.10
            n_trades = 3
            max_dd = 0.05
            regime_asset = "BULL_STRONG"
            regime_btc = "BULL_STRONG"
        }
        $r = Test-GateObservationToC -Metrics $m
        $r.passed | Should Be $false
        ($r.failures -join ",") -match "n_trades" | Should Be $true
    }

    It "falha quando ambos regimes bear (regime iii bloqueia)" {
        $m = @{
            sharpe_30d = 1.5
            mom_20d = 0.05
            n_trades = 10
            max_dd = 0.05
            regime_asset = "BEAR_STRONG"
            regime_btc = "BEAR_WEAK"
        }
        $r = Test-GateObservationToC -Metrics $m
        $r.passed | Should Be $false
        ($r.failures -join ",") -match "regime" | Should Be $true
    }

    It "passa quando asset bull mesmo BTC bear (regime iii OR)" {
        $m = @{
            sharpe_30d = 1.2
            mom_20d = 0.05
            n_trades = 10
            max_dd = 0.10
            regime_asset = "BULL_STRONG"
            regime_btc = "BEAR_STRONG"
        }
        $r = Test-GateObservationToC -Metrics $m
        $r.passed | Should Be $true
    }

    It "falha quando max_dd > 15%" {
        $m = @{
            sharpe_30d = 1.5
            mom_20d = 0.05
            n_trades = 10
            max_dd = 0.20
            regime_asset = "BULL_STRONG"
            regime_btc = "BULL_STRONG"
        }
        $r = Test-GateObservationToC -Metrics $m
        $r.passed | Should Be $false
        ($r.failures -join ",") -match "max_dd" | Should Be $true
    }
}

Describe "Test-GateCToB" {

    It "passa Versao alpha completa" {
        $m = @{
            sharpe_60d = 1.7
            psr = 0.88
            n_trades = 18
            max_dd = 0.10
            equity_curve_monotonic = $true
        }
        $r = Test-GateCToB -Metrics $m
        $r.passed | Should Be $true
    }

    It "falha quando PSR < 0.85" {
        $m = @{
            sharpe_60d = 1.5
            psr = 0.70
            n_trades = 20
            max_dd = 0.10
            equity_curve_monotonic = $true
        }
        $r = Test-GateCToB -Metrics $m
        $r.passed | Should Be $false
        ($r.failures -join ",") -match "psr" | Should Be $true
    }
}

Describe "Test-GateBToLive" {

    It "passa criterio recomendado completo" {
        $m = @{
            pnl_real = 50.0
            n_trades_real = 28
            sharpe_real = 1.6
            max_dd = 0.08
            psr = 0.92
            dsr_global = 0.65
        }
        $r = Test-GateBToLive -Metrics $m
        $r.passed | Should Be $true
    }

    It "falha quando dsr_global < 0.60 (multi-testing penalty)" {
        $m = @{
            pnl_real = 100
            n_trades_real = 30
            sharpe_real = 2.0
            max_dd = 0.05
            psr = 0.95
            dsr_global = 0.45
        }
        $r = Test-GateBToLive -Metrics $m
        $r.passed | Should Be $false
        ($r.failures -join ",") -match "dsr_global" | Should Be $true
    }
}

Describe "Test-DemoteTrigger" {

    It "detecta 4 semanas consecutivas Sharpe<0 -> demote" {
        $weeklySharpes = @(-0.1, -0.3, -0.05, -0.2)
        $r = Test-DemoteTrigger -WeeklySharpes $weeklySharpes -DaysSinceLastTrade 30
        $r.should_demote | Should Be $true
        $r.reason -match "consecutive_negative" | Should Be $true
    }

    It "180d sem trade -> demote" {
        $r = Test-DemoteTrigger -WeeklySharpes @(0.5, 0.3, 0.1, 0.4) -DaysSinceLastTrade 200
        $r.should_demote | Should Be $true
        $r.reason -match "no_trades" | Should Be $true
    }

    It "Sharpe misto e trade recente -> NAO demote" {
        $r = Test-DemoteTrigger -WeeklySharpes @(0.5, -0.1, 0.3, 0.4) -DaysSinceLastTrade 14
        $r.should_demote | Should Be $false
    }
}

Describe "Invoke-PromotionPropose com EnforceGates" {
    $tDir = Join-Path $env:TEMP ("plp_$([guid]::NewGuid())")
    New-Item -ItemType Directory -Path $tDir -Force | Out-Null
    $jl = Join-Path $tDir "pipeline.jsonl"
    $sectorMap = Join-Path $tDir "sector_map.json"
    @{ markets = @{ INJUSDT="l1"; ETHUSDT="l1"; BTCUSDT="store_of_value" } } | ConvertTo-Json -Compress | Out-File $sectorMap -Encoding utf8

    # Setup: market em PAPER_B (state 3) com metricas perfeitas
    Add-PromotionEvent -Path $jl -Market "INJUSDT" -Event "promoted" -TierState 3 | Out-Null
    $metrics = @{
        pnl_real = 50.0
        n_trades_real = 30
        sharpe_real = 2.0
        max_dd = 0.05
        psr = 0.95
        dsr_global = 0.75
    }

    It "sem EnforceGates: promove se gate de tier passa" {
        $r = Invoke-PromotionPropose -Path $jl -Market "INJUSDT" -Metrics $metrics
        $r.action | Should Be "propose_promote"
    }

    It "com EnforceGates: bloqueia se concentration excedida" {
        # 6 Tier A markets ja existentes -> concentration block
        $tierA = @("BTCUSDT","ETHUSDT","XRPUSDT","SOLUSDT","DOGEUSDT","ADAUSDT")
        $script:SECTOR_MAP_DEFAULT_PATH = $sectorMap
        $r = Invoke-PromotionPropose -Path $jl -Market "INJUSDT" -Metrics $metrics `
            -EnforceGates -CurrentTierAMarkets $tierA -VolumeUsd 1000000
        $r.action | Should Be "blocked_by_gates"
        ($r.blocked_by -join ",") -match "concentration" | Should Be $true
    }

    It "com EnforceGates: passa se gates limpos" {
        $tierA = @("BTCUSDT")
        $script:SECTOR_MAP_DEFAULT_PATH = $sectorMap
        $r = Invoke-PromotionPropose -Path $jl -Market "INJUSDT" -Metrics $metrics `
            -EnforceGates -CurrentTierAMarkets $tierA -VolumeUsd 1000000
        $r.action | Should Be "propose_promote"
    }

    Remove-Item $tDir -Recurse -Force -ErrorAction SilentlyContinue
}
