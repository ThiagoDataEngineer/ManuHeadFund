# lib_tori_proximity.ps1 -- Tori trendline PROXIMITY scanner (anticipatory).
#
# Filosofia: GEM/V6 atuais validam Tori DEPOIS que vol_spike acorda o pipeline
# (lagging). Esta lib computa proximidade da action_line ANTES do bounce, dando
# tempo de assistir o setup maturar.
#
# Determinístico, ZERO LLM. Reaproveita Get-TrendlineScore + _LinearRegression
# de lib_trendline_filter.ps1 (mesma matemática já validada em backtest).
#
# Saída:
#   Get-ToriProximity -Market <X> -> PSCustomObject {
#       market, valid, reason?, price, action_line, proximity_pct,
#       touches, slope_deg, rsi, vol_drying, setup_ripening
#   }
#
#   setup_ripening (side-aware, 4-AND predicate):
#     LONG  (ascending support bounce):
#       - trendline valida (>=3 toques em LOWS, slope +5deg a +35deg soft gate)
#       - proximity -3% a +5% (preco descendo testar a linha de baixo)
#       - RSI < 40 (oversold curto, espaco pra bounce)
#       - vol secando (compressao pre-explosao)
#     SHORT (descending resistance rejection):
#       - trendline valida (>=3 toques em HIGHS, slope -5deg a -35deg)
#       - proximity -5% a +3% (preco subindo testar a linha de cima)
#       - RSI > 60 (overbought curto, rally exaurindo)
#       - vol secando (forca da subida exaurindo)
#
# PS 5.1. UTF-8 BOM.

# Auto-contida -- nao dot-source lib_trendline_filter (canonical Tori A+ 20-35deg
# eh muito restritivo pra varredura; aqui usamos soft 5-35deg validado em backtest
# 2026-05-19: trendline soft 5-15deg venceu todos os backtests
# (Sharpe 8.84, +1.32R, metade do DD). Ver MEMORY refino_v2_breakthrough.
#
# Inlining tambem garante zero side-effects e zero dependency drift.

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }


# ── Defaults ─────────────────────────────────────────────────────────────────

# Trendline gate (VALIDATED 2026-05-23 TDD)
$script:TORI_PROX_SLOPE_DEG_MIN  = 5.0    # uptrend gentil (validated)
$script:TORI_PROX_SLOPE_DEG_MAX  = 35.0   # uptrend moderado (validated)
$script:TORI_PROX_TOUCH_TOL_PCT  = 1.5    # +-1.5% da linha = touch
$script:TORI_PROX_MIN_TOUCHES    = 3      # MINIMUM 3 touches (knowledge-based)
$script:TORI_PROX_MIN_HISTORY    = 20

# Ripening predicate (VALIDATED 2026-05-23 TDD)
$script:TORI_PROX_PCT_MIN     = -3.0   # preco ate 3% abaixo da linha
$script:TORI_PROX_PCT_MAX     =  5.0   # preco ate 5% acima da linha

# FILTERS REMOVED (validated as unnecessary):
# - RSI filter: NO improvement (median +0.70% vs +0.70%)
# - Vol drying: NO improvement (blocks all signals)
# USE REGIME FILTER + TAKE-PROFIT instead (validated +4.30pp improvement)

# Regime filter (VALIDATED 2026-05-23 TDD)
# Other years (consolidation): median +3.20% vs +0.70% baseline
$script:TORI_OTHER_YEARS = @(2012, 2016, 2019, 2023, 2026, 2027, 2028, 2029, 2030)
$script:TORI_BULL_YEARS  = @(2013, 2017, 2020, 2021, 2024, 2025)  # median -0.25% (AVOID)
$script:TORI_BEAR_YEARS  = @(2014, 2015, 2018, 2022)              # median -3.18% (AVOID)

# Take-profit (VALIDATED 2026-05-23 TDD)
# TP +5%: median +5.00% vs +0.70% baseline (+4.30pp improvement, p=0.0087)
$script:TORI_TAKE_PROFIT_PCT = 5.0

