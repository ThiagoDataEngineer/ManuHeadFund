# lib_trailing_spot_partial_exit.ps1 -- Execucao REAL de PARTIAL/EXIT do
# motor de trailing unificado (Resolve-TrailingDecision) para posicoes SPOT.
#
# 2026-08-26: achado real em producao (owner reportou "vejo +10%, +30%, e
# volta pro stop sem pegar nada"). Causa raiz: PARTIAL_EXIT_EXECUTION_ENABLED.flag
# (lib_trailing_partial_exit.ps1, 2026-07-31) so cobre FUTURES ($tuIsFutures
# em scripts/trailing_stop_monitor.ps1:464) -- decisao de escopo de origem
# ("SPOT fica pra fase seguinte, escopo menor"), nunca fechada. Flagrado ao
# vivo: BMTUSDT +12.34% de ganho, Resolve-TrailingDecision recomendou
# PARTIAL (size_pct=0.75), mas nada executou -- SPOT nao tem o recurso
# nativo de "ladder de TP" que FUTURES tem (posicao com multiplos niveis),
# entao o mecanismo de lib_trailing_partial_exit.ps1 nao se aplica aqui.
#
# Diferente do ladder nativo (a corretora executa cada nivel sozinha,
# resolvendo o problema "size_pct e stateless" de Get-ExitDecision sem
# depender do pipeline rodar no momento exato), SPOT precisa de venda a
# mercado REAL agora -- e' o unico mecanismo disponivel (CoinEx spot nao tem
# TP/SL nativo multi-nivel atrelado a posicao, so ordens soltas). Isso reabre
# o problema stateless: se a recomendacao PARTIAL persistir por varios ciclos
# (confirmado real com DOGEUSDT em FUTURES, size_pct=0.75 por >1h sem mudar),
# vender ingenuamente a cada ciclo esvaziaria a posicao. Fix: idempotencia
# por NIVEL (nao por posicao inteira como o ladder) -- registra "ja vendi a
# fracao recomendada para este profile/size_pct" e so vende de novo se o
# motor recomendar uma fracao ADICIONAL maior que a ja vendida.
#
# Dependencias (dot-source pelo caller):
#   agents/lib_coinex.ps1        (CoinEx-PlaceSpotOrder, CoinEx-GetTicker)
#   agents/lib_state_store.ps1   (Get-StateRecords/Save-StateRecords)
#   agents/lib_trailing.ps1      (Close-TrailingPosition, so para EXIT)

function Get-SpotPartialExitState {
    <#
    .SYNOPSIS
    Fracao ja realizada (0..1) da posicao original para este market via
    execucao real de PARTIAL. 0 = nada vendido ainda por este mecanismo.
    Fail-soft: qualquer falha de leitura retorna 0 (nunca bloqueia, no
    pior caso repete uma venda -- mitigado pelo caller comparando fracoes).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market)

    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return 0.0 }
    try {
        $rows = @(Get-StateRecords -Table "spot_partial_exits" -Filter @{ market = $Market; active = $true })
        if ($rows.Count -eq 0) { return 0.0 }
        $maxPct = ($rows | ForEach-Object { [double]$_.cumulative_pct } | Measure-Object -Maximum).Maximum
        return [double]$maxPct
    } catch {
        return 0.0
    }
}

function Save-SpotPartialExitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $CumulativePct,
        [string] $Reason = ""
    )
    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    try {
        Save-StateRecords -Table "spot_partial_exits" -Records @([PSCustomObject]@{
            market         = $Market
            active         = $true
            cumulative_pct = $CumulativePct
            reason         = $Reason
            updated_at     = (Get-Date -Format "o")
        })
        return $true
    } catch {
        return $false
    }
}

function Remove-SpotPartialExitState {
    <#
    .SYNOPSIS
    Desativa o registro quando a posicao fecha -- mesmo bug de "registro
    fantasma herdado por posicao nova no mesmo market" ja corrigido para o
    ladder de FUTURES (Remove-PartialExitLadder, 2026-08-06) se aplicaria
    aqui sem isso.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market)

    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    try {
        $rows = @(Get-StateRecords -Table "spot_partial_exits" -Filter @{ market = $Market })
        $activeRows = @($rows | Where-Object { $_.active -eq $true })
        if ($activeRows.Count -eq 0) { return $true }
        foreach ($r in $activeRows) {
            $updated = [PSCustomObject]@{
                id             = $r.id
                market         = $r.market
                active         = $false
                cumulative_pct = $r.cumulative_pct
                reason         = $r.reason
                updated_at     = $r.updated_at
            }
            Save-StateRecords -Table "spot_partial_exits" -Records @($updated) -PrimaryKey "id" | Out-Null
        }
        return $true
    } catch {
        return $false
    }
}

