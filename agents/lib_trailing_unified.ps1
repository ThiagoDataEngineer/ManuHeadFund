# lib_trailing_unified.ps1 -- Motor unico de trailing (decisao pura, sem I/O)
#
# 2026-07-18: substitui a logica de calculo de stop espalhada em
# Get-TrailingNewStopAdaptive (lib_trailing_adaptive.ps1, ATR placeholder
# nunca preenchido), Calculate-TrailingStopPrice (lib_trailing_stop_
# intelligent.ps1) e Get-SmartStopPrice (lib_trailing_smart.ps1, nunca
# ligado em producao) -- um SO core de decisao, resolvendo por origem do
# trade (Position.origin.asset_class = SPOT|FUTURES,
# Position.origin.trade_style = SCALP|SWING). Ver
# docs/ARCHITECTURE_TATICA.md secao "Tese Central do Fundo" -- exhaustion
# pesa mais que % fixo, a mesma tese validada com dado real de mercado em
# 2026-07-18.
#
# 2026-07-29: 3o fator adicionado -- trendline Tori real (reta de suporte/
# resistencia que anda com a tendencia, lib_tori_proximity.ps1). Achado real
# em producao: DOGEUSDT SHORT chegou a ter +$20 de lucro e devolveu tudo
# (foi a -$2) sem o trailing mover 1 centimetro, porque os motores ativos
# ate entao (Update-AllTrailingStops, Invoke-TrailingPolicyLive) so reagem
# a ATR/exhaustion/lucro-minimo -- nenhum considera ONDE o preco esta em
# relacao a niveis reais de suporte/resistencia. Get-ToriProximityFromArrays/
# Get-ToriShortProximityFromArrays ja calculam essa reta (regressao linear
# sobre lows/highs) mas so eram usadas pra decidir ENTRADA -- nunca pra
# decidir SAIDA. Owner pediu explicitamente: "deixar o lucro subir, cortar
# risco antes de devolver" -- a trendline e o sinal real de "onde o mercado
# historicamente reage", nao um % fixo arbitrario.
#
# PURO: nenhuma chamada de API, nenhuma escrita em disco/exchange. O
# caller (trailing_stop_monitor.ps1) e' responsavel por buscar candles/preco
# e por chamar Sync-TrailingToExchange com o resultado.
#
# Reaproveita (nao reimplementa): Get-ExhaustionScore/Get-StopTighteningFactor
# (lib_trailing_exhaustion.ps1), Get-TrendDirection (lib_multiframe_analysis.ps1,
# ja validado por lib_trailing_policy_live.ps1), Calculate-ATR/Find-SupportLevels
# (lib_trailing_stop_intelligent.ps1), Get-ToriProximityFromArrays/
# Get-ToriShortProximityFromArrays (lib_tori_proximity.ps1).
#
# Dot-source ordem exigida pelo caller (ver tests/lib_trailing_unified.Tests.ps1):
#   lib_trailing_exhaustion.ps1, lib_multiframe_analysis.ps1,
#   lib_trailing_stop_intelligent.ps1, lib_tori_proximity.ps1, lib_trailing_unified.ps1

$script:MIN_CANDLES_REQUIRED = 24   # Get-ExhaustionScore exige 24 p/ volume drying

$script:ATR_PERIOD_BY_STYLE = @{
    "SCALP" = 7    # reage rapido -- horizonte curto, candles de baixa TF
    "SWING" = 14   # padrao mais estavel -- mesmo period do stop_intelligent atual
}

function _Get-BaseTrailingPct {
    <#
    .SYNOPSIS
    Trailing % base por leverage (FUTURES) -- reaproveita a mesma tabela
    ja validada em lib_trailing_stop_intelligent.ps1 Calculate-TrailingStopPrice,
    so extraida pra funcao pura testavel isoladamente.
    #>
    param([int]$Leverage)
    if ($Leverage -ge 50) { return 1.5 }
    if ($Leverage -ge 20) { return 2.5 }
    if ($Leverage -ge 10) { return 3.5 }
    return 4.5
}

