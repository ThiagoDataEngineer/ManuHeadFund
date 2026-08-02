# lib_short_universe_dynamic_radar.Tests.ps1 -- TDD
#
# Achado 2026-08-02 (owner, percebendo mais SPOT / menos FUTURES): o radar
# dinamico de 24h/30d (commit f3fdef4, 2026-08-01) so foi ligado no
# gem_executor.ps1 (que SEMPRE roteia pra SPOT por design, "GEM: sizing
# pequeno, sem leverage"). O short_scanner.ps1 (FUTURES real via
# config/short_universe.json, tier_a_live) continua com lista fixa de
# 15 majors desde 2026-07-09, sem nenhum radar dinamico. Confirmado real
# (comparando logs antes/depois do deploy): short_scanner nao cresceu
# (mesmo volume ~187 linhas de log), so o lado SPOT ganhou (pouco) volume.
#
# Owner decidiu: radar dinamico entra DIRETO no tier_a_live (execucao real),
# nao so como observatorio -- confiando nos gates de seguranca ja existentes
# (Tori >=80, Mesa, Mentor, sizing cap, funding-squeeze guard) pra filtrar
# risco, igual ja acontece com os 15 majors curados hoje.
#
# Get-DynamicShortUniverseWithTierALive combina a lista curada (markets +
# tier_a_live do config/short_universe.json) com os movers dinamicos de 24h
# (Get-DynamicMarketMoversFromRawTickers, ja existente desde ontem) --
# retorna tanto o universo de scan completo quanto o subconjunto elegivel
# a tier_a_live (curados + dinamicos, unidos).

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_short_universe.ps1")
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-RawTicker {
    param([string]$Market, [double]$Open, [double]$Close, [double]$Value = 100000)
    [PSCustomObject]@{ market = $Market; open = $Open; close = $Close; value = $Value }
}

Describe "Get-DynamicShortUniverseWithTierALive -- soma movers dinamicos ao universo SHORT curado" {

    It "inclui todos os markets curados (scan + tier_a_live) mesmo sem raw tickers" {
        $curatedMarkets = @("BTCUSDT", "ETHUSDT", "SOLUSDT")
        $curatedTierALive = @("BTCUSDT", "ETHUSDT")
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets $curatedMarkets -CuratedTierALive $curatedTierALive -RawTickers @()

        ($r.markets -contains "BTCUSDT") | Should Be $true
        ($r.markets -contains "SOLUSDT") | Should Be $true
        ($r.tier_a_live -contains "BTCUSDT") | Should Be $true
        ($r.tier_a_live -contains "SOLUSDT") | Should Be $false
    }

    It "adiciona mover dinamico de 24h (queda forte, candidato SHORT) tanto em markets quanto tier_a_live" {
        $curatedMarkets = @("BTCUSDT")
        $curatedTierALive = @("BTCUSDT")
        $raw = @( (New-RawTicker -Market "MMTUSDT" -Open 0.2946 -Close 0.1997) )  # -32.2%
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets $curatedMarkets -CuratedTierALive $curatedTierALive -RawTickers $raw

        ($r.markets -contains "MMTUSDT") | Should Be $true
        ($r.tier_a_live -contains "MMTUSDT") | Should Be $true
    }

    It "adiciona mover dinamico de gainer forte tambem (candidato SHORT por reversao, mesma logica de descoberta)" {
        $raw = @( (New-RawTicker -Market "RATSUSDT" -Open 0.00027 -Close 0.00047) )  # +74%
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets @("BTCUSDT") -CuratedTierALive @("BTCUSDT") -RawTickers $raw

        ($r.markets -contains "RATSUSDT") | Should Be $true
        ($r.tier_a_live -contains "RATSUSDT") | Should Be $true
    }

    It "nao duplica mover dinamico que ja esta na lista curada" {
        $curatedMarkets = @("BTCUSDT", "MMTUSDT")
        $raw = @( (New-RawTicker -Market "MMTUSDT" -Open 0.2946 -Close 0.1997) )
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets $curatedMarkets -CuratedTierALive @("BTCUSDT") -RawTickers $raw

        @($r.markets | Where-Object { $_ -eq "MMTUSDT" }).Count | Should Be 1
    }

    It "nao inclui ticker quiet (nao mover em 24h)" {
        $raw = @( (New-RawTicker -Market "QUIETUSDT" -Open 100 -Close 101) )  # +1%
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets @("BTCUSDT") -CuratedTierALive @("BTCUSDT") -RawTickers $raw

        ($r.markets -contains "QUIETUSDT") | Should Be $false
    }

    It "RawTickers vazio ou ausente nao quebra -- retorna so a lista curada" {
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets @("BTCUSDT") -CuratedTierALive @("BTCUSDT")
        $r.markets.Count | Should Be 1
        $r.tier_a_live.Count | Should Be 1
    }

    It "cenario real do owner: MMT (dump 24h) e RATS (pump 24h) entram, BTC (curado, quiet) permanece" {
        $curatedMarkets = @("BTCUSDT", "ETHUSDT", "XRPUSDT")
        $curatedTierALive = @("BTCUSDT", "ETHUSDT", "XRPUSDT")
        $raw = @(
            (New-RawTicker -Market "BTCUSDT" -Open 64000 -Close 63029)   # -1.5%, ja curado, quiet
            (New-RawTicker -Market "MMTUSDT" -Open 0.2946 -Close 0.1997) # -32.2%
            (New-RawTicker -Market "RATSUSDT" -Open 0.00027 -Close 0.00047) # +74%
        )
        $r = Get-DynamicShortUniverseWithTierALive -CuratedMarkets $curatedMarkets -CuratedTierALive $curatedTierALive -RawTickers $raw

        ($r.markets -contains "BTCUSDT") | Should Be $true
        ($r.markets -contains "MMTUSDT") | Should Be $true
        ($r.markets -contains "RATSUSDT") | Should Be $true
        ($r.tier_a_live -contains "MMTUSDT") | Should Be $true
        ($r.tier_a_live -contains "RATSUSDT") | Should Be $true
        # BTC continua tier_a_live por ser curado, independente de ser quiet agora
        ($r.tier_a_live -contains "BTCUSDT") | Should Be $true
    }
}
