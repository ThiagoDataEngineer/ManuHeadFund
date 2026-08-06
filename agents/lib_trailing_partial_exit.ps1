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

# 2026-08-06 FIX CRITICO: nenhum caller desativava o registro quando a
# posicao FECHAVA (achado real: ARBUSDT registrado em 2026-07-31 20:12:57,
# aquela posicao fechou ha dias, uma posicao NOVA no mesmo market abriu em
# 2026-08-04 -- Get-PartialExitLadderRegistered so olha market+active=true,
# entao a posicao nova "herdava" o registro fantasma da antiga e nunca
# tentava registrar um ladder de verdade (sempre already_registered, ciclo
# apos ciclo, owner reportou "multi TPSL nunca funciona"). Mesmo padrao ja
# corrigido manualmente 1x pra DOGEUSDT (scripts/fix_dogeusdt_stale_
# ladder_registration_2026_07_31.ps1) mas a causa raiz nunca foi fechada --
# so aquele market especifico foi limpo na mao, o bug generico continuou.
function Remove-PartialExitLadder {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market)

    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return $false }
    try {
        $rows = @(Get-StateRecords -Table "partial_exit_ladders" -Filter @{ market = $Market })
        $activeRows = @($rows | Where-Object { $_.active -eq $true })
        if ($activeRows.Count -eq 0) { return $true }  # nada pra desativar, nao e erro

        foreach ($r in $activeRows) {
            $updated = [PSCustomObject]@{
                id            = $r.id
                market        = $r.market
                active        = $false
                registered_at = $r.registered_at
                levels_json   = $r.levels_json
            }
            Save-StateRecords -Table "partial_exit_ladders" -Records @($updated) -PrimaryKey "id" | Out-Null
        }
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

    # 2026-07-31 FIX #1 (causa raiz de "ladder_call_failed"): _MultiLadder-
    # ResolvePrice le $Level.PSObject.Properties['type'] -- em hashtable puro
    # (@{...}) essa colecao expoe membros do PSObject (Keys/Values/Count),
    # NAO as chaves do hashtable, entao $type ficava sempre $null e caia no
    # branch "default" (throw "tipo de level desconhecido"). Os levels abaixo
    # usam [PSCustomObject] (confirmado via teste isolado que funciona).
    $positionSide = ([string]$Position.side).ToLower()
    $isLong = ($positionSide -eq "long")
    $totalAmount = [decimal]$Position.open_interest
    $entry = [decimal]$Position.entry

    # 2026-07-31 FIX #2 (achado real DOGEUSDT, run 30660720356): rr_multiple
    # calcula o trigger a partir do ENTRY, mas se o preco ja andou a favor
    # MAIS do que aquele nivel de R (posicao ja em lucro > nivel pedido), o
    # trigger calculado fica ENTRE entry e preco atual -- do lado ERRADO pra
    # TP (CoinEx rejeita: code=3137 "Take-Profit price cannot be higher than
    # the current price" pra SHORT, equivalente invertido pra LONG). Ex real:
    # entry=0.070493, preco atual=0.0698, StopDistance(1R)=0.0000785 -- rr=1
    # e rr=2 resolvem pra 0.070415/0.070336, AMBOS ainda acima do preco atual
    # (SHORT ja rodou ~9x mais que 1R). Fix: resolve o preco de cada nivel
    # AQUI (nao dentro de CoinEx-PlaceMultiExitLadder), busca o preco de
    # mercado atual, e ANCORA no preco atual (nao no entry) quando o nivel
    # baseado em entry ja foi ultrapassado -- preserva a intencao (sair em
    # fatias conforme o lucro cresce) sem nunca gerar um TP do lado errado.
    # Os niveis viram type="absolute" (price ja resolvido) em vez de
    # "rr_multiple" -- CoinEx-PlaceMultiExitLadder ja suporta esse type
    # nativamente (so usa o valor de $Level.price direto, sem recalcular).
    $currentPrice = $entry
    if (Get-Command CoinEx-GetTicker -ErrorAction SilentlyContinue) {
        try {
            $ticker = CoinEx-GetTicker -market $market
            if ($ticker -and $ticker.last) { $currentPrice = [decimal]$ticker.last }
        } catch {}
    }

    $tpLevels = @($Partials | ForEach-Object {
        $rr = [double]$_.at_r
        $qtyPct = [double]$_.pct * 100
        $entryBasedLevel = [PSCustomObject]@{ type = "rr_multiple"; rr_multiple = $rr; qty_pct = $qtyPct }
        $entryBasedPrice = _MultiLadder-ResolvePrice -Level $entryBasedLevel -Entry $entry -StopDistance $StopDistance -IsLong $isLong -IsStop:$false
        $isValidSide = if ($isLong) { $entryBasedPrice -gt $currentPrice } else { $entryBasedPrice -lt $currentPrice }
        $finalPrice = if ($isValidSide) {
            $entryBasedPrice
        } else {
            $dir = if ($isLong) { 1 } else { -1 }
            $currentPrice + ($dir * [decimal][math]::Abs($rr) * $StopDistance)
        }
        [PSCustomObject]@{ type = "absolute"; price = [double]$finalPrice; qty_pct = $qtyPct }
    })

    foreach ($lvl in $tpLevels) {
        if ($lvl.price -le 0) {
            return [PSCustomObject]@{ success = $false; reason = "ladder_level_invalid_price"; ladder_result = $null }
        }
    }

    # stop_distance embutido no Ladder por completude (nao usado pelos
    # niveis "absolute" acima, mas SL nao e tocado por esta funcao entao
    # sl_levels fica vazio de proposito).
    $ladder = [PSCustomObject]@{
        template_id    = "partial_exit_$market"
        tp_levels      = $tpLevels
        sl_levels      = @()
        stop_distance  = $StopDistance
    }

    $cancelResult = CoinEx-CancelPositionTakeProfit -Market $market
    if (-not $cancelResult -or $cancelResult.success -ne $true) {
        return [PSCustomObject]@{ success = $false; reason = "cancel_tp_failed"; ladder_result = $null }
    }

    $restoreOriginalTp = {
        $restoreBody = @{
            market            = $market
            market_type       = "FUTURES"
            take_profit_type  = "mark_price"
            take_profit_price = ([string]$Position.take_profit_price)
            amount            = "0"
        }
        try { CoinEx-Post "/v2/futures/set-position-take-profit" $restoreBody | Out-Null } catch {}
    }

    $ladderResult = $null
    try {
        $ladderResult = CoinEx-PlaceMultiExitLadder -Market $market -PositionSide $positionSide `
            -TotalAmount $totalAmount -Entry $entry -Ladder $ladder
    } catch {
        # Cancelamento ja aconteceu -- restaura o TP "cobre tudo" original
        # imediatamente em vez de depender de outra rotina notar o gap.
        & $restoreOriginalTp
        return [PSCustomObject]@{ success = $false; reason = "ladder_call_failed: $($_.Exception.Message)"; ladder_result = $null }
    }

    # 2026-07-31 FIX #3: CoinEx-PlaceMultiExitLadder NAO lanca excecao por
    # ordem individual rejeitada (so registra response.code=-1/erro no
    # elemento tp_orders correspondente e segue) -- confirmado real:
    # ambos os niveis retornaram code=3137 (preco do lado errado) e a funcao
    # ainda assim retornou normalmente, fazendo Register-PartialExitLadder
    # reportar success=true com a posicao efetivamente SEM nenhum TP novo
    # (o antigo ja tinha sido cancelado).
    #
    # 2026-08-01 FIX #4 (owner pediu explicitamente): checar so "pelo menos
    # 1 nivel aceito" nao basta -- um ladder com apenas parte dos niveis
    # aceitos deixa a posicao com protecao "pela metade" (ex: 50% coberto
    # por TP planejado, os outros 50% sem nenhum nivel de saida parcial,
    # so o SL). Agora exige que TODOS os niveis do ladder tenham sido
    # aceitos (response.code -eq 0) -- se algum nivel falhar (total ou
    # parcialmente), desfaz e restaura o TP original em vez de deixar um
    # ladder incompleto valendo.
    $tpOrdersOk = @($ladderResult.tp_orders | Where-Object { $_.response -and $_.response.code -eq 0 })
    $tpOrdersTotal = @($ladderResult.tp_orders).Count
    if ($tpOrdersOk.Count -eq 0) {
        & $restoreOriginalTp
        $firstError = ($ladderResult.tp_orders | Select-Object -First 1).response
        return [PSCustomObject]@{ success = $false; reason = "ladder_all_levels_rejected: code=$($firstError.code) message=$($firstError.message)"; ladder_result = $ladderResult }
    }
    if ($tpOrdersOk.Count -lt $tpOrdersTotal) {
        & $restoreOriginalTp
        $firstRejected = ($ladderResult.tp_orders | Where-Object { -not ($_.response -and $_.response.code -eq 0) } | Select-Object -First 1).response
        return [PSCustomObject]@{ success = $false; reason = "ladder_partial_rejection: aceitos=$($tpOrdersOk.Count)/$tpOrdersTotal code=$($firstRejected.code) message=$($firstRejected.message)"; ladder_result = $ladderResult }
    }

    Save-PartialExitLadderRegistered -Market $market -Details $ladder | Out-Null

    return [PSCustomObject]@{ success = $true; reason = "ok"; ladder_result = $ladderResult }
}
