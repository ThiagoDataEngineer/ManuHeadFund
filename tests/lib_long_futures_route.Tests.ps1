# lib_long_futures_route.Tests.ps1 -- TDD
#
# Achado 2026-08-02 (owner, percebendo que LONG nunca abre em futures, so
# SHORT): Get-RouteForMode com modo GEM sempre prefere spot por design.
# SHORT ja tem override tardio OBRIGATORIO em Invoke-GemExecute (SHORT so
# existe via futures). Owner pediu o mesmo tipo de caminho pro LONG "serio"
# -- mas OPCIONAL (nao obrigatorio como o SHORT): so promove LONG pra
# futures quando o ativo tem qualidade fundamentalista suficiente
# (FQS BLUE_CHIP ou QUALITY, mesmo criterio ja usado pro gate
# TIER_A_LIVE/TIER_B_PAPER). Sem automatico -- roda no pipeline JA
# EXISTENTE (gem_scanner_executor_live.ps1, chamado a cada 5min), sem
# aprovacao manual, mesmo padrao dos outros 2 canais (SPOT LONG, FUTURES
# SHORT) que ja rodam sozinhos.

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_long_futures_route.ps1")

Describe "Test-LongFuturesRouteEligible -- promove LONG pra futures so com qualidade suficiente" {

    It "promove: LONG + SPOT atual + futures disponivel + FQS BLUE_CHIP" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "BLUE_CHIP"
        $r | Should Be $true
    }

    It "promove: LONG + SPOT atual + futures disponivel + FQS QUALITY" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "QUALITY"
        $r | Should Be $true
    }

    It "NAO promove: FQS SPECULATIVE (abaixo do piso de qualidade)" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "SPECULATIVE"
        $r | Should Be $false
    }

    It "NAO promove: FQS AVOID (pior categoria)" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "AVOID"
        $r | Should Be $false
    }

    It "NAO promove: FQS null (fail-closed -- erro ao consultar registry mantem SPOT)" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory $null
        $r | Should Be $false
    }

    It "NAO promove: futures indisponivel pro mercado, mesmo com FQS BLUE_CHIP" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $false -FqsCategory "BLUE_CHIP"
        $r | Should Be $false
    }

    It "NAO promove: ja esta em FUTURES (nada a fazer, idempotente)" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "FUTURES" -FuturesAvailable $true -FqsCategory "BLUE_CHIP"
        $r | Should Be $false
    }

    It "NAO promove: direcao SHORT (esse override e so pro LONG -- SHORT ja tem o proprio override obrigatorio em gem_executor.ps1)" {
        $r = Test-LongFuturesRouteEligible -Direction "SHORT" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "BLUE_CHIP"
        $r | Should Be $false
    }

    It "cenario real: BTCUSDT LONG, FQS BLUE_CHIP tipico de major -- promove" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "BLUE_CHIP"
        $r | Should Be $true
    }

    It "cenario real: micro-cap gem LONG sem registry (categoria AVOID por default de Get-FundamentalScore) -- nao promove, mantem SPOT pequeno" {
        $r = Test-LongFuturesRouteEligible -Direction "LONG" -MarketType "SPOT" -FuturesAvailable $true -FqsCategory "AVOID"
        $r | Should Be $false
    }
}