# Candle fetch
$script:TORI_PROX_CANDLES_TF  = "4hour"
$script:TORI_PROX_CANDLES_N   = 80
$script:TORI_PROX_API_TIMEOUT = 10


# ── Helpers matematicos (inlined) ────────────────────────────────────────────

function _ToriProx-LinearRegression {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]] $Y)
    $n = $Y.Length
    if ($n -lt 2) {
        $intercept = if ($n -eq 1) { $Y[0] } else { 0 }
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


function _ToriProx-CountTouches {
    [CmdletBinding()]
    param(
        [double[]] $Lows,
        [double]   $Slope,
        [double]   $Intercept,
        [double]   $TolerancePct = 1.5
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


# ── Fetchers (inlined pra desacoplar de tech_agent.ps1) ──────────────────────

function _ToriProx-GetCandles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $Period = $script:TORI_PROX_CANDLES_TF,
        [int]    $Limit  = $script:TORI_PROX_CANDLES_N
    )
    $urls = @(
        "https://api.coinex.com/v2/futures/kline?market=$Market&period=$Period&limit=$Limit",
        "https://api.coinex.com/v2/spot/kline?market=$Market&period=$Period&limit=$Limit"
    )
    foreach ($u in $urls) {
        try {
            $r = Invoke-RestMethod -Uri $u -Method GET -TimeoutSec $script:TORI_PROX_API_TIMEOUT -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -gt 0) {
                return @($r.data | ForEach-Object {
                    [PSCustomObject]@{
                        ts     = $_.created_at
                        open   = [double]$_.open
                        high   = [double]$_.high
                        low    = [double]$_.low
                        close  = [double]$_.close
                        volume = [double]$_.volume
                    }
                })
            }
        } catch {}
    }
    return @()
}


function _ToriProx-CalcRSI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [int] $Period = 14
    )
    if ($Closes.Length -lt ($Period + 1)) { return 50.0 }
    $g = 0.0; $l = 0.0
    for ($i = 1; $i -le $Period; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        if ($d -gt 0) { $g += $d } else { $l += [math]::Abs($d) }
    }
    $ag = $g / $Period; $al = $l / $Period
    for ($i = $Period + 1; $i -lt $Closes.Length; $i++) {
        $d = $Closes[$i] - $Closes[$i - 1]
        if ($d -gt 0) {
            $ag = ($ag * ($Period - 1) + $d) / $Period
            $al = $al * ($Period - 1) / $Period
        } else {
            $ag = $ag * ($Period - 1) / $Period
            $al = ($al * ($Period - 1) + [math]::Abs($d)) / $Period
        }
    }
    if ($al -eq 0) { return 100.0 }
    return 100 - (100 / (1 + $ag / $al))
}


# ── Core: proximidade derivada de Get-TrendlineScore + projecao linear ───────

