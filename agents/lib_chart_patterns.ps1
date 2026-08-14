# lib_chart_patterns.ps1 -- Pure-math chart pattern recognition.
#
# Filosofia: identificar formacoes graficas classicas SEM LLM. Auto-similar em
# qualquer timeframe (daily/4h/1h). Resultado: PSCustomObject com detected/strength/etc.
#
# Patterns:
#   - Detect-VolumeClimax       (selling/buying climax)
#   - Detect-CandlestickReversal (hammer, engulfing, shooting star)
#   - Detect-RsiDivergence      (bullish/bearish)
#
# Determinístico, pure-math, testado via lib_chart_patterns.Tests.ps1.
#
# PS 5.1. UTF-8 BOM.


# ─── Helper RSI (replicado de lib_tori_proximity pra zero dependency) ─────────

function _CP-CalcRsiArray {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [int] $Period = 14
    )
    # Returns array de RSI valores (mesmo length de Closes, primeiros Period values=50)
    $n = $Closes.Length
    $rsi = @()
    for ($i = 0; $i -lt $n; $i++) { $rsi += 50.0 }
    if ($n -lt ($Period + 1)) { return $rsi }
    $g = 0.0; $l = 0.0
    for ($i = 1; $i -le $Period; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        if ($d -gt 0) { $g += $d } else { $l += [math]::Abs($d) }
    }
    $ag = $g / $Period; $al = $l / $Period
    if ($al -eq 0) { $rsi[$Period] = 100.0 } else { $rsi[$Period] = 100 - (100 / (1 + $ag / $al)) }
    for ($i = $Period + 1; $i -lt $n; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        if ($d -gt 0) {
            $ag = ($ag * ($Period - 1) + $d) / $Period
            $al = $al * ($Period - 1) / $Period
        } else {
            $ag = $ag * ($Period - 1) / $Period
            $al = ($al * ($Period - 1) + [math]::Abs($d)) / $Period
        }
        if ($al -eq 0) { $rsi[$i] = 100.0 } else { $rsi[$i] = 100 - (100 / (1 + $ag / $al)) }
    }
    return $rsi
}


function _CP-FindSwingLows {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]] $Lows, [int] $Window = 3)
    # Swing low: bar i tem low menor que +/-Window vizinhos
    $swings = @()
    for ($i = $Window; $i -lt ($Lows.Length - $Window); $i++) {
        $isSwing = $true
        for ($j = 1; $j -le $Window; $j++) {
            if ($Lows[$i] -ge $Lows[$i - $j] -or $Lows[$i] -ge $Lows[$i + $j]) { $isSwing = $false; break }
        }
        if ($isSwing) { $swings += $i }
    }
    return $swings
}


function _CP-FindSwingHighs {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]] $Highs, [int] $Window = 3)
    $swings = @()
    for ($i = $Window; $i -lt ($Highs.Length - $Window); $i++) {
        $isSwing = $true
        for ($j = 1; $j -le $Window; $j++) {
            if ($Highs[$i] -le $Highs[$i - $j] -or $Highs[$i] -le $Highs[$i + $j]) { $isSwing = $false; break }
        }
        if ($isSwing) { $swings += $i }
    }
    return $swings
}


# ============================================================================
# 1. VOLUME CLIMAX
# ============================================================================

function Get-VolClimaxConviction {
    # Mapeia resultado do vol_climax -> conviccao 0-100 para o trigger-bus.
    # Alinhado a regra do scanner: SO Tier S (paper-trade eligible) e nao
    # cluster-suprimido dispara fast-path. Conviccao = WSS (composito 0-100 ja
    # validado OOS). Tier A/B = observatorio, nao dispara (retorna 0).
    [CmdletBinding()]
    param(
        [string] $Tier,
        [double] $Wss,
        [bool]   $ClusterSuppressed = $false
    )
    if ($ClusterSuppressed) { return 0 }
    if ($Tier -ne "S")      { return 0 }
    $w = [int][Math]::Round($Wss)
    if ($w -lt 0)   { $w = 0 }
    if ($w -gt 100) { $w = 100 }
    return $w
}

