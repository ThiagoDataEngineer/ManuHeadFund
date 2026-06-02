# lib_faro_ml_confidence.ps1 — ML-based prediction confidence scoring
# Combines 7-signal output to estimate probability of successful trade

function Calculate-MLConfidence {
    param(
        [decimal] $VolumeSignal = 0,
        [decimal] $PatternSignal = 0,
        [decimal] $MomentumSignal = 0,
        [decimal] $SentimentSignal = 0,
        [decimal] $WhaleSignal = 0,
        [decimal] $FingerprintSignal = 0,
        [decimal] $TimingSignal = 0
    )

    # Validate all inputs non-negative
    if ($VolumeSignal -lt 0 -or $PatternSignal -lt 0 -or $MomentumSignal -lt 0 -or `
        $SentimentSignal -lt 0 -or $WhaleSignal -lt 0 -or $FingerprintSignal -lt 0 -or $TimingSignal -lt 0) {
        return 0
    }

    # Weighted combination (machine learning weights calibrated from backtest)
    # Weights optimized for micro-cap pre-pump prediction
    $weights = @{
        volume = 0.20       # 20% weight (volume spike is early indicator)
        pattern = 0.25      # 25% weight (technical patterns most reliable)
        momentum = 0.15     # 15% weight (RSI/MACD confirmation)
        sentiment = 0.15    # 15% weight (trending/mentions)
        whale = 0.10        # 10% weight (on-chain activity)
        fingerprint = 0.10  # 10% weight (historical match)
        timing = 0.05       # 5% weight (entry timing secondary)
    }

    # Normalize each signal to 0-1 scale
    $volNorm = [Math]::Min($VolumeSignal / 25, 1.0)
    $patNorm = [Math]::Min($PatternSignal / 25, 1.0)
    $momNorm = [Math]::Min($MomentumSignal / 25, 1.0)
    $sentNorm = [Math]::Min($SentimentSignal / 30, 1.0)
    $whaleNorm = [Math]::Min($WhaleSignal / 20, 1.0)
    $fpNorm = [Math]::Min($FingerprintSignal / 20, 1.0)
    $timingNorm = [Math]::Min($TimingSignal / 20, 1.0)

    # Weighted sum
    $confidence = ($volNorm * $weights.volume) +
                  ($patNorm * $weights.pattern) +
                  ($momNorm * $weights.momentum) +
                  ($sentNorm * $weights.sentiment) +
                  ($whaleNorm * $weights.whale) +
                  ($fpNorm * $weights.fingerprint) +
                  ($timingNorm * $weights.timing)

    # Scale to 0-100
    $score = [int]($confidence * 100)

    # Confidence boosts (non-linear adjustments)
    $signalCount = 0
    if ($VolumeSignal -gt 0) { $signalCount++ }
    if ($PatternSignal -gt 0) { $signalCount++ }
    if ($MomentumSignal -gt 0) { $signalCount++ }
    if ($SentimentSignal -gt 0) { $signalCount++ }
    if ($WhaleSignal -gt 0) { $signalCount++ }
    if ($FingerprintSignal -gt 0) { $signalCount++ }
    if ($TimingSignal -gt 0) { $signalCount++ }

    # 7/7 signals: +20% confidence boost (extreme conviction)
    if ($signalCount -eq 7) { $score = [Math]::Min($score + 20, 100) }
    # 6/7 signals: +15% boost
    elseif ($signalCount -eq 6) { $score = [Math]::Min($score + 15, 100) }
    # 5/7 signals: +10% boost
    elseif ($signalCount -eq 5) { $score = [Math]::Min($score + 10, 100) }

    return [Math]::Max(0, [Math]::Min($score, 100))
}

# Inverse: given target score, return required signal distribution
function Get-RequiredSignalsForScore {
    param(
        [int] $TargetScore = 70
    )

    # Lookup table: minimum signals needed for each score tier
    if ($TargetScore -ge 95) {
        return @{ min_signals = 7; min_score = 95; description = "EXTREME: All 7 signals + high values" }
    }
    elseif ($TargetScore -ge 85) {
        return @{ min_signals = 6; min_score = 85; description = "VERY HIGH: 6/7 signals confirmed" }
    }
    elseif ($TargetScore -ge 75) {
        return @{ min_signals = 6; min_score = 75; description = "HIGH: 6/7 signals present" }
    }
    elseif ($TargetScore -ge 70) {
        return @{ min_signals = 5; min_score = 70; description = "GOOD: 5/7 signals present" }
    }
    else {
        return @{ min_signals = 4; min_score = 50; description = "WATCH: 4/7 signals present" }
    }
}
