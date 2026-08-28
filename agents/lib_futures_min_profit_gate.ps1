# lib_futures_min_profit_gate.ps1 -- Piso minimo de lucro EM DOLAR antes de
# liberar PARTIAL/EXIT do motor de trailing unificado em posicoes FUTURES
# (LONG ou SHORT).
#
# 2026-08-28: mesmo piso ja aplicado em SPOT (lib_trailing_spot_partial_exit.ps1
# Register-SpotPartialExit -MinProfitUsd) -- owner pediu estender pra FUTURES,
# ambos os lados. Achado que motivou o piso original: trades SPOT subindo,
# nada travando, devolvendo tudo ate o stop; owner pensou em $15 mas dado
# real (Supabase trade_outcomes) mostrou que $15-19 e' o TETO observado de
# lucro em $ em trades SPOT, nao um piso folgado -- ajustado pra $5-8
# (default $6). Mesmo raciocinio/numero se aplica aqui.
#
# Diferente de SPOT (sempre LONG, PnL calculado manualmente por falta de
# campo pronto), FUTURES ja expoe unrealized_pnl DIRETO na posicao real
# (CoinEx-GetPendingPositions/GetOpenOrders, ver lib_coinex.ps1:709) --
# reusa esse campo (fonte de verdade da corretora, ja inclui leverage e
# lado LONG/SHORT corretamente) em vez de recalcular na mao (evita reabrir
# a classe de bug de formula PnL invertida ja corrigida antes no projeto,
# ver memoria "SUIUSDT SHORT registrado como LONG").

function Test-FuturesMinProfitGate {
    <#
    .SYNOPSIS
    Decide se o lucro NAO-REALIZADO atual da posicao FUTURES atinge o piso
    minimo antes de liberar PARTIAL/EXIT real. Funcao pura, testavel.

    .PARAMETER UnrealizedPnlUsd
    PnL nao-realizado real da posicao (CoinEx unrealized_pnl -- ja correto
    pra LONG e SHORT, ja inclui leverage). $null = dado indisponivel.

    .PARAMETER MinProfitUsd
    Piso minimo em dolar (default $6, mesmo valor decidido pelo owner p/
    SPOT -- consistencia entre os 2 mecanismos).

    .OUTPUTS
    PSCustomObject { allowed, reason }
    #>
    [CmdletBinding()]
    param(
        [Nullable[double]] $UnrealizedPnlUsd = $null,
        [double] $MinProfitUsd = 6.0
    )

    # Dado indisponivel: fail-OPEN (nao bloqueia) -- ausencia de PnL nao e'
    # prova de que o trade nao tem lucro, so falta de informacao. Mesmo
    # principio do gate de fundamental (Resolve-NoFundamentalSizingPenalty):
    # nao usar dado ausente pra travar decisao que ja passou por outros
    # gates reais.
    if ($null -eq $UnrealizedPnlUsd) {
        return [PSCustomObject]@{ allowed = $true; reason = "pnl_indisponivel_fail_open" }
    }

    $pnl = [double]$UnrealizedPnlUsd
    if ($pnl -lt $MinProfitUsd) {
        return [PSCustomObject]@{ allowed = $false; reason = "lucro_abaixo_piso_minimo (`$$([math]::Round($pnl,2)) < `$$MinProfitUsd)" }
    }

    return [PSCustomObject]@{ allowed = $true; reason = "acima_piso_minimo" }
}
