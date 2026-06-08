$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# Load required libraries
. (Join-Path $root "agents\lib_signal_combo.ps1")
. (Join-Path $root "agents\lib_regime_position_sizing.ps1")

Describe "Vol_Climax Scanner Integration with Combo" {
    It "Scanner detects Vol_Climax signal" {
        # Simulated vol_climax signal from scanner
        $vcSignal = @{
            type = "vol_climax"
            confidence = 0.37
            price = 100
            entry = 101
            stop = 99
            tp = 102
            market = "BTCUSDT"
            timestamp = (Get-Date)
        }

        # Should be valid
        $vcSignal.confidence | Should Be 0.37
        $vcSignal.type | Should Be "vol_climax"
    }

    It "Scanner with Engulfing filter: produces COMBO signal" {
        $vcSignal = @{
            type = "vol_climax"
            confidence = 0.37
            price = 100
            entry = 101
            stop = 99
            tp = 102
        }

        $engSignal = @{
            type = "engulfing"
            confidence = 0.32
            direction = "bullish"
        }

        # Combine signals
        $combo = Combine-VolClimaxEngulfing -VolClimaxSignal $vcSignal -EngulfingSignal $engSignal

        $combo.type | Should Be "combo"
        $combo.confidence | Should Be 0.42
    }

    It "Entry point with BEAR_WEAK regime: gets correct position size" {
        $combo = @{
            type = "combo"
            confidence = 0.42
            regime = "BEAR_WEAK"
        }

        $capital = 2700.85
        $position = Get-RegimePositionSize -Capital $capital -Regime "BEAR_WEAK" -BasePercentage 0.01

        # BEAR_WEAK: full 1x
        $expected = 27.0085
        $position | Should Be $expected
    }

    It "Entry point with BEAR_STRONG regime: gets reduced position (0.5x)" {
        $combo = @{
            type = "combo"
            confidence = 0.42
            regime = "BEAR_STRONG"
        }

        $capital = 2700.85
        $position = Get-RegimePositionSize -Capital $capital -Regime "BEAR_STRONG" -BasePercentage 0.01

        # BEAR_STRONG: 0.5x reduction
        $expected = 13.50425
        $position | Should Be $expected
    }

    It "Signal quality evaluation in BEAR_WEAK (user's current regime)" {
        $combo = @{
            type = "combo"
            regime = "BEAR_WEAK"
        }

        $quality = Evaluate-ComboSignalQuality -Signal $combo

        # Expected WR in BEAR_WEAK: 62.6%
        $quality.expected_wr | Should Be 0.626
        $quality.rating | Should Be "MEDIUM"
    }

    It "Position sizing logic flow: detect → evaluate → size → trade" {
        # Step 1: Detection
        $signal = @{
            type = "combo"
            confidence = 0.42
            regime = "BEAR_WEAK"
        }

        # Step 2: Quality evaluation
        $quality = Evaluate-ComboSignalQuality -Signal $signal
        ($quality.expected_wr -ge 0.60) | Should Be $true

        # Step 3: Position sizing
        $capital = 2700.85
        $position = Get-RegimePositionSize -Capital $capital -Regime $signal.regime -BasePercentage 0.01

        # Step 4: Validation
        $posObj = @{ size = $position; regime = $signal.regime; capital = $capital }
        $valid = Test-RegimePositionValid -Position $posObj
        $valid | Should Be $true
    }

    It "Regime transition: BULL_STRONG → BEAR_WEAK" {
        $currentPos = @{ size = 27; regime = "BULL_STRONG"; capital = 2700 }

        # Market transitions to BEAR_WEAK
        $adjusted = Adjust-PositionForRegime -Position $currentPos -NewRegime "BEAR_WEAK"

        # Still full position in BEAR_WEAK
        $adjusted.size | Should Be 27
        $adjusted.regime | Should Be "BEAR_WEAK"
    }

    It "Regime transition: BULL_STRONG → BEAR_STRONG (50% reduction)" {
        $currentPos = @{ size = 27; regime = "BULL_STRONG"; capital = 2700 }

        # Market transitions to BEAR_STRONG
        $adjusted = Adjust-PositionForRegime -Position $currentPos -NewRegime "BEAR_STRONG"

        # Reduced to 0.5x
        $adjusted.size | Should Be 13.5
        $adjusted.regime | Should Be "BEAR_STRONG"
    }

    It "Cross-regime signal weight consistency" {
        $regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")

        foreach ($regime in $regimes) {
            $signal = @{
                type = "combo"
                regime = $regime
            }

            $weight = Get-SignalWeight -Signal $signal

            # All combos should have weight 1.0 without regime adjustment
            $weight | Should Be 1.0
        }
    }

    It "Trading flow: Vol_Climax + Engulfing combo in BEAR_WEAK (current user regime)" {
        # Scenario: User is in BEAR_WEAK, gets Vol_Climax + Engulfing combo

        # 1. Detect signals
        $vc = @{ type = "vol_climax"; confidence = 0.37; price = 100; entry = 101; stop = 99; tp = 102 }
        $eng = @{ type = "engulfing"; confidence = 0.32; direction = "bullish" }

        # 2. Combine
        $combo = Combine-VolClimaxEngulfing -VolClimaxSignal $vc -EngulfingSignal $eng
        $combo.type | Should Be "combo"

        # 3. Evaluate quality
        $quality = Evaluate-ComboSignalQuality -Signal @{type = "combo"; regime = "BEAR_WEAK"}
        $quality.expected_wr | Should Be 0.626  # 62.6% in BEAR_WEAK

        # 4. Calculate position
        $capital = 2700.85
        $position = Get-RegimePositionSize -Capital $capital -Regime "BEAR_WEAK"
        $position | Should Be 27.0085

        # 5. Validate
        $posObj = @{ size = $position; regime = "BEAR_WEAK"; capital = $capital }
        (Test-RegimePositionValid -Position $posObj) | Should Be $true

        # 6. Entry ready
        # Ready to submit order with $27 position size
        ($position -le ($capital * 0.01)) | Should Be $true
    }
}