function Detect-VolumeClimax {
    <#
    .SYNOPSIS
    Detecta selling climax (LONG) ou buying climax (SHORT) na ultima barra.

    PARAMETROS REFINED 2026-05-22 (data-driven grid calibration phase_3_bear):
      mult=2.5 + RSI<30 confluence produziu edge +20.7pp em phase_3_bear
      (cross-cycle h20+h24 STABLE).
      Default mantido 3.0 pra backward compat; use ClimaxMultiplier=2.5 +
      RsiOversoldMax=30 pra modo REFINED.

    .PARAMETER ClimaxMultiplier
    Vol bar deve ser >= ClimaxMultiplier × media. Default 3.0 (canonical),
    refined 2.5 (calibrado phase_3_bear).
    .PARAMETER Lookback
    Janela pra calcular vol media + checar swing low/high (default 20)
    .PARAMETER RsiOversoldMax
    Se passado, exige RSI < RsiOversoldMax (LONG) ou RSI > 100-RsiOversoldMax (SHORT)
    como confluence. Refined: RsiOversoldMax=30 → edge sobe ~+11pp em phase_3_bear.
    Default null = sem confluence (modo v1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [double] $ClimaxMultiplier = 3.0,
        [int]    $Lookback = 20,
        [Nullable[double]] $RsiOversoldMax = $null
    )
    $n = $Volumes.Length
    if ($n -lt $Lookback) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="insufficient_history" }
    }

    $lastIdx = $n - 1
    $prior = $Volumes[($n - $Lookback)..($lastIdx - 1)]
    $avgVol = ($prior | Measure-Object -Average).Average
    if ($avgVol -le 0) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="zero_avg_vol" }
    }

    $climaxRatio = $Volumes[$lastIdx] / $avgVol
    if ($climaxRatio -lt $ClimaxMultiplier) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="vol_below_climax_threshold"; ratio=[math]::Round($climaxRatio,2) }
    }

    # Now check swing context
    $priorLows  = $Lows[($n - $Lookback)..($lastIdx - 1)]
    $priorHighs = $Highs[($n - $Lookback)..($lastIdx - 1)]
    $minPriorLow  = ($priorLows  | Measure-Object -Minimum).Minimum
    $maxPriorHigh = ($priorHighs | Measure-Object -Maximum).Maximum

    # RSI confluence (REFINED 2026-05-22) — opcional
    $rsiPassed = $true
    $rsiVal = $null
    if ($null -ne $RsiOversoldMax) {
        $rsiArr = _CP-CalcRsiArray -Closes $Closes -Period 14
        $rsiVal = $rsiArr[-1]
        if ($Side -eq "LONG") {
            # LONG exige RSI baixo (oversold confluence)
            $rsiPassed = $rsiVal -lt [double]$RsiOversoldMax
        } else {
            # SHORT exige RSI alto (overbought) — espelho: > 100 - RsiOversoldMax
            $rsiPassed = $rsiVal -gt (100.0 - [double]$RsiOversoldMax)
        }
        if (-not $rsiPassed) {
            return [PSCustomObject]@{
                detected=$false; pattern_name=$null; strength=0; bar_idx=$null
                reason="rsi_confluence_failed"; rsi=[math]::Round($rsiVal,1)
                rsi_threshold=$RsiOversoldMax; ratio=[math]::Round($climaxRatio,2)
            }
        }
    }

    if ($Side -eq "LONG") {
        # Selling climax: low quebra minimo recente + close acima do low (rejeicao)
        $newLow = $Lows[$lastIdx] -lt $minPriorLow
        $closeAboveLow = $Closes[$lastIdx] -gt ($Lows[$lastIdx] + (($Highs[$lastIdx] - $Lows[$lastIdx]) * 0.3))
        if ($newLow -and $closeAboveLow) {
            # Strength: combina ratio + intensidade do break
            $breakPct = (($minPriorLow - $Lows[$lastIdx]) / $minPriorLow) * 100
            $strength = [Math]::Min(100, [int](20 + ($climaxRatio * 10) + ($breakPct * 5)))
            $out = [PSCustomObject]@{
                detected     = $true
                pattern_name = "selling_climax"
                strength     = $strength
                bar_idx      = $lastIdx
                vol_ratio    = [math]::Round($climaxRatio, 2)
                break_pct    = [math]::Round($breakPct, 2)
            }
            if ($null -ne $rsiVal) {
                Add-Member -InputObject $out -MemberType NoteProperty -Name 'rsi' -Value ([math]::Round($rsiVal,1)) -Force
                Add-Member -InputObject $out -MemberType NoteProperty -Name 'rsi_confluence' -Value $true -Force
            }
            return $out
        }
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="vol_spike_no_swing_low"; ratio=[math]::Round($climaxRatio,2) }
    } else {
        # SHORT: buying climax - high quebra maximo recente + close baixo no range (rejeicao)
        $newHigh = $Highs[$lastIdx] -gt $maxPriorHigh
        $closeBelowHigh = $Closes[$lastIdx] -lt ($Highs[$lastIdx] - (($Highs[$lastIdx] - $Lows[$lastIdx]) * 0.3))
        if ($newHigh -and $closeBelowHigh) {
            $breakPct = (($Highs[$lastIdx] - $maxPriorHigh) / $maxPriorHigh) * 100
            $strength = [Math]::Min(100, [int](20 + ($climaxRatio * 10) + ($breakPct * 5)))
            $out = [PSCustomObject]@{
                detected     = $true
                pattern_name = "buying_climax"
                strength     = $strength
                bar_idx      = $lastIdx
                vol_ratio    = [math]::Round($climaxRatio, 2)
                break_pct    = [math]::Round($breakPct, 2)
            }
            if ($null -ne $rsiVal) {
                Add-Member -InputObject $out -MemberType NoteProperty -Name 'rsi' -Value ([math]::Round($rsiVal,1)) -Force
                Add-Member -InputObject $out -MemberType NoteProperty -Name 'rsi_confluence' -Value $true -Force
            }
            return $out
        }
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="vol_spike_no_swing_high"; ratio=[math]::Round($climaxRatio,2) }
    }
}


