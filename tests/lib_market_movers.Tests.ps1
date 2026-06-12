# lib_market_movers.Tests.ps1 -- TDD universo dinamico top movers
# 2026-06-09: prioriza gainers/losers (vol spike real) sobre quiet tickers

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-Ticker {
    param([string]$Symbol, [double]$Change24h, [double]$Price = 1, [double]$Volume = 1000)
    [PSCustomObject]@{ symbol = $Symbol; change_24h = $Change24h; price = $Price; volume_24h = $Volume }
}

Describe "MarketMovers: Get-MarketMovers (classifica por 24h change)" {
    It "separa gainers (+10%+) de losers (-10%-)" {
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
        $movers = Get-MarketMovers -Tickers $tickers -GainerThreshold 10 -LoserThreshold -10
        @($movers.gainers).Count | Should Be 3
        @($movers.losers).Count | Should Be 3
    }

    It "ordena gainers por magnitude descrescente" {
        $tickers = @(
            (New-Ticker "A" 15),
            (New-Ticker "B" 45),
            (New-Ticker "C" 25)
        )
        $movers = Get-MarketMovers -Tickers $tickers -GainerThreshold 10
        $movers.gainers[0].symbol | Should Be "B"
        $movers.gainers[1].symbol | Should Be "C"
        $movers.gainers[2].symbol | Should Be "A"
    }

    It "ordena losers por magnitude (mais negativo primeiro)" {
        $tickers = @(
            (New-Ticker "X" -15),
            (New-Ticker "Y" -45),
            (New-Ticker "Z" -25)
        )
        $movers = Get-MarketMovers -Tickers $tickers -LoserThreshold -10
        $movers.losers[0].symbol | Should Be "Y"
        $movers.losers[1].symbol | Should Be "Z"
        $movers.losers[2].symbol | Should Be "X"
    }

    It "respeita topCount (máximo 15 gainers, máximo 15 losers)" {
        $tickers = 1..30 | ForEach-Object { New-Ticker "T$_" (50 - $_) }
        $movers = Get-MarketMovers -Tickers $tickers -GainerThreshold 10 -TopCount 10
        @($movers.gainers).Count | Should Be 10
    }

    It "ignora tickers sem change_24h" {
        $tickers = @(
            (New-Ticker "GOOD" 25),
            [PSCustomObject]@{ symbol = "BAD"; price = 1 }  # sem change_24h
        )
        $movers = Get-MarketMovers -Tickers $tickers -GainerThreshold 10
        @($movers.gainers).Count | Should Be 1
    }

    It "lista vazia nao quebra" {
        $movers = Get-MarketMovers -Tickers @()
        @($movers.gainers).Count | Should Be 0
        @($movers.losers).Count | Should Be 0
    }
}

Describe "MarketMovers: Get-ScanPriority (ordena scan: movers primeiro, quiet depois)" {
    It "prioriza gainers + losers sobre quiet" {
        $tickers = @(
            (New-Ticker "MOVER1" 45),
            (New-Ticker "MOVER2" -35),
            (New-Ticker "QUIET1" 5),
            (New-Ticker "QUIET2" -3),
            (New-Ticker "QUIET3" 2)
        )
        $priority = Get-ScanPriority -Tickers $tickers -GainerThreshold 10 -LoserThreshold -10
        $priority.prioritized[0].symbol | Should Be "MOVER1"
        $priority.prioritized[1].symbol | Should Be "MOVER2"
        @($priority.prioritized[2..4].symbol) | Should Contain "QUIET1"
        $priority.movers_count | Should Be 2
        $priority.quiet_count | Should Be 3
        $priority.total | Should Be 5
    }

    It "reordena: lider sempre top gainer, segundo lugar top loser" {
        $tickers = @(
            (New-Ticker "MEGA_UP" 150),
            (New-Ticker "MEGA_DOWN" -120),
            (New-Ticker "SMALL_UP" 12)
        )
        $priority = Get-ScanPriority -Tickers $tickers -GainerThreshold 10 -LoserThreshold -10 -TopMoversCount 5
        $priority.prioritized[0].symbol | Should Be "MEGA_UP"
        $priority.prioritized[1].symbol | Should Be "MEGA_DOWN"
        $priority.prioritized[2].symbol | Should Be "SMALL_UP"
    }

    It "quiet tickers (entre -10% e +10%) vao pro final" {
        $tickers = @(
            (New-Ticker "UP_QUIET" 8),
            (New-Ticker "DOWN_QUIET" -5),
            (New-Ticker "UP_MOVER" 25)
        )
        $priority = Get-ScanPriority -Tickers $tickers
        $priority.quiet_count | Should Be 2
        $priority.movers_count | Should Be 1
        $priority.prioritized[0].symbol | Should Be "UP_MOVER"
    }

    It "ordena quiet por algum critério estável (nao quebra)" {
        $tickers = @(
            (New-Ticker "Q1" 3),
            (New-Ticker "Q2" 5),
            (New-Ticker "Q3" 1)
        )
        $priority = Get-ScanPriority -Tickers $tickers
        @($priority.prioritized).Count | Should Be 3
    }

    It "totais batem: movers + quiet = total" {
        $tickers = 1..50 | ForEach-Object { New-Ticker "T$_" (40 - $_) }
        $priority = Get-ScanPriority -Tickers $tickers -TopMoversCount 10
        ($priority.movers_count + $priority.quiet_count) | Should Be $priority.total
    }
}
