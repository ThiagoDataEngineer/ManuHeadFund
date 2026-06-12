$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
. (Join-Path $root "agents\lib_regime_position_sizing.ps1")

Describe "Get-RegimePositionSize" {
    It "BULL_STRONG: full 1x position" {
        $capital = 2700.85
        $regime = "BULL_STRONG"
        $basePercent = 0.01  # 1%

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        $expected = $capital * 0.01  # No adjustment
        $size | Should Be $expected
    }

    It "BULL_WEAK: full 1x position" {
        $capital = 2700.85
        $regime = "BULL_WEAK"
        $basePercent = 0.01

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        $expected = $capital * 0.01
        $size | Should Be $expected
    }

    It "BEAR_WEAK: full 1x position (still safe)" {
        $capital = 2700.85
        $regime = "BEAR_WEAK"
        $basePercent = 0.01

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        $expected = $capital * 0.01
        $size | Should Be $expected
    }

    It "BEAR_STRONG: 0.5x position (50% reduction)" {
        $capital = 2700.85
        $regime = "BEAR_STRONG"
        $basePercent = 0.01

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        $expected = $capital * 0.01 * 0.5  # 50% adjustment
        $size | Should Be $expected
    }

    It "Unknown regime: returns base position (safety default)" {
        $capital = 2700.85
        $regime = "UNKNOWN_REGIME"
        $basePercent = 0.01

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        $expected = $capital * 0.01
        $size | Should Be $expected
    }

    It "BEAR_STRONG with custom base percent: applies regime multiplier" {
        $capital = 5000
        $regime = "BEAR_STRONG"
        $basePercent = 0.02

        $size = Get-RegimePositionSize -Capital $capital -Regime $regime -BasePercentage $basePercent

        # Expected: 5000 * 0.02 * 0.5
        $expected = 50
        $size | Should Be $expected
    }

    It "Regime multipliers hash available" {
        $mults = Get-RegimeMultipliers

        $mults.BULL_STRONG | Should Be 1.0
        $mults.BULL_WEAK | Should Be 1.0
        $mults.BEAR_WEAK | Should Be 1.0
        $mults.BEAR_STRONG | Should Be 0.5
    }
}

Describe "Test-RegimePositionValid" {
    It "BULL_STRONG with 1x position: valid" {
        $position = @{ size = 27; regime = "BULL_STRONG"; capital = 2700 }

        $valid = Test-RegimePositionValid -Position $position

        $valid | Should Be $true
    }

    It "BEAR_STRONG with 2x position: INVALID (exceeds regime cap)" {
        $position = @{ size = 54; regime = "BEAR_STRONG"; capital = 2700 }

        $valid = Test-RegimePositionValid -Position $position

        $valid | Should Be $false
    }

    It "BEAR_STRONG with 0.5x position: valid" {
        $position = @{ size = 13.5; regime = "BEAR_STRONG"; capital = 2700 }

        $valid = Test-RegimePositionValid -Position $position

        $valid | Should Be $true
    }

    It "Position exactly at regime limit: valid" {
        $position = @{ size = 27; regime = "BEAR_WEAK"; capital = 2700 }

        $valid = Test-RegimePositionValid -Position $position

        $valid | Should Be $true
    }

    It "Position exceeds 1% capital hard cap: INVALID" {
        $position = @{ size = 100; regime = "BULL_STRONG"; capital = 2700 }

        $valid = Test-RegimePositionValid -Position $position

        $valid | Should Be $false
    }
}

Describe "Adjust-PositionForRegime" {
    It "Downsizing BULL_STRONG to BEAR_STRONG: reduces by 50%" {
        $position = @{ size = 27; regime = "BULL_STRONG"; capital = 2700 }

        $adjusted = Adjust-PositionForRegime -Position $position -NewRegime "BEAR_STRONG"

        $adjusted.size | Should Be 13.5
        $adjusted.regime | Should Be "BEAR_STRONG"
        $adjusted.reason | Should Match "regime"
    }

    It "Upgrading BEAR_STRONG to BULL_STRONG: increases 2x" {
        $position = @{ size = 13.5; regime = "BEAR_STRONG"; capital = 2700 }

        $adjusted = Adjust-PositionForRegime -Position $position -NewRegime "BULL_STRONG"

        $adjusted.size | Should Be 27
        $adjusted.regime | Should Be "BULL_STRONG"
    }

    It "Same regime: no adjustment" {
        $position = @{ size = 27; regime = "BULL_STRONG"; capital = 2700 }

        $adjusted = Adjust-PositionForRegime -Position $position -NewRegime "BULL_STRONG"

        $adjusted.size | Should Be 27
        $adjusted.adjusted | Should Be $false
    }

    It "Adjustment never exceeds 1% capital hard cap" {
        $position = @{ size = 27; regime = "BULL_WEAK"; capital = 2700 }

        $adjusted = Adjust-PositionForRegime -Position $position -NewRegime "BULL_STRONG"

        # Max is still 1% = 27
        ($adjusted.size -le 27) | Should Be $true
    }
}

Describe "Get-RegimePositionLabel" {
    It "BULL_STRONG 1x: returns label" {
        $label = Get-RegimePositionLabel -Regime "BULL_STRONG" -Multiplier 1.0

        $label | Should Match "BULL_STRONG"
        $label | Should Match "1(\.0)?x"
    }

    It "BEAR_STRONG 0.5x: returns label with warning" {
        $label = Get-RegimePositionLabel -Regime "BEAR_STRONG" -Multiplier 0.5

        $label | Should Match "BEAR_STRONG"
        $label | Should Match "0\.5x"
        $label | Should Match "CAUTION|reduced|risk"  # Some warning
    }

    It "All regimes have descriptive labels" {
        $regimes = @("BULL_STRONG", "BULL_WEAK", "BEAR_WEAK", "BEAR_STRONG")

        foreach ($regime in $regimes) {
            $label = Get-RegimePositionLabel -Regime $regime -Multiplier 1.0

            $label | Should Not BeNullOrEmpty
            $label | Should Match $regime
        }
    }
}