function Get-ToriProximityFromArrays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Volumes
    )

    # $Highs reservado para extensao SHORT-side (descending trendline em highs) -- futura
    $null = $Highs

    $n = $Closes.Length
    if ($n -lt $script:TORI_PROX_MIN_HISTORY) {
        return [PSCustomObject]@{
            valid          = $false
            reason         = "insufficient_history"
            touches        = 0
            slope_deg      = 0.0
            price          = if ($n -gt 0) { $Closes[-1] } else { $null }
            action_line    = $null
            proximity_pct  = $null
            rsi            = $null
            vol_drying     = $null
            setup_ripening = $false
        }
    }

    # Regressao sobre lows (suporte ascendente)
    $reg = _ToriProx-LinearRegression -Y $Lows
    $slope = $reg.slope
    $mean_price = ($Closes | Measure-Object -Average).Average

    if ($mean_price -le 0) {
        return [PSCustomObject]@{
            valid=$false; reason="invalid_price"; touches=0; slope_deg=0.0
            price=$Closes[-1]; action_line=$null; proximity_pct=$null
            rsi=$null; vol_drying=$null; setup_ripening=$false
        }
    }

    $slope_pct = ($slope / $mean_price) * 100
    $slope_deg = [Math]::Atan($slope_pct) * (180 / [Math]::PI)

    $touches = _ToriProx-CountTouches -Lows $Lows -Slope $slope -Intercept $reg.intercept -TolerancePct $script:TORI_PROX_TOUCH_TOL_PCT

    # Gate soft 5-35deg (mais permissivo que Tori A+ canonical 20-35deg)
    $slope_ok   = ($slope_deg -ge $script:TORI_PROX_SLOPE_DEG_MIN) -and ($slope_deg -le $script:TORI_PROX_SLOPE_DEG_MAX)
    $touches_ok = $touches -ge $script:TORI_PROX_MIN_TOUCHES

    if (-not $slope_ok -or -not $touches_ok) {
        $reason = if (-not $slope_ok) { "slope_out_of_range" } else { "insufficient_touches" }
        return [PSCustomObject]@{
            valid          = $false
            reason         = $reason
            touches        = $touches
            slope_deg      = [Math]::Round($slope_deg, 2)
            price          = $Closes[-1]
            action_line    = $null
            proximity_pct  = $null
            rsi            = $null
            vol_drying     = $null
            setup_ripening = $false
        }
    }

    $action_line = $reg.intercept + ($slope * ($n - 1))
    $price       = $Closes[-1]

    if ($action_line -le 0) {
        return [PSCustomObject]@{
            valid          = $false
            reason         = "invalid_action_line"
            touches        = $touches
            slope_deg      = [Math]::Round($slope_deg, 2)
            price          = $price
            action_line    = $action_line
            proximity_pct  = $null
            rsi            = $null
            vol_drying     = $null
            setup_ripening = $false
        }
    }

    $proximity_pct = (($price - $action_line) / $action_line) * 100

    # 4. Regime filter (VALIDATED 2026-05-23 TDD)
    # Other years (consolidation): +2.50pp improvement
    # Bull/bear years: negative edge (avoid)
    $currentYear = (Get-Date).Year
    $regime_ok = $currentYear -in $script:TORI_OTHER_YEARS
    
    if (-not $regime_ok) {
        return [PSCustomObject]@{
            valid          = $false
            reason         = "regime_filter_bull_or_bear"
            touches        = $touches
            slope_deg      = [Math]::Round($slope_deg, 2)
            price          = $Closes[-1]
            action_line    = $action_line
            proximity_pct  = [Math]::Round($proximity_pct, 2)
            rsi            = $null
            vol_drying     = $null
            setup_ripening = $false
        }
    }
    
    # 5. Setup ripening (SIMPLIFIED - no RSI/vol filters)
    # VALIDATED: RSI and vol_drying do NOT improve edge
    # Only trendline quality + proximity + regime matter
    $ripening = ($proximity_pct -ge $script:TORI_PROX_PCT_MIN) -and `
                ($proximity_pct -le $script:TORI_PROX_PCT_MAX)

    return [PSCustomObject]@{
        valid          = $true
        reason         = "ok"
        side           = "LONG"
        touches        = $touches
        slope_deg      = [Math]::Round($slope_deg, 2)
        price          = [math]::Round($price, 6)
        action_line    = [math]::Round($action_line, 6)
        proximity_pct  = [math]::Round($proximity_pct, 2)
        rsi            = $null  # Removed (not used)
        vol_drying     = $null  # Removed (not used)
        setup_ripening = $ripening
        take_profit    = [math]::Round($price * (1 + $script:TORI_TAKE_PROFIT_PCT / 100), 6)  # +5% TP (VALIDATED)
        stop_loss      = [math]::Round($action_line * 0.98, 6)  # -2% below trendline
    }
}


# ── SHORT-side proximity (descending resistance, mirror em highs) ────────────
#
# Setup-tipo: bear market rally rejection. Preco subindo testar a linha
# descendente (resistencia), candidato a reverter pra continuacao do downtrend.
#
# Gate slope: -35 a -5deg (downtrend gentil ate vertical inverso). Touches >= 3
# em highs. Ripening: prox in [-5%, +3%] (preco subindo aproximar de cima),
# RSI > 60 (overbought de curto), vol secando.

function Get-ToriShortProximityFromArrays {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]] $Closes,
        [Parameter(Mandatory)] [double[]] $Highs,
        [Parameter(Mandatory)] [double[]] $Lows,
        [Parameter(Mandatory)] [double[]] $Volumes
    )
    $null = $Lows  # reservado pra confluencia futura

    $n = $Closes.Length
    if ($n -lt $script:TORI_PROX_MIN_HISTORY) {
        return [PSCustomObject]@{
            valid=$false; reason="insufficient_history"; side="SHORT"
            touches=0; slope_deg=0.0
            price=$(if ($n -gt 0) { $Closes[-1] } else { $null })
            action_line=$null; proximity_pct=$null; rsi=$null; vol_drying=$null
            setup_ripening=$false
        }
    }

    # Regressao sobre HIGHS (resistencia descendente)
    $reg = _ToriProx-LinearRegression -Y $Highs
    $slope = $reg.slope
    $mean_price = ($Closes | Measure-Object -Average).Average

    if ($mean_price -le 0) {
        return [PSCustomObject]@{
            valid=$false; reason="invalid_price"; side="SHORT"
            touches=0; slope_deg=0.0; price=$Closes[-1]
            action_line=$null; proximity_pct=$null; rsi=$null; vol_drying=$null
            setup_ripening=$false
        }
    }

    $slope_pct = ($slope / $mean_price) * 100
    $slope_deg = [Math]::Atan($slope_pct) * (180 / [Math]::PI)

    # Touch counting em HIGHS (tolerancia 1.5%)
    $touches = _ToriProx-CountTouches -Lows $Highs -Slope $slope -Intercept $reg.intercept -TolerancePct $script:TORI_PROX_TOUCH_TOL_PCT

    # Gate: slope NEGATIVO de -35 a -5deg (mirror do LONG +5 a +35)
    $slope_ok   = ($slope_deg -le -$script:TORI_PROX_SLOPE_DEG_MIN) -and ($slope_deg -ge -$script:TORI_PROX_SLOPE_DEG_MAX)
    $touches_ok = $touches -ge $script:TORI_PROX_MIN_TOUCHES

    if (-not $slope_ok -or -not $touches_ok) {
        $reason = if (-not $slope_ok) { "slope_out_of_range" } else { "insufficient_touches" }
        return [PSCustomObject]@{
            valid=$false; reason=$reason; side="SHORT"
            touches=$touches; slope_deg=[Math]::Round($slope_deg, 2)
            price=$Closes[-1]; action_line=$null; proximity_pct=$null
            rsi=$null; vol_drying=$null; setup_ripening=$false
        }
    }

    $action_line = $reg.intercept + ($slope * ($n - 1))
    $price       = $Closes[-1]

    if ($action_line -le 0) {
        return [PSCustomObject]@{
            valid=$false; reason="invalid_action_line"; side="SHORT"
            touches=$touches; slope_deg=[Math]::Round($slope_deg, 2)
            price=$price; action_line=$action_line; proximity_pct=$null
            rsi=$null; vol_drying=$null; setup_ripening=$false
        }
    }

    # SHORT: proximity = quanto preco esta ABAIXO da linha (negativo = subindo testar)
    $proximity_pct = (($price - $action_line) / $action_line) * 100

    $rsi = _ToriProx-CalcRSI -Closes $Closes -Period 14

    $vol_drying = $false
    if ($Volumes.Length -ge 10) {
        $recent = $Volumes[($Volumes.Length - 3)..($Volumes.Length - 1)]
        $prior  = $Volumes[($Volumes.Length - 10)..($Volumes.Length - 4)]
        $recentAvg = ($recent | Measure-Object -Average).Average
        $priorAvg  = ($prior  | Measure-Object -Average).Average
        if ($priorAvg -gt 0) {
            $vol_drying = $recentAvg -lt ($priorAvg * $script:TORI_PROX_VOL_RATIO)
        }
    }

    # SHORT ripening: preco aproximando da linha DESCENDENTE FROM BELOW
    # prox de -5% (5% abaixo da linha = se aproximando) ate +3% (acabou de tocar/passou levemente)
    # RSI > 60 (overbought rally em bear) | vol secando (forca da subida exaurindo)
    $ripening = ($proximity_pct -ge -5.0) -and `
                ($proximity_pct -le 3.0) -and `
                ($rsi -gt 60.0) -and `
                $vol_drying

    return [PSCustomObject]@{
        valid          = $true
        reason         = "ok"
        side           = "SHORT"
        touches        = $touches
        slope_deg      = [Math]::Round($slope_deg, 2)
        price          = [math]::Round($price, 6)
        action_line    = [math]::Round($action_line, 6)
        proximity_pct  = [math]::Round($proximity_pct, 2)
        rsi            = [math]::Round($rsi, 1)
        vol_drying     = $vol_drying
        setup_ripening = $ripening
    }
}