# ============================================================================
# 1b. VOLUME ACCUMULATION (2026-08-15)
# ============================================================================

function Detect-VolumeAccumulation {
    <#
    .SYNOPSIS
    Detecta pico de volume ANOMALO isolado (acumulacao silenciosa) na ultima
    barra -- DIFERENTE de Detect-VolumeClimax, que so dispara em quebra de
    swing high/low (exaustao de reversao). Este detector nao exige swing --
    o alvo e pegar volume anormal no MEIO de um range, antes do preco reagir.

    .NOTES
    Achado real (2026-08-14, auditoria ACE +168%/24h): candlestick patterns
    sozinhos disparam ruido demais (1 sinal a cada ~6h num range lateral,
    30+ sinais em 190h sem filtro util). O sinal que de fato precedeu o pump
    por horas foi volume 9x-58x a media, em candles verdes, SEM nenhuma
    quebra de estrutura -- Detect-VolumeClimax nao pega isso porque exige
    newLow/newHigh. Threshold default 8x calibrado contra o caso real (ACE
    teve hits em 9x, 14.3x, 31x, 58x -- 3 dos 4 foram candles verdes
    precedendo alta real, 1 foi candle vermelho isolado sem sequencia,
    filtrado pela exigencia de candle na direcao certa).

    Zero custo de API nova -- reusa os mesmos candles ja buscados por
    Detect-VolumeClimax/Detect-CandlestickReversal no mesmo chamador.

    .PARAMETER AccumMultiplier
    Vol da ultima barra deve ser >= AccumMultiplier x media do Lookback
    anterior (exclusive). Default 8.0 (calibrado contra ACE real).
    .PARAMETER Lookback
    Janela pra media de volume (default 20, mesmo padrao de Detect-VolumeClimax).

    .OUTPUTS
    PSCustomObject { detected, pattern_name="volume_accumulation", strength,
    bar_idx, vol_ratio }. LONG exige candle verde (close>open); SHORT exige
    candle vermelho (close<open) -- direcao do candle na barra do pico, nao
    da tendencia previa (este detector nao olha tendencia, e sinal de
    ACUMULACAO, nao de reversao).

    .NOTES
    LIMITACAO CONHECIDA (2026-08-15, validacao contra 10 casos reais adicionais
    -- 4 pumps: SAL/NEOX/H/ALICE, 4 dumps: KROAK/NCT/X/ONE, alem dos 2 originais
    ACE/TUT): taxa de deteccao ANTES do pico do movimento foi 4/10 (40%). Nao e
    bug -- e a natureza do mercado: so 2 dos 8 casos novos (ALICE 22x, XUSDT 87x)
    tiveram volume genuinamente anomalo perto do movimento; os outros 6 (SAL,
    NEOX, H, KROAK, NCT, ONE) tiveram pump/dump com volume normal (1.5x-4.7x),
    as vezes subindo JUNTO com o preco (nao antes). Volume anomalo isolado
    precede so uma fracao dos movimentos -- moedas de baixa liquidez onde
    acumulacao lenta antecede o movimento (padrao ACE/TUT), nao o mercado
    inteiro. CONCLUSAO: usar como 1 sinal a mais no score combinado (ja
    integrado em lib_auto_market_analysis.ps1), NUNCA como gate isolado de
    "vai pumpar/dumpar" -- 60% dos movimentos reais testados nao dao nenhum
    aviso previo por volume.

    .NOTES
    2026-08-15: usa MEDIANA (nao media) do Lookback como baseline -- achado
    real (validacao contra dump real do TUT, -24%/24h): media e sensivel a
    outlier -- um unico pico de volume normal (109849 vs base ~15-30k) nas
    20h anteriores ao dump inflava a media base o suficiente pra diluir o
    ratio do candle real do dump pra 6.88x, ABAIXO do threshold 8x (nao
    disparava). Mediana e robusta a esse outlier: mesmo caso sobe pra 9.83x
    (dispara corretamente). Sem essa troca, o detector so funcionava bem em
    moedas com volume de base ja estavel (caso ACE original) e falhava em
    moedas ja voláteis/barulhentas de base (caso TUT).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Opens,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Volumes,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [double] $AccumMultiplier = 8.0,
        [int]    $Lookback = 20
    )
    $n = $Volumes.Length
    if ($n -lt $Lookback + 1) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="insufficient_history" }
    }

    $lastIdx = $n - 1
    $prior = @($Volumes[($n - 1 - $Lookback)..($lastIdx - 1)])
    $sorted = @($prior | Sort-Object)
    $mid = [int]($sorted.Count / 2)
    $avgVol = if ($sorted.Count % 2 -eq 0) {
        ($sorted[$mid - 1] + $sorted[$mid]) / 2.0
    } else {
        $sorted[$mid]
    }
    if ($avgVol -le 0) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="zero_avg_vol" }
    }

    $ratio = $Volumes[$lastIdx] / $avgVol
    if ($ratio -lt $AccumMultiplier) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="vol_below_accum_threshold"; vol_ratio=[math]::Round($ratio,2) }
    }

    $isGreen = $Closes[$lastIdx] -gt $Opens[$lastIdx]
    $isRed   = $Closes[$lastIdx] -lt $Opens[$lastIdx]
    $directionOk = if ($Side -eq "LONG") { $isGreen } else { $isRed }
    if (-not $directionOk) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; bar_idx=$null; reason="vol_spike_wrong_candle_direction"; vol_ratio=[math]::Round($ratio,2) }
    }

    $strength = [Math]::Min(100, [int](30 + ($ratio * 3)))
    return [PSCustomObject]@{
        detected=$true; pattern_name="volume_accumulation"; strength=$strength; bar_idx=$lastIdx
        vol_ratio=[math]::Round($ratio,2)
    }
}

