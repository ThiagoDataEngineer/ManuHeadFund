# lib_tori_confluence_detector.ps1 - Confluence signal detection for Tori Trades
#
# Detects 5 advanced confluence signals:
# 1. Volume Climax - volume spike at trendline test
# 2. RSI Extremes - oversold/overbought at reversal
# 3. Fractal Pattern - bullish/bearish fractals
# 4. CHoCH (Change of Character) - structural break
# 5. Volume Profile - volume cluster at support/resistance
#
# Confluence score: 0-100, with detailed breakdown of which signals fired
# PS 5.1, UTF-8 BOM

# ============================================================================
# CONFIGURATION & DEFAULTS
# ============================================================================

$script:CONFLUENCE_WEIGHTS = @{
    "volume_climax"     = 20
    "rsi_extreme"       = 20
    "fractal_pattern"   = 15
    "choch_structure"   = 15
    "volume_profile"    = 10
}

# Volume climax threshold (multiple of average volume)
$script:VOLUME_CLIMAX_THRESHOLD = 2.0
$script:VOLUME_PROFILE_BINS = 20

# RSI extremes
$script:RSI_OVERSOLD = 30
$script:RSI_OVERBOUGHT = 70

# ============================================================================
# HELPER: VOLUME CLIMAX DETECTION
# ============================================================================

function Get-VolumeClimax {
    <#
    .SYNOPSIS
        Detect if current volume is a climax (spike at trendline test)

    .PARAMETER Volumes
        Array of volume values (most recent last)

    .PARAMETER Threshold
        Multiple of average volume to trigger climax (default 2.0)

    .OUTPUTS
        PSCustomObject with is_climax (bool) and ratio (double)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Volumes,

        [Parameter(Mandatory=$false)]
        [double]$Threshold = $script:VOLUME_CLIMAX_THRESHOLD
    )

    if ($Volumes.Length -lt 5) {
        return [PSCustomObject]@{ is_climax = $false; ratio = 0.0 }
    }

    # Average volume of last 5 candles
    $avgVolume = 0.0
    for ($i = -5; $i -lt 0; $i++) {
        $avgVolume += $Volumes[$Volumes.Length + $i]
    }
    $avgVolume = $avgVolume / 5.0

    if ($avgVolume -eq 0) {
        return [PSCustomObject]@{ is_climax = $false; ratio = 0.0 }
    }

    $currentVolume = $Volumes[-1]
    $ratio = $currentVolume / $avgVolume

    $isClimax = $ratio -ge $Threshold

    return [PSCustomObject]@{
        is_climax = $isClimax
        ratio = $ratio
        avg_volume = $avgVolume
        current_volume = $currentVolume
    }
}

# ============================================================================
# HELPER: RSI EXTREMES DETECTION
# ============================================================================

function Get-RSIExtreme {
    <#
    .SYNOPSIS
        Detect if RSI is in extreme zone (oversold/overbought)

    .PARAMETER RSI
        Current RSI value (0-100)

    .PARAMETER SetupType
        "LONG" or "SHORT" - determines which extreme to check

    .OUTPUTS
        PSCustomObject with is_extreme (bool), extreme_type (string), and points
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$RSI,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$SetupType
    )

    $isExtreme = $false
    $extremeType = ""
    $points = 0

    if ($SetupType -eq "LONG") {
        # LONG: looking for oversold
        if ($RSI -lt $script:RSI_OVERSOLD) {
            $isExtreme = $true
            $extremeType = "OVERSOLD"
            $points = 20
        }
    } else {
        # SHORT: looking for overbought
        if ($RSI -gt $script:RSI_OVERBOUGHT) {
            $isExtreme = $true
            $extremeType = "OVERBOUGHT"
            $points = 20
        }
    }

    return [PSCustomObject]@{
        is_extreme = $isExtreme
        extreme_type = $extremeType
        rsi = $RSI
        points = $points
    }
}

# ============================================================================
# HELPER: FRACTAL PATTERN DETECTION
# ============================================================================

