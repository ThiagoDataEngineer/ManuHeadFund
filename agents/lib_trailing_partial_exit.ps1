# lib_trailing_partial_exit.ps1 -- Execucao REAL de saidas parciais (PARTIAL/EXIT)
#
# 2026-07-31: ate agora Resolve-TrailingDecision so LOGAVA a recomendacao
# PARTIAL/EXIT (size_pct, profile_selected) -- nunca executava venda de
# verdade (ver scripts/trailing_stop_monitor.ps1, comentario "SO LOG,
# execucao automatica ainda nao implementada"). Owner pediu execucao real.
#
# Achado critico durante o design: Get-ExitDecision (lib_trailing_policy.ps1)
# e STATELESS -- size_pct retornado e "quanto DEVERIA sobrar" (remaining -
# target_remaining do nivel de R atingido), nao "quanto vender agora".
# Executar isso ingenuamente a cada ciclo de 5min (venda a mercado toda
# vez que a recomendacao aparecer) vende repetidamente sobre o que sobrou
# e esvazia a posicao de forma descontrolada -- confirmado real: DOGEUSDT
# recomendou size_pct=0.75 continuamente por mais de 1h sem mudar.
#
# Solucao: registra um LADDER de saida escalonada NATIVO na corretora
# (CoinEx-PlaceMultiExitLadder, ja em producao real na abertura de
# posicoes novas -- suporta ate 20 TPs por posicao com quantidade parcial
# real, confirmado via teste existente: 30%+30%+40%=100% da posicao).
# A corretora executa cada nivel sozinha quando o preco bate o gatilho --
# resolve o problema "stateless" de raiz (nao depende do pipeline rodar
# no momento exato), e a idempotencia (nao registrar de novo a cada ciclo)
# fica garantida por um registro simples no Supabase (registrei 1x, nao
# "quanto falta vender").
#
# Confirmado real (diagnostico DOGEUSDT 2026-07-31): a posicao ja tem um
# TP "cobre tudo" (take_profit_list com is_all=true, amount=0) -- por isso
# o fluxo SEMPRE cancela esse TP antigo (CoinEx-CancelPositionTakeProfit)
# ANTES de registrar o ladder parcial novo. Se o cancelamento falhar, NAO
# registra o ladder (evita 2 TPs conflitantes / posicao com protecao
# ambigua). O SL nao e tocado por esta funcao -- Resolve-TrailingDecision
# continua cuidando dele via CoinEx-ModifyPositionStopLoss, caminho
# separado e ja validado.
#
# Dependencias (dot-source pelo caller):
#   agents/lib_coinex.ps1                      (CoinEx-PlaceMultiExitLadder)
#   agents/lib_coinex_position_management.ps1  (CoinEx-CancelPositionTakeProfit)
#   agents/lib_state_store.ps1                 (Get-StateRecords/Save-StateRecords,
#                                                usados por Get/Save-PartialExitLadderRegistered)

# ============================================================================
# Get-PartialExitLadderRegistered / Save-PartialExitLadderRegistered
# Idempotencia: registra 1x por posicao (nao "quanto falta vender", so
# "ja registrei o ladder pra essa posicao?"). Persistido no Supabase
# (manuheadfund.partial_exit_ladders) pra sobreviver entre runs do
# GitHub Actions -- mesma classe de fix ja aplicada em gem_position_events/
# llm_usage hoje (CSV/arquivo local nao sobrevive ao runner efemero).
# ============================================================================

function Get-PartialExitLadderRegistered {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market)

    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    try {
        $rows = @(Get-StateRecords -Table "partial_exit_ladders" -Filter @{ market = $Market })
        return (@($rows | Where-Object { $_.active -eq $true }).Count -gt 0)
    } catch {
        return $false
    }
}

function Save-PartialExitLadderRegistered {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [object] $Details
    )

    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    try {
        Save-StateRecords -Table "partial_exit_ladders" -Records @([PSCustomObject]@{
            market      = $Market
            active      = $true
            registered_at = (Get-Date -Format "o")
            levels_json = ($Details | ConvertTo-Json -Depth 6 -Compress)
        })
        return $true
    } catch {
        return $false
    }
}

# ============================================================================
# Register-PartialExitLadder -- ponto de entrada real
# ============================================================================

