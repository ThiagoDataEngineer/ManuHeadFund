# lib_auto_market_analysis.ps1
# "AI Analysis" AUTOMATICA propria (sem depender de endpoint externo).
# Reusa o que ja existe no projeto:
#   - candles: CoinEx-GetFuturesCandles (multi-timeframe 1h/4h/1d)
#   - RSI: _CP-CalcRsiArray / padroes: Detect-RsiDivergence, Detect-CandlestickReversal,
#          Detect-VolumeClimax (lib_chart_patterns.ps1)
#   - suporte/resistencia: Find-SupportLevels (lib_trailing_stop_intelligent.ps1)
# Adiciona MACD + Bollinger puros (nao existiam como funcoes isoladas).
# Deterministico, offline-testavel. 2026-05-29
#
# Dependencias carregadas pelo caller (orchestrator/scan) ou aqui via dot-source defensivo:
$__amaRoot = $PSScriptRoot
foreach ($__dep in @("lib_chart_patterns.ps1","lib_trailing_stop_intelligent.ps1")) {
    $__p = Join-Path $__amaRoot $__dep
    if ((Test-Path $__p) -and -not (Get-Command Detect-RsiDivergence -ErrorAction SilentlyContinue)) {
        try { . $__p } catch {}
    }
}

# ============================================================================
# Get-Ema -- EMA simples (helper interno)
# ============================================================================
function Get-Ema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [double[]]$Values,
        [Parameter(Mandatory=$true)] [int]$Period
    )
    if ($Values.Count -eq 0) { return @() }
    $k = 2.0 / ($Period + 1)
    $ema = @(); $prev = $Values[0]
    for ($i = 0; $i -lt $Values.Count; $i++) {
        if ($i -eq 0) { $prev = $Values[0] }
        else { $prev = ($Values[$i] * $k) + ($prev * (1 - $k)) }
        $ema += $prev
    }
    return $ema
}

# ============================================================================
# Get-MacdValue -- MACD(12,26,9). Retorna ultimo valor + trend.
# ============================================================================
function Get-MacdValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [double[]]$Closes,
        [int]$Fast = 12,
        [int]$Slow = 26,
        [int]$Signal = 9
    )
    if ($Closes.Count -lt ($Slow + $Signal)) {
        return [PSCustomObject]@{ macd=0.0; signal=0.0; histogram=0.0; trend="NEUTRAL" }
    }
    $emaFast = Get-Ema -Values $Closes -Period $Fast
    $emaSlow = Get-Ema -Values $Closes -Period $Slow
    $macdLine = @()
    for ($i = 0; $i -lt $Closes.Count; $i++) { $macdLine += ($emaFast[$i] - $emaSlow[$i]) }
    $signalLine = Get-Ema -Values $macdLine -Period $Signal

    $macd = [math]::Round($macdLine[-1], 6)
    $sig  = [math]::Round($signalLine[-1], 6)
    $hist = [math]::Round($macd - $sig, 6)
    $trend = if ($hist -gt 0) { "BULLISH" } elseif ($hist -lt 0) { "BEARISH" } else { "NEUTRAL" }

    return [PSCustomObject]@{ macd=$macd; signal=$sig; histogram=$hist; trend=$trend }
}

# ============================================================================
# Get-BollingerBands -- Bandas de Bollinger(20,2). Retorna ultimo valor + %B.
# ============================================================================
function Get-BollingerBands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [double[]]$Closes,
        [int]$Period = 20,
        [double]$StdDevMult = 2.0
    )
    if ($Closes.Count -lt $Period) {
        $last = if ($Closes.Count -gt 0) { $Closes[-1] } else { 0.0 }
        return [PSCustomObject]@{ upper=$last; mid=$last; lower=$last; pct_b=0.5; bandwidth=0.0 }
    }
    $window = $Closes[($Closes.Count - $Period)..($Closes.Count - 1)]
    $mid = ($window | Measure-Object -Average).Average
    $variance = ($window | ForEach-Object { [math]::Pow($_ - $mid, 2) } | Measure-Object -Average).Average
    $sd = [math]::Sqrt($variance)
    $upper = $mid + ($StdDevMult * $sd)
    $lower = $mid - ($StdDevMult * $sd)
    $last = $Closes[-1]
    $pctB = if (($upper - $lower) -ne 0) { ($last - $lower) / ($upper - $lower) } else { 0.5 }
    $bandwidth = if ($mid -ne 0) { ($upper - $lower) / $mid } else { 0.0 }

    return [PSCustomObject]@{
        upper     = [math]::Round($upper, 6)
        mid       = [math]::Round($mid, 6)
        lower     = [math]::Round($lower, 6)
        pct_b     = [math]::Round($pctB, 4)
        bandwidth = [math]::Round($bandwidth, 4)
    }
}

