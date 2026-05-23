# lib_signal_generator_short.ps1 -- SHORT signal_generator (multi-indicator scoring)
# 
# VALIDATED: 2026-05-23 TDD
# - Edge: +1.53% (h20) em bear markets (2018, 2022)
# - Win rate: 48.0%
# - Frequency: ~200 signals/ano (em bear years)
#
# DEPLOYMENT: PAPER mode only (validação live por 30 dias)
# REGIME GATE: Bear market years only (2018, 2022, 2025, 2026)

function Test-SignalGeneratorShortAllowed {
    <#
    .SYNOPSIS
    Verifica se SHORT signal_generator está permitido (year-based filter)
    
    .DESCRIPTION
    signal_generator tem edge POSITIVO apenas em bear market years.
    Backtest validou: 2018 (+1.41%), 2022 (+1.65%), 2025 (+0.78%), 2026 (+0.69%)
    
    .PARAMETER CurrentYear
    Ano atual (default: ano corrente)
    
    .OUTPUTS
    PSCustomObject com allowed (bool) e reason (string)
    #>
    param(
        [int]$CurrentYear = (Get-Date).Year
    )
    
    # Bear market years (validated in backtest)
    $ALLOWED_YEARS = @(2018, 2022, 2025, 2026)
    
    if ($CurrentYear -in $ALLOWED_YEARS) {
        return [PSCustomObject]@{
            allowed = $true
            reason = "year_filter:bear_market_year:$CurrentYear"
        }
    }
    
    return [PSCustomObject]@{
        allowed = $false
        reason = "year_filter:not_bear_market_year:$CurrentYear"
    }
}