function Get-FractalPattern {
    <#
    .SYNOPSIS
        Detect bullish or bearish fractal patterns

        Bearish fractal: High with lower highs on both sides (SHORT signal)
        Bullish fractal: Low with higher lows on both sides (LONG signal)

    .PARAMETER Opens
        Array of open prices

    .PARAMETER Highs
        Array of high prices

    .PARAMETER Lows
        Array of low prices

    .PARAMETER Closes
        Array of close prices

    .OUTPUTS
        PSCustomObject with fractal_type (string), index (int), and points
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Opens,

        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [double[]]$Closes
    )

    $fractalType = ""
    $fractalIndex = -1
    $points = 0

    # Need at least 5 candles to detect fractal (2 before, 1 middle, 2 after)
    if ($Highs.Length -lt 5) {
        return [PSCustomObject]@{
            fractal_type = ""
            fractal_index = -1
            points = 0
        }
    }

    $n = $Highs.Length
    # Check middle 3 candles (skip first 2 and last 2)
    for ($i = 2; $i -lt ($n - 2); $i++) {
        # Bearish fractal: High[i] > High[i-1] AND High[i] > High[i-2] AND High[i] > High[i+1] AND High[i] > High[i+2]
        if ($Highs[$i] -gt $Highs[$i - 1] -and $Highs[$i] -gt $Highs[$i - 2] -and
            $Highs[$i] -gt $Highs[$i + 1] -and $Highs[$i] -gt $Highs[$i + 2]) {
            $fractalType = "BEARISH"
            $fractalIndex = $i
            $points = 15
            break
        }

        # Bullish fractal: Low[i] < Low[i-1] AND Low[i] < Low[i-2] AND Low[i] < Low[i+1] AND Low[i] < Low[i+2]
        if ($Lows[$i] -lt $Lows[$i - 1] -and $Lows[$i] -lt $Lows[$i - 2] -and
            $Lows[$i] -lt $Lows[$i + 1] -and $Lows[$i] -lt $Lows[$i + 2]) {
            $fractalType = "BULLISH"
            $fractalIndex = $i
            $points = 15
            break
        }
    }

    return [PSCustomObject]@{
        fractal_type = $fractalType
        fractal_index = $fractalIndex
        points = $points
    }
}

# ============================================================================
# HELPER: STRUCTURAL BREAK (CHoCH) DETECTION
# ============================================================================

function Get-StructuralBreak {
    <#
    .SYNOPSIS
        Detect Change of Character (CHoCH) - structural break of swing

        LONG: New swing low below prior support
        SHORT: New swing high above prior resistance

    .PARAMETER Lows
        Array of low prices

    .PARAMETER Highs
        Array of high prices

    .PARAMETER SetupType
        "LONG" or "SHORT"

    .OUTPUTS
        PSCustomObject with has_choch (bool), break_level (double), and points
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Lows,

        [Parameter(Mandatory=$true)]
        [double[]]$Highs,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$SetupType
    )

    $hasChoch = $false
    $breakLevel = 0.0
    $points = 0

    if ($Lows.Length -lt 4) {
        return [PSCustomObject]@{
            has_choch = $false
            break_level = 0.0
            points = 0
        }
    }

    $n = $Lows.Length

    if ($SetupType -eq "LONG") {
        # LONG CHoCH: Find prior swing low, check if current low breaks below it
        # Simplified: Check if most recent 2 lows are lower than previous 2
        $recentLowAvg = ($Lows[$n - 1] + $Lows[$n - 2]) / 2.0
        $priorLowAvg = ($Lows[$n - 3] + $Lows[$n - 4]) / 2.0

        if ($recentLowAvg -lt $priorLowAvg) {
            $hasChoch = $true
            $breakLevel = $recentLowAvg
            $points = 15
        }
    } else {
        # SHORT CHoCH: Find prior swing high, check if current high breaks above it
        $recentHighAvg = ($Highs[$n - 1] + $Highs[$n - 2]) / 2.0
        $priorHighAvg = ($Highs[$n - 3] + $Highs[$n - 4]) / 2.0

        if ($recentHighAvg -gt $priorHighAvg) {
            $hasChoch = $true
            $breakLevel = $recentHighAvg
            $points = 15
        }
    }

    return [PSCustomObject]@{
        has_choch = $hasChoch
        break_level = $breakLevel
        points = $points
    }
}

# ============================================================================
# HELPER: VOLUME PROFILE DETECTION
# ============================================================================

