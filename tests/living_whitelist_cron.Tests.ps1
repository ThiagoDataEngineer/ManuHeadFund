# living_whitelist_cron.Tests.ps1 -- TDD Item 2: Get-LivingWhitelistMetrics + cron integration
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_living_whitelist.ps1")

$testDir = Join-Path $env:TEMP ("lw_cron_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$pipelinePath = Join-Path $testDir "promotion_pipeline.jsonl"


# =============================================================================
Describe "Get-LivingWhitelistMetrics" {

    It "retorna hashtable com campos obrigatorios" {
        $m = Get-LivingWhitelistMetrics -Market "BTCUSDT"
        $m | Should Not BeNullOrEmpty
        $m.ContainsKey("regime_asset") | Should Be $true
        $m.ContainsKey("regime_btc")   | Should Be $true
        $m.ContainsKey("mom_20d")      | Should Be $true
        $m.ContainsKey("sharpe_30d")   | Should Be $true
        $m.ContainsKey("n_trades")     | Should Be $true
    }

    It "regime_asset nao e null" {
        $m = Get-LivingWhitelistMetrics -Market "BTCUSDT"
        $m.regime_asset | Should Not BeNullOrEmpty
    }

    It "fail-soft retorna defaults quando CoinEx indisponivel" {
        # Simula falha forcando market invalido que nao existe na API
        $m = Get-LivingWhitelistMetrics -Market "XXXXINVALIDUSDT_NAOEXISTE"
        $m | Should Not BeNullOrEmpty
        $m.ContainsKey("regime_asset") | Should Be $true
        # Deve retornar UNKNOWN como fallback seguro
        $m.regime_asset | Should Be "UNKNOWN"
    }
}


# =============================================================================
Describe "Invoke-LivingWhitelistScan BullStrongAutoAdd (cron integration)" {

    It "auto-adiciona BULL_STRONG com mom_20d alto" {
        $tickers = @([PSCustomObject]@{ market = "HOTUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{
                regime_asset = "BULL_STRONG"
                regime_btc   = "BULL_WEAK"
                mom_20d      = 0.35
                sharpe_30d   = 0.0
                n_trades     = 0
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.auto_added -contains "HOTUSDT" | Should Be $true
        $r.new_candidates -contains "HOTUSDT" | Should Be $true
    }

    It "nao adiciona BEAR_STRONG" {
        $tickers = @([PSCustomObject]@{ market = "COLDUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{
                regime_asset = "BEAR_STRONG"
                regime_btc   = "BEAR_WEAK"
                mom_20d      = -0.20
                sharpe_30d   = 0.0
                n_trades     = 0
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.auto_added.Count | Should Be 0
        $r.filtered_out -contains "COLDUSDT" | Should Be $true
    }

    It "idempotente (nao re-adiciona ja trackeado)" {
        Add-PromotionEvent -Path $pipelinePath -Market "IDEMPTUSDT" -Event "discovered" | Out-Null
        $tickers = @([PSCustomObject]@{ market = "IDEMPTUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{
                regime_asset = "BULL_STRONG"
                regime_btc   = "BULL_STRONG"
                mom_20d      = 0.50
                sharpe_30d   = 2.0
                n_trades     = 10
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.auto_added.Count | Should Be 0
        $r.already_tracked -contains "IDEMPTUSDT" | Should Be $true
    }

    It "retorna regime_counts com distribuicao" {
        $tickers = @(
            [PSCustomObject]@{ market = "AAUSDT"; value = 5000000 }
            [PSCustomObject]@{ market = "BBUSDT"; value = 5000000 }
            [PSCustomObject]@{ market = "CCUSDT"; value = 5000000 }
        )
        $regimes = @{ "AAUSDT" = "BULL_STRONG"; "BBUSDT" = "BEAR_WEAK"; "CCUSDT" = "SIDEWAYS" }
        $provider = {
            param($m)
            return @{
                regime_asset = $regimes[$m]
                regime_btc   = "SIDEWAYS"
                mom_20d      = 0.0
                sharpe_30d   = 0.0
                n_trades     = 0
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.ContainsKey("regime_counts") | Should Be $true
        $r.regime_counts.Count | Should BeGreaterThan 0
    }
}


# Cleanup
Remove-Item -Recurse -Force $testDir -ErrorAction SilentlyContinue
