# lib_tori_trades_scanner.ps1 - Read-only Tori Trades trendline analyzer
#
# Analyzes EVERY CoinEx futures-eligible pair from inception using Tori's top-down
# methodology: Weekly -> Daily -> 4H -> 1H -> 15m -> 5m trendline confluence analysis.
#
# Output: PSCustomObject[] ready for JSON export + HTML visualization
# Status: Exploratory analysis only (no trades, no API writes)
#
# PS 5.1, UTF-8 BOM

param(
    [int]$MaxPairsPerBatch = 20,
    [int]$MaxCandles = 300,
    [int]$VerboseOutput = $false
)

# ============================================================================
# CONFIGURATION & DEFAULTS
# ============================================================================

$script:TIMEFRAMES = @("1W", "1D", "4H", "1H", "15m", "5m")

# Trendline quality gates (validated in lib_tori_proximity.ps1)
$script:TRENDLINE_MIN_TOUCHES = 2
$script:TRENDLINE_TOUCH_TOL_PCT = 1.5
$script:TRENDLINE_SLOPE_MIN_DEG = 5.0
$script:TRENDLINE_SLOPE_MAX_DEG = 35.0

# Action line proximity (entry confirmation)
$script:PROXIMITY_MIN_PCT = -3.0    # price up to 3% below line
$script:PROXIMITY_MAX_PCT = 5.0     # price up to 5% above line

# Confluence scoring (multiple signals improve quality)
$script:CONFLUENCE_WEIGHTS = @{
    "volume_climax"     = 1.0      # relative volume spike
    "fractal_pattern"   = 1.0      # structural reversal
    "choch_structure"   = 1.0      # change of character
    "rsi_extreme"       = 0.5      # RSI overbought/oversold
    "divergence"        = 0.5      # price action divergence
}

# R:R thresholds
$script:RR_SCALP_THRESHOLD = 10.0

# ============================================================================
# HELPER: LINEAR REGRESSION FOR TRENDLINE DETECTION
# ============================================================================

function _LinReg {
    param([double[]]$Y)
    $n = $Y.Length
    if ($n -lt 2) {
        $intercept = if ($n -eq 1) { $Y[0] } else { 0 }
        return @{ slope = 0; intercept = $intercept }
    }
    $sumX = 0; $sumY = 0; $sumXY = 0; $sumX2 = 0
    for ($i = 0; $i -lt $n; $i++) {
        $sumX  += $i
        $sumY  += $Y[$i]
        $sumXY += $i * $Y[$i]
        $sumX2 += $i * $i
    }
    $denom = ($n * $sumX2) - ($sumX * $sumX)
    if ($denom -eq 0) {
        return @{ slope = 0; intercept = ($sumY / $n) }
    }
    $slope = (($n * $sumXY) - ($sumX * $sumY)) / $denom
    $intercept = ($sumY - ($slope * $sumX)) / $n
    return @{ slope = $slope; intercept = $intercept }
}

# ============================================================================
# HELPER: DETECT TRENDLINE FROM PRICE SERIES
# ============================================================================

function Get-Trendline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double[]]$Lows,
        [Parameter(Mandatory)] [double[]]$Highs,
        [Parameter(Mandatory)] [string]$TrendType  # "LONG" or "SHORT"
    )

    if ($Lows.Length -lt $script:TRENDLINE_MIN_TOUCHES) {
        return $null
    }

    # LONG trendline: fit to LOWS (ascending support)
    # SHORT trendline: fit to HIGHS (descending resistance)
    $fitData = if ($TrendType -eq "LONG") { $Lows } else { $Highs }

    $lr = _LinReg -Y $fitData

    # Count touches within tolerance
    $touches = 0
    foreach ($i in 0..($fitData.Length - 1)) {
        $lineValue = $lr.intercept + ($lr.slope * $i)
        if ($lineValue -le 0) { continue }
        $diffPct = [Math]::Abs($fitData[$i] - $lineValue) / $lineValue * 100
        if ($diffPct -le $script:TRENDLINE_TOUCH_TOL_PCT) {
            $touches += 1
        }
    }

    if ($touches -lt $script:TRENDLINE_MIN_TOUCHES) {
        return $null
    }

    # Convert slope to degrees
    $slopeDeg = [Math]::Atan($lr.slope) * (180 / [Math]::PI)

    # Gate on slope angle
    if ([Math]::Abs($slopeDeg) -lt $script:TRENDLINE_SLOPE_MIN_DEG -or
        [Math]::Abs($slopeDeg) -gt $script:TRENDLINE_SLOPE_MAX_DEG) {
        return $null
    }

    # Get start and end prices from trendline
    $startPrice = $lr.intercept
    $endPrice = $lr.intercept + ($lr.slope * ($fitData.Length - 1))

    return [PSCustomObject]@{
        slope_deg    = $slopeDeg
        touches      = $touches
        intercept    = $lr.intercept
        slope_raw    = $lr.slope
        start_price  = $startPrice
        end_price    = $endPrice
        quality      = if ($touches -ge 3) { "A+" } else { "A" }
    }
}

