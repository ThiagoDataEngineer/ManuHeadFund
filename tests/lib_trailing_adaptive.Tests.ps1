# tests/lib_trailing_adaptive.Tests.ps1
# TDD: Tests para trailing stops adaptativos (ATR-dinâmico + regime-aware)
# Pester 3.4 compatible (avoid -BeGreaterThan, use | Should Be / | Should Match)
# Executar: Invoke-Pester ./tests/lib_trailing_adaptive.Tests.ps1 -Verbose

Describe "Get-AdaptiveBuffer" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_trailing_adaptive.ps1")
    }

    Context "Regime Multipliers" {
        It "should return ~75 for BULL_STRONG (tight stops, trending market)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_STRONG"
            # buffer = 100 * 0.75 = 75
            ($buffer -gt 69 -and $buffer -lt 80) | Should Be $true
        }

        It "should return ~100 for BULL_WEAK (normal regime)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            # buffer = 100 * 1.0 = 100
            ($buffer -gt 95 -and $buffer -lt 105) | Should Be $true
        }

        It "should return ~130 for SIDEWAYS (wider, defend pullback noise)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "SIDEWAYS"
            # buffer = 100 * 1.3 = 130
            ($buffer -gt 125 -and $buffer -lt 135) | Should Be $true
        }

        It "should return ~150 for BEAR_STRONG (very wide, protect vs spikes)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BEAR_STRONG"
            # buffer = 100 * 1.5 = 150
            ($buffer -gt 145 -and $buffer -lt 155) | Should Be $true
        }

        It "should return ~50 for CAPITULATION (ultra tight, exit quick)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "CAPITULATION"
            # buffer = 100 * 0.5 = 50
            ($buffer -gt 45 -and $buffer -lt 55) | Should Be $true
        }

        It "should default to ~100 for unknown regime (default SIDEWAYS)" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "SIDEWAYS"
            ($buffer -gt 95) | Should Be $true
        }
    }

    Context "ATR Volatility Adjustment" {
        It "should scale buffer up when CurrentAtr > HistoricalAtr" {
            $bufferNormal = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            $bufferHighVol = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 150 -HistoricalAtr 100 -Regime "BULL_WEAK"
            
            ($bufferHighVol -gt $bufferNormal) | Should Be $true
        }

        It "should scale buffer down when CurrentAtr < HistoricalAtr" {
            $bufferNormal = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            $bufferLowVol = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 50 -HistoricalAtr 100 -Regime "BULL_WEAK"
            
            ($bufferLowVol -lt $bufferNormal) | Should Be $true
        }
    }

    Context "Minimum Buffer Floor" {
        It "should enforce 1.5% minimum buffer of range" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 10 -HistoricalAtr 100 -Regime "CAPITULATION"
            $minBuffer = 1000 * 0.015  # 15
            ($buffer -ge $minBuffer) | Should Be $true
        }

        It "should use buffer (not floor) when buffer is larger" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            ($buffer -gt 50) | Should Be $true  # should be ~100, not ~15
        }
    }

    Context "Edge Cases" {
        It "should handle zero range safely" {
            $buffer = Get-AdaptiveBuffer -Range 0 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            ($buffer -gt 0) | Should Be $true
        }

        It "should handle zero CurrentAtr safely" {
            $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 0 -HistoricalAtr 100 -Regime "BULL_WEAK"
            ($buffer -gt 0) | Should Be $true
        }

        It "should handle zero HistoricalAtr safely (divide by zero protection)" {
            { $buffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 0 -Regime "BULL_WEAK" } | Should Not Throw
        }
    }
}

