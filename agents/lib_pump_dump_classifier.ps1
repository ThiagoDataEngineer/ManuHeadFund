# lib_pump_dump_classifier.ps1 -- Pump-Dump vs Natural uptrend classifier
# 2026-07-15: Gate #3 — distingue pump natural de pump-and-dump
# Usa 7+ features ponderadas para classificar

param()

$script:__pumpCache = @{}
$script:__pumpCacheAt = @{}

function Get-PumpDumpClass {
    <#
    .SYNOPSIS
        Classifica moeda em {natural_uptrend|pump_and_dump|reaccumulation|new_listing}.
        Score: -15 até +25 por feature, threshold 60+ = dump.
    .PARAMETER Market
        Symbol (ex: BILLUSDT)
    .PARAMETER Metadata
        Hashtable com: mcap, listing_date_days, volume_7d_avg (opcional).
    .PARAMETER UseCache
        Se $true, usa cache 1H antes de refetch (default: $true).
    .EXAMPLE
        $c = Get-PumpDumpClass -Market BILLUSDT -Metadata @{mcap=80000000; listing_date_days=30}
        $c.class  # "pump_and_dump" | "natural_uptrend" | "reaccumulation" | "new_listing"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [hashtable] $Metadata = @{},
        [bool] $UseCache = $true,
        [int] $CacheMinutes = 60
    )

    # === Cache check ===
    if ($UseCache -and $script:__pumpCache.ContainsKey($Market)) {
        $cacheTime = $script:__pumpCacheAt[$Market]
        if ($cacheTime -and ((Get-Date) - $cacheTime).TotalMinutes -lt $CacheMinutes) {
            return $script:__pumpCache[$Market]
        }
    }

    try {
        # === Fetch 7d history ===
        $candles = @(Get-CoinExCandles -Market $Market -Period "1day" -Limit 7 -ErrorAction Stop)
        if ($candles.Count -lt 2) {
            return @{
                class = "unknown"
                score = -100
                confidence = 0
                reason = "insufficient_data"
                details = @{}
            }
        }

        # === Extract candle data ===
        $today = $candles[-1]
        $peak7d = ($candles | ForEach-Object { [double]$_.high } | Measure-Object -Maximum).Maximum
        # 2026-08-14 FIX: $avgVol7d incluia o proprio candle de hoje -- auto-
        # contaminacao, nao so vies de outlier (achado real: auditoria do
        # motor de Volume Accumulation revelou o mesmo padrao Measure-Object
        # -Average em varios pontos do sistema). O dia do pump SEMPRE puxa a
        # propria media pra cima contra a qual ele mesmo e comparado, sub-
        # estimando volRatio de forma sistematica (nao aleatoria) -- caso de
        # fronteira medido: pump real de 3.1x aparecia como 2.38x, perdendo
        # os 20 pontos de "vol_spike_score" pro nivel de 10 (10 pontos a
        # menos no score final, podendo mudar reaccumulation<->pump_and_dump
        # perto do threshold de 60). Fix: media usa so os candles ANTERIORES
        # a hoje (exclui o ultimo). Fail-safe: se so 1 candle disponivel
        # (candles.Count<2 ja bloqueado acima, mas defensivo aqui tambem),
        # cai no proprio $today.volume (evita divisao por zero/vazio).
        $priorCandles = if ($candles.Count -gt 1) { $candles[0..($candles.Count - 2)] } else { $candles }
        $avgVol7d = ($priorCandles | ForEach-Object { [double]$_.volume } | Measure-Object -Average).Average
        $price = [double]$today.close

        # === Feature extraction ===
        $score = 0
        $details = @{}

        # Feature 1: Duration of pump (how fast reached peak)
        # Simplified: if pump happened in <24H, score +20
        # If in <48H, score +10. Since we only have 1D candles, estimate from peak distance
        $daysFromPeak = 0  # Assume peak is today for now (simplified)
        if ($daysFromPeak -eq 0 -and $price -ge $peak7d * 0.99) {
            # Peak today or yesterday = extreme pump
            $score += 20
            $details["duration_score"] = 20
        } elseif ($daysFromPeak -le 1) {
            $score += 10
            $details["duration_score"] = 10
        } else {
            $details["duration_score"] = 0
        }

        # Feature 2: Market cap (low cap = pump risk)
        # MCap < 100M: +15, < 50M: +20
        $mcap = if ($Metadata.mcap) { [double]$Metadata.mcap } else { 50000000 }
        if ($mcap -lt 50000000) {
            $score += 20
            $details["mcap_score"] = 20
        } elseif ($mcap -lt 100000000) {
            $score += 15
            $details["mcap_score"] = 15
        } else {
            $details["mcap_score"] = 0
        }

        # Feature 3: Price absolute level (penny stock = dump signature)
        # Price < 0.01 USD: +10
        if ($price -lt 0.01) {
            $score += 10
            $details["penny_stock_score"] = 10
        } else {
            $details["penny_stock_score"] = 0
        }

        # Feature 4: Volume spike ratio
        # Vol > 3x: +20, > 2x: +10, > 1.5x: +5
        $volRatio = if ($avgVol7d -gt 0) { [double]$today.volume / $avgVol7d } else { 1.0 }
        if ($volRatio -gt 3.0) {
            $score += 20
            $details["vol_spike_score"] = 20
        } elseif ($volRatio -gt 2.0) {
            $score += 10
            $details["vol_spike_score"] = 10
        } elseif ($volRatio -gt 1.5) {
            $score += 5
            $details["vol_spike_score"] = 5
        } else {
            $details["vol_spike_score"] = 0
        }

        # Feature 5: Retracement from peak (fast drop = dump signature)
        # 2026-07-16 FIX: threshold fixo de -30% foi calibrado so pra gemas
        # pump-and-dump (volatilidade nativa alta) -- majors/blue-chips (ARBUSDT,
        # AVAXUSDT) raramente caem 30% em 7d mesmo em reversao tecnica real
        # confirmada (achado real: ARBUSDT -13% do pico + Tori confluence=100
        # RSI_EXTREME+FRACTAL_BEARISH+CHOCH+VOLUME_PROFILE ainda classificava
        # "natural_uptrend" por eliminacao, bloqueando 2/2 SHORTs no dia com
        # confluence tecnica maxima). Fix: threshold RELATIVO a volatilidade
        # normal do proprio par (ATR% medio dos candles 1D), nao fixo -- retracement
        # de 2x a volatilidade normal do ativo e proporcionalmente tao significativo
        # quanto -30% numa gema, seja o ativo qual for.
        $atrPct = ($candles | ForEach-Object {
            $h = [double]$_.high; $l = [double]$_.low; $c = [double]$_.close
            if ($c -gt 0) { (($h - $l) / $c) * 100 } else { 0 }
        } | Measure-Object -Average).Average
        if ($atrPct -le 0) { $atrPct = 5.0 }  # fallback conservador se sem dado
        $retracementThreshold = [Math]::Max(-30, -2.5 * $atrPct)  # nunca mais restritivo que -30% fixo original

        $distFromPeak = (($price - $peak7d) / $peak7d) * 100
        if ($distFromPeak -lt $retracementThreshold) {
            # Check if recent drop (last candle) is dramatic (relativo ao ATR tambem)
            if ($candles.Count -gt 1) {
                $prevClose = [double]$candles[-2].close
                $todayReturn = (($price - $prevClose) / $prevClose) * 100
                if ($todayReturn -lt (-1.5 * $atrPct)) {
                    $score += 25
                    $details["retracement_score"] = 25
                } else {
                    $score += 15
                    $details["retracement_score"] = 15
                }
            } else {
                $score += 15
                $details["retracement_score"] = 15
            }
        } else {
            $details["retracement_score"] = 0
        }
        $details["atr_pct"] = [Math]::Round($atrPct, 2)
        $details["retracement_threshold"] = [Math]::Round($retracementThreshold, 2)

        # Feature 6: Candle strength (body vs wick = distribution signal)
        # Strong close (body > 70% of range): -5 (good sign)
        # Weak/doji (body < 20% of range): +5 (distribution sign)
        $high = [double]$today.high
        $low = [double]$today.low
        $open = [double]$today.open
        $range = $high - $low
        if ($range -gt 0) {
            $body = [Math]::Abs($price - $open)
            $bodyRatio = $body / $range
            if ($bodyRatio -gt 0.7) {
                $score -= 5  # Strong close, likely accumulation
                $details["candle_strength_score"] = -5
            } elseif ($bodyRatio -lt 0.2) {
                $score += 5   # Weak close, likely distribution
                $details["candle_strength_score"] = 5
            } else {
                $details["candle_strength_score"] = 0
            }
        } else {
            $details["candle_strength_score"] = 0
        }

        # Feature 7: New listing bonus (organic growth)
        # Listed < 7 days: -15 (new listings grow naturally, not dump)
        $daysListed = if ($Metadata.listing_date_days) { [int]$Metadata.listing_date_days } else { 100 }
        if ($daysListed -lt 7) {
            $score -= 15
            $details["new_listing_score"] = -15
        } else {
            $details["new_listing_score"] = 0
        }

        # === Classification ===
        $class = if ($score -ge 60) {
            "pump_and_dump"
        } elseif ($score -ge 30) {
            "reaccumulation"
        } elseif ($score -gt 0) {
            "natural_uptrend"
        } else {
            "new_listing"
        }

        $confidence = switch ($class) {
            "pump_and_dump" { 0.85 }
            "reaccumulation" { 0.65 }
            "natural_uptrend" { 0.55 }
            default { 0.40 }
        }

        $result = @{
            class = $class
            score = $score
            confidence = [Math]::Round($confidence, 3)
            details = $details
            metadata = @{
                price = [Math]::Round($price, 8)
                peak_7d = [Math]::Round($peak7d, 8)
                dist_from_peak_pct = [Math]::Round($distFromPeak, 2)
                vol_ratio_today_vs_7d_avg = [Math]::Round($volRatio, 2)
                mcap = $mcap
                days_listed = $daysListed
            }
            reason = "classified: score=$score"
            ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        # === Cache result ===
        $script:__pumpCache[$Market] = $result
        $script:__pumpCacheAt[$Market] = Get-Date

        return $result

    } catch {
        return @{
            class = "error"
            score = -100
            confidence = 0
            reason = "exception: $_"
            details = @{}
        }
    }
}

