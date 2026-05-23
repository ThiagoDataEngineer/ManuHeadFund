# promotion_cycle.Tests.ps1 -- TDD Invoke-PromotionCycle (cron logic)
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_dsr_global.ps1")
. (Join-Path $agentsDir "lib_promotion_cycle.ps1")

$testDir = Join-Path $env:TEMP ("pc_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$pipelinePath = Join-Path $testDir "promotion_pipeline.jsonl"
$dsrPath      = Join-Path $testDir "dsr_global.json"

# Helper: metrics provider que retorna metrics passados
function Get-FixedMetricsProvider {
    param([hashtable]$Map)
    return {
        param([string]$Market)
        if ($Map.ContainsKey($Market)) { return $Map[$Market] }
        return $null
    }.GetNewClosure()
}

Describe "Invoke-PromotionCycle" {

    It "pipeline vazio retorna 0 actions" {
        $provider = Get-FixedMetricsProvider -Map @{}
        $r = Invoke-PromotionCycle -PipelinePath $pipelinePath -DsrPath $dsrPath -MetricsProvider $provider
        $r.actions.Count | Should Be 0
        $r.evaluated.Count | Should Be 0
    }

    It "market em OBSERVATION com gate pass propoe promote" {
        # Adiciona market em OBSERVATION
        Add-PromotionEvent -Path $pipelinePath -Market "PENDLEUSDT" -Event "discovered" -Source "user_manual" | Out-Null
        Add-PromotionEvent -Path $pipelinePath -Market "PENDLEUSDT" -Event "promoted" -TierState 1 -UserDecision "approve" | Out-Null

        # Metrics que passam gate
        $metrics = @{
            sharpe_30d = 1.5
            mom_20d = 0.05
            n_trades = 8
            max_dd = 0.10
            regime_asset = "BULL_STRONG"
            regime_btc = "BEAR_WEAK"
        }
        $provider = Get-FixedMetricsProvider -Map @{ "PENDLEUSDT" = $metrics }

        $r = Invoke-PromotionCycle -PipelinePath $pipelinePath -DsrPath $dsrPath -MetricsProvider $provider
        $r.actions.Count | Should Be 1
        $r.actions[0].action | Should Be "propose_promote"
        $r.actions[0].market | Should Be "PENDLEUSDT"
    }

    It "market em OBSERVATION com gate fail apenas avalia (sem propose)" {
        $testDir2 = Join-Path $env:TEMP ("pc_test2_" + [Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $testDir2 -Force | Out-Null
        $pipelinePath2 = Join-Path $testDir2 "promotion_pipeline.jsonl"
        $dsrPath2      = Join-Path $testDir2 "dsr_global.json"

        Add-PromotionEvent -Path $pipelinePath2 -Market "WEAKUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath2 -Market "WEAKUSDT" -Event "promoted" -TierState 1 | Out-Null

        # Metrics que falham (sharpe baixo + n_trades 2)
        $metrics = @{
            sharpe_30d = 0.3
            mom_20d = 0.01
            n_trades = 2
            max_dd = 0.05
            regime_asset = "SIDEWAYS"
            regime_btc = "BEAR_WEAK"
        }
        $provider = Get-FixedMetricsProvider -Map @{ "WEAKUSDT" = $metrics }

        $r = Invoke-PromotionCycle -PipelinePath $pipelinePath2 -DsrPath $dsrPath2 -MetricsProvider $provider
        $r.actions.Count | Should Be 0
        $r.evaluated.Count | Should Be 1
    }

    It "incrementa DSR global trials para cada gate avaliado" {
        # Reuse first pipeline (PENDLEUSDT em OBSERVATION)
        $beforeN = Get-DsrTrials -Path $dsrPath
        $metrics = @{
            sharpe_30d = 1.5
            mom_20d = 0.05
            n_trades = 8
            max_dd = 0.10
            regime_asset = "BULL_STRONG"
            regime_btc = "BEAR_WEAK"
        }
        $provider = Get-FixedMetricsProvider -Map @{ "PENDLEUSDT" = $metrics }
        Invoke-PromotionCycle -PipelinePath $pipelinePath -DsrPath $dsrPath -MetricsProvider $provider | Out-Null
        $afterN = Get-DsrTrials -Path $dsrPath
        $afterN | Should BeGreaterThan $beforeN
    }

    It "market em TIER_A_LIVE nao avalia promote (skip terminal)" {
        $testDir3 = Join-Path $env:TEMP ("pc_test3_" + [Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $testDir3 -Force | Out-Null
        $pipelinePath3 = Join-Path $testDir3 "promotion_pipeline.jsonl"
        $dsrPath3      = Join-Path $testDir3 "dsr_global.json"

        Add-PromotionEvent -Path $pipelinePath3 -Market "ZECUSDT" -Event "discovered" | Out-Null
        Add-PromotionEvent -Path $pipelinePath3 -Market "ZECUSDT" -Event "promoted" -TierState 4 | Out-Null

        $metrics = @{
            pnl_real = 100; n_trades_real = 30; sharpe_real = 2.0
            max_dd = 0.05; psr = 0.95; dsr_global = 0.8
            weekly_sharpes = @(0.5, 0.3, 0.2, 0.4)
            days_since_last_trade = 5
        }
        $provider = Get-FixedMetricsProvider -Map @{ "ZECUSDT" = $metrics }

        $r = Invoke-PromotionCycle -PipelinePath $pipelinePath3 -DsrPath $dsrPath3 -MetricsProvider $provider
        # Nao propoe promote (ja Tier A terminal)
        ($r.actions | Where-Object { $_.action -eq "propose_promote" }).Count | Should Be 0
    }
}
