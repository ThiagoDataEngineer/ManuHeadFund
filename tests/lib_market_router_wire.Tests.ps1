# lib_market_router_wire.Tests.ps1 -- TDD pra integracao market_router + CoinEx availability.
# Pester 3.x.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"
. (Join-Path $agentsDir "lib_market_router.ps1")
. (Join-Path $agentsDir "lib_market_router_wire.ps1")

# Stubs CoinEx pra isolar test
function CoinEx-HasFuturesMarket { param($m) if ($m -in @("BTCUSDT","ETHUSDT","INJUSDT")) { $true } else { $false } }
function CoinEx-HasSpotMarket { param($m) if ($m -in @("BTCUSDT","ETHUSDT","NEWALTUSDT")) { $true } else { $false } }


Describe "Get-GemRouteForMarket - consolidate gem_executor pattern" {
    It "GEM em market spot-only retorna spot" {
        $r = Get-GemRouteForMarket -Market "NEWALTUSDT"  # spot=$true futures=$false (stub)
        $r.route | Should Be "spot"
        $r.market_type | Should Be "SPOT"
    }
    It "GEM em market ambos: prefere spot (gem pattern)" {
        $r = Get-GemRouteForMarket -Market "BTCUSDT"
        $r.route | Should Be "spot"
        $r.market_type | Should Be "SPOT"
    }
    It "GEM em market futures-only retorna futures" {
        $r = Get-GemRouteForMarket -Market "INJUSDT"  # spot=$false futures=$true (stub)
        $r.route | Should Be "futures"
        $r.market_type | Should Be "FUTURES"
    }
    It "GEM em market delisted retorna none" {
        $r = Get-GemRouteForMarket -Market "DELISTEDUSDT"
        $r.route | Should Be "none"
    }
    It "Override PreferFutures forca futures mesmo em GEM mode" {
        $r = Get-GemRouteForMarket -Market "BTCUSDT" -PreferFutures
        $r.route | Should Be "futures"
        $r.market_type | Should Be "FUTURES"
    }
}


Describe "Add-MarketRouteToContext - orchestrator fase 0 helper" {
    It "Adiciona market_route ao context" {
        $ctx = [PSCustomObject]@{ market = "BTCUSDT"; macro = "ok" }
        $updated = Add-MarketRouteToContext -Context $ctx -Mode "TIER_A"
        $updated.market_route | Should Not Be $null
        $updated.market_route.route | Should Be "futures"
        $updated.market_route.market | Should Be "BTCUSDT"
        # Preserva campos existentes
        $updated.macro | Should Be "ok"
    }
    It "Mode GEM em market spot+futures prefere spot" {
        $ctx = [PSCustomObject]@{ market = "BTCUSDT" }
        $updated = Add-MarketRouteToContext -Context $ctx -Mode "GEM"
        $updated.market_route.route | Should Be "spot"
    }
    It "Market sem futures cai pra spot" {
        $ctx = [PSCustomObject]@{ market = "NEWALTUSDT" }
        $updated = Add-MarketRouteToContext -Context $ctx -Mode "TIER_A"
        $updated.market_route.route | Should Be "spot"
    }
    It "Market sem nada (delisted): route none + reason" {
        $ctx = [PSCustomObject]@{ market = "DELISTEDUSDT" }
        $updated = Add-MarketRouteToContext -Context $ctx -Mode "TIER_A"
        $updated.market_route.route | Should Be "none"
        $updated.market_route.reason | Should Match "no_route"
    }
}


Describe "Resolve-MarketRouteLive" {
    It "Market com ambos disponiveis em CoinEx" {
        $r = Resolve-MarketRouteLive -Market "BTCUSDT" -Mode "TIER_A"
        $r.spot_available | Should Be $true
        $r.futures_available | Should Be $true
        $r.route | Should Be "futures"   # default TIER_A
    }
    It "Market spot-only (INJUSDT na verdade tem futures no stub) - usar NEWALT" {
        $r = Resolve-MarketRouteLive -Market "NEWALTUSDT" -Mode "GEM"
        $r.spot_available | Should Be $true
        $r.futures_available | Should Be $false
        $r.route | Should Be "spot"
    }
    It "Mode GEM em market ambos: prefere spot (gem pattern)" {
        $r = Resolve-MarketRouteLive -Market "BTCUSDT" -Mode "GEM"
        $r.route | Should Be "spot"
    }
    It "Market sem nenhum (delisted) retorna route none" {
        $r = Resolve-MarketRouteLive -Market "DELISTEDUSDT" -Mode "TIER_A"
        $r.route | Should Be "none"
    }
    It "Resposta tem campos necessarios pra orchestrator integrar" {
        $r = Resolve-MarketRouteLive -Market "ETHUSDT" -Mode "TIER_A"
        $r.PSObject.Properties["route"] | Should Not Be $null
        $r.PSObject.Properties["wallet"] | Should Not Be $null
        $r.PSObject.Properties["spot_available"] | Should Not Be $null
        $r.PSObject.Properties["futures_available"] | Should Not Be $null
        $r.PSObject.Properties["market"] | Should Not Be $null
    }
}