function Detect-StructuralRejection {
    <#
    .SYNOPSIS
    Detecta preco perto de um nivel estrutural (suporte/resistencia real,
    via pivots) que falhou em romper nos ultimos N candles -- sinal de
    rejeicao, independente de padrao de vela ou pico de volume.

    .NOTES
    Achado real (2026-08-14, owner trouxe grafico BTC 1D): pico 66920 em
    21/07, grind de baixa ate 62872 em 13/08, com rejeicao clara na regiao
    64470-65361 (EMA20/50) nos ultimos ~9 candles antes do close. Nenhum
    candlestick pattern disparou (movimento gradual demais, sem gap/estrela)
    e Detect-VolumeAccumulation tambem nao (volume 0.81x, DECRESCENTE, nao
    e caso de spike) -- confirmado que essa classe de setup (rejeicao lenta
    de resistencia em tendencia de baixa, sem volume anomalo) e uma lacuna
    real dos detectores existentes, que so cobrem reversao abrupta (vela)
    ou acumulacao/climax (volume). Zero custo de API nova -- recebe os
    niveis de suporte/resistencia JA calculados por Get-AutoTimeframeAnalysis
    (Find-SupportLevels + espelho), so adiciona a checagem de proximidade +
    falha em romper que ate 2026-08-14 era descartada (support_levels/
    resistance_levels iam pro output mas nunca entravam no score).

    .PARAMETER Levels
    Array de niveis estruturais candidatos (resistances p/ SHORT, supports
    p/ LONG) -- mesmo array ja retornado por Find-SupportLevels/espelho.
    .PARAMETER ProximityPct
    Nivel so conta se estiver a ate ProximityPct% do preco atual (default
    5.0 -- perto o bastante pra ser relevante, mas nao exige toque exato).
    .PARAMETER FailureLookback
    Quantos candles anteriores (incl. o atual) precisam ter falhado em
    fechar alem do nivel pra confirmar rejeicao (default 5).

    .OUTPUTS
    PSCustomObject { detected, pattern_name="structural_rejection", strength,
    level, dist_pct }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [double[]] $Levels = @(),
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [double] $ProximityPct = 5.0,
        [int]    $FailureLookback = 5
    )
    $n = $Closes.Length
    if ($n -lt $FailureLookback) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="insufficient_history" }
    }
    if (@($Levels).Count -eq 0) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_levels" }
    }

    $price = $Closes[$n - 1]
    $recent = @($Closes[($n - $FailureLookback)..($n - 1)])

    # SHORT: resistencia ACIMA do preco, nenhum close recente pode ter
    # fechado acima dela. LONG: suporte ABAIXO, nenhum close recente pode
    # ter fechado abaixo dele.
    $candidates = if ($Side -eq "SHORT") {
        @($Levels | Where-Object { $_ -gt $price })
    } else {
        @($Levels | Where-Object { $_ -lt $price })
    }
    if ($candidates.Count -eq 0) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_level_on_correct_side" }
    }

    # Nivel mais proximo do preco (mais relevante pra rejeicao imediata)
    $nearest = if ($Side -eq "SHORT") {
        $candidates | Sort-Object | Select-Object -First 1
    } else {
        $candidates | Sort-Object -Descending | Select-Object -First 1
    }
    $distPct = [Math]::Abs(($nearest - $price) / $price) * 100.0
    if ($distPct -gt $ProximityPct) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_level_within_proximity"; dist_pct=[math]::Round($distPct,2) }
    }

    $failed = if ($Side -eq "SHORT") {
        -not ($recent | Where-Object { $_ -gt $nearest })
    } else {
        -not ($recent | Where-Object { $_ -lt $nearest })
    }
    if (-not $failed) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="level_broken_recently"; dist_pct=[math]::Round($distPct,2) }
    }

    # Nivel precisa ter sido de fato REJEITADO, nao so estar por perto no
    # ultimo candle. Achado real (2026-08-14, validacao contra o mesmo caso
    # BTC): um pivot de suporte a 0.34% do close passava direto pela
    # checagem de "nao rompeu" mesmo sem NUNCA ter havido bounce -- os
    # closes da janela convergiam MONOTONICAMENTE pro nivel (2.50% -> 1.11%
    # -> 0.56% -> 0.35% -> 0.34%), ou seja, o preco estava so CHEGANDO la
    # pela 1a vez, nao repelindo dele. Rejeicao real exige que algum ponto
    # anterior da janela tenha ficado MAIS PERTO do nivel do que o candle
    # atual (aproximou e recuou) -- convergencia pura (sempre mais perto a
    # cada candle) e desqualificada.
    $distToLevel = @($recent | ForEach-Object { [Math]::Abs(($nearest - $_) / $_) * 100.0 })
    $currentDist = $distToLevel[-1]
    $closerEarlier = $distToLevel[0..($distToLevel.Count - 2)] | Where-Object { $_ -lt $currentDist }
    if (-not $closerEarlier) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="monotonic_approach_not_rejection"; dist_pct=[math]::Round($distPct,2) }
    }

    $strength = [Math]::Min(100, [int](40 + ((($ProximityPct - $distPct) / $ProximityPct) * 40)))
    return [PSCustomObject]@{
        detected=$true; pattern_name="structural_rejection"; strength=$strength
        level=[math]::Round($nearest,6); dist_pct=[math]::Round($distPct,2)
    }
}