function Get-ToriProximity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $Period = $script:TORI_PROX_CANDLES_TF,
        [int]    $Limit  = $script:TORI_PROX_CANDLES_N
    )
    $candles = _ToriProx-GetCandles -Market $Market -Period $Period -Limit $Limit
    if (-not $candles -or @($candles).Count -lt $script:TORI_PROX_MIN_HISTORY) {
        return [PSCustomObject]@{
            market         = $Market
            valid          = $false
            reason         = "no_candles_or_insufficient"
            side           = "NONE"
            price          = $null
            action_line    = $null
            proximity_pct  = $null
            touches        = 0
            slope_deg      = 0.0
            rsi            = $null
            vol_drying     = $null
            setup_ripening = $false
            long_side      = $null
            short_side     = $null
        }
    }

    $closes  = @($candles | ForEach-Object { $_.close })
    $highs   = @($candles | ForEach-Object { $_.high })
    $lows    = @($candles | ForEach-Object { $_.low })
    $volumes = @($candles | ForEach-Object { $_.volume })

    $long  = Get-ToriProximityFromArrays      -Closes $closes -Highs $highs -Lows $lows -Volumes $volumes
    $short = Get-ToriShortProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $volumes

    # Escolha do "active side": prioriza ripening (acionavel). Se ambos ripening,
    # ganha o de proximidade absoluta menor (mais cedo no setup). Se nenhum ripening,
    # retorna o lado valido (se algum), senao o long (com reason).
    $active = $null
    if ($long.setup_ripening -and $short.setup_ripening) {
        $active = if ([math]::Abs($long.proximity_pct) -le [math]::Abs($short.proximity_pct)) { $long } else { $short }
    } elseif ($long.setup_ripening) {
        $active = $long
    } elseif ($short.setup_ripening) {
        $active = $short
    } elseif ($long.valid -and $short.valid) {
        # Ambos validos sem ripening: prefere o de proximidade absoluta menor
        $active = if ([math]::Abs($long.proximity_pct) -le [math]::Abs($short.proximity_pct)) { $long } else { $short }
    } elseif ($long.valid) {
        $active = $long
    } elseif ($short.valid) {
        $active = $short
    } else {
        $active = $long  # ambos invalidos: usa LONG default com reason
    }

    return [PSCustomObject]@{
        market         = $Market
        valid          = [bool]$active.valid
        reason         = "$($active.reason)"
        side           = "$($active.side)"
        price          = $active.price
        action_line    = $active.action_line
        proximity_pct  = $active.proximity_pct
        touches        = $active.touches
        slope_deg      = $active.slope_deg
        rsi            = $active.rsi
        vol_drying     = $active.vol_drying
        setup_ripening = [bool]$active.setup_ripening
        long_side      = $long
        short_side     = $short
    }
}


