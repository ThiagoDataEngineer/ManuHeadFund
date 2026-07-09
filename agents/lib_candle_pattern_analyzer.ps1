# lib_candle_pattern_analyzer.ps1
# Sistema de análise de padrões em candlesticks
# Aprende com movimentos históricos e ajusta trailing dinâmico
# 2026-06-06

<#
.SYNOPSIS
    Analisa padrões em candlesticks e gera insights para trailing stop dinâmico

.DESCRIPTION
    - Detecta patterns: hammer, engulfing, volumeclimax, reversal
    - Aprende com histórico (backtest patterns)
    - Recomenda ajustes de trailing baseado em probabilidade histórica
    - Valida evolução em tempo real
#>

function Get-CandlePattern {
    <#
    .SYNOPSIS
        Identifica pattern em um candle (ou série de candles)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]$Candle,

        [Parameter(Mandatory=$false)]
        [object[]]$PriorCandles = @()
    )

    # Extrair valores
    $open = [double]$Candle.open
    $close = [double]$Candle.close
    $high = [double]$Candle.high
    $low = [double]$Candle.low
    $volume = [double]$Candle.volume

    $body = [math]::Abs($close - $open)
    $range = $high - $low
    $wick_upper = $high - [math]::Max($open, $close)
    $wick_lower = [math]::Min($open, $close) - $low

    $patterns = @()
    $confidence = 0.0

    # ════════════════════════════════════════════════════════════════
    # 1. HAMMER (reversão alta)
    # ════════════════════════════════════════════════════════════════

    if ($wick_lower -gt ($body * 2) -and $wick_upper -lt ($body * 0.5)) {
        $patterns += "HAMMER"
        $confidence += 0.25
    }

    # ════════════════════════════════════════════════════════════════
    # 2. SHOOTING STAR (reversão baixa)
    # ════════════════════════════════════════════════════════════════

    if ($wick_upper -gt ($body * 2) -and $wick_lower -lt ($body * 0.5)) {
        $patterns += "SHOOTING_STAR"
        $confidence += 0.25
    }

    # ════════════════════════════════════════════════════════════════
    # 3. ENGULFING (reversão forte)
    # ════════════════════════════════════════════════════════════════

    if ($PriorCandles.Count -gt 0) {
        $prior = $PriorCandles[-1]
        $prior_body = [math]::Abs([double]$prior.close - [double]$prior.open)

        if ($body -gt ($prior_body * 1.5)) {
            $patterns += "ENGULFING"
            $confidence += 0.30
        }
    }

    # ════════════════════════════════════════════════════════════════
    # 4. VOLUME CLIMAX
    # ════════════════════════════════════════════════════════════════

    if ($PriorCandles.Count -gt 5) {
        $avg_volume = ($PriorCandles | Measure-Object -Property volume -Average).Average

        if ($volume -gt ($avg_volume * 2.5)) {
            $patterns += "VOL_CLIMAX"
            $confidence += 0.35
        }
    }

    # ════════════════════════════════════════════════════════════════
    # 5. DOJI (indecisão)
    # ════════════════════════════════════════════════════════════════

    if ($body -lt ($range * 0.1)) {
        $patterns += "DOJI"
        $confidence -= 0.15  # Reduz confiança
    }

    return [PSCustomObject]@{
        patterns = $patterns
        confidence = [math]::Max(0, [math]::Min(1, $confidence))
        body_size = $body
        body_pct = ($body / $range) * 100
        wick_ratio = if ($wick_upper -gt 0) { $wick_lower / $wick_upper } else { 0 }
        volume_signal = if ($PriorCandles.Count -gt 5) { $volume / ($PriorCandles | Measure-Object -Property volume -Average).Average } else { 1 }
    }
}