function Register-SpotPartialExit {
    <#
    .SYNOPSIS
    Executa PARTIAL real (venda a mercado) para uma posicao SPOT, com
    idempotencia por fracao acumulada (nao vende de novo se o size_pct
    recomendado ja foi coberto por uma venda anterior).

    .PARAMETER Market
    .PARAMETER SizePct
    Fracao da posicao ORIGINAL recomendada por Resolve-TrailingDecision
    (0..1). Semantica igual ao ladder de FUTURES: "quanto deveria ja ter
    saido no total", nao "quanto vender agora" -- so a fracao ADICIONAL
    (SizePct - fracao_ja_vendida) e executada.
    .PARAMETER RealQty
    Saldo real disponivel na corretora (base currency) -- ground truth da
    quantidade, mesmo principio de lib_exit_intelligence_auto.ps1.
    .PARAMETER Reason
    Motivo da decisao (profile_selected/reason de Resolve-TrailingDecision),
    so para log/auditoria.

    .OUTPUTS
    PSCustomObject { success, reason, sold_qty }
    reason: "ok" | "already_covered" | "qty_zero" | "sell_failed" | erro
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $SizePct,
        [Parameter(Mandatory)] [double] $RealQty,
        [string] $Reason = ""
    )

    if ($SizePct -le 0) {
        return [PSCustomObject]@{ success = $false; reason = "size_pct_invalido"; sold_qty = 0.0 }
    }
    if ($RealQty -le 0) {
        return [PSCustomObject]@{ success = $false; reason = "qty_zero"; sold_qty = 0.0 }
    }

    $alreadyCoveredPct = Get-SpotPartialExitState -Market $Market
    $additionalPct = $SizePct - $alreadyCoveredPct
    if ($additionalPct -le 0) {
        return [PSCustomObject]@{ success = $true; reason = "already_covered"; sold_qty = 0.0 }
    }

    # Fracao ADICIONAL e' sobre o saldo REAL atual (nao sobre a posicao
    # original) -- RealQty ja reflete qualquer venda parcial anterior (o
    # proximo ciclo le o saldo fresco), entao vender additionalPct/(1-ja
    # coberto) do saldo atual entrega a fracao adicional certa da posicao
    # ORIGINAL. Ex: coberto=0.30 ja vendido, novo alvo=0.75 -> falta 0.45
    # da posicao original = 0.45/0.70 = ~64% do que resta no saldo atual.
    $remainingFractionOfOriginal = 1.0 - $alreadyCoveredPct
    $fracOfCurrentBalance = if ($remainingFractionOfOriginal -gt 0) {
        [Math]::Min(1.0, $additionalPct / $remainingFractionOfOriginal)
    } else { 1.0 }

    $sellQty = [math]::Floor($RealQty * $fracOfCurrentBalance * 1e6) / 1e6
    if ($sellQty -le 0) {
        return [PSCustomObject]@{ success = $false; reason = "qty_zero_apos_arredondamento"; sold_qty = 0.0 }
    }

    if (-not (Get-Command CoinEx-PlaceSpotOrder -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ success = $false; reason = "coinex_placespotorder_unavailable"; sold_qty = 0.0 }
    }

    try {
        $r = CoinEx-PlaceSpotOrder -Market $Market -Side "sell" -Type "market" -Amount $sellQty
        $filled = if ($r -and $r.PSObject.Properties['filled_amount']) { [double]$r.filled_amount } else { $sellQty }
    } catch {
        return [PSCustomObject]@{ success = $false; reason = "sell_failed: $($_.Exception.Message)"; sold_qty = 0.0 }
    }

    Save-SpotPartialExitState -Market $Market -CumulativePct $SizePct -Reason $Reason | Out-Null

    return [PSCustomObject]@{ success = $true; reason = "ok"; sold_qty = $filled }
}