# ── Dedup helper (rolling alerts) ────────────────────────────────────────────

function Test-ProximityAlertRecent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $JsonlPath,
        [int] $TtlMinutes = 240
    )
    if (-not (Test-Path $JsonlPath)) { return $false }
    $cutoff = (Get-Date).ToUniversalTime().AddMinutes(-$TtlMinutes)
    try {
        $lines = Get-Content $JsonlPath -Encoding UTF8 -ErrorAction Stop
    } catch { return $false }
    foreach ($line in $lines) {
        if (-not $line) { continue }
        try {
            $j = $line | ConvertFrom-Json
            if ($j.market -ne $Market) { continue }
            $ts = ([datetimeoffset]::Parse($j.ts_utc)).UtcDateTime
            if ($ts -ge $cutoff) { return $true }
        } catch {}
    }
    return $false
}


function Add-ProximityAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $JsonlPath,
        [Parameter(Mandatory)] [PSObject] $Proximity
    )
    $entry = [ordered]@{
        ts_utc         = (Get-Date).ToUniversalTime().ToString("o")
        market         = $Market
        price          = $Proximity.price
        action_line    = $Proximity.action_line
        proximity_pct  = $Proximity.proximity_pct
        touches        = $Proximity.touches
        slope_deg      = $Proximity.slope_deg
        rsi            = $Proximity.rsi
        vol_drying     = $Proximity.vol_drying
    }
    $json = $entry | ConvertTo-Json -Compress
    $dir = Split-Path -Parent $JsonlPath
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Add-Content -Path $JsonlPath -Value $json -Encoding UTF8
}