# ============================================================================
# HELPER: CALCULATE RSI (14-period)
# ============================================================================

function Get-RSI {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]]$Closes, [int]$Period = 14)

    if ($Closes.Length -lt ($Period + 1)) { return 50.0 }

    $gains = 0; $losses = 0
    for ($i = 1; $i -le $Period; $i++) {
        $delta = $Closes[$i] - $Closes[$i - 1]
        if ($delta -gt 0) { $gains += $delta }
        else { $losses += [Math]::Abs($delta) }
    }

    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period

    for ($i = $Period + 1; $i -lt $Closes.Length; $i++) {
        $delta = $Closes[$i] - $Closes[$i - 1]
        if ($delta -gt 0) {
            $avgGain = ($avgGain * ($Period - 1) + $delta) / $Period
            $avgLoss = $avgLoss * ($Period - 1) / $Period
        } else {
            $avgGain = $avgGain * ($Period - 1) / $Period
            $avgLoss = ($avgLoss * ($Period - 1) + [Math]::Abs($delta)) / $Period
        }
    }

    if ($avgLoss -eq 0) { return 100.0 }
    $rs = $avgGain / $avgLoss
    return 100 - (100 / (1 + $rs))
}

# ============================================================================
# HELPER: DETECT VOLUME CLIMAX
# ============================================================================

function Get-VolumeSignal {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [double[]]$Volumes)

    if ($Volumes.Length -lt 5) { return 0 }

    # Compare recent volume to 5-period average
    $recent = $Volumes[-1]
    $avg = ($Volumes[-5..-1] | Measure-Object -Sum).Sum / 5

    if ($avg -eq 0) { return 0 }

    $ratio = $recent / $avg

    # Volume climax: >2.5x normal
    if ($ratio -ge 2.5) { return 2 }
    if ($ratio -ge 1.8) { return 1 }
    if ($ratio -le 0.5) { return -1 }  # Drying

    return 0
}

# ============================================================================
# HELPER: DETECT REVERSAL CANDLE PATTERNS
# ============================================================================

function Get-ReversalPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double]$Open,
        [Parameter(Mandatory)] [double]$Close,
        [Parameter(Mandatory)] [double]$High,
        [Parameter(Mandatory)] [double]$Low,
        [Parameter(Mandatory)] [double]$ActionLine,
        [Parameter(Mandatory)] [string]$TrendType
    )

    # Check if candle closes beyond action line
    if ($TrendType -eq "LONG") {
        # LONG: candle closing below support = rejection
        if ($Close -lt $ActionLine) { return "SUPPORT_TESTED" }
    } else {
        # SHORT: candle closing above resistance = rejection
        if ($Close -gt $ActionLine) { return "RESISTANCE_TESTED" }
    }

    return $null
}

# ============================================================================
# HELPER: CALCULATE FIBONACCI EXTENSION TARGET
# ============================================================================

function Get-FibonacciTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double]$Entry,
        [Parameter(Mandatory)] [double]$Stop,
        [string]$TrendType = "LONG",
        [double]$RatioTarget = 5.0  # 1:5 R:R minimum
    )

    $risk = [Math]::Abs($Entry - $Stop)

    if ($TrendType -eq "LONG") {
        # Target = Entry + (Risk * RatioTarget)
        return $Entry + ($risk * $RatioTarget)
    } else {
        # Target = Entry - (Risk * RatioTarget)
        return $Entry - ($risk * $RatioTarget)
    }
}

# ============================================================================
# HELPER: CONFLUENCE SCORE (0-100)
# ============================================================================

