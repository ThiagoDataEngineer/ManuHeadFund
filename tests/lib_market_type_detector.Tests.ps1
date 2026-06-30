# Tests para lib_market_type_detector.ps1 (Pester 3.4.0)
# TDD: deteccao automatica FUTURES vs SPOT, sem whitelist hardcoded.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_market_type_detector.ps1")

# Mock de API CoinEx pra testes
$script:__futuresCacheAt = $null
$script:__futuresCache = @()

Describe "Get-AvailableFuturesMarkets" {
    It "Retorna array de mercados (mock)" {
        # Simula resposta da API
        $script:__futuresCache = @("BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT")
        $script:__futuresCacheAt = Get-Date

        $m = Get-AvailableFuturesMarkets
        $m.Count | Should Be 5
        ($m -contains "BTCUSDT") | Should Be $true
        ($m -contains "ETHUSDT") | Should Be $true
    }

    It "Cache persiste (nao refetch antes de CacheMinutes)" {
        $script:__futuresCache = @("BTCUSDT")
        $script:__futuresCacheAt = Get-Date

        $m1 = Get-AvailableFuturesMarkets -CacheMinutes 60
        $m2 = Get-AvailableFuturesMarkets -CacheMinutes 60

        # Ambas devem retornar cache (mesmo que chamadas 2x)
        $m1.Count | Should Be 1
        $m2.Count | Should Be 1
    }
}

Describe "Test-MarketHasFutures" {
    BeforeAll {
        $script:__futuresCache = @("BTCUSDT", "ETHUSDT", "SOLUSDT")
        $script:__futuresCacheAt = Get-Date
    }

    It "BTCUSDT tem FUTURES" {
        Test-MarketHasFutures -Market "BTCUSDT" | Should Be $true
    }

    It "ETHUSDT tem FUTURES" {
        Test-MarketHasFutures -Market "ETHUSDT" | Should Be $true
    }

    It "SOLUSDT tem FUTURES" {
        Test-MarketHasFutures -Market "SOLUSDT" | Should Be $true
    }

    It "AIUSDT NAO tem FUTURES (nao na lista)" {
        Test-MarketHasFutures -Market "AIUSDT" | Should Be $false
    }

    It "UNKNOWNUSDT NAO tem FUTURES" {
        Test-MarketHasFutures -Market "UNKNOWNUSDT" | Should Be $false
    }
}

Describe "Get-MarketType (rota automatica)" {
    BeforeAll {
        $script:__futuresCache = @("BTCUSDT", "ETHUSDT")
        $script:__futuresCacheAt = Get-Date
    }

    It "BTCUSDT -> FUTURES" {
        Get-MarketType -Market "BTCUSDT" | Should Be "FUTURES"
    }

    It "ETHUSDT -> FUTURES" {
        Get-MarketType -Market "ETHUSDT" | Should Be "FUTURES"
    }

    It "AIUSDT (SPOT) -> SPOT" {
        Get-MarketType -Market "AIUSDT" | Should Be "SPOT"
    }

    It "INUSDT (SPOT) -> SPOT" {
        Get-MarketType -Market "INUSDT" | Should Be "SPOT"
    }
}
