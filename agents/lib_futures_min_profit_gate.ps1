# lib_futures_min_profit_gate.ps1 -- Piso minimo de lucro antes de liberar
# PARTIAL/EXIT do motor de trailing unificado em posicoes FUTURES (LONG ou
# SHORT).
#
# 2026-08-28: mesmo piso ja aplicado em SPOT (lib_trailing_spot_partial_exit.ps1
# Register-SpotPartialExit -MinProfitUsd) -- owner pediu estender pra FUTURES,
# ambos os lados. Achado que motivou o piso original: trades SPOT subindo,
# nada travando, devolvendo tudo ate o stop; owner pensou em $15 mas dado
# real (Supabase trade_outcomes) mostrou que $15-19 e' o TETO observado de
# lucro em $ em trades SPOT, nao um piso folgado -- ajustado pra $5-8
# (default $6). Mesmo raciocinio/numero se aplica aqui.
#
# 2026-09-03 FIX CRITICO: achado real via auditoria profunda pos-3-dias-de-
# fixes-sem-resultado ("ainda morrendo quase todas com stop, mesmo passando
# do minimo de $6/7, e depois volta tudo") -- confirmado com 5h de log real:
# o motor de reversao (corrigido em 92a4bff/8d3ecde) estava DETECTANDO
# reversao real e decidindo EXIT corretamente, MAS este piso de $6 fixo
# bloqueava 9 de 9 vezes observadas (lucro real $0.65-$3.75, sempre abaixo
# de $6 -- trades tem margem de so ~$90-150, entao um sinal de reversao
# CEDO o suficiente pra ser util aparece com lucro em dolar ainda pequeno).
# Os 2 gates se anulavam por construcao: quanto melhor o motor de reversao
# detecta cedo, menor o $ naquele momento, mais certo o veto deste piso.
# Fix: quando a decisao e' EXIT por REVERSAO CONFIRMADA (ja passou pelo
# crivo de 2+ sinais simultaneos, reversal_exit_signals -- NAO e ruido, e'
# tese de trade invalidada), usa piso em R-multiple (MinProfitRMultiple,
# mesma metrica ja calibrada em MinProfitRMultipleToTighten=0.1R,
# lib_trailing_unified.ps1) em vez de dolar fixo -- risco e' proporcional
# ao tamanho do trade, nao um valor absoluto que so faz sentido pra trades
# grandes. PARTIAL (nao passou por esse crivo, so R-multiple ou reversao
# ISOLADA menos confirmada) continua usando o piso em dolar -- protecao
# contra realizar migalhas de ruido permanece intacta onde fazia sentido
# desde o inicio.

function Test-FuturesMinProfitGate {
    <#
    .SYNOPSIS
    Decide se o lucro atual da posicao FUTURES atinge o piso minimo antes
    de liberar PARTIAL/EXIT real. Funcao pura, testavel.

    .PARAMETER UnrealizedPnlUsd
    PnL nao-realizado real da posicao (CoinEx unrealized_pnl -- ja correto
    pra LONG e SHORT, ja inclui leverage). $null = dado indisponivel.

    .PARAMETER MinProfitUsd
    Piso minimo em dolar (default $6) -- usado quando -Action nao e' "EXIT",
    ou quando -RMultiple nao e' fornecido (preserva 100% o comportamento
    anterior pra callers que nao passam os novos parametros).

    .PARAMETER Action
    Opcional. "EXIT" ativa o piso alternativo em R-multiple (ver -RMultiple)
    -- reflete que EXIT so acontece apos reversao CONFIRMADA (2+ sinais
    simultaneos), um crivo de qualidade que PARTIAL nao tem necessariamente.
    Qualquer outro valor (ou ausente) usa sempre o piso em dolar.

    .PARAMETER RMultiple
    Opcional. R-multiple atual do trade (ganho / risco original em preco).
    So usado quando -Action="EXIT". $null = fail-soft pro piso em dolar
    (dado ausente nao deve travar uma decisao que ja passou por outros
    gates reais).

    .PARAMETER MinProfitRMultiple
    Piso minimo em R-multiple pra EXIT (default 0.1R -- MESMA metrica e
    MESMO valor ja calibrado em MinProfitRMultipleToTighten,
    lib_trailing_unified.ps1 -- consistencia entre os 2 mecanismos que
    decidem "ja ha lucro real o suficiente pra agir").

    .OUTPUTS
    PSCustomObject { allowed, reason }
    #>
    [CmdletBinding()]
    param(
        [Nullable[double]] $UnrealizedPnlUsd = $null,
        [double] $MinProfitUsd = 6.0,
        [string] $Action = "",
        [Nullable[double]] $RMultiple = $null,
        [double] $MinProfitRMultiple = 0.1
    )

    # EXIT por reversao confirmada: usa piso em R-multiple (proporcional ao
    # risco do trade) em vez de dolar fixo -- so quando o dado esta
    # disponivel. RMultiple ausente cai no piso em dolar normal abaixo
    # (fail-soft -- nao inventa criterio novo sem o dado pra sustenta-lo).
    if ($Action -eq "EXIT" -and $null -ne $RMultiple) {
        $r = [double]$RMultiple
        if ($r -lt $MinProfitRMultiple) {
            return [PSCustomObject]@{ allowed = $false; reason = "exit_abaixo_piso_r_multiple (${r}R < ${MinProfitRMultiple}R)" }
        }
        return [PSCustomObject]@{ allowed = $true; reason = "exit_acima_piso_r_multiple" }
    }

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
