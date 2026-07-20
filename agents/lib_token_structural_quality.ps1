# lib_token_structural_quality.ps1 -- Gate de qualidade ESTRUTURAL do token,
# so-CoinEx (sem dependencia externa nova).
#
# Achado 2026-07-20: BABYDOGEUSDT comprado autonomo ($100 real, client_id
# c515ed803e0d84b20aec0fb18e5f708, 2026-07-11 23:22:53 UTC) via gem_executor.ps1
# -- pipeline tem gates de MOMENTUM/TECNICO (breadth, pump/dump, entry timing)
# mas NUNCA de qualidade ESTRUTURAL do token em si. lib_fundamental_quality.ps1
# (FQS) existe mas exige coin_registry.json curado (55 mercados) -- aplicar
# ali mataria a estrategia GEM inteira (qualquer coisa nova = AVOID).
#
# Pesquisa (2026-07-20, paper arXiv 2507.01963v2, 707 tokens analisados):
# liquidez rasa vs. market cap e' o sinal mais forte de manipulacao/memecoin-
# lixo (88.1% de cobertura), e e' o UNICO dos 3 sinais recomendados que nao
# precisa de fonte externa (CoinEx nao expoe supply -- confirmado, CoinGecko
# seria necessario pros outros 2 sinais, fora de escopo desta implementacao).
#
# 2 sinais so-CoinEx:
#   A. Liquidez efetiva perto do preco (+-2%) vs tamanho da posicao pretendida
#      -- proxy pratico de "liquidez rasa vs cap" sem precisar saber o cap.
#   B. Preco unitario extremo (< $0.00001) -- proxy fraco pro sinal de supply
#      astronomico (CoinGecko daria supply direto; sem isso, preco unitario
#      e' o unico proxy disponivel via CoinEx).
#
# Veredito por CONTAGEM de flags (nao flag unico -- pesquisa mostra 2+ flags
# simultaneos e' o padrao real de lixo estrutural, 1 flag isolado pode ser
# falso positivo em moeda legitima barata):
#   2 flags -> BLOCK
#   1 flag  -> CAUTION (sizing reduzido, nao bloqueia -- fail-closed seria
#              bloquear e perder gems legitimas por falso positivo)
#   0 flags -> PASS
# Fail-closed: se a chamada de depth falhar, trata como CAUTION (nunca PASS
# silencioso por falta de dado).

$script:MIN_LIQUIDITY_MULTIPLE = 20.0      # liquidez efetiva >= 20x o tamanho da posicao
$script:MAX_UNIT_PRICE_FLAG = 0.00001      # preco unitario abaixo disso = flag B

function Get-SpotLiquidityNearPrice {
    <#
    .SYNOPSIS
    PURA (recebe depth ja buscado). Soma o valor em USD disponivel em
    bids+asks dentro de +-PctBand% do preco de referencia.

    .PARAMETER Depth
    Objeto retornado por CoinEx-GetSpotDepth -- espera .depth.bids/.depth.asks,
    cada item [preco, quantidade] (strings, formato confirmado via docs.coinex.com).

    .PARAMETER ReferencePrice
    Preco de referencia (ultimo preco negociado).

    .PARAMETER PctBand
    Banda em % pra considerar "perto do preco" (default 2.0 = +-2%).

    .OUTPUTS
    double -- soma em USD (preco * quantidade) dos niveis dentro da banda.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Depth,
        [Parameter(Mandatory)] [double] $ReferencePrice,
        [double] $PctBand = 2.0
    )
    if ($ReferencePrice -le 0) { return 0.0 }
    $lowerBound = $ReferencePrice * (1 - ($PctBand / 100))
    $upperBound = $ReferencePrice * (1 + ($PctBand / 100))

    $total = 0.0
    $levels = @()
    if ($Depth.depth -and $Depth.depth.bids) { $levels += @($Depth.depth.bids) }
    if ($Depth.depth -and $Depth.depth.asks) { $levels += @($Depth.depth.asks) }

    foreach ($lvl in $levels) {
        if (-not $lvl -or @($lvl).Count -lt 2) { continue }
        $px = [double]$lvl[0]
        $qty = [double]$lvl[1]
        if ($px -ge $lowerBound -and $px -le $upperBound) {
            $total += ($px * $qty)
        }
    }
    return [Math]::Round($total, 2)
}

function Test-TokenStructuralQuality {
    <#
    .SYNOPSIS
    Gate de qualidade estrutural, so-CoinEx. NAO substitui Test-FundamentalQualityGate
    (FQS) -- e' ortogonal, roda ANTES dos gates de momentum/tecnico em
    gem_executor.ps1, pra pegar lixo estrutural puro (memecoin supply
    infinito + liquidez fantasma) sem exigir registry curado.

    .PARAMETER Market
    Mercado SPOT (ex: BABYDOGEUSDT).

    .PARAMETER CurrentPrice
    Preco atual (last).

    .PARAMETER IntendedSizeUsd
    Tamanho da posicao que o sistema pretende abrir, em USD.

    .PARAMETER Depth
    Objeto de depth ja buscado (CoinEx-GetSpotDepth). Se $null, tenta buscar
    via CoinEx-GetSpotDepth se a funcao estiver disponivel; se falhar/nao
    disponivel, fail-closed -> CAUTION (nunca PASS sem dado real).

    .OUTPUTS
    PSCustomObject: verdict (PASS|CAUTION|BLOCK), flags (string[]),
    liquidity_usd, liquidity_multiple, unit_price, reason.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $IntendedSizeUsd,
        $Depth = $null
    )

    $flags = @()
    $liquidityUsd = -1.0
    $liquidityMultiple = -1.0

    # --- Sinal B: preco unitario extremo (nao depende de depth) ---
    if ($CurrentPrice -gt 0 -and $CurrentPrice -lt $script:MAX_UNIT_PRICE_FLAG) {
        $flags += "unit_price_extreme"
    }

    # --- Sinal A: liquidez efetiva vs tamanho pretendido ---
    if (-not $Depth -and (Get-Command CoinEx-GetSpotDepth -ErrorAction SilentlyContinue)) {
        try { $Depth = CoinEx-GetSpotDepth $Market 20 } catch { $Depth = $null }
    }

    if ($Depth -and $CurrentPrice -gt 0) {
        $liquidityUsd = Get-SpotLiquidityNearPrice -Depth $Depth -ReferencePrice $CurrentPrice -PctBand 2.0
        $liquidityMultiple = if ($IntendedSizeUsd -gt 0) { $liquidityUsd / $IntendedSizeUsd } else { 0.0 }
        if ($liquidityMultiple -lt $script:MIN_LIQUIDITY_MULTIPLE) {
            $flags += "liquidity_thin"
        }
    } else {
        # Fail-closed: sem dado de depth real, nao afirma PASS -- conta como
        # 1 flag (CAUTION), nunca 0 flags por falta de informacao.
        $flags += "liquidity_unknown"
    }

    $flagCount = @($flags).Count
    $verdict = if ($flagCount -ge 2) { "BLOCK" }
               elseif ($flagCount -eq 1) { "CAUTION" }
               else { "PASS" }

    $reason = if ($flagCount -eq 0) { "ok" } else { ($flags -join "+") }

    return [PSCustomObject]@{
        market             = $Market
        verdict            = $verdict
        flags              = [string[]]@($flags)
        liquidity_usd      = $liquidityUsd
        liquidity_multiple = [Math]::Round($liquidityMultiple, 2)
        unit_price         = $CurrentPrice
        reason             = $reason
    }
}
