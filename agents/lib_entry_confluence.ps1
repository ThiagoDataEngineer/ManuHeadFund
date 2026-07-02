# lib_entry_confluence.ps1 -- Detecta confluência de sinais ANTECIPADAMENTE
# Objetivo: entrada rápida no INÍCIO do pump (não no meio)
#
# Fluxo:
#   1. FARO V3 (vol_climax): score pré-pump (4-72h antes)
#   2. Momentum detector: RSI<30 bounce ou MACD crossover
#   3. Estrutura: trendline + suporte
#   4. Se 3+ sinais em paralelo → ENTRADA + confidence alta
#
# 2026-06-17: MVP para otimizar HYPE/PEPE/similar

function Test-VolumeClimax {
    param(
        [PSCustomObject]$Market,  # {name, vol_24h, vol_7d, vol_30d, price}
        [double]$ZScoreThreshold = 2.0
    )

    if (-not $Market) { return @{score=0; reason="no_market"} }

    # Vol climax = volume day >> average
    # Calc z-score: (vol_24h - vol_7d_mean) / vol_7d_stdev
    # Se z > 2.0 = unusual volume (pre-pump signal)

    $vol_ratio = if ($Market.vol_7d -gt 0) { $Market.vol_24h / $Market.vol_7d } else { 0 }

    return @{
        score = if ($vol_ratio -gt 1.5) { 40 } else { 10 }
        reason = "vol_ratio_$([math]::Round($vol_ratio, 2))"
        vol_24h = $Market.vol_24h
        vol_7d_avg = $Market.vol_7d
        confidence = [math]::Min(100, ($vol_ratio - 1.0) * 50)
    }
}

function Test-MomentumBounce {
    param(
        [PSCustomObject[]]$Candles,  # recent candles {time, open, high, low, close}
        [double]$RSIThreshold = 30,
        [int]$LookbackBars = 14
    )

    if (-not $Candles -or @($Candles).Count -lt $LookbackBars) {
        return @{score=0; reason="insufficient_bars"}
    }

    # RSI < 30 = oversold bounce likely
    $closes = @($Candles | Select-Object -Last $LookbackBars | ForEach-Object { [double]$_.close })

    $rsi = Calculate-RSI -Closes $closes
    $is_bouncing = $rsi -lt $RSIThreshold -and $closes[-1] -gt $closes[-2]

    return @{
        score = if ($is_bouncing) { 30 } else { 5 }
        reason = "rsi_$([math]::Round($rsi, 1))_bounce_$(if ($is_bouncing) {'yes'} else {'no'})"
        rsi = $rsi
        confidence = if ($is_bouncing) { [math]::Min(100, (30 - $rsi) * 3) } else { 0 }
    }
}

function Test-StructureSupport {
    param(
        [PSCustomObject]$Market,  # {name, price, support_level, resistance_level}
        [double]$BouncePercent = 2.0
    )

    if (-not $Market -or -not $Market.support_level) {
        return @{score=0; reason="no_structure"}
    }

    # Preço próximo ao suporte = bounce likely
    $distance_to_support = (($Market.price - $Market.support_level) / $Market.support_level) * 100
    $is_at_support = $distance_to_support -le $BouncePercent -and $distance_to_support -ge 0

    return @{
        score = if ($is_at_support) { 30 } else { 10 }
        reason = "dist_to_support_$([math]::Round($distance_to_support, 2))pct"
        support_level = $Market.support_level
        distance_pct = $distance_to_support
        confidence = if ($is_at_support) { 100 } else { [math]::Max(0, $distance_to_support * 10) }
    }
}

function Resolve-ConfluenceScore {
    param(
        [hashtable]$VolumeScore,    # from Test-VolumeClimax
        [hashtable]$MomentumScore,  # from Test-MomentumBounce
        [hashtable]$StructureScore  # from Test-StructureSupport
    )

    $raw_score = ($VolumeScore.score + $MomentumScore.score + $StructureScore.score)
    $confidence_avg = (($(if ($null -ne $VolumeScore.confidence) { $VolumeScore.confidence } else { 0 })) + ($(if ($null -ne $MomentumScore.confidence) { $MomentumScore.confidence } else { 0 })) + ($(if ($null -ne $StructureScore.confidence) { $StructureScore.confidence } else { 0 }))) / 3

    # Score 0-100 + confidence 0-100
    # raw_score é 0-120 (40+30+30 max), então não precisa multiplicar por 0.33
    $final_score = [math]::Min(100, $raw_score)

    return [PSCustomObject]@{
        confluenceScore = [math]::Round($final_score, 1)
        confidenceAvg = [math]::Round($confidence_avg, 1)
        components = @{
            volume = $VolumeScore
            momentum = $MomentumScore
            structure = $StructureScore
        }
        readyToEnter = ($final_score -ge 70)  # threshold: need 70+ para entrar
        entryTiming = if ($final_score -ge 70) { "IMMEDIATE" } else { "WAIT_CONFLUENCE" }
    }
}

function Calculate-RSI {
    param([double[]]$Closes)

    if ($Closes.Count -lt 2) { return 50 }

    $gains = @()
    $losses = @()

    for ($i = 1; $i -lt $Closes.Count; $i++) {
        $diff = $Closes[$i] - $Closes[$i-1]
        if ($diff -gt 0) {
            $gains += $diff
            $losses += 0
        } else {
            $gains += 0
            $losses += [math]::Abs($diff)
        }
    }

    $avg_gain = ($gains | Measure-Object -Average).Average
    $avg_loss = ($losses | Measure-Object -Average).Average

    if ($avg_loss -eq 0) { return 100 }
    if ($avg_gain -eq 0) { return 0 }

    $rs = $avg_gain / $avg_loss
    return 100 - (100 / (1 + $rs))
}

# Funções exportadas implicitamente (sem Export-ModuleMember pra compatibilidade Pester 3.4)
