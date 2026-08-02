# lib_long_futures_route.ps1 -- decisao PURA de promover LONG pra FUTURES.
#
# 2026-08-02: owner percebeu que LONG nunca abre em futures, so SPOT (Get-
# RouteForMode com modo GEM sempre prefere spot por design -- "sizing
# pequeno sem leverage = risco controlado", agents/lib_market_router.ps1).
# SHORT ja tem um override tardio OBRIGATORIO em Invoke-GemExecute
# (agents/gem_executor.ps1 ~linha 1707: SHORT so existe via futures, sem
# excecao). LONG-futures e OPCIONAL: so promove se o ativo tiver qualidade
# fundamentalista suficiente (FQS BLUE_CHIP ou QUALITY,
# agents/lib_fundamental_quality.ps1 -- mesmo criterio ja usado pro gate
# TIER_A_LIVE/TIER_B_PAPER, nunca conectado ao roteamento em si ate agora).
#
# Logica pura (sem I/O) -- Invoke-GemExecute chama Get-FundamentalScore
# (I/O, le coin_registry.json) e passa so a categoria resultante aqui.

function Test-LongFuturesRouteEligible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [string] $MarketType,       # "SPOT" | "FUTURES" | "NONE"
        [Parameter(Mandatory)] [bool]   $FuturesAvailable,
        [string] $FqsCategory = $null
    )

    if ($Direction -ne "LONG") { return $false }
    if ($MarketType -eq "FUTURES") { return $false }   # ja esta em futures, nada a fazer
    if (-not $FuturesAvailable) { return $false }
    if ($FqsCategory -notin @("BLUE_CHIP", "QUALITY")) { return $false }

    return $true
}
