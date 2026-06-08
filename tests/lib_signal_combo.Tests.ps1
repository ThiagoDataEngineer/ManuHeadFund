$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_signal_combo.ps1")

Describe "Combine-VolClimaxEngulfing" {
    It "Vol_Climax alone: returns vol_climax signal" {
        $signal = @{
            type = "vol_climax"
            confidence = 0.37
            price = 100
            entry = 101
            stop = 99
            tp = 102
        }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $signal -EngulfingSignal $null

        $result.type | Should Be "vol_climax"
        $result.confidence | Should Be 0.37
        $result.combo | Should Be $false
    }

    It "Engulfing alone: returns null (requires vol_climax)" {
        $signal = @{
            type = "engulfing"
            confidence = 0.32
        }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $null -EngulfingSignal $signal

        $result | Should Be $null
    }

    It "Both signals present: returns COMBO (synergy boost)" {
        $vc = @{
            type = "vol_climax"
            confidence = 0.37
            price = 100
            entry = 101
            stop = 99
            tp = 102
        }
        $eng = @{
            type = "engulfing"
            confidence = 0.32
            direction = "bullish"
        }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $vc -EngulfingSignal $eng

        $result.type | Should Be "combo"
        $result.combo | Should Be $true
        $result.confidence | Should Be 0.42
        $result.primary | Should Be "vol_climax"
        $result.filter | Should Be "engulfing"
    }

    It "Vol_Climax too low confidence: skipped" {
        $vc = @{
            type = "vol_climax"
            confidence = 0.20  # Below threshold
        }
        $eng = @{
            type = "engulfing"
            confidence = 0.32
        }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $vc -EngulfingSignal $eng

        $result | Should Be $null
    }

    It "Engulfing contradicts vol_climax direction: rejected" {
        $vc = @{
            type = "vol_climax"
            confidence = 0.37
            direction = "bullish"
        }
        $eng = @{
            type = "engulfing"
            confidence = 0.32
            direction = "bearish"  # Opposite!
        }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $vc -EngulfingSignal $eng -CheckDirection $true

        $result | Should Be $null
    }

    It "Combo confidence = 0.42 (validated synergy)" {
        $vc = @{ type = "vol_climax"; confidence = 0.37 }
        $eng = @{ type = "engulfing"; confidence = 0.32 }

        $result = Combine-VolClimaxEngulfing -VolClimaxSignal $vc -EngulfingSignal $eng

        # Synergy: higher than both individual signals
        $result.confidence | Should Be 0.42
        $result.confidence -gt 0.37 | Should Be $true
        $result.confidence -gt 0.32 | Should Be $true
    }
}

Describe "Evaluate-ComboSignalQuality" {
    It "Combo with 71% expected win rate: HIGH quality" {
        $combo = @{
            type = "combo"
            confidence = 0.42
            regime = "BULL_STRONG"
        }

        $quality = Evaluate-ComboSignalQuality -Signal $combo

        $quality.rating | Should Be "HIGH"
        $quality.expected_wr | Should Be 0.714
    }

    It "Combo with 62% expected win rate (BEAR_WEAK): MEDIUM quality" {
        $combo = @{
            type = "combo"
            confidence = 0.42
            regime = "BEAR_WEAK"
        }

        $quality = Evaluate-ComboSignalQuality -Signal $combo

        $quality.rating | Should Be "MEDIUM"
        $quality.expected_wr | Should Be 0.626
    }

    It "Vol_Climax solo with 56% in BEAR_WEAK: CAUTION" {
        $vc = @{
            type = "vol_climax"
            confidence = 0.37
            regime = "BEAR_WEAK"
        }

        $quality = Evaluate-ComboSignalQuality -Signal $vc

        $quality.rating | Should Be "CAUTION"
        $quality.expected_wr | Should Be 0.56
        $quality.recommendation | Should Match "combo"
    }

    It "Returns regime-specific expected win rates" {
        $regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")

        foreach ($regime in $regimes) {
            $signal = @{ type = "combo"; regime = $regime }
            $quality = Evaluate-ComboSignalQuality -Signal $signal

            # All combos should have 60%+ expected WR
            ($quality.expected_wr -ge 0.60) | Should Be $true
        }
    }
}

Describe "Get-SignalWeight" {
    It "Combo signal: weight 1.0 (max)" {
        $signal = @{ type = "combo"; confidence = 0.42 }

        $weight = Get-SignalWeight -Signal $signal

        $weight | Should Be 1.0
    }

    It "Vol_Climax signal: weight 0.85" {
        $signal = @{ type = "vol_climax"; confidence = 0.37 }

        $weight = Get-SignalWeight -Signal $signal

        $weight | Should Be 0.85
    }

    It "Low confidence signal in BEAR_STRONG: weight reduced" {
        $signal = @{ type = "vol_climax"; confidence = 0.25; regime = "BEAR_STRONG" }

        $weight = Get-SignalWeight -Signal $signal -ApplyRegimeAdjustment

        # BEAR_STRONG reduces weight: 0.85 * 0.8 = 0.68
        $weight | Should BeLessThan 0.85
    }

    It "Weight scales with regime stress" {
        $bullSignal = @{ type = "combo"; regime = "BULL_STRONG" }
        $bearSignal = @{ type = "combo"; regime = "BEAR_STRONG" }

        $bullWeight = Get-SignalWeight -Signal $bullSignal -ApplyRegimeAdjustment
        $bearWeight = Get-SignalWeight -Signal $bearSignal -ApplyRegimeAdjustment

        # Bull should have higher weight (more reliable)
        ($bullWeight -gt $bearWeight) | Should Be $true
    }
}