# ============================================================================
# 2. CANDLESTICK REVERSAL
# ============================================================================

function _CP-IsBearishTrend {
    param([double[]] $Closes, [int] $Lookback = 8)
    if ($Closes.Length -lt ($Lookback + 1)) { return $false }
    $start = $Closes.Length - $Lookback - 1
    $end   = $Closes.Length - 1   # nao inclui ultimo (sera testado)
    $down = 0; $up = 0
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Closes[$i] -lt $Closes[$i - 1]) { $down++ } else { $up++ }
    }
    return $down -gt $up
}


function _CP-IsBullishTrend {
    param([double[]] $Closes, [int] $Lookback = 8)
    if ($Closes.Length -lt ($Lookback + 1)) { return $false }
    $start = $Closes.Length - $Lookback - 1
    $end   = $Closes.Length - 1
    $down = 0; $up = 0
    for ($i = $start + 1; $i -lt $end; $i++) {
        if ($Closes[$i] -lt $Closes[$i - 1]) { $down++ } else { $up++ }
    }
    return $up -gt $down
}


function Detect-CandlestickReversal {
    <#
    .SYNOPSIS
    Detecta padrao candlestick reversal na ultima barra (ou nas ultimas 2-3
    barras, pros padroes multi-vela) com contexto de tendencia.

    LONG (ordem de prioridade -- mais confiavel primeiro):
      morning_star (3 velas) > bullish_harami / piercing_line (2 velas) >
      three_white_soldiers (3 velas, continuacao) > hammer / bullish_engulfing
      (ja existentes) > doji (1 vela, menor confianca sozinho)

    SHORT (espelhado):
      evening_star > bearish_harami / dark_cloud_cover >
      three_black_crows > shooting_star / bearish_engulfing > doji

    .NOTES
    2026-08-14: expansao do card de referencia classico (Doji, Harami,
    Piercing Line, Dark Cloud Cover, Morning/Evening Star, 3 Soldados
    Brancos/3 Corvos Negros) -- ate entao so hammer/engulfing/shooting star
    estavam implementados, apesar do cabecalho do arquivo de teste ja citar
    "doji/morning-evening star" desde a criacao original.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Opens,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side
    )
    $n = $Closes.Length
    if ($n -lt 10) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="insufficient_history" }
    }

    $i = $n - 1
    $body  = [Math]::Abs($Closes[$i] - $Opens[$i])
    $range = $Highs[$i] - $Lows[$i]
    $upper = $Highs[$i] - [Math]::Max($Closes[$i], $Opens[$i])
    $lower = [Math]::Min($Closes[$i], $Opens[$i]) - $Lows[$i]
    if ($range -le 0) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="zero_range" }
    }

    if ($Side -eq "LONG") {
        $isDownTrend = _CP-IsBearishTrend -Closes $Closes

        # MORNING STAR (3 velas, alta confiabilidade): bar i-2 bearish grande +
        # bar i-1 corpo pequeno (estrela, gap down) + bar i bullish grande
        # fechando acima do meio do corpo da bar i-2.
        if ($i -ge 2 -and $isDownTrend) {
            $body2 = $Opens[$i-2] - $Closes[$i-2]   # bar -2 esperada bearish
            $body1 = [Math]::Abs($Closes[$i-1] - $Opens[$i-1])
            $body0 = $Closes[$i] - $Opens[$i]        # bar 0 esperada bullish
            $bar2Bear = $Closes[$i-2] -lt $Opens[$i-2]
            $bar0Bull = $Closes[$i] -gt $Opens[$i]
            $starSmall = $body2 -gt 0 -and $body1 -le ($body2 * 0.4)
            $midBar2 = ($Opens[$i-2] + $Closes[$i-2]) / 2.0
            $closesAboveMid = $Closes[$i] -gt $midBar2
            if ($bar2Bear -and $bar0Bull -and $starSmall -and $closesAboveMid) {
                $strength = [Math]::Min(100, [int](60 + (($body0 / [Math]::Max($body2, 0.001)) * 10)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="morning_star"; strength=$strength; bar_idx=$i
                }
            }
        }

        # 3 SOLDADOS BRANCOS (3 velas, continuacao confirmada): 3 bullish
        # consecutivas, cada abrindo dentro do corpo anterior e fechando
        # numa nova alta, sem sombras superiores grandes (corpos solidos).
        if ($i -ge 2 -and $isDownTrend) {
            $bull2 = $Closes[$i-2] -gt $Opens[$i-2]
            $bull1 = $Closes[$i-1] -gt $Opens[$i-1]
            $bull0 = $Closes[$i] -gt $Opens[$i]
            $risingCloses = ($Closes[$i-1] -gt $Closes[$i-2]) -and ($Closes[$i] -gt $Closes[$i-1])
            $opensInsidePrior = ($Opens[$i-1] -gt $Opens[$i-2] -and $Opens[$i-1] -lt $Closes[$i-2]) -and
                                ($Opens[$i] -gt $Opens[$i-1] -and $Opens[$i] -lt $Closes[$i-1])
            if ($bull2 -and $bull1 -and $bull0 -and $risingCloses -and $opensInsidePrior) {
                return [PSCustomObject]@{
                    detected=$true; pattern_name="three_white_soldiers"; strength=75; bar_idx=$i
                }
            }
        }

        # HAMMER: lower shadow >=2x body + body pequeno + upper shadow pequeno + downtrend prior
        $hammerShape = ($lower -ge 2 * $body) -and ($upper -le $body) -and ($body -gt 0)
        if ($isDownTrend -and $hammerShape) {
            $strength = [Math]::Min(100, [int](40 + (($lower / [Math]::Max($body, 0.001)) * 5)))
            return [PSCustomObject]@{
                detected=$true; pattern_name="hammer"; strength=$strength; bar_idx=$i
                lower_shadow_ratio = [math]::Round($lower / [Math]::Max($body, 0.001), 2)
            }
        }

        # BULLISH ENGULFING: bar i-1 bearish + bar i bullish + body i envolve body i-1
        if ($i -ge 1) {
            $prevBear = $Closes[$i-1] -lt $Opens[$i-1]
            $currBull = $Closes[$i] -gt $Opens[$i]
            $engulfs  = ($Opens[$i] -le $Closes[$i-1]) -and ($Closes[$i] -ge $Opens[$i-1])
            if ($prevBear -and $currBull -and $engulfs -and $isDownTrend) {
                $bodyCurr = $Closes[$i] - $Opens[$i]
                $bodyPrev = $Opens[$i-1] - $Closes[$i-1]
                $strength = [Math]::Min(100, [int](50 + (($bodyCurr / [Math]::Max($bodyPrev, 0.001)) * 10)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="bullish_engulfing"; strength=$strength; bar_idx=$i
                    body_ratio = [math]::Round($bodyCurr / [Math]::Max($bodyPrev, 0.001), 2)
                }
            }
        }

        # HARAMI DE ALTA: bar i-1 bearish grande + bar i corpo pequeno,
        # TOTALMENTE contido dentro do corpo da bar i-1 (contracao -- mercado
        # perdendo forca vendedora).
        if ($i -ge 1 -and $isDownTrend) {
            $prevBear = $Closes[$i-1] -lt $Opens[$i-1]
            $bodyPrev = $Opens[$i-1] - $Closes[$i-1]
            $containedInside = ($Opens[$i] -gt $Closes[$i-1]) -and ($Opens[$i] -lt $Opens[$i-1]) -and
                                ($Closes[$i] -gt $Closes[$i-1]) -and ($Closes[$i] -lt $Opens[$i-1])
            if ($prevBear -and $containedInside -and $body -le ($bodyPrev * 0.5)) {
                $strength = [Math]::Min(100, [int](45 + ((1 - ($body / [Math]::Max($bodyPrev, 0.001))) * 30)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="bullish_harami"; strength=$strength; bar_idx=$i
                }
            }
        }

        # PIERCING LINE: bar i-1 bearish grande + bar i abre abaixo do low
        # anterior mas fecha ACIMA do meio do corpo anterior (recuperacao forte,
        # sem chegar a engolfar o corpo inteiro).
        if ($i -ge 1 -and $isDownTrend) {
            $prevBear = $Closes[$i-1] -lt $Opens[$i-1]
            $currBull = $Closes[$i] -gt $Opens[$i]
            $midPrev = ($Opens[$i-1] + $Closes[$i-1]) / 2.0
            $opensBelowLow = $Opens[$i] -lt $Closes[$i-1]
            $closesAboveMidBelowOpen = ($Closes[$i] -gt $midPrev) -and ($Closes[$i] -lt $Opens[$i-1])
            if ($prevBear -and $currBull -and $opensBelowLow -and $closesAboveMidBelowOpen) {
                return [PSCustomObject]@{
                    detected=$true; pattern_name="piercing_line"; strength=65; bar_idx=$i
                }
            }
        }

        # DOJI: corpo quase zero (indecisao) -- menor confianca sozinho,
        # por isso checado por ultimo dentre os padroes de reversao LONG.
        $isDoji = $range -gt 0 -and $body -le ($range * 0.1)
        if ($isDownTrend -and $isDoji) {
            return [PSCustomObject]@{
                detected=$true; pattern_name="doji"; strength=35; bar_idx=$i
            }
        }

        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_pattern_in_downtrend" }
    } else {
        $isUpTrend = _CP-IsBullishTrend -Closes $Closes

        # EVENING STAR (3 velas, alta confiabilidade): espelho do morning star.
        if ($i -ge 2 -and $isUpTrend) {
            $body2 = $Closes[$i-2] - $Opens[$i-2]   # bar -2 esperada bullish
            $body1 = [Math]::Abs($Closes[$i-1] - $Opens[$i-1])
            $body0 = $Opens[$i] - $Closes[$i]        # bar 0 esperada bearish
            $bar2Bull = $Closes[$i-2] -gt $Opens[$i-2]
            $bar0Bear = $Closes[$i] -lt $Opens[$i]
            $starSmall = $body2 -gt 0 -and $body1 -le ($body2 * 0.4)
            $midBar2 = ($Opens[$i-2] + $Closes[$i-2]) / 2.0
            $closesBelowMid = $Closes[$i] -lt $midBar2
            if ($bar2Bull -and $bar0Bear -and $starSmall -and $closesBelowMid) {
                $strength = [Math]::Min(100, [int](60 + (($body0 / [Math]::Max($body2, 0.001)) * 10)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="evening_star"; strength=$strength; bar_idx=$i
                }
            }
        }

        # 3 CORVOS NEGROS (3 velas, continuacao confirmada): espelho dos
        # 3 soldados brancos.
        if ($i -ge 2 -and $isUpTrend) {
            $bear2 = $Closes[$i-2] -lt $Opens[$i-2]
            $bear1 = $Closes[$i-1] -lt $Opens[$i-1]
            $bear0 = $Closes[$i] -lt $Opens[$i]
            $fallingCloses = ($Closes[$i-1] -lt $Closes[$i-2]) -and ($Closes[$i] -lt $Closes[$i-1])
            $opensInsidePrior = ($Opens[$i-1] -lt $Opens[$i-2] -and $Opens[$i-1] -gt $Closes[$i-2]) -and
                                ($Opens[$i] -lt $Opens[$i-1] -and $Opens[$i] -gt $Closes[$i-1])
            if ($bear2 -and $bear1 -and $bear0 -and $fallingCloses -and $opensInsidePrior) {
                return [PSCustomObject]@{
                    detected=$true; pattern_name="three_black_crows"; strength=75; bar_idx=$i
                }
            }
        }

        # SHOOTING STAR: upper shadow >=2x body + body pequeno + lower pequeno + uptrend prior
        $starShape = ($upper -ge 2 * $body) -and ($lower -le $body) -and ($body -gt 0)
        if ($isUpTrend -and $starShape) {
            $strength = [Math]::Min(100, [int](40 + (($upper / [Math]::Max($body, 0.001)) * 5)))
            return [PSCustomObject]@{
                detected=$true; pattern_name="shooting_star"; strength=$strength; bar_idx=$i
                upper_shadow_ratio = [math]::Round($upper / [Math]::Max($body, 0.001), 2)
            }
        }

        # BEARISH ENGULFING
        if ($i -ge 1) {
            $prevBull = $Closes[$i-1] -gt $Opens[$i-1]
            $currBear = $Closes[$i] -lt $Opens[$i]
            $engulfs  = ($Opens[$i] -ge $Closes[$i-1]) -and ($Closes[$i] -le $Opens[$i-1])
            if ($prevBull -and $currBear -and $engulfs -and $isUpTrend) {
                $bodyCurr = $Opens[$i] - $Closes[$i]
                $bodyPrev = $Closes[$i-1] - $Opens[$i-1]
                $strength = [Math]::Min(100, [int](50 + (($bodyCurr / [Math]::Max($bodyPrev, 0.001)) * 10)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="bearish_engulfing"; strength=$strength; bar_idx=$i
                    body_ratio = [math]::Round($bodyCurr / [Math]::Max($bodyPrev, 0.001), 2)
                }
            }
        }

        # HARAMI DE QUEDA: espelho do harami de alta.
        if ($i -ge 1 -and $isUpTrend) {
            $prevBull = $Closes[$i-1] -gt $Opens[$i-1]
            $bodyPrev = $Closes[$i-1] - $Opens[$i-1]
            $containedInside = ($Opens[$i] -lt $Closes[$i-1]) -and ($Opens[$i] -gt $Opens[$i-1]) -and
                                ($Closes[$i] -lt $Closes[$i-1]) -and ($Closes[$i] -gt $Opens[$i-1])
            if ($prevBull -and $containedInside -and $body -le ($bodyPrev * 0.5)) {
                $strength = [Math]::Min(100, [int](45 + ((1 - ($body / [Math]::Max($bodyPrev, 0.001))) * 30)))
                return [PSCustomObject]@{
                    detected=$true; pattern_name="bearish_harami"; strength=$strength; bar_idx=$i
                }
            }
        }

        # DARK CLOUD COVER: espelho do piercing line.
        if ($i -ge 1 -and $isUpTrend) {
            $prevBull = $Closes[$i-1] -gt $Opens[$i-1]
            $currBear = $Closes[$i] -lt $Opens[$i]
            $midPrev = ($Opens[$i-1] + $Closes[$i-1]) / 2.0
            $opensAboveHigh = $Opens[$i] -gt $Closes[$i-1]
            $closesBelowMidAboveOpen = ($Closes[$i] -lt $midPrev) -and ($Closes[$i] -gt $Opens[$i-1])
            if ($prevBull -and $currBear -and $opensAboveHigh -and $closesBelowMidAboveOpen) {
                return [PSCustomObject]@{
                    detected=$true; pattern_name="dark_cloud_cover"; strength=65; bar_idx=$i
                }
            }
        }

        # DOJI: menor confianca sozinho, checado por ultimo.
        $isDoji = $range -gt 0 -and $body -le ($range * 0.1)
        if ($isUpTrend -and $isDoji) {
            return [PSCustomObject]@{
                detected=$true; pattern_name="doji"; strength=35; bar_idx=$i
            }
        }

        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_pattern_in_uptrend" }
    }
}


# ============================================================================
# 3. RSI DIVERGENCE
# ============================================================================

function Detect-RsiDivergence {
    <#
    .SYNOPSIS
    Detecta divergencia entre price + RSI nos ultimos 2 swing lows (LONG) ou highs (SHORT).
    LONG bullish: price LL + RSI HL
    SHORT bearish: price HH + RSI LH
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [ValidateSet("LONG","SHORT")] [string] $Side,
        [int] $RsiPeriod = 14,
        [int] $SwingWindow = 2,
        [int] $Lookback = 30
    )
    $n = $Closes.Length
    if ($n -lt $Lookback) {
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="insufficient_history" }
    }

    $rsi = _CP-CalcRsiArray -Closes $Closes -Period $RsiPeriod
    $start = $n - $Lookback
    $closesWindow = $Closes[$start..($n-1)]
    $rsiWindow    = $rsi[$start..($n-1)]

    if ($Side -eq "LONG") {
        # Find last 2 swing lows in closes
        $swings = _CP-FindSwingLows -Lows $closesWindow -Window $SwingWindow
        if (@($swings).Count -lt 2) {
            return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="not_enough_swing_lows" }
        }
        $idx2 = $swings[-1]
        $idx1 = $swings[-2]
        $price1 = $closesWindow[$idx1]; $price2 = $closesWindow[$idx2]
        $rsi1   = $rsiWindow[$idx1];    $rsi2   = $rsiWindow[$idx2]
        # Bullish divergence: price LL (price2 < price1) AND RSI HL (rsi2 > rsi1)
        if (($price2 -lt $price1) -and ($rsi2 -gt $rsi1)) {
            $priceLLPct = (($price1 - $price2) / $price1) * 100
            $rsiHLDelta = $rsi2 - $rsi1
            $strength = [Math]::Min(100, [int](40 + ($priceLLPct * 2) + ($rsiHLDelta * 3)))
            return [PSCustomObject]@{
                detected=$true; pattern_name="bullish_divergence"; strength=$strength
                swing1_idx=($start + $idx1); swing2_idx=($start + $idx2)
                price_ll_pct=[math]::Round($priceLLPct,2); rsi_delta=[math]::Round($rsiHLDelta,2)
            }
        }
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_bullish_divergence" }
    } else {
        # SHORT bearish: price HH + RSI LH
        $closesNeg = $closesWindow | ForEach-Object { -$_ }
        $swings = _CP-FindSwingLows -Lows $closesNeg -Window $SwingWindow   # swing highs no preco = swing lows no negated
        if (@($swings).Count -lt 2) {
            return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="not_enough_swing_highs" }
        }
        $idx2 = $swings[-1]; $idx1 = $swings[-2]
        $price1 = $closesWindow[$idx1]; $price2 = $closesWindow[$idx2]
        $rsi1   = $rsiWindow[$idx1];    $rsi2   = $rsiWindow[$idx2]
        # HH price (price2 > price1) AND LH RSI (rsi2 < rsi1)
        if (($price2 -gt $price1) -and ($rsi2 -lt $rsi1)) {
            $priceHHPct = (($price2 - $price1) / $price1) * 100
            $rsiLHDelta = $rsi1 - $rsi2
            $strength = [Math]::Min(100, [int](40 + ($priceHHPct * 2) + ($rsiLHDelta * 3)))
            return [PSCustomObject]@{
                detected=$true; pattern_name="bearish_divergence"; strength=$strength
                swing1_idx=($start + $idx1); swing2_idx=($start + $idx2)
                price_hh_pct=[math]::Round($priceHHPct,2); rsi_delta=[math]::Round($rsiLHDelta,2)
            }
        }
        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_bearish_divergence" }
    }
}