function Register-PartialExitLadder {
    <#
    .SYNOPSIS
        Registra um ladder de saida parcial REAL na corretora (CoinEx),
        convertendo os "partials" da policy de trailing (at_r/pct) em
        multiplos TPs nativos com quantidade parcial.

    .PARAMETER Position
        PSCustomObject com pelo menos: market, side ("LONG"|"SHORT"),
        entry, open_interest (quantidade total da posicao).

    .PARAMETER Partials
        Array de @{ at_r; pct } -- mesma estrutura de Get-CurrentTrailingPolicy/
        Resolve-ExitPolicy (lib_trailing_baseline.ps1/lib_trailing_policy.ps1).
        pct = fracao da posicao ORIGINAL a fechar quando aquele nivel de R
        for atingido (nao cumulativo -- cada nivel e um qty_pct independente
        do ladder nativo da CoinEx).

    .PARAMETER StopDistance
        Distancia entre entry e o stop inicial (risk / "1R" em preco
        absoluto) -- usada por _MultiLadder-ResolvePrice pra resolver o
        preco de cada nivel rr_multiple.

    .OUTPUTS
        PSCustomObject { success, reason, ladder_result }
        reason: "ok" | "already_registered" | "no_partials" | "cancel_tp_failed"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Position,
        # Nao-mandatory de proposito: [array] Mandatory rejeita @() no bind
        # (PowerShell trata array vazio como "nao fornecido"), impedindo o
        # caller de passar explicitamente "sem partials" -- checagem manual
        # abaixo cobre tanto @() quanto $null.
        [array]  $Partials = @(),
        [Parameter(Mandatory)] [double] $StopDistance
    )

    $market = [string]$Position.market

    if (@($Partials).Count -eq 0) {
        return [PSCustomObject]@{ success = $false; reason = "no_partials"; ladder_result = $null }
    }

    if (Get-PartialExitLadderRegistered -Market $market) {
        return [PSCustomObject]@{ success = $true; reason = "already_registered"; ladder_result = $null }
    }

    if (-not (Get-Command CoinEx-CancelPositionTakeProfit -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ success = $false; reason = "cancel_tp_unavailable"; ladder_result = $null }
    }
    if (-not (Get-Command CoinEx-PlaceMultiExitLadder -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ success = $false; reason = "ladder_fn_unavailable"; ladder_result = $null }
    }

    # 2026-07-31 FIX (causa raiz de "ladder_call_failed"): _MultiLadder-ResolvePrice
    # le $Level.PSObject.Properties['type'] -- em hashtable puro (@{...}) essa
    # colecao expoe membros do PSObject (Keys/Values/Count), NAO as chaves do
    # hashtable, entao $type ficava sempre $null e caia no branch "default"
    # (throw "tipo de level desconhecido"). PSCustomObject funciona corretamente
    # (confirmado via teste isolado). CoinEx-PlaceMultiExitLadder ja usada em
    # producao (abertura de posicao) sempre recebeu PSCustomObject -- por isso
    # o bug so apareceu agora, na 1a chamada com hashtable.
    $tpLevels = @($Partials | ForEach-Object {
        [PSCustomObject]@{ type = "rr_multiple"; rr_multiple = [double]$_.at_r; qty_pct = [double]$_.pct * 100 }
    })

    # stop_distance embutido no Ladder -- _MultiLadder-ResolvePrice usa isso
    # pra resolver o preco de cada nivel "rr_multiple" (1R = StopDistance em
    # preco absoluto). Sem isso, cairia no fallback de inferir do 1o SL, que
    # nao existe aqui (sl_levels vazio de proposito -- SL nao e tocado por
    # esta funcao).
    $ladder = [PSCustomObject]@{
        template_id    = "partial_exit_$market"
        tp_levels      = $tpLevels
        sl_levels      = @()
        stop_distance  = $StopDistance
    }

    $positionSide = ([string]$Position.side).ToLower()
    $totalAmount = [decimal]$Position.open_interest
    $entry = [decimal]$Position.entry

    # 2026-07-31 FIX: 1a versao cancelava o TP antigo ANTES de registrar o
    # novo ladder -- se o registro falhasse (confirmado real: DOGEUSDT ficou
    # sem TP por alguns segundos, so' notado e corrigido por coincidencia de
    # timing pelo auto-repair externo -- Repair-PositionProtection -- rodando
    # depois no mesmo job), a posicao ficava sem protecao ate outra rotina
    # notar. CoinEx-PlaceMultiExitLadder nao tem modo dry-run (nao existe
    # -DryRun na API real, so' aceita executar de verdade), entao a validacao
    # possivel aqui e local: garante que cada nivel resolve pra um trigger
    # price > 0 ANTES de cancelar o TP original (essa e a causa mais provavel
    # de "ladder_call_failed" -- StopDistance/Entry invalidos gerando preco
    # <= 0, que CoinEx rejeitaria). Se o cancelamento em si falhar, aborta
    # sem tentar o ladder (guard ja existente). Se o cancelamento suceder mas
    # o ladder falhar mesmo assim (erro de rede/API no momento da chamada
    # real), restaura o TP original imediatamente (catch abaixo) em vez de
    # depender de outra rotina notar o gap depois.
    foreach ($lvl in $tpLevels) {
        $previewPrice = _MultiLadder-ResolvePrice -Level $lvl -Entry $entry -StopDistance $StopDistance -IsLong ($positionSide -eq "long") -IsStop:$false
        if ($previewPrice -le 0) {
            return [PSCustomObject]@{ success = $false; reason = "ladder_level_invalid_price"; ladder_result = $null }
        }
    }

    $cancelResult = CoinEx-CancelPositionTakeProfit -Market $market
    if (-not $cancelResult -or $cancelResult.success -ne $true) {
        return [PSCustomObject]@{ success = $false; reason = "cancel_tp_failed"; ladder_result = $null }
    }

    $ladderResult = $null
    try {
        $ladderResult = CoinEx-PlaceMultiExitLadder -Market $market -PositionSide $positionSide `
            -TotalAmount $totalAmount -Entry $entry -Ladder $ladder
    } catch {
        # Cancelamento ja aconteceu -- restaura o TP "cobre tudo" original
        # imediatamente em vez de depender de outra rotina notar o gap.
        $restoreBody = @{
            market            = $market
            market_type       = "FUTURES"
            take_profit_type  = "mark_price"
            take_profit_price = ([string]$Position.take_profit_price)
            amount            = "0"
        }
        try { CoinEx-Post "/v2/futures/set-position-take-profit" $restoreBody | Out-Null } catch {}
        return [PSCustomObject]@{ success = $false; reason = "ladder_call_failed: $($_.Exception.Message)"; ladder_result = $null }
    }

    Save-PartialExitLadderRegistered -Market $market -Details $ladder | Out-Null

    return [PSCustomObject]@{ success = $true; reason = "ok"; ladder_result = $ladderResult }
}
