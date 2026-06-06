# lib_performance_refiner.ps1 — Sintetiza TODOS sinais + confluência + validação entrada
# PROBLEMA: 6 trades, 33% win rate, -$26 PnL. SOLUÇÃO: consenso multi-sinal + timing real
#
# Estratégia:
#   1. FARO V3 (7 sinais) — volume/pattern/sentiment/whale/momentum/fingerprint/timing
#   2. Tori proximity — distância de entrada vs estrutura
#   3. DSR live — confiança da borda (walk-forward)
#   4. Mentor conviction — o quão certo o LLM está
#   5. Confluência = CONSENSO entre 5 fontes (FARO + Tori + DSR + Mentor + Mesa)
#
# Entrada válida = confluência >= 3/5 fontes + sem ruído (vol <5% change 5m)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-PerformanceRefiner {
    <#
    .SYNOPSIS
    Sintetiza consenso multi-sinal. Rejeita entradas fracas (confluência < 3/5).
    .PARAMETER Market
    Ex: LINKUSDT, SOLUSDT
    .PARAMETER FaroV3Score
    Score FARO V3 (0-100). Consenso 5/7+ = 70+, 4/7 = 50+, 3/7 = 30+
    .PARAMETER ToriProximity
    Proximidade Tori (0-100). 80+ = entrada bem-alineada, <30 = longe da estrutura
    .PARAMETER DsrConfidence
    Confiança DSR (0-100). >= 70 = HIGH, 30-70 = MEDIUM, <30 = LOW
    .PARAMETER MentorConviction
    Conviction Mentor (0-100). >= 80 = muito certo, 50-80 = moderado, <50 = duvida
    .PARAMETER MesaConsensus
    Consensus Mesa (FORTE_3/MEDIO_2/MEDIO_1/CAOS)
    .PARAMETER VolatilityChange5m
    Volatilidade últimos 5 minutos (pct). > 5% = ruído alto, <= 2% = entrada boa
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [double] $FaroV3Score = 0,
        [double] $ToriProximity = 0,
        [double] $DsrConfidence = 0,
        [double] $MentorConviction = 0,
        [string] $MesaConsensus = "CAOS",
        [double] $VolatilityChange5m = 0,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $auditPath = Join-Path $JournalDir "performance_refiner_audit.jsonl"

    # === CONFLUÊNCIA: consenso multi-sinal ===
    $sources = @()
    $sourceWeights = @{
        faro = 0; tori = 0; dsr = 0; mentor = 0; mesa = 0
    }

    # 1. FARO V3 (0-100)
    $faroOk = $FaroV3Score -ge 50
    if ($faroOk) { $sources += "faro"; $sourceWeights.faro = $FaroV3Score / 100 }

    # 2. Tori (0-100) — proximidade à estrutura
    $toriOk = $ToriProximity -ge 50
    if ($toriOk) { $sources += "tori"; $sourceWeights.tori = $ToriProximity / 100 }

    # 3. DSR (0-100) — confiança da borda
    $dsrOk = $DsrConfidence -ge 50
    if ($dsrOk) { $sources += "dsr"; $sourceWeights.dsr = $DsrConfidence / 100 }

    # 4. Mentor (0-100) — conviction
    $mentorOk = $MentorConviction -ge 60
    if ($mentorOk) { $sources += "mentor"; $sourceWeights.mentor = $MentorConviction / 100 }

    # 5. Mesa (FORTE_3 = forte consensus)
    $mesaOk = $MesaConsensus -eq "FORTE_3"
    if ($mesaOk) { $sources += "mesa"; $sourceWeights.mesa = 1.0 }

    $confluenceCount = $sources.Count
    $confluenceScore = [Math]::Round(($sourceWeights.Values | Measure-Object -Sum).Sum / 5 * 100, 2)

    # === VALIDAÇÃO RUÍDO ===
    $noisyEntry = $VolatilityChange5m -gt 5
    $isGoodTiming = $VolatilityChange5m -le 2

    # === DECISÃO FINAL ===
    $approved = ($confluenceCount -ge 3) -and -not $noisyEntry
    $reason = ""

    if ($confluenceCount -lt 3) {
        $reason = "WEAK_CONFLUENCE: apenas $confluenceCount/5 sinais concordam (limiar 3)"
    }
    elseif ($noisyEntry) {
        $reason = "NOISY_ENTRY: volatilidade 5m = $([Math]::Round($VolatilityChange5m, 2))% (limiar 5%)"
    }
    else {
        $reason = "OK: confluência $confluenceCount/5, timing limpo"
    }

    # === REFINAMENTO SL/TP (baseado em confluência) ===
    # Se confluência alta (5/5), usar R:R 1:10. Se moderada (3/5), usar 1:5
    $rr_ratio = if ($confluenceCount -eq 5) { 10 } elseif ($confluenceCount -ge 4) { 8 } else { 5 }
    $position_confidence = $confluenceCount / 5.0

    # === LOG ===
    $entry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        confluence_count = $confluenceCount
        confluence_score = $confluenceScore
        approved = $approved
        reason = $reason
        sources_agree = ($sources -join '+')
        faro_v3_score = $FaroV3Score
        tori_proximity = $ToriProximity
        dsr_confidence = $DsrConfidence
        mentor_conviction = $MentorConviction
        mesa_consensus = $MesaConsensus
        volatility_5m_pct = [Math]::Round($VolatilityChange5m, 2)
        is_good_timing = $isGoodTiming
        recommended_rr_ratio = $rr_ratio
        position_confidence = [Math]::Round($position_confidence, 2)
    } | ConvertTo-Json -Compress

    Add-Content -Path $auditPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        market = $Market
        approved = $approved
        confluence_count = $confluenceCount
        confluence_score = $confluenceScore
        reason = $reason
        sources_agree = ($sources -join '+')
        recommended_rr_ratio = $rr_ratio
        position_confidence = $position_confidence
        is_good_timing = $isGoodTiming
        timestamp = $timestamp
    }
}

