# lib_market_movers_dual_radar.Tests.ps1 -- TDD radar duplo 24h + 30d
#
# Achado 2026-08-01 (owner, olhando "Top Gainers"/"Value Leaders" reais na
# CoinEx): o scanner real (scripts/gem_scanner_executor_live.ps1) so avalia
# um universo FIXO e curado manualmente (config/short_universe.json,
# config/long_universe.json -- 15 tickers cada, ultima curadoria 2026-07-09).
# Moedas que dispararam nas ultimas 24h (GIGGLE +74%, RATS +71%, IDOL +47%)
# ou que cairam forte (MMT -32%, HTR -18%, RLC -17%) nunca entram no radar,
# porque a lista e estatica -- nao ha ranking dinamico de movers real na
# nuvem (Get-PrioritizedMarkets existe mas so e chamada por gem_agent.ps1/
# gem_loop.ps1, que nao rodam em producao hoje).
#
# Owner pediu radar duplo: UNIAO dos rankings de 24h e 30d (nao intersecao)
# -- pega tanto spikes de curto prazo quanto tendencias de 30d sem spike
# forte hoje. Get-PrioritizedMarketsDualRadar reusa Get-PrioritizedMarkets
# (24h) e aplica a MESMA logica de threshold pro change_30d, unindo os
# 2 conjuntos sem duplicar simbolos.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-DualTicker {
    param(
        [string]$Symbol,
        [double]$Change24h = 0,
        [double]$Change30d = 0,
        [double]$Price = 1,
        [double]$Volume = 1000
    )
    [PSCustomObject]@{
        symbol     = $Symbol
        change_24h = $Change24h
        change_30d = $Change30d
        price      = $Price
        volume_24h = $Volume
    }
}

Describe "Get-PrioritizedMarketsDualRadar -- uniao 24h + 30d (nao intersecao)" {

    It "inclui ticker que so e mover em 24h (30d quiet)" {
        $tickers = @( (New-DualTicker "SPIKE24H" -Change24h 45 -Change30d 2) )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 1
        $result[0].symbol | Should Be "SPIKE24H"
    }

    It "inclui ticker que so e mover em 30d (24h quiet) -- tendencia sem spike hoje" {
        $tickers = @( (New-DualTicker "TREND30D" -Change24h 1 -Change30d 55) )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 1
        $result[0].symbol | Should Be "TREND30D"
    }

    It "nao duplica ticker que e mover nos dois periodos" {
        $tickers = @( (New-DualTicker "BOTH" -Change24h 30 -Change30d 60) )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 1
    }

    It "exclui ticker quiet nos dois periodos" {
        $tickers = @( (New-DualTicker "QUIET" -Change24h 1 -Change30d 3) )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 0
    }

    It "captura losers de 24h e de 30d (SHORT candidates)" {
        $tickers = @(
            (New-DualTicker "DUMP24H" -Change24h -32 -Change30d -1)
            (New-DualTicker "BLEED30D" -Change24h -2 -Change30d -35)
        )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 2
        ($result | Select-Object -ExpandProperty symbol) | Should Be @("DUMP24H", "BLEED30D")
    }

    It "cenario real do owner: GIGGLE/RATS (24h gainers fortes) + moeda so forte em 30d, ambos aparecem" {
        $tickers = @(
            (New-DualTicker "GIGGLE" -Change24h 74.31 -Change30d 12)
            (New-DualTicker "RATS" -Change24h 71.79 -Change30d 8)
            (New-DualTicker "MMT" -Change24h -32.22 -Change30d -5)
            (New-DualTicker "SLOWBURN" -Change24h 3 -Change30d 40)
            (New-DualTicker "BTCUSDT" -Change24h -1.91 -Change30d -15)
        )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $symbols = @($result | Select-Object -ExpandProperty symbol)
        ($symbols -contains "GIGGLE") | Should Be $true
        ($symbols -contains "RATS") | Should Be $true
        ($symbols -contains "MMT") | Should Be $true
        ($symbols -contains "SLOWBURN") | Should Be $true
        ($symbols -contains "BTCUSDT") | Should Be $false
    }

    It "sem change_30d no ticker (campo ausente) -- trata como 0, nao quebra" {
        $tickers = @( [PSCustomObject]@{ symbol = "NOFIELD"; change_24h = 25 } )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers -GainerThreshold24h 10 -LoserThreshold24h -10 -GainerThreshold30d 20 -LoserThreshold30d -20)
        $result.Count | Should Be 1
        $result[0].symbol | Should Be "NOFIELD"
    }

    It "lista vazia nao quebra" {
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets @())
        $result.Count | Should Be 0
    }

    It "usa defaults de threshold (10/-10 pra 24h, 20/-20 pra 30d) quando nao especificado" {
        $tickers = @(
            (New-DualTicker "DEF24H" -Change24h 15 -Change30d 0)
            (New-DualTicker "DEF30D" -Change24h 0 -Change30d 25)
            (New-DualTicker "DEFQUIET" -Change24h 5 -Change30d 10)
        )
        $result = @(Get-PrioritizedMarketsDualRadar -AllMarkets $tickers)
        $symbols = @($result | Select-Object -ExpandProperty symbol)
        ($symbols -contains "DEF24H") | Should Be $true
        ($symbols -contains "DEF30D") | Should Be $true
        ($symbols -contains "DEFQUIET") | Should Be $false
    }
}