function Get-VolumeProfile {
    <#
    .SYNOPSIS
        Detect volume profile - identify high-volume price levels

    .PARAMETER Candles
        Array of candle objects with close and volume properties

    .PARAMETER Bins
        Number of price bins for profile (default 20)

    .OUTPUTS
        PSCustomObject with profile (hashtable), peak_volume_level (double)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$Candles,

        [Parameter(Mandatory=$false)]
        [int]$Bins = $script:VOLUME_PROFILE_BINS
    )

    if ($Candles.Length -eq 0) {
        return [PSCustomObject]@{
            profile = @{}
            peak_volume_level = 0.0
            volume_at_price = @{}
        }
    }

    # Find price range
    $closes = @($Candles | ForEach-Object { [double]$_.close })
    $volumes = @($Candles | ForEach-Object { [double]$_.volume })

    $minPrice = $closes | Measure-Object -Minimum | Select-Object -ExpandProperty Minimum
    $maxPrice = $closes | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    if ($minPrice -eq $maxPrice) {
        return [PSCustomObject]@{
            profile = @{}
            peak_volume_level = $minPrice
            volume_at_price = @{}
        }
    }

    # Create bins
    $binSize = ($maxPrice - $minPrice) / $Bins
    $profile = @{}
    $volumeAtPrice = @{}

    for ($i = 0; $i -lt $Candles.Length; $i++) {
        $close = $closes[$i]
        $volume = $volumes[$i]

        # Find bin index
        $binIndex = [Math]::Floor(($close - $minPrice) / $binSize)
        if ($binIndex -ge $Bins) { $binIndex = $Bins - 1 }

        $binKey = "bin_$binIndex"
        if (-not $profile.ContainsKey($binKey)) {
            $profile[$binKey] = 0.0
            $volumeAtPrice[$binKey] = @{
                bin_index = $binIndex
                price_level = $minPrice + ($binIndex * $binSize)
                volume = 0.0
            }
        }

        $profile[$binKey] += $volume
        $volumeAtPrice[$binKey].volume = $profile[$binKey]
    }

    # Find peak volume level
    $peakVolume = 0.0
    $peakLevel = $minPrice

    foreach ($key in $profile.Keys) {
        if ($profile[$key] -gt $peakVolume) {
            $peakVolume = $profile[$key]
            $peakLevel = $volumeAtPrice[$key].price_level
        }
    }

    return [PSCustomObject]@{
        profile = $profile
        peak_volume_level = $peakLevel
        volume_at_price = $volumeAtPrice
        total_volume = ($volumes | Measure-Object -Sum).Sum
    }
}

# ============================================================================
# MAIN: CALCULATE CONFLUENCE SCORE WITH BREAKDOWN
# ============================================================================

