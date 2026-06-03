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
    Detecta padrao candlestick reversal na ultima barra com contexto de tendencia.
    LONG: hammer (em downtrend) OR bullish engulfing
    SHORT: shooting star (em uptrend) OR bearish engulfing
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

        return [PSCustomObject]@{ detected=$false; pattern_name=$null; strength=0; reason="no_pattern_in_downtrend" }
    } else {
        $isUpTrend = _CP-IsBullishTrend -Closes $Closes
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