function Get-ConfluenceScore {
    [CmdletBinding()]
    param(
        [int]$VolumeSignal = 0,
        [double]$RSI = 50,
        [bool]$ReversalConfirmed = $false,
        [string]$TrendType = "LONG",
        [int]$TouchCount = 2
    )

    $score = 50  # baseline

    # Volume confluence
    if ($VolumeSignal -eq 2) { $score += 15 }
    elseif ($VolumeSignal -eq 1) { $score += 8 }
    elseif ($VolumeSignal -eq -1) { $score += 5 }  # Drying = preparing

    # RSI confluence
    if ($TrendType -eq "LONG") {
        if ($RSI -lt 30) { $score += 15 }    # Oversold
        elseif ($RSI -lt 40) { $score += 10 }
        elseif ($RSI -gt 70) { $score -= 10 }
    } else {
        if ($RSI -gt 70) { $score += 15 }    # Overbought
        elseif ($RSI -gt 60) { $score += 10 }
        elseif ($RSI -lt 30) { $score -= 10 }
    }

    # Reversal confirmation
    if ($ReversalConfirmed) { $score += 15 }

    # Touch quality
    $score += [Math]::Min(10, $TouchCount * 2)

    return [Math]::Max(0, [Math]::Min(100, $score))
}

# ============================================================================
# MAIN: ANALYZE SINGLE PAIR ACROSS ALL TIMEFRAMES
# ============================================================================