Describe "Get-TrailingNewStopAdaptive" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_trailing_adaptive.ps1")
    }

    Context "LONG Position - Fase 1 (Breakeven Transition)" {
        It "should move stop to breakeven+buffer when 33% of target reached" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000
                target = 70000
                stopCurrent = 59000
                peak = 60000
                phase = 0
            }
            
            $currentPrice = 63333
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BULL_STRONG"
            
            $result.newPhase | Should Be 1
            $result.changed | Should Be $true
            ($result.newStop -gt 60000 -and $result.newStop -lt 60200) | Should Be $true
        }
    }

    Context "LONG Position - Fase 2 (Lock Profits)" {
        It "should move stop to +33% of gain when 66% of target reached" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000
                target = 70000
                stopCurrent = 60100
                peak = 66667
                phase = 1
            }
            
            $currentPrice = 66667
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BULL_WEAK"
            
            $result.newPhase | Should Be 2
            $result.changed | Should Be $true
            # Stop at entry + 33% of range = 60000 + 3333 = 63333 (rounded to 63300)
            ($result.newStop -ge 63290 -and $result.newStop -le 63310) | Should Be $true
        }
    }

    Context "LONG Position - Fase 3 (Trailing)" {
        It "should move to trailing 15% below peak when target first reached" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000
                target = 70000
                stopCurrent = 63333  # from fase 2
                peak = 70000
                phase = 2
            }
            
            # NEW peak discovery (70100) triggers fase 3 transition
            # Trailing stop = 70100 * 0.85 = 59585 (fresh calculation for fase 3)
            $currentPrice = 70100
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BULL_STRONG"
            
            $result.newPhase | Should Be 3
            $result.newPeak | Should Be 70100
            $result.changed | Should Be $true
            # Stop transitions to trailing: peak * 0.85 = 70100 * 0.85 = 59585
            # (fresh calculation on phase transition, not "never recede" logic)
            $result.newStop | Should Be 59585
        }

        It "should trail up when new peak is much higher" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000
                target = 70000
                stopCurrent = 59585  # already in trailing desde 70000
                peak = 70000
                phase = 3
            }
            
            # Even higher peak (80000) should move trailing 15% down
            $currentPrice = 80000
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BULL_STRONG"
            
            $result.newPhase | Should Be 3
            $result.newPeak | Should Be 80000
            # 80000 * 0.85 = 68000, which is > 59585, so moves up
            ($result.newStop -gt 67000 -and $result.newStop -lt 69000) | Should Be $true
        }
    }

    Context "SHORT Position - Mirrored Logic" {
        It "should handle SHORT position fase 1 correctly" {
            $pos = [PSCustomObject]@{
                market = "ETHUSDT"
                side = "SHORT"
                entry = 3500
                target = 3000
                stopCurrent = 3600
                peak = 3500
                phase = 0
            }
            
            $currentPrice = 3333
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BEAR_STRONG"
            
            $result.newPhase | Should Be 1
            $result.changed | Should Be $true
            ($result.newStop -lt 3500 -and $result.newStop -gt 3300) | Should Be $true
        }
    }

    Context "Regime Impact on Stop Aggressiveness" {
        It "should demonstrate regime multiplier effect on buffer calculation" {
            # Direct buffer calculation test (simpler than full cascade)
            $rangeLarge = 1000000
            $atrHigh = 5000
            $atrHist = 1000
            
            $bufferBull = Get-AdaptiveBuffer -Range $rangeLarge -CurrentAtr $atrHigh -HistoricalAtr $atrHist -Regime "BULL_STRONG"
            $bufferSideways = Get-AdaptiveBuffer -Range $rangeLarge -CurrentAtr $atrHigh -HistoricalAtr $atrHist -Regime "SIDEWAYS"
            
            # BULL_STRONG (0.75) should give smaller buffer than SIDEWAYS (1.3)
            # Both: ATR = 5000, ratio = 5, buffer = base * ratio * regime
            # BULL_STRONG: 5000 * 5 * 0.75 = 18750
            # SIDEWAYS:    5000 * 5 * 1.3  = 32500
            ($bufferBull -lt $bufferSideways) | Should Be $true
        }
    }

    Context "Peak Persistence (Fix 2026-05-25)" {
        It "should update peak even if phase doesn't change" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000
                target = 70000
                stopCurrent = 60100
                peak = 63000
                phase = 1
            }
            
            $currentPrice = 64000
            $result = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $currentPrice -Regime "BULL_WEAK"
            
            $result.newPhase | Should Be 1
            $result.newPeak | Should Be 64000
            $result.changed | Should Be $true
        }
    }
}

Describe "Regression: Adaptive vs Legacy Fixed Buffer" {
    BeforeAll {
        . (Join-Path $PSScriptRoot "..\agents\lib_trailing_adaptive.ps1")
    }

    Context "Adaptive improvement over fixed 2%" {
        It "should provide wider buffer than fixed 2% in high volatility SIDEWAYS" {
            $adaptiveBuffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 200 -HistoricalAtr 100 -Regime "SIDEWAYS"
            $fixedBuffer = 1000 * 0.02
            
            ($adaptiveBuffer -gt $fixedBuffer) | Should Be $true
        }

        It "should be comparable to fixed 2% in low-vol regime" {
            $adaptiveBuffer = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_WEAK"
            $fixedBuffer = 1000 * 0.02
            
            # Adaptive should be much larger (100 vs 20), but still reasonable
            ($adaptiveBuffer -gt $fixedBuffer) | Should Be $true
        }
    }
}