# ── Snapshot consumers (discovery: scan_master / gem_loop / Mentor) ──────────
#
# Contract:
#   scanner cron escreve journal/tori_proximity_state.json a cada 15min.
#   Consumers leem com TTL guard (default 30min = 2x ciclo) -- snapshot stale
#   eh ignorado, fail-safe (consumer recebe array vazio / market=$null).

function Get-ToriProximitySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StatePath,
        [int] $MaxAgeMinutes = 30    # fresco se ts_utc dentro deste range
    )
    if (-not (Test-Path $StatePath)) {
        return [PSCustomObject]@{ fresh = $false; reason = "missing"; markets = @{} }
    }
    try {
        $raw = Get-Content $StatePath -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw -or -not $raw.Trim()) {
            return [PSCustomObject]@{ fresh = $false; reason = "empty"; markets = @{} }
        }
        $j = $raw | ConvertFrom-Json
    } catch {
        return [PSCustomObject]@{ fresh = $false; reason = "parse_error"; markets = @{} }
    }
    if (-not $j.ts_utc) {
        return [PSCustomObject]@{ fresh = $false; reason = "no_timestamp"; markets = @{} }
    }
    # PS 5.1: [datetime]::Parse retorna Kind=Local pra string com 'Z' -> bug TZ.
    # DateTimeOffset.Parse respeita o offset embutido, UtcDateTime garante Kind=Utc.
    $ts = ([datetimeoffset]::Parse($j.ts_utc)).UtcDateTime
    $ageMin = ((Get-Date).ToUniversalTime() - $ts).TotalMinutes
    if ($ageMin -gt $MaxAgeMinutes) {
        $ageRounded = [math]::Round($ageMin, 1)
        return [PSCustomObject]@{ fresh = $false; reason = "stale_age_${ageRounded}min"; markets = @{} }
    }

    # ConvertFrom-Json retorna PSCustomObject pra .markets -- normaliza pra hashtable
    $markets = @{}
    if ($j.markets) {
        foreach ($prop in $j.markets.PSObject.Properties) {
            $markets[$prop.Name] = $prop.Value
        }
    }
    return [PSCustomObject]@{
        fresh    = $true
        reason   = "ok"
        ts_utc   = $j.ts_utc
        age_min  = [math]::Round($ageMin, 1)
        markets  = $markets
    }
}


function Get-ToriProximityForMarket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $StatePath,
        [int] $MaxAgeMinutes = 30
    )
    $snap = Get-ToriProximitySnapshot -StatePath $StatePath -MaxAgeMinutes $MaxAgeMinutes
    if (-not $snap.fresh) { return $null }
    if (-not $snap.markets.ContainsKey($Market)) { return $null }
    return $snap.markets[$Market]
}


function Get-ToriProximityRipeningMarkets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $StatePath,
        [int] $MaxAgeMinutes = 30
    )
    $snap = Get-ToriProximitySnapshot -StatePath $StatePath -MaxAgeMinutes $MaxAgeMinutes
    if (-not $snap.fresh) { return @() }
    $result = @()
    foreach ($k in $snap.markets.Keys) {
        $m = $snap.markets[$k]
        if ($m.setup_ripening -eq $true) { $result += $k }
    }
    return @($result)
}