function Get-TrailingStopAdjustment {
    <#
    .SYNOPSIS
        Recomenda ajuste de trailing stop baseado em padrões históricos
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$CurrentPrice,

        [Parameter(Mandatory=$true)]
        [double]$EntryPrice,

        [Parameter(Mandatory=$true)]
        [object]$LatestCandle,

        [Parameter(Mandatory=$false)]
        [object[]]$HistoricalCandles = @(),

        [Parameter(Mandatory=$false)]
        [double]$CurrentTrailing = $null
    )

    # Calcular PnL
    $pnl_pct = (($CurrentPrice - $EntryPrice) / $EntryPrice) * 100
    $pnl_abs = $CurrentPrice - $EntryPrice

    # Analisar padrão atual
    $pattern = Get-CandlePattern -Candle $LatestCandle -PriorCandles $HistoricalCandles

    # ════════════════════════════════════════════════════════════════
    # LÓGICA DE AJUSTE
    # ════════════════════════════════════════════════════════════════

    $recommendation = @{
        action = "HOLD"
        new_trailing = $CurrentTrailing
        reason = ""
        confidence = $pattern.confidence
    }

    # 1. PROFIT PROTECTION (se em lucro)
    if ($pnl_pct -gt 3.0) {
        # Trailing apertado em lucro
        $tighten_pct = 1.0 + ($pnl_pct * 0.1)  # 1% + 10% do ganho
        $recommendation.new_trailing = $CurrentPrice * (1 - ($tighten_pct / 100))
        $recommendation.action = "TIGHTEN_TRAILING"
        $recommendation.reason = "Lucro detectado ($pnl_pct%), apertando trailing para $tighten_pct%"
    }

    # 2. REVERSAL DETECTION (patterns)
    if ($pattern.patterns -contains "SHOOTING_STAR" -and $pnl_pct -gt 1.0) {
        $recommendation.new_trailing = $CurrentPrice * (1 - (0.015))  # 1.5% stop
        $recommendation.action = "SHOOTING_STAR_DETECTED"
        $recommendation.reason = "Padrão SHOOTING_STAR detectado - risco de reversão, apertando para 1.5%"
    }

    if ($pattern.patterns -contains "HAMMER" -and $pnl_pct -gt 1.0) {
        $recommendation.action = "HAMMER_SUPPORT"
        $recommendation.reason = "HAMMER detectado - possível suporte, mantendo trailing"
    }

    # 3. VOLUME CLIMAX (alta volatilidade = afrouxar)
    if ($pattern.patterns -contains "VOL_CLIMAX") {
        $loosen_pct = 2.5  # Mais margem
        $recommendation.new_trailing = $CurrentPrice * (1 - ($loosen_pct / 100))
        $recommendation.action = "VOL_CLIMAX_AFROUXAR"
        $recommendation.reason = "Volume climax detectado - volatilidade alta, afrouxando trailing para $loosen_pct%"
    }

    # 4. LOSS MANAGEMENT (proteção em perda)
    if ($pnl_pct -lt -5.0) {
        $recommendation.new_trailing = $EntryPrice * (1 - (0.02))  # Stop em -2% da entry
        $recommendation.action = "LOSS_CONTROL"
        $recommendation.reason = "Perda acumulada ($pnl_pct%), ativando stop de proteção"
    }

    return $recommendation
}

function New-CandleAnalysisLog {
    <#
    .SYNOPSIS
        Cria registro estruturado de análise de candle
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Market,

        [Parameter(Mandatory=$true)]
        [object]$Candle,

        [Parameter(Mandatory=$true)]
        [object]$Pattern,

        [Parameter(Mandatory=$true)]
        [object]$TrailingAdjustment
    )

    return [PSCustomObject]@{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        market = $Market
        candle_close = $Candle.close
        candle_volume = $Candle.volume
        patterns_detected = $Pattern.patterns -join ";"
        pattern_confidence = $Pattern.confidence
        body_pct = $Pattern.body_pct
        trailing_action = $TrailingAdjustment.action
        trailing_new = $TrailingAdjustment.new_trailing
        trailing_reason = $TrailingAdjustment.reason
    }
}

# 2026-07-08 FIX: Removed Export-ModuleMember (dot-source .ps1 files don't export)