# ============================================================================
# Get-AutoTimeframeAnalysis -- analisa UM timeframe a partir de candles.
# Candles: array de PSCustomObject { open, high, low, close, volume }.
# ============================================================================
function Get-AutoTimeframeAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [array]$Candles,
        [Parameter(Mandatory=$false)] [string]$Timeframe = "1h"
    )

    $n = $Candles.Count
    if ($n -lt 20) {
        return [PSCustomObject]@{
            timeframe=$Timeframe; close=0; rsi=50; bias="NEUTRAL"; score=50
            macd=$null; bollinger=$null; support_levels=@(); resistance_levels=@()
            signals=@("insufficient_data")
        }
    }

    $closes = @($Candles | ForEach-Object { [double]$_.close })
    $highs  = @($Candles | ForEach-Object { [double]$_.high })
    $lows   = @($Candles | ForEach-Object { [double]$_.low })
    $opens  = @($Candles | ForEach-Object { [double]$_.open })
    $vols   = @($Candles | ForEach-Object { if ($null -ne $_.volume) { [double]$_.volume } else { 0.0 } })
    $close  = $closes[-1]

    # RSI (reusa helper de chart_patterns)
    $rsiArr = _CP-CalcRsiArray -Closes $closes -Period 14
    $rsi = [math]::Round($rsiArr[-1], 1)

    # MACD + Bollinger
    $macd = Get-MacdValue -Closes $closes
    $bb   = Get-BollingerBands -Closes $closes -Period 20 -StdDevMult 2.0

    # Suporte/Resistencia (reusa Find-SupportLevels do trailing; resistencia = espelho)
    $supports = @()
    $resistances = @()
    if (Get-Command Find-SupportLevels -ErrorAction SilentlyContinue) {
        $supports = @(Find-SupportLevels -Candles $Candles -LookbackPeriod ([math]::Min(30, $n)))
        # Resistencia: inverte lows<->highs criando candles espelhados
        $mirror = @()
        foreach ($c in $Candles) {
            $mirror += [PSCustomObject]@{ high=(-[double]$c.low); low=(-[double]$c.high); close=(-[double]$c.close); open=(-[double]$c.open) }
        }
        $resNeg = @(Find-SupportLevels -Candles $mirror -LookbackPeriod ([math]::Min(30, $n)))
        $resistances = @($resNeg | ForEach-Object { -$_ } | Where-Object { $_ -gt $close } | Sort-Object)
        $supports = @($supports | Where-Object { $_ -lt $close } | Sort-Object -Descending)
    }

    # Padroes (chart_patterns) -- detecta tanto LONG quanto SHORT
    $signals = @()
    $bullPattern = $false; $bearPattern = $false
    if (Get-Command Detect-RsiDivergence -ErrorAction SilentlyContinue) {
        $divL = Detect-RsiDivergence -Closes $closes -Side "LONG"
        $divS = Detect-RsiDivergence -Closes $closes -Side "SHORT"
        if ($divL.detected) { $signals += "bullish_divergence"; $bullPattern = $true }
        if ($divS.detected) { $signals += "bearish_divergence"; $bearPattern = $true }
    }
    if (Get-Command Detect-CandlestickReversal -ErrorAction SilentlyContinue) {
        $revL = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side "LONG"
        $revS = Detect-CandlestickReversal -Opens $opens -Highs $highs -Lows $lows -Closes $closes -Side "SHORT"
        if ($revL.detected) { $signals += $revL.pattern_name; $bullPattern = $true }
        if ($revS.detected) { $signals += $revS.pattern_name; $bearPattern = $true }
    }
    if (Get-Command Detect-VolumeClimax -ErrorAction SilentlyContinue) {
        $climL = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side "LONG"
        $climS = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side "SHORT"
        if ($climL.detected) { $signals += "selling_climax"; $bullPattern = $true }
        if ($climS.detected) { $signals += "buying_climax"; $bearPattern = $true }
    }

    # --- Bias + score (combinacao ponderada) ---
    # EMA rapida vs lenta para tendencia base
    $emaFast = (Get-Ema -Values $closes -Period 9)[-1]
    $emaSlow = (Get-Ema -Values $closes -Period 21)[-1]

    $score = 50.0
    if ($macd.trend -eq "BULLISH") { $score += 12 } elseif ($macd.trend -eq "BEARISH") { $score -= 12 }
    if ($emaFast -gt $emaSlow) { $score += 12 } else { $score -= 12 }
    if ($rsi -gt 70) { $score -= 8 } elseif ($rsi -lt 30) { $score += 8 }
    elseif ($rsi -gt 55) { $score += 4 } elseif ($rsi -lt 45) { $score -= 4 }
    if ($bb.pct_b -gt 1.0) { $score -= 6 } elseif ($bb.pct_b -lt 0.0) { $score += 6 }
    if ($bullPattern) { $score += 8 }
    if ($bearPattern) { $score -= 8 }
    $score = [math]::Max(0, [math]::Min(100, [math]::Round($score)))

    $bias = if ($score -ge 58) { "BULLISH" } elseif ($score -le 42) { "BEARISH" } else { "NEUTRAL" }

    # Sinais informativos de RSI extremo
    if ($rsi -gt 70) { $signals += "overbought_rsi" }
    if ($rsi -lt 30) { $signals += "oversold_rsi" }

    return [PSCustomObject]@{
        timeframe         = $Timeframe
        close             = [math]::Round($close, 6)
        rsi               = $rsi
        macd              = $macd
        bollinger         = $bb
        ema_fast          = [math]::Round($emaFast, 6)
        ema_slow          = [math]::Round($emaSlow, 6)
        bias              = $bias
        score             = $score
        support_levels    = @($supports | Select-Object -First 3 | ForEach-Object { [math]::Round($_, 6) })
        resistance_levels = @($resistances | Select-Object -First 3 | ForEach-Object { [math]::Round($_, 6) })
        signals           = @($signals | Select-Object -Unique)
    }
}

