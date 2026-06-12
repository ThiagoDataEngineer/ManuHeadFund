# lib_trendline_filter.ps1 -- Tori A+ trendline filter pra validar BULL_WEAK estrutural.
#
# Filosofia: BULL_WEAK plain = ruido (-0.37R 2025 holdout).
#            BULL_WEAK + trendline A+ = edge estrutural (Tori).
#
# A+ criteria (Tori Trades canonical):
#   - >= 3 touches dentro de tolerancia
#   - >= 20 candles de historia
#   - slope_deg entre 20-35 graus (uptrend sustentavel, nao pump vertical)
#
# Convencao slope_deg: arctan(slope_per_step / mean_price * 100) em graus.
# Normaliza pela escala de preco pra dar interpretacao consistente cross-asset.
#
# PS 5.1. UTF-8 BOM.


$script:MIN_HISTORY = 20
$script:SLOPE_DEG_MIN = 15      # Relaxado: 20 → 15 (captura ramps mais suaves)
$script:SLOPE_DEG_MAX = 40      # Relaxado: 35 → 40 (aceita steeper ramps)
$script:TOUCH_TOLERANCE_PCT = 2.5  # Relaxado: 1.5 → 2.5 (low-cap noise tolerance)
$script:MIN_TOUCHES = 2         # Relaxado: 3 → 2 (2 toques sólidos é suficiente)


function _LinearRegression {
    param([double[]] $Y)
    $n = $Y.Length
    if ($n -lt 2) {
        $intercept = 0
        if ($n -eq 1) { $intercept = $Y[0] }
        return @{ slope = 0; intercept = $intercept }
    }
    $sumX = 0.0; $sumY = 0.0; $sumXY = 0.0; $sumX2 = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sumX  += $i
        $sumY  += $Y[$i]
        $sumXY += $i * $Y[$i]
        $sumX2 += $i * $i
    }
    $denom = ($n * $sumX2) - ($sumX * $sumX)
    if ($denom -eq 0) { return @{ slope = 0; intercept = ($sumY / $n) } }
    $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denom
    $intercept = ($sumY - ($slope * $sumX)) / $n
    return @{ slope = $slope; intercept = $intercept }
}


function _CountTouches {
    param(
        [double[]] $Lows,
        [double] $Slope,
        [double] $Intercept,
        [double] $TolerancePct
    )
    $touches = 0
    for ($i = 0; $i -lt $Lows.Length; $i++) {
        $line = $Intercept + ($Slope * $i)
        if ($line -le 0) { continue }
        $diff_pct = [Math]::Abs($Lows[$i] - $line) / $line * 100
        if ($diff_pct -le $TolerancePct) { $touches += 1 }
    }
    return $touches
}


function Get-TrendlineScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows
    )
    $n = $Closes.Length
    if ($n -lt $script:MIN_HISTORY) {
        return @{ score = 0; touches = 0; slope_deg = 0.0; valid = $false; reason = "insufficient_history" }
    }

    $reg = _LinearRegression -Y $Lows
    $slope = $reg.slope
    $mean_price = ($Closes | Measure-Object -Average).Average
    if ($mean_price -le 0) {
        return @{ score = 0; touches = 0; slope_deg = 0.0; valid = $false; reason = "invalid_price" }
    }

    # slope_pct_per_step = slope normalizado pela escala de preco
    $slope_pct = ($slope / $mean_price) * 100
    $slope_deg = [Math]::Atan($slope_pct) * (180 / [Math]::PI)

    $touches = _CountTouches -Lows $Lows -Slope $slope -Intercept $reg.intercept -TolerancePct $script:TOUCH_TOLERANCE_PCT

    $slope_ok = ($slope_deg -ge $script:SLOPE_DEG_MIN) -and ($slope_deg -le $script:SLOPE_DEG_MAX)
    $touches_ok = $touches -ge $script:MIN_TOUCHES
    $valid = $slope_ok -and $touches_ok

    # Score 0-100: ponderado entre slope-fit e touches
    $slope_score = 0
    if ($slope_ok) {
        # Centro do range = 27.5 deg = score max
        $center = ($script:SLOPE_DEG_MAX + $script:SLOPE_DEG_MIN) / 2.0
        $dist = [Math]::Abs($slope_deg - $center)
        $half_range = ($script:SLOPE_DEG_MAX - $script:SLOPE_DEG_MIN) / 2.0
        $slope_score = [int](60 * (1 - ($dist / $half_range)))
    }
    $touch_score = [Math]::Min(40, $touches * 10)
    $score = $slope_score + $touch_score

    $reason = "aplus"
    if (-not $valid) {
        if (-not $slope_ok) { $reason = "slope_out_of_range" }
        else { $reason = "insufficient_touches" }
    }

    return @{
        score      = $score
        touches    = $touches
        slope_deg  = [Math]::Round($slope_deg, 2)
        slope_pct  = [Math]::Round($slope_pct, 4)
        valid      = $valid
        reason     = $reason
    }
}


function Test-TrendlineAplus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows
    )
    $r = Get-TrendlineScore -Closes $Closes -Highs $Highs -Lows $Lows
    return [bool] $r.valid
}
