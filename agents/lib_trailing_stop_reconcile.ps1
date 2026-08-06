# lib_trailing_stop_reconcile.ps1 -- decisao PURA de reconciliacao journal-vs-corretora.
#
# 2026-08-06: achado real em producao -- ARBUSDT/NEARUSDT/OPUSDT tiveram
# origin corrigido (backfill) DEPOIS de varios ciclos com origin=UNKNOWN,
# onde Resolve-TrailingDecision ja calculava e gravava stopCurrent no
# journal mas NUNCA empurrava pra CoinEx (tuIsFutures era false, pulava o
# push -- ver trailing_stop_monitor.ps1). Resultado: journal "achava" que
# o stop ja tinha avancado, entao o proximo ciclo (origin ja correto)
# comparava contra esse valor adiantado e decidia "stop_calculado_nao_
# melhora" -- nunca reenviava, corretora ficava presa no valor antigo pra
# sempre. Esta funcao decide QUANDO reconciliar (journal a frente do
# real, nunca visto pela corretora) sem nunca afrouxar o que ja esta
# correto.

# ─────────────────────────────────────────────────────────────────────────
# Test-JournalStopAheadOfExchange (PURA) -- decide se o stopCurrent do
# journal esta "a frente" do SL real na corretora (nunca foi enviado).
# ─────────────────────────────────────────────────────────────────────────
function Test-JournalStopAheadOfExchange {
    <#
    .SYNOPSIS
    Decide (pura, sem I/O) se o stopCurrent do journal precisa ser
    reconciliado pro valor real da corretora antes do motor decidir.

    .PARAMETER Side
    "LONG" | "SHORT".

    .PARAMETER JournalStop
    stopCurrent gravado no journal (trailing_state).

    .PARAMETER RealStop
    stop_loss_price real, confirmado via CoinEx-GetPendingPositions.

    .OUTPUTS
    [bool] $true = journal esta a frente (precisa reconciliar pro real)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double] $JournalStop,
        [Parameter(Mandatory)] [double] $RealStop
    )

    if ($RealStop -le 0) { return $false }  # sem SL real confirmado, nao mexe

    $sideUpper = $Side.ToUpper()
    if ($sideUpper -eq "LONG") {
        # LONG: stop sobe com o lucro. Journal "a frente" = journal > real
        # (journal ja acha que subiu, mas a corretora ainda esta no valor antigo).
        return ($JournalStop -gt $RealStop)
    } else {
        # SHORT: stop desce com o lucro. Journal "a frente" = journal < real.
        return ($JournalStop -lt $RealStop)
    }
}
