# lib_breadth_monitor.ps1 -- Parallel breadth gate (altcoin micro-trends)
# 2026-07-15: Destranca altcoin trades mesmo quando BTC em NEUTRO/chop
# Detecta: top 50 gainers/losers, breadth%, vol spike, trend classification

param()

$script:__breadthCache = $null
$script:__breadthCacheAt = [datetime]::MinValue

function Get-AltcoinBreadth {
    <#
    .SYNOPSIS
        Calcula breadth de top 50 gainers/losers em 24H (CoinEx API).
        Retorna: trend {bullish|neutral|bearish}, breadth_pct, vol_ratio, confidence.
    .PARAMETER UseCache
        Se $true, usa cache 5min antes de refetch (default: $true).
    .PARAMETER CacheMinutes
        Duração do cache em minutos (default: 5).
    .EXAMPLE
        $b = Get-AltcoinBreadth
        $b.trend  # "bullish" | "neutral" | "bearish"
    #>
    [CmdletBinding()]
    param(
        [bool] $UseCache = $true,
        [int] $CacheMinutes = 5
    )

    # === Cache check ===
    if ($UseCache -and $script:__breadthCache -and
        ((Get-Date) - $script:__breadthCacheAt).TotalMinutes -lt $CacheMinutes) {
        return $script:__breadthCache
    }

    try {
        # === Fetch all spot tickers (24h OHLCV) ===
        # 2026-07-15 FIX: /v2/public/markets NAO EXISTE na API CoinEx v2 (404
        # confirmado). Endpoint real e /v2/spot/ticker -- sem params, retorna
        # ~1300 mercados de uma vez com open/close/volume, sem paginacao.
        # Causa raiz de breadth_trend="unknown" em producao (auditoria 2026-07-15,
        # agent a8499866). Achado P5.
        $base = if ($global:COINEX_BASE_URL) { $global:COINEX_BASE_URL } else { "https://api.coinex.com" }
        $url = "$base/v2/spot/ticker"

        $r = Invoke-RestMethod -Uri $url -Method GET -TimeoutSec 8 -ErrorAction Stop

        if ($r.code -ne 0 -or -not $r.data -or $r.data.Count -eq 0) {
            return @{
                trend = "unknown"
                breadth_pct = 0
                vol_ratio = 1.0
                green_count = 0
                total_count = 0
                confidence = 0
                reason = "no_market_data"
            }
        }

        # === Parse market data ===
        # Filtra so pares *USDT (evita contar BTC-quoted/ETH-quoted markets 2x)
        $markets = @($r.data | Where-Object { $_.market -match "USDT$" })
        $green = 0
        $totalVolUSD = 0.0
        $volatilityScores = @()

        foreach ($m in $markets) {
            $openPx = if ($m.open) { [double]$m.open } else { 0 }
            $closePx = if ($m.close) { [double]$m.close } else { 0 }
            $change24h = if ($openPx -gt 0) { (($closePx - $openPx) / $openPx) * 100 } else { 0 }
            $vol24h = if ($m.value) { [double]$m.value } else { 0 }  # value = volume em quote currency (USDT)

            # Count greens
            if ($change24h -gt 0) { $green++ }

            # Accumulate volume
            $totalVolUSD += $vol24h

            # Capture volatility (price change magnitude)
            $volScore = [Math]::Abs($change24h)
            $volatilityScores += $volScore
        }

        $breadth_pct = if ($markets.Count -gt 0) {
            [Math]::Round(($green / $markets.Count) * 100, 1)
        } else {
            0
        }

        $avgVolatility = if ($volatilityScores.Count -gt 0) {
            ($volatilityScores | Measure-Object -Average).Average
        } else {
            0
        }

        # === Calculate vol_ratio proxy ===
        # Since we don't have 7d average in single call, use volatility magnitude as proxy:
        $vol_ratio = if ($avgVolatility -gt 0) {
            if ($avgVolatility -gt 10) { 2.0 }      # Extreme volatility
            elseif ($avgVolatility -gt 5) { 1.8 }   # High volatility
            elseif ($avgVolatility -gt 2) { 1.5 }   # Moderate volatility
            else { 1.0 }                             # Low volatility
        } else {
            1.0
        }

        # === Classification: breadth + volatility ===
        # 2026-07-16 FIX: bearish exigia vol_ratio>1.8 enquanto bullish so
        # exigia >1.5 -- assimetria sem justificativa de mercado documentada,
        # presente desde o commit original (f3fc329). Grid search confirmou:
        # bullish disparava ~2.1x mais facil que bearish em condicoes
        # espelhadas de breadth. Dado real (gate_replay_study, 22 pares SHORT
        # bloqueados por este gate em 2026-07-16): 54.5% teriam dado retorno
        # positivo, media +0.99% -- indicativo de que o SHORT estava
        # estruturalmente mais dificil de liberar do que deveria. Alinhado
        # pro mesmo threshold (1.5) dos dois lados.
        #
        # 2026-07-16 FIX 2: bug de fronteira pre-existente nos dois lados --
        # vol_ratio=1.5 (faixa "moderada", volatilidade 2-5%) e um valor
        # EXATO, nunca "> 1.5". So volatilidade alta (>5%->1.8) ou extrema
        # (>10%->2.0) conseguiam passar; a faixa moderada era uma zona morta
        # que nunca liberava breadth em nenhum sentido. Confirmado ao vivo:
        # breadth=35.9% (bateria SHORT) + vol_ratio=1.5 (nao batia, igual nao
        # e maior) = ainda "neutral". Trocado -gt por -ge nos dois lados.
        $trend = "neutral"
        $confidence = 0.50

        if ($breadth_pct -gt 60 -and $vol_ratio -ge 1.5) {
            $trend = "bullish"
            $confidence = 0.75 + ($breadth_pct - 60) / 40 * 0.15  # up to 0.90 at 100%
            $confidence = [Math]::Min($confidence, 0.90)
        } elseif ($breadth_pct -lt 40 -and $vol_ratio -ge 1.5) {
            $trend = "bearish"
            $confidence = 0.70 + ((40 - $breadth_pct) / 40) * 0.15  # up to 0.85 at 0%
            $confidence = [Math]::Min($confidence, 0.85)
        } else {
            $trend = "neutral"
            $confidence = 0.50
        }

        $result = @{
            trend = $trend
            breadth_pct = $breadth_pct
            vol_ratio = [Math]::Round($vol_ratio, 2)
            green_count = $green
            total_count = $markets.Count
            avg_volatility_pct = [Math]::Round($avgVolatility, 2)
            confidence = [Math]::Round($confidence, 3)
            reason = "market_data_fetched"
            ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        # === Cache result ===
        $script:__breadthCache = $result
        $script:__breadthCacheAt = Get-Date

        return $result

    } catch {
        return @{
            trend = "unknown"
            breadth_pct = 0
            vol_ratio = 1.0
            green_count = 0
            total_count = 0
            confidence = 0
            reason = "api_error: $_"
            ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

function Test-ParallelBreadthGate {
    <#
    .SYNOPSIS
        Aplica breadth como gate PARALELO ao cenário BTC global.
        Libera LONG se breadth bullish OU cenário permite.
        Libera SHORT se breadth bearish OU cenário permite.
    .PARAMETER BtcScenario
        Cenário BTC atual (de Get-MarketScenario: BULL|BEAR|NEUTRO|CAPITULACAO|UNKNOWN)
    .PARAMETER BtcAllowLong
        BTC scenario.allow_long (padrão: $false)
    .PARAMETER BtcAllowShort
        BTC scenario.allow_short (padrão: $false)
    .PARAMETER BreadthBullishThreshold
        Threshold de breadth para bullish (default: 60)
    .PARAMETER BreadthBearishThreshold
        Threshold de breadth para bearish (default: 40)
    .PARAMETER ConfidenceMinBullish
        Confidence mínima para aceitar bullish (default: 0.70)
    .PARAMETER ConfidenceMinBearish
        Confidence mínima para aceitar bearish (default: 0.65)
    .EXAMPLE
        $gate = Test-ParallelBreadthGate -BtcScenario "NEUTRO" -BtcAllowLong $false -BtcAllowShort $false
        $gate.allow_long  # $true se breadth bullish, $false se bearish/neutral
    #>
    [CmdletBinding()]
    param(
        [string] $BtcScenario = "UNKNOWN",
        [bool] $BtcAllowLong = $false,
        [bool] $BtcAllowShort = $false,
        [int] $BreadthBullishThreshold = 60,
        [int] $BreadthBearishThreshold = 40,
        [double] $ConfidenceMinBullish = 0.70,
        [double] $ConfidenceMinBearish = 0.65,
        # 2026-07-16: breadth mede saude do MERCADO INTEIRO (~1300 pares),
        # nao da moeda candidata -- ficava ~47-50% (neutro) o dia inteiro
        # e bloqueava candidatos com sinal PROPRIO forte (ex: ARGUSDT
        # +51%/24h + mais 2.5% em 10min, confirmado via gate_replay_study,
        # bloqueado so pq o mercado geral estava parado). Change24h e
        # StrongMoveThresholdPct sao opcionais (default 0/30, comportamento
        # identico ao anterior se o caller nao passar) -- so ativa o desvio
        # quando o candidato tem movimento isolado extremo. Nao remove as
        # gates seguintes (pump-dump, Tori/LLM, quality) que continuam
        # filtrando pump artificial vs movimento real.
        #
        # 2026-07-16 (rodada 2, apos feedback do usuario): change_24h
        # sozinho pode estar "velho" -- moeda que fez todo o movimento ha
        # 20h e ja perdeu forca/reverteu continua com change_24h alto
        # enganosamente. Market (opcional) ativa confirmacao via
        # Test-RecentMomentumConfirmed: exige que 1h E 4h estejam na MESMA
        # direcao do change_24h antes de liberar por movimento individual.
        # Sem Market informado, cai fail-closed (nao libera por movimento
        # individual -- precisa do dado de confirmacao pra ativar o desvio).
        [double] $Change24h = 0,
        [double] $StrongMoveThresholdPct = 30,
        [string] $Market = ""
    )

    $breadth = Get-AltcoinBreadth -UseCache $true
    $strongIndividualMove = [Math]::Abs($Change24h) -ge $StrongMoveThresholdPct

    $momentumConfirmedUp = $false
    $momentumConfirmedDown = $false
    if ($strongIndividualMove -and $Market) {
        if ($Change24h -gt 0) {
            $momentumConfirmedUp = Test-RecentMomentumConfirmed -Market $Market -Direction "gt"
        } else {
            $momentumConfirmedDown = Test-RecentMomentumConfirmed -Market $Market -Direction "lt"
        }
    }

    # === OR logic: Parallel gates ===
    # LONG: allowed if BTC allows OR (breadth bullish AND confidence ok) OR
    #       (movimento isolado forte E positivo E confirmado em 1h+4h)
    $allowLong = $BtcAllowLong -or `
                 ($breadth.trend -eq "bullish" -and $breadth.breadth_pct -gt $BreadthBullishThreshold -and `
                  $breadth.confidence -gt $ConfidenceMinBullish) -or `
                 $momentumConfirmedUp

    # SHORT: allowed if BTC allows OR (breadth bearish AND confidence ok) OR
    #        (movimento isolado forte E negativo E confirmado em 1h+4h)
    $allowShort = $BtcAllowShort -or `
                  ($breadth.trend -eq "bearish" -and $breadth.breadth_pct -lt $BreadthBearishThreshold -and `
                   $breadth.confidence -gt $ConfidenceMinBearish) -or `
                  $momentumConfirmedDown

    return [PSCustomObject]@{
        allow_long = $allowLong
        allow_short = $allowShort
        breadth_trend = $breadth.trend
        breadth_pct = $breadth.breadth_pct
        breadth_confidence = $breadth.confidence
        breadth_vol_ratio = $breadth.vol_ratio
        breadth_green = $breadth.green_count
        breadth_total = $breadth.total_count
        btc_scenario = $BtcScenario
        btc_allow_long = $BtcAllowLong
        btc_allow_short = $BtcAllowShort
        strong_individual_move = $strongIndividualMove
        change_24h = $Change24h
        source = "parallel_breadth_gate"
        reason = "or_logic: breadth_${($breadth.trend)}_${($breadth.breadth_pct)}pct_conf${($breadth.confidence)}$(if ($strongIndividualMove) { "_OR_strong_move_${Change24h}pct" })"
    }
}

function Test-RecentMomentumConfirmed {
    <#
    .SYNOPSIS
        Confirma se o movimento de 24h ainda esta "quente" AGORA, nao so
        historico. change_24h e janela movel de 24h -- uma moeda que subiu
        tudo ha 20h e ja reverteu/lateralizou continua mostrando change_24h
        alto, enganosamente. Busca candles de 1h e exige que TANTO o
        momentum de 1h QUANTO o de 4h estejam na MESMA direcao do
        change_24h antes de considerar o sinal individual ainda valido.
    .PARAMETER Market
        Symbol (ex: ARGUSDT)
    .PARAMETER Direction
        "gt" (positivo, LONG) ou "lt" (negativo, SHORT) -- direcao esperada
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [ValidateSet("gt", "lt")] [string] $Direction
    )

    if (-not (Get-Command Get-CoinExCandles -ErrorAction SilentlyContinue)) {
        Write-Host "[MOMENTUM DIAG] ${Market}: Get-CoinExCandles indisponivel -- fail-closed" -ForegroundColor DarkGray
        return $false   # fail-closed: sem dado de confirmacao, nao libera
    }

    try {
        # 5 candles de 1h cobre a janela de 4h + 1 de folga
        $candles = @(Get-CoinExCandles -Market $Market -Period "1hour" -Limit 5 -IsFutures $false)
        if ($candles.Count -lt 5) {
            Write-Host "[MOMENTUM DIAG] ${Market}: apenas $($candles.Count) candles (precisa 5) -- fail-closed" -ForegroundColor DarkGray
            return $false
        }

        $last = $candles[-1].close
        $mom1h = (($last - $candles[-2].close) / $candles[-2].close) * 100
        $mom4h = (($last - $candles[0].close) / $candles[0].close) * 100

        $result = if ($Direction -eq "gt") {
            ($mom1h -gt 0 -and $mom4h -gt 0)
        } else {
            ($mom1h -lt 0 -and $mom4h -lt 0)
        }
        # 2026-08-21 DIAG TEMPORARIO: expoe mom1h/mom4h reais pra investigar
        # candidatos TORI score=100 (ARBUSDT/OPUSDT/INJUSDT) bloqueados por
        # breadth_short_blocked -- confirmar se a divergencia 1h-vs-4h
        # documentada no caso ARBUSDT antigo (linha ~545 gem_executor.ps1)
        # ainda e o padrao real, ou se o gate esta rigoroso demais.
        Write-Host "[MOMENTUM DIAG] ${Market} dir=${Direction}: mom1h=$([math]::Round($mom1h,3))% mom4h=$([math]::Round($mom4h,3))% -> confirmed=$result" -ForegroundColor DarkGray
        return $result
    } catch {
        Write-Host "[MOMENTUM DIAG] ${Market}: excecao $_ -- fail-closed" -ForegroundColor DarkGray
        return $false   # fail-closed
    }
}

function Format-BreadthReport {
    <#
    .SYNOPSIS
        Formata breadth para logging/Telegram.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $BreadthGate,
        [bool] $Verbose = $false
    )

    $emoji = switch ($BreadthGate.breadth_trend) {
        "bullish" { "[BULL]" }
        "bearish" { "[BEAR]" }
        default { "[NEUT]" }
    }

    $line1 = "$emoji Breadth: $($BreadthGate.breadth_pct)% ($($BreadthGate.breadth_green)/$($BreadthGate.breadth_total)) " +
             "Trend: $($BreadthGate.breadth_trend) Conf: $($BreadthGate.breadth_confidence)"

    if ($Verbose) {
        $line2 = "  BTC Scenario: $($BreadthGate.btc_scenario) | Vol Ratio: $($BreadthGate.breadth_vol_ratio)"
        $line3 = "  Gates - LONG: $($BreadthGate.allow_long) | SHORT: $($BreadthGate.allow_short)"
        return @($line1, $line2, $line3) -join "`n"
    }

    return $line1
}