function Get-TrendlineTighteningFactor {
    <#
    .SYNOPSIS
    3o fator do trailing (2026-07-29): aperta o stop quando o preco se
    aproxima da propria trendline real (suporte ascendente p/ LONG,
    resistencia descendente p/ SHORT) que sustentou o movimento a favor do
    trade -- sinal de que o nivel que gerou o lucro pode estar prestes a
    furar, nao um % fixo arbitrario.

    .PARAMETER Side
    "LONG" | "SHORT".

    .PARAMETER Closes / Highs / Lows / Volumes
    Arrays de candle (mesmo shape exigido por Get-ToriProximityFromArrays/
    Get-ToriShortProximityFromArrays).

    .OUTPUTS
    [PSCustomObject]@{ factor; reason; trendline_valid; proximity_pct }
    factor: 1.0 (sem trendline valida ou preco longe dela, nao aperta) ate
    0.4 (preco MUITO perto/ja tocando a linha, aperta 60%). Multiplica o
    trailing_pct do mesmo jeito que Get-StopTighteningFactor (exhaustion) --
    os 2 fatores combinam (produto), nao substituem um ao outro.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Volumes
    )

    $sideUpper = $Side.ToUpper()
    $prox = if ($sideUpper -eq "LONG") {
        Get-ToriProximityFromArrays -Closes $Closes -Highs $Highs -Lows $Lows -Volumes $Volumes
    } else {
        Get-ToriShortProximityFromArrays -Closes $Closes -Highs $Highs -Lows $Lows -Volumes $Volumes
    }

    if (-not $prox.valid) {
        return [PSCustomObject]@{
            factor = 1.0; reason = "trendline_invalida:$($prox.reason)"
            trendline_valid = $false; proximity_pct = $null
        }
    }

    # LONG: proximity_pct = (preco - linha_suporte) / linha_suporte * 100.
    # Preco caindo em direcao a linha => proximity_pct cai em direcao a 0
    # (ou fica negativo se ja rompeu). Quanto mais perto de 0 (ou negativo),
    # mais o suporte que sustentou o lucro esta ameacado -- aperta mais.
    #
    # SHORT: mesma logica espelhada -- preco SUBINDO em direcao a resistencia
    # descendente ameaca o lucro do short (proximity_pct sobe em direcao a 0).
    $absProx = [Math]::Abs([double]$prox.proximity_pct)

    $factor = if ($absProx -le 0.5) { 0.4 }       # tocando/rompeu a linha -- aperta forte
              elseif ($absProx -le 1.5) { 0.6 }   # muito perto -- aperta moderado
              elseif ($absProx -le 3.0) { 0.8 }   # se aproximando -- aperta leve
              else { 1.0 }                        # ainda longe -- sem ajuste

    $reason = if ($factor -lt 1.0) { "perto_trendline_prox=$([Math]::Round($prox.proximity_pct,2))pct" } else { "longe_trendline" }

    return [PSCustomObject]@{
        factor = $factor; reason = $reason
        trendline_valid = $true; proximity_pct = [double]$prox.proximity_pct
    }
}