# ============================================================================
# Get-AutoMarketAnalysis -- consolida 1h/4h/1d numa "AI Analysis" propria.
# -CandlesByTimeframe: hashtable opcional { "1h"=candles; ... } para teste/offline.
# Sem ela, busca via CoinEx-GetFuturesCandles.
# ============================================================================
function Get-AutoMarketAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$Market,
        [Parameter(Mandatory=$false)] [hashtable]$CandlesByTimeframe = $null,
        [Parameter(Mandatory=$false)] [int]$Limit = 100
    )

    # Mapa de periodos CoinEx por timeframe logico
    $tfMap = [ordered]@{ "1h"="1hour"; "4h"="4hour"; "1d"="1day" }

    $tfResults = @()
    foreach ($tf in $tfMap.Keys) {
        $candles = $null
        if ($CandlesByTimeframe -and $CandlesByTimeframe.ContainsKey($tf)) {
            $candles = $CandlesByTimeframe[$tf]
        } elseif (Get-Command CoinEx-GetFuturesCandles -ErrorAction SilentlyContinue) {
            try { $candles = CoinEx-GetFuturesCandles -market $Market -period $tfMap[$tf] -limit $Limit } catch { $candles = $null }
        }
        if ($candles -and $candles.Count -ge 20) {
            $tfResults += (Get-AutoTimeframeAnalysis -Candles $candles -Timeframe $tf)
        }
    }

    if ($tfResults.Count -eq 0) {
        return [PSCustomObject]@{
            symbol=$Market; success=$false; generated_at=(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            overall_bias="NEUTRAL"; confidence=0; key_takeaways=@("Dados insuficientes"); timeframes=@()
            short_term_view=""; long_term_view=""; recommendation=""
        }
    }

    # Curto prazo = media 1h/4h; longo = 1d
    $byTf = @{}
    foreach ($r in $tfResults) { $byTf[$r.timeframe] = $r }

    $shortScores = @()
    foreach ($k in @("1h","4h")) { if ($byTf.ContainsKey($k)) { $shortScores += $byTf[$k].score } }
    $shortScore = if ($shortScores.Count -gt 0) { ($shortScores | Measure-Object -Average).Average } else { 50 }
    $longScore  = if ($byTf.ContainsKey("1d")) { $byTf["1d"].score } else { ($tfResults | Measure-Object score -Average).Average }

    $overallScore = [math]::Round(($shortScore * 0.5) + ($longScore * 0.5))
    $overallBias = if ($overallScore -ge 58) { "BULLISH" } elseif ($overallScore -le 42) { "BEARISH" } else { "NEUTRAL" }

    $shortView = if ($shortScore -ge 58) { "ALTA (curto prazo)" } elseif ($shortScore -le 42) { "BAIXA (curto prazo)" } else { "NEUTRO (curto prazo)" }
    $longView  = if ($longScore -ge 58) { "ALTA (longo prazo)" } elseif ($longScore -le 42) { "BAIXA (longo prazo)" } else { "NEUTRO (longo prazo)" }

    # Confianca: alinhamento entre timeframes (quanto mais concordam, maior)
    $biases = $tfResults | ForEach-Object { $_.bias }
    $dominant = ($biases | Group-Object | Sort-Object Count -Descending | Select-Object -First 1)
    $agreement = $dominant.Count / [double]$tfResults.Count
    $confidence = [math]::Round($agreement * 100)

    # Takeaways automaticos
    $takeaways = @()
    $price = $byTf[(@("1h","4h","1d") | Where-Object { $byTf.ContainsKey($_) } | Select-Object -First 1)].close
    $takeaways += "Vies geral: $overallBias (score $overallScore/100, confianca $confidence%)."
    if ($shortView -ne $longView) {
        $takeaways += "Divergencia de horizonte: $shortView vs $longView -- possivel consolidacao/retracao."
    } else {
        $takeaways += "Curto e longo prazo alinhados: $shortView."
    }
    # RSI extremos
    foreach ($r in $tfResults) {
        if ($r.rsi -gt 70) { $takeaways += "RSI sobrecomprado em $($r.timeframe) ($($r.rsi)) -- risco de pullback." }
        if ($r.rsi -lt 30) { $takeaways += "RSI sobrevendido em $($r.timeframe) ($($r.rsi)) -- possivel repique." }
    }
    # Niveis (do 4h se houver, senao 1h)
    $lvlTf = if ($byTf.ContainsKey("4h")) { $byTf["4h"] } else { $tfResults[0] }
    if ($lvlTf.resistance_levels.Count -gt 0) { $takeaways += "Resistencia proxima: $($lvlTf.resistance_levels[0])." }
    if ($lvlTf.support_levels.Count -gt 0)    { $takeaways += "Suporte proximo: $($lvlTf.support_levels[0])." }
    # Sinais relevantes
    $allSignals = @($tfResults | ForEach-Object { $_.signals } | Where-Object { $_ -and $_ -ne "insufficient_data" } | Select-Object -Unique)
    if ($allSignals.Count -gt 0) { $takeaways += "Sinais: $($allSignals -join ', ')." }

    # Recomendacao
    $recommendation = switch ($overallBias) {
        "BULLISH" {
            if (($tfResults | Where-Object { $_.rsi -gt 70 }).Count -gt 0) {
                "Tendencia de alta, mas sobrecomprado: aguardar pullback a suporte antes de novas entradas; segurar posicoes com trailing."
            } else { "Tendencia de alta: favorecer LONG em recuos a suporte; respeitar stop." }
        }
        "BEARISH" {
            if (($tfResults | Where-Object { $_.rsi -lt 30 }).Count -gt 0) {
                "Tendencia de baixa, mas sobrevendido: evitar SHORT tardio; possivel repique tecnico."
            } else { "Tendencia de baixa: cautela com LONG; proteger capital, stops curtos." }
        }
        default { "Mercado sem direcao clara: reduzir exposicao, operar niveis (suporte/resistencia) com stop curto." }
    }

    return [PSCustomObject]@{
        symbol          = $Market
        success         = $true
        generated_at    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        price           = $price
        overall_bias    = $overallBias
        overall_score   = $overallScore
        confidence      = $confidence
        short_term_view = $shortView
        long_term_view  = $longView
        key_takeaways   = $takeaways
        recommendation  = $recommendation
        timeframes      = $tfResults
        source          = "auto_internal"
    }
}

