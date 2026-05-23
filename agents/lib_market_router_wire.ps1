# lib_market_router_wire.ps1 -- Integra Resolve-MarketRoute com CoinEx availability live.
#
# Usage:
#   $r = Resolve-MarketRouteLive -Market "INJUSDT" -Mode "TIER_A"
#   $r.route -> "futures" | "spot" | "none"
#   $r.wallet -> qual wallet usar pra capital
#   $r.spot_available + $r.futures_available -> info bruta CoinEx
#
# Wire em orchestrator_v6: chamado no Fase 0 pra popular context.market_route.
# Downstream usa pra decidir endpoint de execucao.


function Resolve-MarketRouteLive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Mode
    )
    # Probe CoinEx availability (best-effort; functions devem existir em lib_coinex)
    $hasFut = $false
    $hasSpot = $false
    if (Get-Command CoinEx-HasFuturesMarket -ErrorAction SilentlyContinue) {
        try { $hasFut = [bool](CoinEx-HasFuturesMarket $Market) } catch {}
    }
    if (Get-Command CoinEx-HasSpotMarket -ErrorAction SilentlyContinue) {
        try { $hasSpot = [bool](CoinEx-HasSpotMarket $Market) } catch {}
    } else {
        # Fallback heuristico: se nao tem helper, assume spot disponivel se futures tem
        # (CoinEx em geral tem spot pra todo futures USDT)
        $hasSpot = $true
    }

    $route = Get-RouteForMode -Mode $Mode -SpotAvailable $hasSpot -FuturesAvailable $hasFut -Market $Market

    return [PSCustomObject]@{
        market            = $Market
        mode              = $Mode
        spot_available    = $hasSpot
        futures_available = $hasFut
        route             = $route.route
        wallet            = $route.wallet
        reason            = $route.reason
    }
}


function Get-GemRouteForMarket {
    # Helper especifico pra gem_executor: consolidate routing decision.
    # Returns @{route, market_type, wallet} pronto pra usar.
    # PreferFutures override pra force quando user quiser leverage em gem (raro).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [switch] $PreferFutures
    )
    $modeForRoute = if ($PreferFutures) { "TIER_A" } else { "GEM" }
    $route = Resolve-MarketRouteLive -Market $Market -Mode $modeForRoute
    $marketType = switch ($route.route) {
        "spot"    { "SPOT" }
        "futures" { "FUTURES" }
        default   { "NONE" }
    }
    return [PSCustomObject]@{
        market      = $Market
        route       = $route.route
        market_type = $marketType
        wallet      = $route.wallet
        spot_available = $route.spot_available
        futures_available = $route.futures_available
        reason      = $route.reason
    }
}


function Add-MarketRouteToContext {
    # Helper pra orchestrator_v6 fase 0: chama Resolve-MarketRouteLive + anexa
    # ao context retornado. Imutavel-style: cria novo Context com market_route.
    # Wire em Invoke-OrchestratorV6 antes da cascade.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Context,
        [Parameter(Mandatory)] [string] $Mode
    )
    $market = if ($Context.PSObject.Properties['market']) { [string]$Context.market } else { "" }
    if (-not $market) { return $Context }

    $route = Resolve-MarketRouteLive -Market $market -Mode $Mode
    Add-Member -InputObject $Context -MemberType NoteProperty -Name market_route -Value $route -Force
    return $Context
}