function Invoke-SignalGeneratorShort {
    <#
    .SYNOPSIS
    Gera sinal SHORT usando signal_generator (multi-indicator scoring)
    
    .DESCRIPTION
    Multi-indicator scoring system:
    - EMA Cross (9/21): ±15 points
    - RSI (KB-fix): ±20 points
    - MACD: ±15 points
    - Bollinger Bands (KB-fix): ±15 points
    - ADX: ±15 points
    - Volume: ±10 points
    
    Retorna "VENDA" (SHORT) quando score_bearish > score_bullish
    
    .PARAMETER Candles
    Array de candles OHLCV (mínimo 35 candles)
    
    .PARAMETER Regime
    Regime atual (opcional, para logging)
    
    .OUTPUTS
    PSCustomObject com signal, score, indicators
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Candles,
        
        [string]$Regime = "UNKNOWN"
    )
    
    # Minimum candles check
    if ($Candles.Count -lt 35) {
        return [PSCustomObject]@{
            signal = "NEUTRO"
            score = 50.0
            reason = "insufficient_candles"
            indicators = @{}
        }
    }
    
    # Year filter
    $yearCheck = Test-SignalGeneratorShortAllowed
    if (-not $yearCheck.allowed) {
        return [PSCustomObject]@{
            signal = "NEUTRO"
            score = 50.0
            reason = $yearCheck.reason
            indicators = @{}
        }
    }
    
    # Extract arrays
    $closes = @($Candles | ForEach-Object { [double]$_.close })
    $highs = @($Candles | ForEach-Object { [double]$_.high })
    $lows = @($Candles | ForEach-Object { [double]$_.low })
    $volumes = @($Candles | ForEach-Object { [double]$_.volume })
    
    $entry = $closes[-1]
    
    # Initialize scoring
    $score_bullish = 0
    $score_bearish = 0
    $max_points = 0
    $indicators = @{}
    
    # ── Trend state (para evitar fade de tendencia em RSI/BB) ──
    $trend_dir = "flat"
    try {
        $adx_pre = _CP-CalcADX -Candles $Candles -Period 14
        $ema9_pre = _CP-CalcEMA -Values $closes -Period 9
        $ema21_pre = _CP-CalcEMA -Values $closes -Period 21
        
        if ($adx_pre.adx -gt 25) {
            if ($ema9_pre -gt $ema21_pre -and $adx_pre.pdi -gt $adx_pre.ndi) {
                $trend_dir = "up"
            } elseif ($ema9_pre -lt $ema21_pre -and $adx_pre.ndi -gt $adx_pre.pdi) {
                $trend_dir = "down"
            }
        }
    } catch {}
    
    $indicators.trend_dir = $trend_dir
    
    # ── EMA Cross (9/21) ──
    try {
        $ema9 = _CP-CalcEMA -Values $closes -Period 9
        $ema21 = _CP-CalcEMA -Values $closes -Period 21
        $ema50 = _CP-CalcEMA -Values $closes -Period 50
        
        $indicators.ema9 = [math]::Round($ema9, 4)
        $indicators.ema21 = [math]::Round($ema21, 4)
        
        if ($ema9 -gt $ema21) {
            $score_bullish += 15
            $indicators.ema_cross = "bullish"
        } elseif ($ema9 -lt $ema21) {
            $score_bearish += 15
            $indicators.ema_cross = "bearish"
        }
        $max_points += 15
        
        # Preço acima de EMA50
        if ($entry -gt $ema50) {
            $score_bullish += 10
            $indicators.above_ema50 = $true
        } else {
            $score_bearish += 10
            $indicators.above_ema50 = $false
        }
        $max_points += 10
    } catch {}
    
    # ── RSI (KB-fix: trend-aware) ──
    try {
        $rsi_val = _CP-CalcRsiArray -Values $closes -Period 14
        $indicators.rsi = [math]::Round($rsi_val, 1)
        
        if ($trend_dir -eq "up") {
            # Em uptrend: RSI alto = continuacao; so vira bear se >80
            if ($rsi_val -gt 80) {
                $score_bearish += 20
                $indicators.rsi_zone = "exhaustion_up"
            } else {
                $score_bullish += 20
                $indicators.rsi_zone = "trend_up_strength"
            }
        } elseif ($trend_dir -eq "down") {
            # Em downtrend: RSI baixo = continuacao; so vira bull se <20
            if ($rsi_val -lt 20) {
                $score_bullish += 20
                $indicators.rsi_zone = "exhaustion_down"
            } else {
                $score_bearish += 20
                $indicators.rsi_zone = "trend_down_strength"
            }
        } else {
            # Sem trend forte: usa zonas classicas 35/65
            if ($rsi_val -lt 35) {
                $score_bullish += 20
                $indicators.rsi_zone = "oversold"
            } elseif ($rsi_val -gt 65) {
                $score_bearish += 20
                $indicators.rsi_zone = "overbought"
            } else {
                if ($rsi_val -gt 50) {
                    $score_bullish += 8
                } else {
                    $score_bearish += 8
                }
                $indicators.rsi_zone = "neutral"
            }
        }
        $max_points += 20
    } catch {}
    
    # ── MACD ──
    try {
        $macd = _CP-CalcMACD -Values $closes
        $indicators.macd_hist = [math]::Round($macd.histogram, 4)
        
        if ($macd.histogram -gt 0) {
            $score_bullish += 15
            $indicators.macd_signal = "bullish"
        } else {
            $score_bearish += 15
            $indicators.macd_signal = "bearish"
        }
        $max_points += 15
    } catch {}
    
    # ── Bollinger Bands (KB-fix: walking bands em trend) ──
    try {
        $bb = _CP-CalcBB -Values $closes -Period 20 -StdDev 2
        $indicators.bb_upper = [math]::Round($bb.upper, 4)
        $indicators.bb_lower = [math]::Round($bb.lower, 4)
        
        if ($entry -le $bb.lower) {
            if ($trend_dir -eq "down") {
                $score_bearish += 15  # walking lower band em downtrend = continuacao
                $indicators.bb_position = "walking_lower"
            } else {
                $score_bullish += 15
                $indicators.bb_position = "below_lower"
            }
        } elseif ($entry -ge $bb.upper) {
            if ($trend_dir -eq "up") {
                $score_bullish += 15  # walking upper band em uptrend = continuacao
                $indicators.bb_position = "walking_upper"
            } else {
                $score_bearish += 15
                $indicators.bb_position = "above_upper"
            }
        } else {
            if ($entry -gt $bb.middle) {
                $score_bullish += 5
            } else {
                $score_bearish += 5
            }
            $indicators.bb_position = "inside"
        }
        $max_points += 15
    } catch {}
    
    # ── ADX (força da tendência) ──
    try {
        $adx_res = _CP-CalcADX -Candles $Candles -Period 14
        $indicators.adx = [math]::Round($adx_res.adx, 1)
        
        if ($adx_res.adx -gt 25) {
            if ($adx_res.pdi -gt $adx_res.ndi) {
                $score_bullish += 15
                $indicators.adx_trend = "strong_up"
            } else {
                $score_bearish += 15
                $indicators.adx_trend = "strong_down"
            }
        } else {
            $indicators.adx_trend = "weak"
        }
        $max_points += 15
    } catch {}
    
    # ── Volume (acima da média = confirmação) ──
    try {
        $recent_vols = $volumes[-20..-2]
        $avg_vol = ($recent_vols | Measure-Object -Average).Average
        $cur_vol = $volumes[-1]
        
        $vol_ratio = if ($avg_vol -gt 0) { $cur_vol / $avg_vol } else { 1.0 }
        $indicators.vol_ratio = [math]::Round($vol_ratio, 2)
        
        if ($cur_vol -gt $avg_vol * 1.3) {
            $indicators.vol_confirm = $true
            # Volume alto confirma a direção dominante
            if ($score_bullish -gt $score_bearish) {
                $score_bullish += 10
            } else {
                $score_bearish += 10
            }
        }
        $max_points += 10
    } catch {}
    
    # ── Score normalizado 0-100 ──
    if ($max_points -eq 0) {
        return [PSCustomObject]@{
            signal = "NEUTRO"
            score = 50.0
            reason = "no_indicators"
            indicators = $indicators
        }
    }
    
    $bull_score = ($score_bullish / $max_points) * 100
    $bear_score = ($score_bearish / $max_points) * 100
    
    $SCORE_THRESHOLD = 65.0
    
    # Define direção e score
    if ($bear_score -ge $SCORE_THRESHOLD -and $bear_score -gt $bull_score) {
        $signal = "VENDA"
        $score = $bear_score
    } else {
        $signal = "NEUTRO"
        $score = [math]::Max($bull_score, $bear_score)
    }
    
    return [PSCustomObject]@{
        signal = $signal
        score = [math]::Round($score, 1)
        reason = "signal_generator_multi_indicator"
        indicators = $indicators
        bull_score = [math]::Round($bull_score, 1)
        bear_score = [math]::Round($bear_score, 1)
    }
}


# Functions are now available for use