function Resolve-TrailingDecision {
    <#
    .SYNOPSIS
    Decide o novo stop (e um veredito HOLD/UPDATE) para UMA posicao, combinando
    ATR por trade_style + leverage (se FUTURES) + exhaustion score.

    .PARAMETER Position
    PSCustomObject com: market, side (LONG|SHORT), entry, stopCurrent,
    [leverage], origin=@{ asset_class; trade_style }. origin e' OBRIGATORIO --
    esta funcao NUNCA adivinha a origem do trade (principio: fail loud, nao
    fail silent -- adivinhar origem errado e pior que travar explicito).

    .PARAMETER CurrentPrice
    Preco atual do mercado.

    .PARAMETER Candles
    Array de candles (>= 24, mesmo shape de Get-ExhaustionScore/Calculate-ATR:
    open/high/low/close/volume).

    .OUTPUTS
    PSCustomObject: action (HOLD|UPDATE), new_stop, reason, exhaustion_score,
    atr_period, atr_pct, trailing_pct, leverage_applied (bool).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Position,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [array] $Candles
    )

    if (-not $Position.origin -or -not $Position.origin.asset_class -or -not $Position.origin.trade_style) {
        throw "Resolve-TrailingDecision: Position.origin.{asset_class,trade_style} e obrigatorio -- nao adivinha origem do trade"
    }

    $side = "$($Position.side)".ToUpper()
    $entry = [double]$Position.entry
    $currentStop = [double]$Position.stopCurrent
    $assetClass = "$($Position.origin.asset_class)".ToUpper()
    $tradeStyle = "$($Position.origin.trade_style)".ToUpper()

    $hold = {
        param($reason, $extra)
        $o = [PSCustomObject]@{
            action = "HOLD"; new_stop = $currentStop; reason = $reason
            exhaustion_score = 0; atr_period = 0; atr_pct = 0.0
            trailing_pct = 0.0; leverage_applied = $false
            trendline_factor = 1.0; trendline_reason = "nao_avaliado"
        }
        if ($extra) { foreach ($k in $extra.Keys) { $o.$k = $extra[$k] } }
        return $o
    }

    if (-not $Candles -or @($Candles).Count -lt $script:MIN_CANDLES_REQUIRED) {
        return (& $hold "candles_insuficientes")
    }

    if (-not $script:ATR_PERIOD_BY_STYLE.ContainsKey($tradeStyle)) {
        return (& $hold "trade_style_desconhecido")
    }
    $atrPeriod = $script:ATR_PERIOD_BY_STYLE[$tradeStyle]

    # --- ATR base (reaproveita Calculate-ATR ja testado) ---------------------
    $atrAbs = Calculate-ATR -Candles $Candles -Period $atrPeriod
    $atrPct = if ($CurrentPrice -gt 0) { ($atrAbs / $CurrentPrice) * 100 } else { 0 }

    # --- Trailing % base: leverage (FUTURES) ou ATR-only (SPOT) --------------
    $leverageApplied = $false
    if ($assetClass -eq "FUTURES") {
        $leverage = if ($Position.PSObject.Properties['leverage'] -and [int]$Position.leverage -gt 0) { [int]$Position.leverage } else { 1 }
        $trailingPct = _Get-BaseTrailingPct -Leverage $leverage
        $leverageApplied = $true
    } else {
        # SPOT: sem leverage. Usa ATR% direto como base do trailing (mais largo
        # em vol alta, mais apertado em vol baixa) -- ignora leverage mesmo que
        # o campo esteja presente por engano no registro (guard explicito).
        $trailingPct = [Math]::Max(2.0, [Math]::Min(6.0, $atrPct * 1.5))
    }

    # Ajuste por volatilidade real (ATR), igual ao stop_intelligent atual.
    if ($atrPct -gt 3.0) { $trailingPct += 1.0 }
    elseif ($atrPct -lt 1.0) { $trailingPct -= 0.5 }
    $trailingPct = [Math]::Max(0.5, $trailingPct)

    # --- Exhaustion (reaproveita lib_trailing_exhaustion.ps1, ja testado) ----
    $exhaustionScore = Get-ExhaustionScore -Candles $Candles -Side $side
    $tighteningFactor = Get-StopTighteningFactor -ExhaustionScore $exhaustionScore

    # --- Trendline Tori (2026-07-29, 3o fator) -------------------------------
    # Fail-soft: candles deste caller sao array de PSCustomObject com
    # open/high/low/close/volume (mesmo shape de Calculate-ATR) -- extrai os
    # arrays que Get-ToriProximityFromArrays/Get-ToriShortProximityFromArrays
    # exigem. Se faltar Get-Command (lib nao carregada) ou os candles nao
    # tiverem o campo esperado, factor=1.0 (sem ajuste, comportamento
    # identico ao pre-2026-07-29) -- nunca bloqueia o trailing por falta
    # desta feature opcional.
    $trendlineFactor = 1.0
    $trendlineReason = "trendline_indisponivel"
    if (Get-Command Get-ToriProximityFromArrays -ErrorAction SilentlyContinue) {
        try {
            $tlCloses  = @($Candles | ForEach-Object { [double]$_.close })
            $tlHighs   = @($Candles | ForEach-Object { [double]$_.high })
            $tlLows    = @($Candles | ForEach-Object { [double]$_.low })
            $tlVolumes = @($Candles | ForEach-Object { [double]$_.volume })
            $tl = Get-TrendlineTighteningFactor -Side $side -Closes $tlCloses -Highs $tlHighs -Lows $tlLows -Volumes $tlVolumes
            $trendlineFactor = [double]$tl.factor
            $trendlineReason = $tl.reason
        } catch {
            $trendlineFactor = 1.0
            $trendlineReason = "trendline_erro"
        }
    }

    # Trailing % efetivo: exhaustion alto E proximidade da trendline real
    # reduzem a distancia do stop ao preco (produto dos 2 fatores -- ambos
    # 1.0 = sem aperto, ambos 0.5/0.4 = aperta bastante mais que so um).
    $effectiveTrailingPct = $trailingPct * $tighteningFactor * $trendlineFactor

    $calculatedStop = if ($side -eq "LONG") {
        $CurrentPrice * (1 - ($effectiveTrailingPct / 100))
    } else {
        $CurrentPrice * (1 + ($effectiveTrailingPct / 100))
    }
    $calculatedStop = [Math]::Round($calculatedStop, 8)

    # --- Guard monotonico: NUNCA recua o stop -------------------------------
    $improved = if ($side -eq "LONG") { $calculatedStop -gt $currentStop } else { $calculatedStop -lt $currentStop }

    if (-not $improved) {
        return (& $hold "stop_calculado_nao_melhora" @{
            exhaustion_score = $exhaustionScore; atr_period = $atrPeriod
            atr_pct = [Math]::Round($atrPct, 2); trailing_pct = [Math]::Round($effectiveTrailingPct, 2)
            leverage_applied = $leverageApplied
            trendline_factor = $trendlineFactor; trendline_reason = $trendlineReason
        })
    }

    # Trendline perto (factor < 1.0) domina a razao reportada quando e o
    # fator mais apertado -- owner quer visibilidade de QUAL sinal real
    # (exhaustion de volume vs proximidade de suporte/resistencia) motivou
    # o aperto, nao so um numero generico.
    $reason = if ($trendlineFactor -lt 1.0 -and $trendlineFactor -le $tighteningFactor) { "trendline_$trendlineReason" }
              elseif ($exhaustionScore -ge 66) { "exhaustion_alto_aperta_forte" }
              elseif ($exhaustionScore -ge 33) { "exhaustion_moderado_aperta" }
              else { "trail_normal" }

    return [PSCustomObject]@{
        action = "UPDATE"
        new_stop = $calculatedStop
        reason = $reason
        exhaustion_score = $exhaustionScore
        atr_period = $atrPeriod
        atr_pct = [Math]::Round($atrPct, 2)
        trailing_pct = [Math]::Round($effectiveTrailingPct, 2)
        leverage_applied = $leverageApplied
        trendline_factor = $trendlineFactor
        trendline_reason = $trendlineReason
    }
}

# Exportadas: Resolve-TrailingDecision
# Dot-source ao usar (nao e modulo formal, consistente com o resto do projeto)