# ============================================================================
# Format-TgAutoAnalysis -- mensagem Telegram (HTML) da analise automatica.
# ============================================================================
function Format-TgAutoAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)] [PSCustomObject]$Analysis
    )

    $esc = {
        param($t)
        if (Get-Command Format-TelegramText -ErrorAction SilentlyContinue) { return (Format-TelegramText -Text "$t") }
        return ("$t" -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;')
    }

    $biasIcon = switch ($Analysis.overall_bias) {
        "BULLISH" { "[ALTA]" }
        "BEARISH" { "[BAIXA]" }
        default   { "[NEUTRO]" }
    }

    $sym = & $esc $Analysis.symbol
    $lines = @()
    $lines += "$biasIcon <b>ANALISE AUTO - $sym</b>"
    $lines += "Vies: <b>$(& $esc $Analysis.overall_bias)</b> | Score: <code>$($Analysis.overall_score)/100</code> | Conf: <code>$($Analysis.confidence)%</code>"
    if ($Analysis.price) { $lines += "Preco: <code>$(& $esc $Analysis.price)</code>" }
    $lines += "$(& $esc $Analysis.short_term_view) | $(& $esc $Analysis.long_term_view)"

    # Resumo por timeframe
    foreach ($tf in $Analysis.timeframes) {
        $tfIcon = switch ($tf.bias) { "BULLISH" { "+" } "BEARISH" { "-" } default { "=" } }
        $lines += "[$($tf.timeframe)] $tfIcon RSI $($tf.rsi) | MACD $($tf.macd.trend) | score $($tf.score)"
    }

    # Takeaways (max 4 para nao poluir)
    $lines += "---"
    foreach ($t in ($Analysis.key_takeaways | Select-Object -First 4)) {
        $lines += "- $(& $esc $t)"
    }

    $lines += "---"
    $lines += "ACAO: $(& $esc $Analysis.recommendation)"

    return ($lines -join "`n")
}
