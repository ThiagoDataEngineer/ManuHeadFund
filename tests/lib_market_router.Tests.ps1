# lib_market_router.Tests.ps1 -- TDD market routing decision (spot vs futures).
# Pester 3.x.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_market_router.ps1")


Describe "Resolve-MarketRoute" {
    It "Market FUTURES-only retorna route futures" {
        $r = Resolve-MarketRoute -Market "BTCUSDT" -SpotAvailable $false -FuturesAvailable $true
        $r.route | Should Be "futures"
        $r.wallet | Should Be "futures"
    }
    It "Market SPOT-only retorna route spot" {
        $r = Resolve-MarketRoute -Market "EXOTICUSDT" -SpotAvailable $true -FuturesAvailable $false
        $r.route | Should Be "spot"
        $r.wallet | Should Be "spot"
    }
    It "Market em AMBOS: futures preferido por default" {
        $r = Resolve-MarketRoute -Market "BTCUSDT" -SpotAvailable $true -FuturesAvailable $true
        $r.route | Should Be "futures"
    }
    It "Market em ambos com PreferSpot=true retorna spot" {
        $r = Resolve-MarketRoute -Market "BTCUSDT" -SpotAvailable $true -FuturesAvailable $true -PreferSpot
        $r.route | Should Be "spot"
    }
    It "Market nenhum: route none + reason" {
        $r = Resolve-MarketRoute -Market "NONE" -SpotAvailable $false -FuturesAvailable $false
        $r.route | Should Be "none"
        $r.reason | Should Match "no_route_available"
    }
}


Describe "Get-RouteForMode" {
    It "Mode GEM force spot (gem_executor pattern)" {
        $r = Get-RouteForMode -Mode "GEM" -SpotAvailable $true -FuturesAvailable $true
        $r.route | Should Be "spot"
    }
    It "Mode TIER_A force futures (leverage controlado)" {
        $r = Get-RouteForMode -Mode "TIER_A" -SpotAvailable $true -FuturesAvailable $true
        $r.route | Should Be "futures"
    }
    It "Mode BLUE_CHIP em market sem futures cai pra spot" {
        $r = Get-RouteForMode -Mode "BLUE_CHIP" -SpotAvailable $true -FuturesAvailable $false
        $r.route | Should Be "spot"
    }
    It "Mode STANDARD usa default (futures preferido)" {
        $r = Get-RouteForMode -Mode "STANDARD" -SpotAvailable $true -FuturesAvailable $true
        $r.route | Should Be "futures"
    }
}
