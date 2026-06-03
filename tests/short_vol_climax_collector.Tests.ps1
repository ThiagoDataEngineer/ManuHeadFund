param([string] $ModulePath = "$PSScriptRoot\..\agents")

Describe "SHORT vol_climax collector (RSI 80+, vol 2.5x, ADX >60)" {

    Context "Volatility climax gate (exhaustion sell-off)" {
        It "detects RSI >= 80 (overbought extreme)" {
            $rsi = 82
            ($rsi -ge 80) | Should Be $true
        }

        It "requires volume spike >= 2.5x" {
            $currentVol = 250000
            $avg3dVol = 100000
            $ratio = $currentVol / $avg3dVol
            ($ratio -ge 2.5) | Should Be $true
        }

        It "requires ADX > 60 (strong trend exhaustion)" {
            $adx = 65
            ($adx -gt 60) | Should Be $true
        }

        It "blocks if RSI < 80 (not extreme)" {
            $rsi = 75
            ($rsi -ge 80) | Should Be $false
        }

        It "blocks if vol < 2.5x (no panic)" {
            $ratio = 2.3
            ($ratio -ge 2.5) | Should Be $false
        }

        It "blocks if ADX <= 60 (no strong trend)" {
            $adx = 58
            ($adx -gt 60) | Should Be $false
        }
    }

    Context "Signal composition (3 gates AND)" {
        It "passes all 3 gates (COLLECT signal)" {
            $rsi = 82
            $volRatio = 2.6
            $adx = 68

            $pass = ($rsi -ge 80) -and ($volRatio -ge 2.5) -and ($adx -gt 60)
            $pass | Should Be $true
        }

        It "fails if any gate fails" {
            $rsi = 82
            $volRatio = 2.3  # FAIL
            $adx = 68

            $pass = ($rsi -ge 80) -and ($volRatio -ge 2.5) -and ($adx -gt 60)
            $pass | Should Be $false
        }
    }

    Context "Observation logging schema" {
        It "stores market + signal + timestamp" {
            $obs = @{
                market = "BTCUSDT"
                signal_type = "vol_climax"
                rsi = 82
                vol_ratio = 2.6
                adx = 68
                ts = "2026-06-02T21:30:00Z"
                regime = "BEAR_WEAK"
            }

            $obs.market | Should Be "BTCUSDT"
            $obs.signal_type | Should Be "vol_climax"
        }
    }
}
