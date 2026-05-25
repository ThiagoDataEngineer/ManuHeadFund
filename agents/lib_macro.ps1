# lib_macro.ps1 -- Macro Context Provider (FRED API, cache 24h, sem Claude)
# Uso: . (Join-Path $PSScriptRoot "lib_macro.ps1"); Get-MacroContext
# Design: utilitario puro, igual a lib_coinex.ps1 -- sem peso no orquestrador,
#         sem chamada Claude. Dado macro muda 1x/dia; injetado nos prompts existentes.

$MACRO_CACHE_PATH  = if ($env:TEMP) { "$env:TEMP\macro_cache.json" } else { (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "logs") "macro_cache.json") }
$MACRO_CACHE_TTL_H = 24

# Extrai o primeiro valor numerico valido de uma resposta FRED (ignora ".")
function Get-FredValue {
    param([object]$Response, [int]$Index = 0)
    if (-not $Response -or -not $Response.observations) { return $null }
    $obs = $Response.observations | Where-Object { $_.value -ne "." } | Select-Object -First ($Index + 2)
    if ($obs.Count -le $Index) { return $null }
    $v = $obs[$Index].value
    $parsed = 0.0
    if ([double]::TryParse($v, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

# Classifica tendencia comparando valor atual vs anterior
function Get-Trend {
    param([double]$Current, [double]$Previous, [double]$ThresholdPct = 0.005)
    if ($Previous -eq 0) { return "lateral" }
    $change = ($Current - $Previous) / $Previous
    if ($change -gt $ThresholdPct)  { return "subindo" }
    if ($change -lt -$ThresholdPct) { return "caindo" }
    return "lateral"
}

# Calcula score macro (0-100) sem Claude, aritmÃ©tica pura
function Invoke-MacroScore {
    param(
        [string]$DxyTrend,
        [string]$M2Trend,
        [string]$YieldCurve,
        [double]$FedRate
    )
    $score = 50
    switch ($DxyTrend) {
        "caindo"  { $score += 20 }
        "subindo" { $score -= 20 }
    }
    switch ($M2Trend) {
        "expansao"  { $score += 20 }
        "contracao" { $score -= 20 }
    }
    switch ($YieldCurve) {
        "normal"   { $score += 10 }
        "invertida"{ $score -= 15 }
    }
    if ($FedRate -le 3.0) { $score += 10 }
    if ($FedRate -ge 5.0) { $score -= 10 }
    return [math]::Max(0, [math]::Min(100, $score))
}

function Get-MacroContext {
    param(
        [string]$CachePath = $MACRO_CACHE_PATH,
        [int]$CacheTtlH   = $MACRO_CACHE_TTL_H
    )

    # â”€â”€ 1. Verificar cache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    if (Test-Path $CachePath) {
        try {
            $raw   = Get-Content $CachePath -Raw -Encoding UTF8
            $cache = $raw | ConvertFrom-Json
            $fetched = [DateTime]::Parse($cache.fetched_at, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $age   = ([DateTime]::UtcNow - $fetched).TotalHours
            if ($age -lt $CacheTtlH) {
                $d = $cache.data
                return [PSCustomObject]@{
                    macro_bias     = $d.macro_bias
                    score          = [int]$d.score
                    dxy_value      = $d.dxy_value
                    dxy_trend      = $d.dxy_trend
                    m2_trend       = $d.m2_trend
                    yield_curve    = $d.yield_curve
                    fed_funds_rate = $d.fed_funds_rate
                    resumo         = $d.resumo
                    cached         = $true
                    cache_age_h    = [math]::Round($age, 1)
                    source         = "cache"
                }
            }
        } catch { <# cache corrompido -- refaz fetch #> }
    }

    # â”€â”€ 2. Fetch FRED API (5 series, timeout 10s cada) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    # FRED exige api_key obrigatorio (sem ele retorna HTTP 400 silenciado pelo catch).
    # Key em $env:FRED_API_KEY (config.local.ps1, gitignored). Sem key -> fallback NEUTRAL.
    $fredBase = "https://api.stlouisfed.org/fred/series/observations"
    $fredKey  = $env:FRED_API_KEY
    $keyParam = if ($fredKey) { "&api_key=$fredKey" } else { "" }
    $params   = "sort_order=desc&limit=5&file_type=json$keyParam"

    $rDxy = $null; $rM2 = $null; $rY10 = $null; $rY2 = $null; $rFed = $null

    try { $rDxy = Invoke-RestMethod -Uri "$fredBase`?series_id=DTWEXBGS&$params" -TimeoutSec 10 -ErrorAction Stop } catch {}
    try { $rM2  = Invoke-RestMethod -Uri "$fredBase`?series_id=WM2NS&$params"    -TimeoutSec 10 -ErrorAction Stop } catch {}
    try { $rY10 = Invoke-RestMethod -Uri "$fredBase`?series_id=DGS10&$params"    -TimeoutSec 10 -ErrorAction Stop } catch {}
    try { $rY2  = Invoke-RestMethod -Uri "$fredBase`?series_id=DGS2&$params"     -TimeoutSec 10 -ErrorAction Stop } catch {}
    try { $rFed = Invoke-RestMethod -Uri "$fredBase`?series_id=FEDFUNDS&$params" -TimeoutSec 10 -ErrorAction Stop } catch {}

    # Se nenhuma call funcionou: fallback
    if (-not $rDxy -and -not $rM2 -and -not $rY10 -and -not $rY2 -and -not $rFed) {
        $reason = if ($fredKey) { "FRED API indisponivel (key configurada mas API offline ou key invalida)" } else { "FRED_API_KEY ausente em config.local.ps1" }
        Write-Host "[MACRO FALLBACK] $reason -- macro_bias=NEUTRAL forcado." -ForegroundColor Yellow
        return [PSCustomObject]@{
            macro_bias     = "NEUTRAL"
            score          = 50
            dxy_value      = $null
            dxy_trend      = "lateral"
            m2_trend       = "lateral"
            yield_curve    = "plana"
            fed_funds_rate = $null
            resumo         = "Dados macro indisponiveis (FRED offline). Contexto neutro por precaucao."
            cached         = $false
            cache_age_h    = 0
            source         = "fallback"
        }
    }

    # â”€â”€ 3. Extrair valores e calcular tendencias â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $dxyNow  = Get-FredValue $rDxy 0
    $dxyPrev = Get-FredValue $rDxy 1
    $dxyTrend = if ($dxyNow -and $dxyPrev) { Get-Trend $dxyNow $dxyPrev 0.005 } else { "lateral" }

    $m2Now  = Get-FredValue $rM2 0
    $m2Prev = Get-FredValue $rM2 1
    $m2Trend = if ($m2Now -and $m2Prev) { Get-Trend $m2Now $m2Prev 0.002 } else { "lateral" }
    $m2TrendLabel = switch ($m2Trend) {
        "subindo" { "expansao" }
        "caindo"  { "contracao" }
        default   { "lateral" }
    }

    $y10 = Get-FredValue $rY10 0
    $y2  = Get-FredValue $rY2  0
    $yieldCurve = if ($y10 -and $y2) {
        if ($y2 -gt $y10) { "invertida" } else { "normal" }
    } else { "plana" }

    $fedRate = Get-FredValue $rFed 0

    # â”€â”€ 4. Score e bias â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $fedRateVal = if ($fedRate -ne $null) { $fedRate } else { 5.0 }
    $score = Invoke-MacroScore -DxyTrend $dxyTrend -M2Trend $m2TrendLabel -YieldCurve $yieldCurve -FedRate $fedRateVal
    $bias  = if ($score -ge 60) { "BULLISH" } elseif ($score -le 40) { "BEARISH" } else { "NEUTRAL" }

    # â”€â”€ 5. Resumo em texto (sem Claude) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    $dxyStr  = if ($dxyNow)  { "DXY $dxyNow ($dxyTrend)" }  else { "DXY indisponivel" }
    $m2Str   = if ($m2Now)   { "M2 $($m2TrendLabel)" }      else { "M2 indisponivel" }
    $yStr    = if ($y10 -and $y2) { "curva $yieldCurve (10Y=$y10% / 2Y=$y2%)" } else { "curva indisponivel" }
    $fedStr  = if ($fedRate) { "Fed $fedRate%" }             else { "Fed indisponivel" }
    $resumo  = "$dxyStr + $m2Str + $yStr + $fedStr = contexto macro $bias para cripto."

    $obj = [PSCustomObject]@{
        macro_bias     = $bias
        score          = $score
        dxy_value      = $dxyNow
        dxy_trend      = $dxyTrend
        m2_trend       = $m2TrendLabel
        yield_curve    = $yieldCurve
        fed_funds_rate = $fedRate
        resumo         = $resumo
        cached         = $false
        cache_age_h    = 0
        source         = "FRED"
    }

    # â”€â”€ 6. Salvar cache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    try {
        $cacheDir = Split-Path $CachePath -Parent
        if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
        @{ fetched_at = [DateTime]::UtcNow.ToString("o"); data = $obj } |
            ConvertTo-Json -Depth 5 |
            Set-Content $CachePath -Encoding UTF8
    } catch {}

    return $obj
}

# â”€â”€ BTC Tech Regime (camada tecnica BTC, complementa macro FRED) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Retorna: ACUMULACAO | TENDENCIA | DISTRIBUICAO | BEAR
# - BEAR:         preco abaixo da SMA200 diaria
# - DISTRIBUICAO: RSI > 70 + volume declinante > 15% vs media 20d
# - TENDENCIA:    RSI > 55 (rally ativo)
# - ACUMULACAO:   default (consolidacao/lateral)

function Get-RsiSimple {
    param([double[]]$Closes, [int]$Period = 14)
    if (-not $Closes -or $Closes.Count -lt ($Period + 1)) { return $null }
    $gains = 0.0; $losses = 0.0
    for ($i = 1; $i -le $Period; $i++) {
        $diff = $Closes[$i] - $Closes[$i-1]
        if ($diff -gt 0) { $gains += $diff } else { $losses += [math]::Abs($diff) }
    }
    $avgG = $gains / $Period
    $avgL = $losses / $Period
    for ($i = $Period + 1; $i -lt $Closes.Count; $i++) {
        $diff = $Closes[$i] - $Closes[$i-1]
        $g = if ($diff -gt 0) { $diff } else { 0 }
        $l = if ($diff -lt 0) { [math]::Abs($diff) } else { 0 }
        $avgG = (($avgG * ($Period - 1)) + $g) / $Period
        $avgL = (($avgL * ($Period - 1)) + $l) / $Period
    }
    if ($avgL -eq 0) { return 100.0 }
    $rs = $avgG / $avgL
    return [math]::Round(100 - (100 / (1 + $rs)), 2)
}

function Get-BtcTechRegime {
    param(
        [object[]]$Candles = $null,
        [string]$Market   = "BTCUSDT",
        [int]$Limit       = 250
    )

    if (-not $Candles) {
        try {
            $Candles = CoinEx-GetCandles $Market "1day" $Limit
        } catch {
            return [PSCustomObject]@{
                regime = "TENDENCIA"; reason = "fallback: candles indisponiveis"
                price = $null; rsi = $null; sma200 = $null; vol_decline_pct = $null
            }
        }
    }

    if (-not $Candles -or @($Candles).Count -lt 50) {
        return [PSCustomObject]@{
            regime = "TENDENCIA"; reason = "fallback: dados insuficientes"
            price = $null; rsi = $null; sma200 = $null; vol_decline_pct = $null
        }
    }

    $closes = @($Candles | ForEach-Object { [double]$_.close })
    $vols   = @($Candles | ForEach-Object { [double]$_.volume })
    $n      = $closes.Count
    $price  = $closes[$n - 1]

    $smaWindow = [math]::Min(200, $n)
    $smaSlice  = $closes[($n - $smaWindow)..($n - 1)]
    $sma200    = ($smaSlice | Measure-Object -Average).Average

    $rsi = Get-RsiSimple -Closes $closes -Period 14

    $vol20Slice = $vols[($n - 20)..($n - 1)]
    $vol20      = ($vol20Slice | Measure-Object -Average).Average
    $vol3Slice  = $vols[($n - 3)..($n - 1)]
    $volNow     = ($vol3Slice | Measure-Object -Average).Average
    $volDecline = if ($vol20 -gt 0) { ($volNow - $vol20) / $vol20 } else { 0 }

    $regime = "ACUMULACAO"
    $reason = "consolidacao (RSI=$rsi)"

    if ($price -lt $sma200) {
        $regime = "BEAR"
        $reason = "preco $([math]::Round($price,2)) abaixo SMA200 $([math]::Round($sma200,2))"
    } elseif ($null -ne $rsi -and $rsi -gt 70 -and $volDecline -lt -0.15) {
        $regime = "DISTRIBUICAO"
        $reason = "RSI=$rsi sobrecompra + volume -$([math]::Round([math]::Abs($volDecline)*100,1))% vs 20d"
    } elseif ($null -ne $rsi -and $rsi -gt 55) {
        $regime = "TENDENCIA"
        $reason = "RSI=$rsi acima 55, preco acima SMA200"
    }

    return [PSCustomObject]@{
        regime          = $regime
        reason          = $reason
        price           = [math]::Round($price, 4)
        rsi             = $rsi
        sma200          = [math]::Round($sma200, 4)
        vol_decline_pct = [math]::Round($volDecline * 100, 2)
    }
}
