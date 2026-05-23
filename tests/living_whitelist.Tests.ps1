# living_whitelist.Tests.ps1 -- TDD lib_living_whitelist
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_living_whitelist.ps1")

$testDir = Join-Path $env:TEMP ("lw_test_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$pipelinePath = Join-Path $testDir "promotion_pipeline.jsonl"

# Tickers fake (simulam top N por volume)
function New-FakeTickers {
    return @(
        [PSCustomObject]@{ market = "BIGUSDT"; value = 50000000 }
        [PSCustomObject]@{ market = "MIDUSDT"; value = 8000000 }
        [PSCustomObject]@{ market = "LOWUSDT"; value = 100000 }
    )
}

Describe "Filter-LiquidMarkets" {

    It "filtra por volume minimo USD" {
        $tickers = New-FakeTickers
        $r = Filter-LiquidMarkets -Tickers $tickers -MinVolumeUsd 1000000
        $r.Count | Should Be 2   # BIG + MID
        $r[0].market | Should Be "BIGUSDT"   # ordem por volume desc
    }

    It "TopN limita resultado" {
        $tickers = New-FakeTickers
        $r = Filter-LiquidMarkets -Tickers $tickers -MinVolumeUsd 0 -TopN 1
        $r.Count | Should Be 1
        $r[0].market | Should Be "BIGUSDT"
    }
}

Describe "Test-ShouldDiscover" {

    It "true quando NAO esta no pipeline" {
        $r = Test-ShouldDiscover -Market "NEWUSDT" -PipelinePath $pipelinePath
        $r | Should Be $true
    }

    It "false quando ja registrado no pipeline" {
        Add-PromotionEvent -Path $pipelinePath -Market "OLDUSDT" -Event "discovered" | Out-Null
        $r = Test-ShouldDiscover -Market "OLDUSDT" -PipelinePath $pipelinePath
        $r | Should Be $false
    }
}

Describe "Invoke-LivingWhitelistScan" {

    It "retorna estrutura com candidates + diff arrays" {
        $tickers = New-FakeTickers
        # Mock metrics provider que retorna stats fixos
        $metricsProvider = {
            param($market)
            return @{
                n_trades = 8; sharpe_30d = 1.2; max_dd = 0.10
                regime_asset = "BULL_STRONG"; regime_btc = "BULL_WEAK"
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $metricsProvider -MinVolumeUsd 1000000
        $r.ContainsKey("new_candidates") | Should Be $true
        $r.ContainsKey("already_tracked") | Should Be $true
        $r.ContainsKey("filtered_out") | Should Be $true
    }

    It "candidato com gate pass entra em new_candidates" {
        $tickers = @([PSCustomObject]@{ market = "GOODUSDT"; value = 5000000 })
        $metricsProvider = {
            param($market)
            return @{
                n_trades = 8; sharpe_30d = 1.5; max_dd = 0.08
                regime_asset = "BULL_STRONG"; regime_btc = "BEAR_WEAK"
                mom_20d = 0.05
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $metricsProvider -MinVolumeUsd 1000000
        $r.new_candidates.Count | Should Be 1
        $r.new_candidates[0] | Should Be "GOODUSDT"
    }

    It "candidato com gate fail vai pra filtered_out" {
        $tickers = @([PSCustomObject]@{ market = "WEAKUSDT"; value = 5000000 })
        $metricsProvider = {
            param($market)
            return @{
                n_trades = 2; sharpe_30d = 0.3; max_dd = 0.30
                regime_asset = "BEAR_STRONG"; regime_btc = "BEAR_WEAK"
                mom_20d = -0.05
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $metricsProvider -MinVolumeUsd 1000000
        $r.new_candidates.Count | Should Be 0
        $r.filtered_out.Count | Should Be 1
    }
}
