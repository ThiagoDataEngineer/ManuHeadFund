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
        # - High volatility + high breadth = bullish (vol_ratio > 1.5)
        # - High volatility + low breadth = bearish dump (vol_ratio > 1.8)
        $vol_ratio = if ($avgVolatility -gt 0) {
            if ($avgVolatility -gt 10) { 2.0 }      # Extreme volatility
            elseif ($avgVolatility -gt 5) { 1.8 }   # High volatility
            elseif ($avgVolatility -gt 2) { 1.5 }   # Moderate volatility
            else { 1.0 }                             # Low volatility
        } else {
            1.0
        }

        # === Classification: breadth + volatility ===
        $trend = "neutral"
        $confidence = 0.50

        if ($breadth_pct -gt 60 -and $vol_ratio -gt 1.5) {
            $trend = "bullish"
            $confidence = 0.75 + ($breadth_pct - 60) / 40 * 0.15  # up to 0.90 at 100%
            $confidence = [Math]::Min($confidence, 0.90)
        } elseif ($breadth_pct -lt 40 -and $vol_ratio -gt 1.8) {
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
        [double] $ConfidenceMinBearish = 0.65
    )

    $breadth = Get-AltcoinBreadth -UseCache $true

    # === OR logic: Parallel gates ===
    # LONG: allowed if BTC allows OR (breadth bullish AND confidence ok)
    $allowLong = $BtcAllowLong -or `
                 ($breadth.trend -eq "bullish" -and $breadth.breadth_pct -gt $BreadthBullishThreshold -and `
                  $breadth.confidence -gt $ConfidenceMinBullish)

    # SHORT: allowed if BTC allows OR (breadth bearish AND confidence ok)
    $allowShort = $BtcAllowShort -or `
                  ($breadth.trend -eq "bearish" -and $breadth.breadth_pct -lt $BreadthBearishThreshold -and `
                   $breadth.confidence -gt $ConfidenceMinBearish)

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
        source = "parallel_breadth_gate"
        reason = "or_logic: breadth_${($breadth.trend)}_${($breadth.breadth_pct)}pct_conf${($breadth.confidence)}"
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