function Get-ConfluenceScoreEnhanced {
    <#
    .SYNOPSIS
        Calculate enhanced confluence score (0-100) with detailed breakdown

    .PARAMETER Candles
        Array of candle objects with OHLCV

    .PARAMETER SetupType
        "LONG" or "SHORT"

    .PARAMETER TrendlineStartPrice
        Action line (trendline) start price

    .PARAMETER TrendlineTouches
        Number of trendline touches

    .OUTPUTS
        PSCustomObject with total_score, breakdown (hashtable), and signals_fired (array)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$Candles,

        [Parameter(Mandatory=$true)]
        [ValidateSet("LONG", "SHORT")]
        [string]$SetupType,

        [Parameter(Mandatory=$true)]
        [double]$TrendlineStartPrice,

        [Parameter(Mandatory=$false)]
        [int]$TrendlineTouches = 2
    )

    if ($Candles.Length -lt 5) {
        return [PSCustomObject]@{
            total_score = 0
            breakdown = @{}
            signals_fired = @()
            details = "Insufficient candle data"
        }
    }

    # Extract OHLCV arrays
    $opens = @($Candles | ForEach-Object { [double]$_.open })
    $highs = @($Candles | ForEach-Object { [double]$_.high })
    $lows = @($Candles | ForEach-Object { [double]$_.low })
    $closes = @($Candles | ForEach-Object { [double]$_.close })
    $volumes = @($Candles | ForEach-Object { [double]$_.volume })

    # Calculate RSI (14-period)
    $rsi = Get-RSI -Closes $closes -Period 14

    $breakdown = @{}
    $signalsFired = @()
    $totalScore = 50  # baseline

    # Signal 1: Volume Climax
    $volumeClimax = Get-VolumeClimax -Volumes $volumes -Threshold $script:VOLUME_CLIMAX_THRESHOLD
    if ($volumeClimax.is_climax) {
        $breakdown["volume_climax"] = $script:CONFLUENCE_WEIGHTS["volume_climax"]
        $totalScore += $script:CONFLUENCE_WEIGHTS["volume_climax"]
        $signalsFired += @("VOLUME_CLIMAX (ratio=$([Math]::Round($volumeClimax.ratio, 2)))")
    } else {
        $breakdown["volume_climax"] = 0
    }

    # Signal 2: RSI Extreme
    $rsiExtreme = Get-RSIExtreme -RSI $rsi -SetupType $SetupType
    if ($rsiExtreme.is_extreme) {
        $breakdown["rsi_extreme"] = $rsiExtreme.points
        $totalScore += $rsiExtreme.points
        $signalsFired += @("RSI_EXTREME ($($rsiExtreme.extreme_type)=$($rsiExtreme.rsi))")
    } else {
        $breakdown["rsi_extreme"] = 0
    }

    # Signal 3: Fractal Pattern
    $fractal = Get-FractalPattern -Opens $opens -Highs $highs -Lows $lows -Closes $closes
    if ($fractal.fractal_type -ne "") {
        $breakdown["fractal_pattern"] = $fractal.points
        $totalScore += $fractal.points
        $signalsFired += @("FRACTAL_$($fractal.fractal_type)")
    } else {
        $breakdown["fractal_pattern"] = 0
    }

    # Signal 4: CHoCH (Change of Character)
    $choch = Get-StructuralBreak -Lows $lows -Highs $highs -SetupType $SetupType
    if ($choch.has_choch) {
        $breakdown["choch_structure"] = $choch.points
        $totalScore += $choch.points
        $signalsFired += @("CHOCH (level=$([Math]::Round($choch.break_level, 8)))")
    } else {
        $breakdown["choch_structure"] = 0
    }

    # Signal 5: Volume Profile (at trendline)
    $volumeProfile = Get-VolumeProfile -Candles $Candles -Bins $script:VOLUME_PROFILE_BINS
    $distanceToPeak = [Math]::Abs($closes[-1] - $volumeProfile.peak_volume_level)
    $priceRange = ($highs | Measure-Object -Maximum).Maximum - ($lows | Measure-Object -Minimum).Minimum

    if ($priceRange -gt 0 -and $distanceToPeak -lt ($priceRange * 0.1)) {
        # Price is within 10% of peak volume level
        $breakdown["volume_profile"] = $script:CONFLUENCE_WEIGHTS["volume_profile"]
        $totalScore += $script:CONFLUENCE_WEIGHTS["volume_profile"]
        $signalsFired += @("VOLUME_PROFILE (peak=$([Math]::Round($volumeProfile.peak_volume_level, 8)))")
    } else {
        $breakdown["volume_profile"] = 0
    }

    # Trendline touches bonus
    $touchBonus = [Math]::Min(10, ($TrendlineTouches - 2) * 5)
    if ($touchBonus -gt 0) {
        $breakdown["trendline_touches"] = $touchBonus
        $totalScore += $touchBonus
    } else {
        $breakdown["trendline_touches"] = 0
    }

    # Cap at 100
    $totalScore = [Math]::Max(0, [Math]::Min(100, $totalScore))

    return [PSCustomObject]@{
        total_score = $totalScore
        breakdown = $breakdown
        signals_fired = $signalsFired
        rsi = [Math]::Round($rsi, 1)
        volume_climax_ratio = [Math]::Round($volumeClimax.ratio, 2)
        peak_volume_level = [Math]::Round($volumeProfile.peak_volume_level, 8)
        trendline_touches = $TrendlineTouches
    }
}

# ============================================================================
# HELPER: CALCULATE RSI (copied from lib_tori_trades_scanner.ps1)
# ============================================================================

function Get-RSI {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double[]]$Closes,

        [int]$Period = 14
    )

    if ($Closes.Length -lt ($Period + 1)) { return 50.0 }

    $gains = 0
    $losses = 0
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
# EXPORT
# ============================================================================

# All functions are automatically available after dot-sourcing
