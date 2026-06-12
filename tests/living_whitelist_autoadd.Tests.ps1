# living_whitelist_autoadd.Tests.ps1 -- TDD auto-add BULL_STRONG mode
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_promotion_ladder.ps1")
. (Join-Path $agentsDir "lib_living_whitelist.ps1")

$testDir = Join-Path $env:TEMP ("lw_aa_" + [Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
$pipelinePath = Join-Path $testDir "pipeline.jsonl"

Describe "Invoke-LivingWhitelistScan (BullStrongAutoAdd mode)" {

    It "auto-adiciona BULL_STRONG nao trackeado como DESCOBERTA + OBSERVATION" {
        $tickers = @([PSCustomObject]@{ market = "BULLUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{
                regime_asset = "BULL_STRONG"
                regime_btc = "BEAR_WEAK"
                mom_20d = 0.40
                sharpe_30d = 0.5   # fail no strict mas auto-add ignora
                n_trades = 1
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.new_candidates -contains "BULLUSDT" | Should Be $true
        $r.auto_added.Count | Should Be 1
        # Verifica state final no pipeline
        $state = Get-PromotionState -Path $pipelinePath -Market "BULLUSDT"
        $state.tier_state | Should Be 1
        $state.tier_label | Should Be "OBSERVATION"
    }

    It "NAO adiciona se asset_regime e BULL_WEAK (so BULL_STRONG)" {
        $tickers = @([PSCustomObject]@{ market = "WEAKBULLUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{
                regime_asset = "BULL_WEAK"; regime_btc = "BULL_WEAK"
                mom_20d = 0.01; sharpe_30d = 0.3; n_trades = 1
            }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.auto_added.Count | Should Be 0
        $r.filtered_out -contains "WEAKBULLUSDT" | Should Be $true
    }

    It "NAO re-adiciona se ja trackeado (idempotent)" {
        Add-PromotionEvent -Path $pipelinePath -Market "ALREADYUSDT" -Event "discovered" | Out-Null
        $tickers = @([PSCustomObject]@{ market = "ALREADYUSDT"; value = 5000000 })
        $provider = {
            param($m)
            return @{ regime_asset = "BULL_STRONG"; regime_btc = "BEAR_WEAK"; mom_20d = 0.30; sharpe_30d = 0; n_trades = 0 }
        }
        $r = Invoke-LivingWhitelistScan -Tickers $tickers -PipelinePath $pipelinePath `
            -MetricsProvider $provider -MinVolumeUsd 1000000 -BullStrongAutoAdd
        $r.auto_added.Count | Should Be 0
        $r.already_tracked -contains "ALREADYUSDT" | Should Be $true
    }
}

Describe "Format-RegimeDistribution" {

    It "produz output com bars ASCII e contagens" {
        $counts = @{
            BULL_STRONG = 4
            BULL_WEAK = 4
            SIDEWAYS = 6
            TRANSITION = 23
            BEAR_WEAK = 27
            BEAR_STRONG = 2
        }
        $r = Format-RegimeDistribution -Counts $counts
        $r -match "BULL_STRONG" | Should Be $true
        $r -match "TRANSITION" | Should Be $true
        $r -match "27" | Should Be $true
    }

    It "lida com counts vazio" {
        $r = Format-RegimeDistribution -Counts @{}
        $r | Should Not BeNullOrEmpty
    }
}
