# lib_market_movers.Tests.ps1 -- TDD universo dinamico top movers
# 2026-06-09: prioriza gainers/losers (vol spike real) sobre quiet tickers
#
# 2026-07-23 FIX: reescrito por completo -- a lib real so define
# Get-PrioritizedMarkets (chamada em producao por agents/gem_agent.ps1 e
# scripts/gem_loop.ps1, um dos motores reais). Get-MarketMovers e
# Get-ScanPriority testados aqui NUNCA existiram -- API real e mais simples:
# um unico array [gainers + losers + quiet] concatenado (sem propriedades
# .gainers/.losers separadas, sem ordenacao por magnitude, sem TopCount).

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-Ticker {
    param([string]$Symbol, [double]$Change24h, [double]$Price = 1, [double]$Volume = 1000)
    [PSCustomObject]@{ symbol = $Symbol; change_24h = $Change24h; price = $Price; volume_24h = $Volume }
}

Describe "MarketMovers: Get-PrioritizedMarkets (movers primeiro, quiet depois)" {
    It "prioriza gainers + losers sobre quiet, na ordem original de cada grupo" {
        $tickers = @(
            (New-Ticker "MOVE" 56),
            (New-Ticker "QUIET1" 5),
            (New-Ticker "H" -80.03),
            (New-Ticker "QUIET2" -3)
        )
        $result = Get-PrioritizedMarkets -AllMarkets $tickers -GainerThreshold 10 -LoserThreshold -10
        # ordem real: gainers (na ordem de entrada) + losers (na ordem de entrada) + quiet
        $result[0].symbol | Should Be "MOVE"
        $result[1].symbol | Should Be "H"
        $result[2].symbol | Should Be "QUIET1"
        $result[3].symbol | Should Be "QUIET2"
    }

    It "classifica corretamente gainers/losers/quiet por threshold" {
        $tickers = @(
            (New-Ticker "MOVE" 56),
            (New-Ticker "SIS" 40.19),
            (New-Ticker "FTT" 31.88),
            (New-Ticker "ZECUSDT" 4.37),
            (New-Ticker "H" -80.03),
            (New-Ticker "EPICCHAIN" -39.24),
            (New-Ticker "CLO" -37.58),
            (New-Ticker "BTC" -0.56)
        )
        $result = @(Get-PrioritizedMarkets -AllMarkets $tickers -GainerThreshold 10 -LoserThreshold -10)
        # gainers (>=10): MOVE, SIS, FTT = 3; losers (<=-10): H, EPICCHAIN, CLO = 3; quiet: ZECUSDT, BTC = 2
        $result.Count | Should Be 8
        @($result | Where-Object { $_.change_24h -ge 10 }).Count | Should Be 3
        @($result | Where-Object { $_.change_24h -le -10 }).Count | Should Be 3
    }

    It "ignora tickers sem change_24h (trata como quiet, change=0)" {
        $tickers = @(
            (New-Ticker "GOOD" 25),
            [PSCustomObject]@{ symbol = "BAD"; price = 1 }  # sem change_24h
        )
        $result = @(Get-PrioritizedMarkets -AllMarkets $tickers -GainerThreshold 10)
        $result.Count | Should Be 2
        $result[0].symbol | Should Be "GOOD"  # gainer vem primeiro
        $result[1].symbol | Should Be "BAD"   # sem change_24h = quiet (change=0)
    }

    It "lista vazia nao quebra" {
        $result = @(Get-PrioritizedMarkets -AllMarkets @())
        $result.Count | Should Be 0
    }

    It "todos os tickers aparecem no resultado (nada se perde)" {
        $tickers = 1..30 | ForEach-Object { New-Ticker "T$_" (50 - ($_ * 3)) }
        $result = @(Get-PrioritizedMarkets -AllMarkets $tickers -GainerThreshold 10 -LoserThreshold -10)
        $result.Count | Should Be 30
    }
}