function Test-PumpDumpGate {
    <#
    .SYNOPSIS
        Aplica pump-dump classifier como gate.
        Bloqueia LONG em dump candidates near peak.
        Permite SHORT em confirmed dumps.
    .PARAMETER Market
        Symbol
    .PARAMETER Metadata
        Hashtable com mcap, listing_date_days
    .PARAMETER DistFromPeakThreshold
        Threshold de distancia do peak para bloquear LONG (default: -5%)
    .EXAMPLE
        $gate = Test-PumpDumpGate -Market BILLUSDT
        $gate.allow_short  # $true se pump_and_dump
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [hashtable] $Metadata = @{},
        [double] $DistFromPeakThreshold = -5.0
    )

    $classifier = Get-PumpDumpClass -Market $Market -Metadata $Metadata

    # Gate logic:
    # 1) pump_and_dump + price near peak (-5% threshold) = BLOCK LONG
    # 2) pump_and_dump = ALLOW SHORT (entry post-reversal)
    # 3) reaccumulation = ALLOW SHORT (consolidation before breakout)
    # 4) natural_uptrend = ALLOW LONG, BLOCK SHORT
    # 5) new_listing = CAUTIOUS (low conviction, allow both with penalty)

    $allowLong = $true
    $allowShort = $false
    $reason = ""

    switch ($classifier.class) {
        "pump_and_dump" {
            $distFromPeak = $classifier.metadata.dist_from_peak_pct
            if ($distFromPeak -gt $DistFromPeakThreshold) {
                # Still near peak = block LONG
                $allowLong = $false
                $reason = "pump_and_dump_near_peak_dist${distFromPeak}pct"
            } else {
                # Already dropped = allow LONG (bargain hunting)
                $reason = "pump_and_dump_retracted_dist${distFromPeak}pct"
            }
            # Always allow SHORT on dumps
            $allowShort = $true
        }

        "reaccumulation" {
            # Consolidation pattern: allow SHORT (wait for breakout)
            $allowShort = $true
            $reason = "reaccumulation_allows_short"
        }

        "natural_uptrend" {
            # Natural growth: allow LONG, block SHORT
            $allowLong = $true
            $allowShort = $false
            $reason = "natural_uptrend_long_only"
        }

        "new_listing" {
            # New listings: cautious (low confidence)
            $allowLong = $true
            $allowShort = $false
            $reason = "new_listing_long_with_caution"
        }

        default {
            # Unknown: default to conservative
            $allowLong = $false
            $allowShort = $false
            $reason = "unknown_class_conservative"
        }
    }

    return [PSCustomObject]@{
        allow_long = $allowLong
        allow_short = $allowShort
        pump_class = $classifier.class
        pump_score = $classifier.score
        pump_confidence = $classifier.confidence
        dist_from_peak_pct = $classifier.metadata.dist_from_peak_pct
        vol_ratio = $classifier.metadata.vol_ratio_today_vs_7d_avg
        reason = $reason
        source = "pump_dump_gate"
    }
}

function Format-PumpDumpReport {
    <#
    .SYNOPSIS
        Formata pump-dump classification para logging/Telegram.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [PSCustomObject] $Classification,
        [bool] $Verbose = $false
    )

    $icon = switch ($Classification.class) {
        "pump_and_dump" { "[DUMP]" }
        "reaccumulation" { "[REAC]" }
        "natural_uptrend" { "[NATL]" }
        "new_listing" { "[NEW]" }
        default { "[UNK]" }
    }

    $line1 = "$icon $Market`: $($Classification.class) score=$($Classification.score) conf=$($Classification.confidence)"

    if ($Verbose) {
        $line2 = "  Price vs Peak: $($Classification.metadata.dist_from_peak_pct)% | Vol Ratio: $($Classification.metadata.vol_ratio_today_vs_7d_avg)x"
        $mcapStr = '$' + $Classification.metadata.mcap
        $line3 = "  MCap: $mcapStr | Days Listed: $($Classification.metadata.days_listed)"
        return @($line1, $line2, $line3) -join "`n"
    }

    return $line1
}