function Analyze-ToriPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Market,
        [PSObject]$CoinExFunc  # Pass CoinEx-GetFuturesCandles function reference
    )

    Write-Verbose "Analyzing $Market..."

    $setups = @()

    # Top-down: Start with Weekly for macro bias
    foreach ($tf in $script:TIMEFRAMES) {
        try {
            # Fetch candles (limit 300 for balance)
            $candles = & $CoinExFunc -market $Market -period $tf -limit 300

            if (-not $candles -or $candles.Count -lt $script:TRENDLINE_MIN_TOUCHES) {
                Write-Verbose "  [$tf] insufficient data ($($candles.Count) candles)"
                continue
            }

            # Extract OHLCV arrays (reverse for chronological order)
            $closes  = @($candles | ForEach-Object { [double]$_.close })
            $lows    = @($candles | ForEach-Object { [double]$_.low })
            $highs   = @($candles | ForEach-Object { [double]$_.high })
            $volumes = @($candles | ForEach-Object { [double]$_.volume })
            $opens   = @($candles | ForEach-Object { [double]$_.open })

            # Analyze LONG (ascending support)
            $longTL = Get-Trendline -Lows $lows -Highs $highs -TrendType "LONG"
            if ($longTL) {
                $currentPrice = $closes[-1]
                $proximity = (($currentPrice - $longTL.start_price) / $longTL.start_price) * 100

                if ($proximity -ge $script:PROXIMITY_MIN_PCT -and $proximity -le $script:PROXIMITY_MAX_PCT) {
                    $rsi = Get-RSI -Closes $closes
                    $volSig = Get-VolumeSignal -Volumes $volumes
                    $reversal = Get-ReversalPattern -Open $opens[-1] -Close $closes[-1] -High $highs[-1] -Low $lows[-1] -ActionLine $longTL.start_price -TrendType "LONG"

                    # Calculate risk and target
                    $stop = $longTL.start_price * 0.98  # 2% below action line
                    $risk = $currentPrice - $stop
                    $target = Get-FibonacciTarget -Entry $currentPrice -Stop $stop -TrendType "LONG" -RatioTarget 5.0
                    $reward = $target - $currentPrice
                    $ratio = if ($risk -ne 0) { $reward / $risk } else { 0 }

                    $confluence = Get-ConfluenceScore -VolumeSignal $volSig -RSI $rsi -ReversalConfirmed ($null -ne $reversal) -TrendType "LONG" -TouchCount $longTL.touches

                    $setups += [PSCustomObject]@{
                        market               = $Market
                        timeframe            = $tf
                        trend_type           = "LONG"
                        trendline_quality    = $longTL.quality
                        action_line          = [Math]::Round($longTL.start_price, 8)
                        safety_line          = [Math]::Round($stop, 8)
                        current_price        = [Math]::Round($currentPrice, 8)
                        proximity_pct        = [Math]::Round($proximity, 2)
                        entry_confirmation   = if ($reversal) { "CONFIRMED" } else { "PENDING" }
                        entry_price          = [Math]::Round($currentPrice, 8)
                        target_price         = [Math]::Round($target, 8)
                        risk_usdt            = [Math]::Round($risk, 8)
                        reward_usdt          = [Math]::Round($reward, 8)
                        ratio                = [Math]::Round($ratio, 2)
                        scalp_eligible       = $ratio -ge $script:RR_SCALP_THRESHOLD
                        confluence_score     = $confluence
                        confluence_count     = ([int]($volSig -ne 0)) + ([int]($reversal -ne $null)) + 1
                        rsi                  = [Math]::Round($rsi, 1)
                        volume_signal        = $volSig
                        touches              = $longTL.touches
                        slope_deg            = [Math]::Round($longTL.slope_deg, 2)
                        chart_data           = @{
                            candles = @($candles | ForEach-Object {
                                @{
                                    ts     = $_.ts
                                    o      = [Math]::Round([double]$_.open, 8)
                                    h      = [Math]::Round([double]$_.high, 8)
                                    l      = [Math]::Round([double]$_.low, 8)
                                    c      = [Math]::Round([double]$_.close, 8)
                                    v      = [Math]::Round([double]$_.volume, 4)
                                }
                            })
                            trendline = @{
                                start_price = $longTL.start_price
                                end_price   = $longTL.end_price
                                slope_pct   = [Math]::Round($longTL.slope_raw * 100, 4)
                            }
                        }
                    }
                }
            }

            # Analyze SHORT (descending resistance)
            $shortTL = Get-Trendline -Lows $lows -Highs $highs -TrendType "SHORT"
            if ($shortTL) {
                $currentPrice = $closes[-1]
                $proximity = (($shortTL.start_price - $currentPrice) / $shortTL.start_price) * 100

                if ($proximity -ge $script:PROXIMITY_MIN_PCT -and $proximity -le $script:PROXIMITY_MAX_PCT) {
                    $rsi = Get-RSI -Closes $closes
                    $volSig = Get-VolumeSignal -Volumes $volumes
                    $reversal = Get-ReversalPattern -Open $opens[-1] -Close $closes[-1] -High $highs[-1] -Low $lows[-1] -ActionLine $shortTL.start_price -TrendType "SHORT"

                    # Calculate risk and target
                    $stop = $shortTL.start_price * 1.02  # 2% above action line
                    $risk = $stop - $currentPrice
                    $target = Get-FibonacciTarget -Entry $currentPrice -Stop $stop -TrendType "SHORT" -RatioTarget 5.0
                    $reward = $currentPrice - $target
                    $ratio = if ($risk -ne 0) { $reward / $risk } else { 0 }

                    $confluence = Get-ConfluenceScore -VolumeSignal $volSig -RSI $rsi -ReversalConfirmed ($null -ne $reversal) -TrendType "SHORT" -TouchCount $shortTL.touches

                    $setups += [PSCustomObject]@{
                        market               = $Market
                        timeframe            = $tf
                        trend_type           = "SHORT"
                        trendline_quality    = $shortTL.quality
                        action_line          = [Math]::Round($shortTL.start_price, 8)
                        safety_line          = [Math]::Round($stop, 8)
                        current_price        = [Math]::Round($currentPrice, 8)
                        proximity_pct        = [Math]::Round($proximity, 2)
                        entry_confirmation   = if ($reversal) { "CONFIRMED" } else { "PENDING" }
                        entry_price          = [Math]::Round($currentPrice, 8)
                        target_price         = [Math]::Round($target, 8)
                        risk_usdt            = [Math]::Round($risk, 8)
                        reward_usdt          = [Math]::Round($reward, 8)
                        ratio                = [Math]::Round($ratio, 2)
                        scalp_eligible       = $ratio -ge $script:RR_SCALP_THRESHOLD
                        confluence_score     = $confluence
                        confluence_count     = ([int]($volSig -ne 0)) + ([int]($reversal -ne $null)) + 1
                        rsi                  = [Math]::Round($rsi, 1)
                        volume_signal        = $volSig
                        touches              = $shortTL.touches
                        slope_deg            = [Math]::Round($shortTL.slope_deg, 2)
                        chart_data           = @{
                            candles = @($candles | ForEach-Object {
                                @{
                                    ts     = $_.ts
                                    o      = [Math]::Round([double]$_.open, 8)
                                    h      = [Math]::Round([double]$_.high, 8)
                                    l      = [Math]::Round([double]$_.low, 8)
                                    c      = [Math]::Round([double]$_.close, 8)
                                    v      = [Math]::Round([double]$_.volume, 4)
                                }
                            })
                            trendline = @{
                                start_price = $shortTL.start_price
                                end_price   = $shortTL.end_price
                                slope_pct   = [Math]::Round($shortTL.slope_raw * 100, 4)
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-Verbose "  [$tf] error: $_"
        }
    }

    return @($setups)
}

# ============================================================================
# MAIN ENTRY POINT: SCAN ALL PAIRS
# ============================================================================

function Invoke-ToriTradesAnalysis {
    [CmdletBinding()]
    param(
        [int]$MaxPairs = 100,
        [int]$BatchSize = 20,
        [switch]$Verbose
    )

    Write-Host "Tori Trades Scanner - Starting analysis..." -ForegroundColor Green

    # Ensure lib_coinex is loaded
    $coinexPath = Join-Path $PSScriptRoot "lib_coinex.ps1"
    if (-not (Get-Command CoinEx-GetFuturesMarkets -ErrorAction SilentlyContinue)) {
        if (Test-Path $coinexPath) {
            . $coinexPath
        } else {
            throw "lib_coinex.ps1 not found at $coinexPath"
        }
    }

    # Get all futures markets
    Write-Host "Fetching CoinEx futures market list..." -ForegroundColor Cyan
    $allMarkets = $null
    try {
        $allMarkets = CoinEx-GetFuturesMarkets | Where-Object { $_.market -match "USDT$" } | Select-Object -ExpandProperty market
    }
    catch {
        Write-Error "Failed to fetch markets: $_"
        return @()
    }

    if (-not $allMarkets) {
        Write-Error "No futures markets found"
        return @()
    }

    $allMarkets = @($allMarkets | Sort-Object)
    $totalMarkets = @($allMarkets).Count
    Write-Host "Found $totalMarkets USDT futures pairs" -ForegroundColor Yellow

    # Limit to MaxPairs for initial scan
    $pairsToAnalyze = $allMarkets | Select-Object -First $MaxPairs
    Write-Host "Analyzing first $($pairsToAnalyze.Count) pairs..." -ForegroundColor Yellow

    # Collect all setups
    $allSetups = @()
    $analyzed = 0

    foreach ($pair in $pairsToAnalyze) {
        $analyzed += 1
        $pct = [Math]::Round(($analyzed / $pairsToAnalyze.Count) * 100)
        Write-Progress -Activity "Analyzing pairs" -Status "$pair ($analyzed/$($pairsToAnalyze.Count))" -PercentComplete $pct

        try {
            $setups = Analyze-ToriPair -Market $pair -CoinExFunc ${function:CoinEx-GetFuturesCandles}
            $allSetups += @($setups)
        }
        catch {
            Write-Verbose "Failed to analyze ${pair}: $_"
        }

        # Throttle API calls
        Start-Sleep -Milliseconds 100
    }

    Write-Progress -Activity "Analyzing pairs" -Completed

    # Sort by confluence score and ratio (best setups first)
    $allSetups = $allSetups | Sort-Object -Property @{Expression="confluence_score"; Descending=$true}, @{Expression="ratio"; Descending=$true}

    Write-Host "`nAnalysis complete: $($allSetups.Count) high-quality setups found" -ForegroundColor Green

    # Summary statistics
    if ($allSetups.Count -gt 0) {
        Write-Host "`nSetup Summary:" -ForegroundColor Cyan
        Write-Host "  LONG setups:     $(($allSetups | Where-Object { $_.trend_type -eq 'LONG' }).Count)"
        Write-Host "  SHORT setups:    $(($allSetups | Where-Object { $_.trend_type -eq 'SHORT' }).Count)"
        Write-Host "  Avg ratio:       $(($allSetups | Measure-Object -Property ratio -Average).Average.ToString('N2'))"
        Write-Host "  Scalp eligible:  $(($allSetups | Where-Object { $_.scalp_eligible }).Count)"
        Write-Host "  A+ quality:      $(($allSetups | Where-Object { $_.trendline_quality -eq 'A+' }).Count)"
    }

    return ,$allSetups
}

# ============================================================================
# EXPORT FUNCTIONS
# ============================================================================

function Export-ToriSetupsToJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]]$Setups,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    $json = $Setups | ConvertTo-Json -Depth 5
    Set-Content -Path $OutputPath -Value $json -Encoding UTF8
    Write-Host "Exported $($Setups.Count) setups to $OutputPath" -ForegroundColor Green
}

# Public interface
Export-ModuleMember -Function Invoke-ToriTradesAnalysis, Export-ToriSetupsToJson
