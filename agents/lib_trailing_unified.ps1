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
# 2026-07-29 (parte 2, mesmo dia): portadas as capacidades REAIS e validadas
# dos 2 motores fragmentados desligados na promocao (Update-AllTrailingStops,
# Invoke-TrailingPolicyLive), pra nao perder nada ao unificar:
#   - Multi-timeframe (1D/4H/1H) conviction-aware + selecao runner-vs-atual
#     (Resolve-ExitPolicyGated, lib_trailing_policy.ps1) -- validado com
#     walk-forward real: runner (trail largo) so vence em uptrend confirmado
#     (+0.183R), perde em downtrend (-0.111R). Ativa quando -HtfTrend fornecido.
#   - Saidas PARCIAIS reais em R-multiple + time-stop + ladder de reversao
#     por sinais (Get-ExitDecision, lib_trailing_policy.ps1) -- 4a acao possivel
#     agora: PARTIAL (com size_pct), alem de HOLD/UPDATE/EXIT. Ativa quando
#     -BarsHeld/-ReversalSignals fornecidos (senao comportamento pre-existente,
#     so HOLD/UPDATE, preservado 100%).
#   - Find-SupportLevels (lib_trailing_stop_intelligent.ps1, pivots de swing
#     low/high) como fator adicional de aperto -- diferente e complementar
#     da trendline Tori (regressao linear continua vs pivot discreto).
# Tudo ADITIVO/opt-in: sem os parametros novos, Resolve-TrailingDecision se
# comporta EXATAMENTE como antes (contrato dos 18 testes pre-existentes
# preservado). Owner: "nao queremos perder nada" + "SPOT ou FUTURES da melhor
# forma possivel" -- por isso optativo, nao substituicao forcada.
#
# Dot-source ordem exigida pelo caller (ver tests/lib_trailing_unified.Tests.ps1):
#   lib_trailing_exhaustion.ps1, lib_multiframe_analysis.ps1,
#   lib_trailing_stop_intelligent.ps1, lib_tori_proximity.ps1,
#   lib_trailing_baseline.ps1, lib_trailing_policy.ps1, lib_trailing_unified.ps1
#   (lib_trailing_baseline define Get-CurrentTrailingPolicy, dependencia de
#   Resolve-ExitPolicyGated no ramo "atual" -- sem ela, Resolve-ExitPolicyGated
#   lanca excecao capturada pelo catch fail-soft do enriquecimento e
#   profile_selected fica sempre vazio, silenciosamente).

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

    .PARAMETER HtfTrend
    OPCIONAL (2026-07-29). Hashtable/PSCustomObject { t1D; t4H; t1H } (strings
    "STRONG_UP"|"UP"|"NEUTRAL"|"DOWN"|"STRONG_DOWN"). Quando fornecido, ativa
    a selecao de perfil runner-vs-atual (Resolve-ExitPolicyGated) via
    conviccao multi-timeframe real, substituindo o calculo generico de
    trailing_pct por leverage/ATR. Ausente = comportamento pre-existente
    (100% preservado).

    .PARAMETER Regime
    OPCIONAL. Regime corrente (ex: "BEAR_STRONG"). So usado se -HtfTrend
    tambem for fornecido (alimenta Resolve-ExitPolicyGated).

    .PARAMETER BarsHeld
    OPCIONAL. Dias/barras que a posicao esta aberta. Quando fornecido (>=0),
    ativa o motor de decisao completo (Get-ExitDecision): habilita time-stop
    e a 4a acao possivel (PARTIAL, saida parcial real em R-multiple). Ausente
    = comportamento pre-existente (so HOLD/UPDATE).

    .PARAMETER RemainingSizePct
    OPCIONAL. Fracao da posicao original ainda aberta (1.0 = 100%, nunca
    reduzida por parciais anteriores). Default 1.0.

    .PARAMETER ReversalSignals
    OPCIONAL. Contagem de sinais de reversao confirmados nesta barra (ex:
    exhaustion + trendline + divergencia -- quem chama decide o que conta
    como "sinal"). Alimenta o ladder ja validado (reversal_tighten_signals/
    reversal_exit_signals) em Get-ExitDecision. Default 0.

    .OUTPUTS
    PSCustomObject: action (HOLD|UPDATE|PARTIAL|EXIT), new_stop, reason,
    exhaustion_score, atr_period, atr_pct, trailing_pct, leverage_applied
    (bool), trendline_factor, trendline_reason, size_pct (so relevante se
    action=PARTIAL|EXIT -- fracao da posicao a fechar AGORA), profile_selected
    ("runner"|"atual"|$null se -HtfTrend nao fornecido).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Position,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [array] $Candles,
        [object] $HtfTrend = $null,
        [string] $Regime = "",
        [Nullable[int]] $BarsHeld = $null,
        [double] $RemainingSizePct = 1.0,
        [int] $ReversalSignals = 0
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
            support_factor = 1.0; support_reason = "nao_avaliado"
            size_pct = 0.0; profile_selected = $null
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

    # --- Support/Resistance por pivots reais (2026-07-29, 4o fator) ----------
    # Find-SupportLevels (lib_trailing_stop_intelligent.ps1) detecta swing
    # lows/highs discretos (pivots locais) -- complementar a trendline Tori
    # (regressao linear continua). Um mercado pode ter um pivot de suporte
    # forte SEM formar uma reta de tendencia limpa (poucos toques/slope fora
    # do range) -- os 2 fatores cobrem casos diferentes, produto dos 2.
    $supportFactor = 1.0
    $supportReason = "sem_suporte_relevante"
    if (Get-Command Find-SupportLevels -ErrorAction SilentlyContinue) {
        try {
            # Find-SupportLevels so conhece "suporte" (lows) -- p/ SHORT
            # (resistencia = highs), espelha o preco em torno da media pra
            # reusar a mesma funcao sem duplicar logica de pivot.
            if ($side -eq "LONG") {
                $supports = @(Find-SupportLevels -Candles $Candles -LookbackPeriod 20)
                if ($supports.Count -gt 0) {
                    $nearestSupport = $supports[0]
                    $distToSupportPct = if ($CurrentPrice -gt 0) { (($CurrentPrice - $nearestSupport) / $CurrentPrice) * 100 } else { 999 }
                    if ($distToSupportPct -ge 0 -and $distToSupportPct -le 2.0) {
                        $supportFactor = [Math]::Max(0.5, ($distToSupportPct / 2.0))
                        $supportReason = "perto_suporte_pivot=$([Math]::Round($nearestSupport,6))_dist=$([Math]::Round($distToSupportPct,2))pct"
                    }
                }
            } else {
                $mirrorCandles = @($Candles | ForEach-Object { [PSCustomObject]@{ open=$_.open; high=(2*$CurrentPrice - $_.low); low=(2*$CurrentPrice - $_.high); close=(2*$CurrentPrice - $_.close); volume=$_.volume } })
                $resistances = @(Find-SupportLevels -Candles $mirrorCandles -LookbackPeriod 20)
                if ($resistances.Count -gt 0) {
                    $mirroredNearest = $resistances[0]
                    $nearestResistance = 2 * $CurrentPrice - $mirroredNearest
                    $distToResPct = if ($CurrentPrice -gt 0) { (($nearestResistance - $CurrentPrice) / $CurrentPrice) * 100 } else { 999 }
                    if ($distToResPct -ge 0 -and $distToResPct -le 2.0) {
                        $supportFactor = [Math]::Max(0.5, ($distToResPct / 2.0))
                        $supportReason = "perto_resistencia_pivot=$([Math]::Round($nearestResistance,6))_dist=$([Math]::Round($distToResPct,2))pct"
                    }
                }
            }
        } catch {
            $supportFactor = 1.0
            $supportReason = "support_erro"
        }
    }

    # Trailing % efetivo: exhaustion alto, proximidade da trendline real, e
    # proximidade de pivot de suporte/resistencia reduzem a distancia do
    # stop ao preco (produto dos 3 fatores).
    $effectiveTrailingPct = $trailingPct * $tighteningFactor * $trendlineFactor * $supportFactor

    $calculatedStop = if ($side -eq "LONG") {
        $CurrentPrice * (1 - ($effectiveTrailingPct / 100))
    } else {
        $CurrentPrice * (1 + ($effectiveTrailingPct / 100))
    }
    $calculatedStop = [Math]::Round($calculatedStop, 8)

    # --- Guard monotonico: NUNCA recua o stop -------------------------------
    # 2026-07-30: piso minimo de 0.05% de melhora antes de considerar UPDATE.
    # Achado em producao (XRPUSDT real, run 30514386549): stop mudou de
    # 1.08178406 pra 1.08168346 (0.0093% -- ruido de arredondamento/precisao
    # de candle, nao sinal real). CoinEx-ModifyPositionStopLoss cancela e
    # recria a ordem de stop inteira a cada chamada -- updates de magnitude
    # irrisoria geram o padrao "seta apaga, seta aparece" que o owner reportou
    # (TP/SL fica vazio na UI por alguns segundos ate a ordem nova aparecer)
    # sem nenhum ganho real de protecao. Dado real de 10 updates observados em
    # producao no mesmo dia: 9 tinham 0.37%-6.18% de mudanca (todos legitimos),
    # so esse 1 era ruido -- 0.05% filtra o ruido com folga (~7x menor que a
    # menor mudanca real observada) sem tocar nenhum update genuino.
    $MIN_IMPROVEMENT_PCT = 0.05
    $improvementPct = if ($currentStop -ne 0) { [Math]::Abs($calculatedStop - $currentStop) / [Math]::Abs($currentStop) * 100 } else { 100 }
    $improved = if ($side -eq "LONG") { $calculatedStop -gt $currentStop } else { $calculatedStop -lt $currentStop }
    $improved = $improved -and ($improvementPct -ge $MIN_IMPROVEMENT_PCT)

    if (-not $improved) {
        return (& $hold "stop_calculado_nao_melhora" @{
            exhaustion_score = $exhaustionScore; atr_period = $atrPeriod
            atr_pct = [Math]::Round($atrPct, 2); trailing_pct = [Math]::Round($effectiveTrailingPct, 2)
            leverage_applied = $leverageApplied
            trendline_factor = $trendlineFactor; trendline_reason = $trendlineReason
            support_factor = $supportFactor; support_reason = $supportReason
        })
    }

    # Fator mais apertado domina a razao reportada -- owner quer visibilidade
    # de QUAL sinal real (exhaustion de volume, trendline por regressao, ou
    # pivot de suporte/resistencia) motivou o aperto, nao so um numero generico.
    $tightestFactor = [Math]::Min([Math]::Min($tighteningFactor, $trendlineFactor), $supportFactor)
    $reason = if ($supportFactor -le $tightestFactor -and $supportFactor -lt 1.0) { "support_$supportReason" }
              elseif ($trendlineFactor -le $tightestFactor -and $trendlineFactor -lt 1.0) { "trendline_$trendlineReason" }
              elseif ($exhaustionScore -ge 66) { "exhaustion_alto_aperta_forte" }
              elseif ($exhaustionScore -ge 33) { "exhaustion_moderado_aperta" }
              else { "trail_normal" }

    $baseDecision = [PSCustomObject]@{
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
        support_factor = $supportFactor
        support_reason = $supportReason
        size_pct = 0.0
        profile_selected = $null
    }

    # --- Enriquecimento opcional: multi-TF + perfil runner/atual + partials -
    # (2026-07-29, portado de lib_trailing_policy.ps1/lib_trailing_policy_live.ps1)
    # So ativa quando $BarsHeld e fornecido pelo caller -- preserva 100% o
    # comportamento pre-existente (contrato dos 18 testes originais) quando
    # ausente. Fail-soft: qualquer excecao aqui devolve $baseDecision (ATR+
    # exhaustion+trendline+support), nunca quebra o ciclo do trailing.
    if ($null -ne $BarsHeld -and (Get-Command Get-ExitDecision -ErrorAction SilentlyContinue) -and (Get-Command Resolve-ExitPolicyGated -ErrorAction SilentlyContinue)) {
        try {
            $risk = if ($side -eq "LONG") { $entry - $currentStop } else { $currentStop - $entry }
            if ($risk -gt 0) {
                $rNow = if ($side -eq "LONG") { ($CurrentPrice - $entry) / $risk } else { ($entry - $CurrentPrice) / $risk }
                $peak = if ($Position.PSObject.Properties['peak'] -and [double]$Position.peak -gt 0) { [double]$Position.peak } else { $CurrentPrice }

                $trendUp = $false
                if ($HtfTrend -and (Get-Command Get-MultiTimeframeConviction -ErrorAction SilentlyContinue)) {
                    $t1D = if ($HtfTrend.t1D) { [string]$HtfTrend.t1D } else { "NEUTRAL" }
                    $t4H = if ($HtfTrend.t4H) { [string]$HtfTrend.t4H } else { "NEUTRAL" }
                    $t1H = if ($HtfTrend.t1H) { [string]$HtfTrend.t1H } else { "NEUTRAL" }
                    $htfConviction = Get-MultiTimeframeConviction -Trend1D $t1D -Trend4H $t4H -Trend1H $t1H -Direction $side
                    $trendUp = ($htfConviction -ge 40)
                }

                $policy = Resolve-ExitPolicyGated -TrendUp $trendUp -Regime $Regime -Direction $side
                $ctx = @{
                    side = $side; entry = $entry; risk = $risk; r_now = $rNow
                    peak = $peak; current_stop = $currentStop; remaining_size = $RemainingSizePct
                    bars_held = $BarsHeld; signals = $ReversalSignals; atr = $atrAbs
                }
                $exitDec = Get-ExitDecision -Policy $policy -Context $ctx

                $enrichedAction = switch ($exitDec.action) {
                    "exit"    { "EXIT" }
                    "partial" { "PARTIAL" }
                    default   { "HOLD" }
                }
                $enrichedNewStop = if ($null -ne $exitDec.new_stop) {
                    $stopImproves = if ($side -eq "LONG") { [double]$exitDec.new_stop -gt $currentStop } else { [double]$exitDec.new_stop -lt $currentStop }
                    if ($stopImproves) { [double]$exitDec.new_stop } else { $currentStop }
                } else { $currentStop }

                # So substitui o veredito base se o motor enriquecido decidir
                # algo ACIONAVEL (PARTIAL/EXIT, ou UPDATE com stop melhor que
                # o ja calculado por ATR/exhaustion/trendline/support) --
                # nunca AFROUXA em relacao ao $baseDecision (ratchet preservado
                # em ambas as camadas).
                if ($enrichedAction -in @("PARTIAL","EXIT")) {
                    return [PSCustomObject]@{
                        action = $enrichedAction; new_stop = $enrichedNewStop
                        reason = "policy_$($policy.selected)_$($policy.gate_reason)"
                        exhaustion_score = $exhaustionScore; atr_period = $atrPeriod
                        atr_pct = [Math]::Round($atrPct, 2); trailing_pct = [Math]::Round($effectiveTrailingPct, 2)
                        leverage_applied = $leverageApplied
                        trendline_factor = $trendlineFactor; trendline_reason = $trendlineReason
                        support_factor = $supportFactor; support_reason = $supportReason
                        size_pct = [double]$exitDec.size_pct; profile_selected = $policy.selected
                    }
                }
                # profile_selected reflete o perfil AVALIADO (runner/atual),
                # independente do stop enriquecido vencer ou nao o ja calculado
                # -- e' informacao de contexto (qual regra decidiu), nao uma
                # decisao condicional. So o new_stop/reason mudam condicionalmente.
                $baseDecision.profile_selected = $policy.selected
                $enrichedImproves = if ($side -eq "LONG") { $enrichedNewStop -gt $calculatedStop } else { $enrichedNewStop -lt $calculatedStop }
                if ($enrichedImproves) {
                    $baseDecision.new_stop = $enrichedNewStop
                    $baseDecision.reason = "policy_$($policy.selected)_$($reason)"
                }
            }
        } catch {
            # fail-soft: mantem $baseDecision (ATR+exhaustion+trendline+support)
        }
    }

    return $baseDecision
}

# Exportadas: Resolve-TrailingDecision
# Dot-source ao usar (nao e modulo formal, consistente com o resto do projeto)