function Invoke-ConfluentEntryFinder {
    <#
    .SYNOPSIS
    Analisa histórico de trades para encontrar padrão: "entradas que ganharam tinham X confluência"
    Refina threshold dinamicamente baseado em historical win rate.
    #>
    param(
        [Parameter(Mandatory)] [array] $TradeHistory,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    # Agrupa por confluence_count
    $byConfluence = @{}
    foreach ($trade in $TradeHistory) {
        $conf = $trade.confluence_count
        if (-not $byConfluence[$conf]) {
            $byConfluence[$conf] = @{ wins=0; total=0 }
        }
        $byConfluence[$conf].total++
        if ($trade.win -eq $true) {
            $byConfluence[$conf].wins++
        }
    }

    # Encontra confluência ótima
    $optimal = @()
    foreach ($conf in $byConfluence.Keys | Sort-Object -Descending) {
        $stats = $byConfluence[$conf]
        $winRate = if ($stats.total -gt 0) { $stats.wins / $stats.total } else { 0 }
        $optimal += [PSCustomObject]@{
            confluence = $conf
            wins = $stats.wins
            total = $stats.total
            win_rate = [Math]::Round($winRate, 3)
        }
    }

    # Recomendação: entrar em confluência onde win_rate >= 50%
    $recommended = $optimal | Where-Object { $_.win_rate -ge 0.50 } | Select-Object -First 1
    $recommendedConfluence = if ($recommended) { [int]$recommended.confluence } else { 3 }

    return [PSCustomObject]@{
        optimal_confluences = $optimal
        recommended_min_confluence = $recommendedConfluence
        historical_analysis = "OK"
    }
}

function Get-AtrEstimate {
    <#
    .SYNOPSIS
    Estima ATR real (CARO: requer candles) vs barato (change 24h proxy).
    Prefere candles se available, fallback pra proxy.
    #>
    param(
        [Parameter(Mandatory)] [string] $Market,
        [double] $Change24hPct = 0,
        [array] $RecentCandles = $null  # Array de candles com high/low/close
    )

    if ($RecentCandles -and $RecentCandles.Count -gt 0) {
        # ATR real via candles
        $tr = @()
        foreach ($candle in $RecentCandles) {
            $h = [double]$candle.high
            $l = [double]$candle.low
            $c = [double]$candle.close

            $tr1 = $h - $l
            $tr2 = [Math]::Abs($h - $c)
            $tr3 = [Math]::Abs($l - $c)

            $tr += [Math]::Max([Math]::Max($tr1, $tr2), $tr3)
        }

        $atr = ($tr | Measure-Object -Average).Average
        $atr_pct = if ($RecentCandles[0].close -gt 0) {
            ($atr / [double]$RecentCandles[0].close) * 100
        } else { 0 }

        return [PSCustomObject]@{
            atr = [Math]::Round($atr, 4)
            atr_pct = [Math]::Round($atr_pct, 2)
            method = "candles"
        }
    }

    # Fallback: ATR proxy via 24h change
    $atr_pct = [Math]::Abs($Change24hPct) * 0.5
    if ($atr_pct -lt 1.5) { $atr_pct = 1.5 }
    if ($atr_pct -gt 10.0) { $atr_pct = 10.0 }

    return [PSCustomObject]@{
        atr = 0
        atr_pct = [Math]::Round($atr_pct, 2)
        method = "proxy"
    }
}

function Invoke-RefinedStopLossTarget {
    <#
    .SYNOPSIS
    Calcula SL/Target refinado baseado em:
      - ATR real (não estimate barato)
      - Confluência (entrada forte = RR maior)
      - Regime (BULL = RR maior, BEAR = RR menor)
    #>
    param(
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $AtrPct,
        [Parameter(Mandatory)] [double] $PositionConfidence,  # 0-1 (confluence/5)
        [string] $Direction = "LONG",
        [string] $Regime = "SIDEWAYS"
    )

    # Stop-loss: ATR * confidence
    # - Se confluence 5/5 (conf=1.0), usar ATR * 1.0
    # - Se confluence 3/5 (conf=0.6), usar ATR * 1.2 (mais largo, menos reativo)
    $posConf = [double]$PositionConfidence
    $atrDouble = [double]$AtrPct
    $sl_pct = [double]($atrDouble * (1 + (1 - $posConf) * 0.5))

    # R:R baseado em confluência + regime
    $rr_ratio = @(switch ($posConf) {
        {$_ -ge 0.99} { if ($Regime -match "BULL") { 12 } else { 8 } }
        {$_ -ge 0.79} { if ($Regime -match "BULL") { 10 } else { 7 } }
        {$_ -ge 0.59} { if ($Regime -match "BULL") { 8 } else { 5 } }
        default { 5 }
    })[0]

    # Calcular SL e Target
    $entry = [double]$EntryPrice
    $rrRatio = [double]$rr_ratio
    if ($Direction -eq "LONG") {
        $stop = [Math]::Round($entry * (1 - $sl_pct / 100), 6)
        $target = [Math]::Round($entry * (1 + (($sl_pct * $rrRatio) / 100)), 6)
    } else {
        $stop = [Math]::Round($entry * (1 + $sl_pct / 100), 6)
        $target = [Math]::Round($entry * (1 - (($sl_pct * $rrRatio) / 100)), 6)
    }

    return [PSCustomObject]@{
        entry = $EntryPrice
        stop_loss = $stop
        target = $target
        stop_pct = [Math]::Round($sl_pct, 2)
        rr_ratio = $rr_ratio
        confidence_adjusted = $true
    }
}
