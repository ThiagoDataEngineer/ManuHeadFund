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
#
# 2026-08-23: achado real #2 -- CoinEx-PlaceMultiExitLadder (gem_executor.ps1)
# colocava um SEGUNDO SL nativo na corretora usando o template generico de
# exit-ladder (sl_levels trigger=-50, ou seja -50% do entry), sobrepondo o SL
# correto que Set-PositionProtection ja tinha colocado segundos antes. Essa
# funcao, cega a ISSO, via o SL de -50% como "a corretora esta certa, o
# journal que esta atrasado" e reconciliava pro valor errado -- RENDERUSDT/
# BTCUSDT/INJUSDT tiveram o journal puxado pra um SL bem mais frouxo que o
# pretendido, ampliando a perda real quando bateu. O bug de origem ja foi
# corrigido (commit 3ae94c1, sl_levels removido do ladder), mas esta funcao
# continuava sem defesa contra qualquer bug FUTURO do mesmo tipo (qualquer
# rotina que escreva um SL errado direto na corretora). Fix: piso de sanidade
# -- reconciliacao so acontece se o real estiver DENTRO de um raio razoavel
# do journal (MaxSanityGapPct, relativo ao proprio JournalStop -- agnostico
# de escala de preco). Gap maior que isso e tratado como suspeito (bug/
# corrupcao), nao como "atraso legitimo do journal" -- retorna $false
# (nao reconcilia) e o caller decide alertar.

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

    .PARAMETER MaxSanityGapPct
    2026-08-23. Gap maximo (fracao do JournalStop, ex: 0.20 = 20%) tolerado
    entre journal e real antes de recusar a reconciliacao por suspeita de bug
    (SL errado escrito na corretora por outra rotina, nao "journal atrasado").
    Default 0.20 -- gaps legitimos de journal atrasado (origin corrigido em
    ciclo seguinte, push que falhou 1x) ficam bem abaixo disso; o caso real
    que motivou o piso (SL do ladder a -50% do entry) e uma ordem de
    magnitude maior. 0 desativa o piso (comportamento pre-existente).

    .OUTPUTS
    [bool] $true = journal esta a frente (precisa reconciliar pro real)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double] $JournalStop,
        [Parameter(Mandatory)] [double] $RealStop,
        [double] $MaxSanityGapPct = 0.20
    )

    if ($RealStop -le 0) { return $false }  # sem SL real confirmado, nao mexe

    $sideUpper = $Side.ToUpper()
    $ahead = if ($sideUpper -eq "LONG") {
        # LONG: stop sobe com o lucro. Journal "a frente" = journal > real
        # (journal ja acha que subiu, mas a corretora ainda esta no valor antigo).
        ($JournalStop -gt $RealStop)
    } else {
        # SHORT: stop desce com o lucro. Journal "a frente" = journal < real.
        ($JournalStop -lt $RealStop)
    }
    if (-not $ahead) { return $false }

    if ($MaxSanityGapPct -gt 0 -and $JournalStop -gt 0) {
        $gapPct = [Math]::Abs($JournalStop - $RealStop) / $JournalStop
        if ($gapPct -gt $MaxSanityGapPct) { return $false }
    }

    return $true
}

# ─────────────────────────────────────────────────────────────────────────
# Get-JournalStopSanityGap (PURA) -- calcula o gap %, pro caller decidir se
# aciona alerta quando a reconciliacao e recusada por suspeita (nao so
# silenciosamente ignora).
# ─────────────────────────────────────────────────────────────────────────
function Get-JournalStopSanityGap {
    <#
    .SYNOPSIS
    Retorna o gap percentual absoluto entre JournalStop e RealStop, relativo
    ao JournalStop. Uso: caller decide alertar quando Test-JournalStopAhead
    OfExchange recusa reconciliar por suspeita (gap grande demais).

    .OUTPUTS
    [double] gap fracionario (ex: 0.35 = 35%). 0 se JournalStop<=0.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param(
        [Parameter(Mandatory)] [double] $JournalStop,
        [Parameter(Mandatory)] [double] $RealStop
    )
    if ($JournalStop -le 0) { return 0.0 }
    return [Math]::Abs($JournalStop - $RealStop) / $JournalStop
}
