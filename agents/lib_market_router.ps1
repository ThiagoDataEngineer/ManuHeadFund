# lib_market_router.ps1 -- Decide spot vs futures routing pra trade execution.
#
# Hoje:
#   - orchestrator_v6 SO opera futures
#   - gem_executor opera spot OR futures (auto-detect via CoinEx-HasFuturesMarket)
#
# Esta lib centraliza a decisao de routing por mode + availability:
#   - GEM: prefere spot (sizing pequeno, sem leverage = risco controlado)
#   - TIER_A/STANDARD: prefere futures (leverage + margem isolada + stop nativo)
#   - BLUE_CHIP: futures se disponivel, fallback spot
#
# ONDA 2.3 wire integration: orchestrator_v6 vai chamar Get-RouteForMode e
# rotear ordem pra spot_executor OU futures_executor (futures eh padrao atual).
# Implementation completa do spot_executor: proxima sessao.


function Resolve-MarketRoute {
    # Pure: decide route baseado em availability + preference.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Market,
        [Parameter(Mandatory)] [bool] $SpotAvailable,
        [Parameter(Mandatory)] [bool] $FuturesAvailable,
        [switch] $PreferSpot
    )
    if (-not $SpotAvailable -and -not $FuturesAvailable) {
        return [PSCustomObject]@{
            market = $Market; route = "none"; wallet = "none"
            reason = "no_route_available"
        }
    }
    if ($SpotAvailable -and -not $FuturesAvailable) {
        return [PSCustomObject]@{ market=$Market; route="spot"; wallet="spot"; reason="futures_unavailable" }
    }
    if ($FuturesAvailable -and -not $SpotAvailable) {
        return [PSCustomObject]@{ market=$Market; route="futures"; wallet="futures"; reason="spot_unavailable" }
    }
    # Ambos disponiveis
    if ($PreferSpot) {
        return [PSCustomObject]@{ market=$Market; route="spot"; wallet="spot"; reason="prefer_spot" }
    }
    return [PSCustomObject]@{ market=$Market; route="futures"; wallet="futures"; reason="default_futures" }
}


function Get-RouteForMode {
    # Aplica regras por mode + availability.
    # GEM      -> spot prefered (small size, no leverage)
    # TIER_A   -> futures prefered (leverage controlado)
    # BLUE_CHIP-> futures, fallback spot
    # STANDARD -> default (futures)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [bool] $SpotAvailable,
        [Parameter(Mandatory)] [bool] $FuturesAvailable,
        [string] $Market = ""
    )
    $preferSpot = ($Mode -eq "GEM")
    if ($Mode -eq "BLUE_CHIP" -and -not $FuturesAvailable -and $SpotAvailable) {
        $preferSpot = $true
    }
    return Resolve-MarketRoute -Market $Market -SpotAvailable $SpotAvailable -FuturesAvailable $FuturesAvailable -PreferSpot:$preferSpot
}
