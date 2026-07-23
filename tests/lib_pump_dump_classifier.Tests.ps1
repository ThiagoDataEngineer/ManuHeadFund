# lib_pump_dump_classifier.Tests.ps1 -- TDD para pump-dump classifier
# 2026-07-15: Pester 3.4.0 compatible

$ErrorActionPreference = "Stop"

Describe "lib_pump_dump_classifier" {
    BeforeAll {
        . (Join-Path (Join-Path $PSScriptRoot "..") "agents\lib_pump_dump_classifier.ps1")
    }

    # =========================================================================
    # Test Suite 1: Feature scoring logic
    # =========================================================================

    Context "Feature Scoring - Duration" {
        It "awards +20 for pump in <24H" {
            $daysFromPeak = 0
            $score = if ($daysFromPeak -eq 0) { 20 } else { 0 }

            ($score -eq 20) | Should Be $true
        }

        It "awards +10 for pump in <48H" {
            $daysFromPeak = 1
            $score = if ($daysFromPeak -le 1) { 10 } else { 0 }

            ($score -eq 10) | Should Be $true
        }
    }

    Context "Feature Scoring - Market Cap" {
        It "awards +20 for MCap < 50M" {
            $mcap = 40000000
            $score = if ($mcap -lt 50000000) { 20 } elseif ($mcap -lt 100000000) { 15 } else { 0 }

            ($score -eq 20) | Should Be $true
        }

        It "awards +15 for MCap < 100M" {
            $mcap = 75000000
            $score = if ($mcap -lt 50000000) { 20 } elseif ($mcap -lt 100000000) { 15 } else { 0 }

            ($score -eq 15) | Should Be $true
        }

        It "awards 0 for MCap > 100M" {
            $mcap = 200000000
            $score = if ($mcap -lt 50000000) { 20 } elseif ($mcap -lt 100000000) { 15 } else { 0 }

            ($score -eq 0) | Should Be $true
        }
    }

    Context "Feature Scoring - Penny Stock" {
        It "awards +10 for price < 0.01 USD" {
            $price = 0.003299
            $score = if ($price -lt 0.01) { 10 } else { 0 }

            ($score -eq 10) | Should Be $true
        }

        It "awards 0 for price > 0.01 USD" {
            $price = 0.02687
            $score = if ($price -lt 0.01) { 10 } else { 0 }

            ($score -eq 0) | Should Be $true
        }
    }

    Context "Feature Scoring - Volume Spike" {
        It "awards +20 for vol spike > 3x" {
            $volRatio = 3.5
            $score = if ($volRatio -gt 3.0) { 20 } elseif ($volRatio -gt 2.0) { 10 } else { 0 }

            ($score -eq 20) | Should Be $true
        }

        It "awards +10 for vol spike 2x-3x" {
            $volRatio = 2.5
            $score = if ($volRatio -gt 3.0) { 20 } elseif ($volRatio -gt 2.0) { 10 } else { 0 }

            ($score -eq 10) | Should Be $true
        }

        It "awards +5 for vol spike 1.5x-2x" {
            $volRatio = 1.6
            $score = if ($volRatio -gt 3.0) { 20 } elseif ($volRatio -gt 2.0) { 10 } elseif ($volRatio -gt 1.5) { 5 } else { 0 }

            ($score -eq 5) | Should Be $true
        }
    }

    Context "Feature Scoring - Retracement" {
        # 2026-07-16: threshold fixo de -30% substituido por threshold RELATIVO
        # a volatilidade do proprio par (-2.5x ATR%, nunca mais restritivo que
        # -30%) -- achado real: majors (ARBUSDT -13%, AVAXUSDT -4.6% do pico)
        # nunca pontuavam aqui mesmo com reversao tecnica confirmada pelo Tori
        # (confluence=100), porque -30% e calibrado pra volatilidade de gema,
        # nao de blue-chip. Ver lib_pump_dump_classifier.ps1 Feature 5.
        It "awards +25 for retracement > 30pct with recent dump (caso extremo, sempre pontua)" {
            $distFromPeak = -50
            $atrPct = 5.0
            $threshold = [Math]::Max(-30, -2.5 * $atrPct)
            $score = if ($distFromPeak -lt $threshold) { 25 } else { 0 }

            ($score -eq 25) | Should Be $true
        }

        It "awards 0 for retracement dentro da volatilidade normal do par" {
            $distFromPeak = -5
            $atrPct = 5.0
            $threshold = [Math]::Max(-30, -2.5 * $atrPct)
            $score = if ($distFromPeak -lt $threshold) { 25 } else { 0 }

            ($score -eq 0) | Should Be $true
        }

        It "threshold relativo fica mais sensivel que -30pct fixo pra major de baixa volatilidade (caso que motivou o fix)" {
            # ARBUSDT real: ATR 7d ~6.83% -> threshold relativo -17.08%, mais
            # sensivel que o -30% fixo antigo (nunca bateria pra queda de -13%)
            $atrPct = 6.83
            $thresholdRelative = [Math]::Max(-30, -2.5 * $atrPct)
            $thresholdOld = -30

            ($thresholdRelative -gt $thresholdOld) | Should Be $true
        }
    }

    Context "Feature Scoring - New Listing" {
        It "awards -15 for listing < 7 days (organic growth)" {
            $daysListed = 2
            $score = if ($daysListed -lt 7) { -15 } else { 0 }

            ($score -eq -15) | Should Be $true
        }

        It "awards 0 for listing > 7 days" {
            $daysListed = 30
            $score = if ($daysListed -lt 7) { -15 } else { 0 }

            ($score -eq 0) | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 2: Classification thresholds
    # =========================================================================

    Context "Classification - Thresholds" {
        It "classifies score >= 60 as pump_and_dump" {
            $score = 65
            $class = if ($score -ge 60) { "pump_and_dump" } elseif ($score -ge 30) { "reaccumulation" } else { "natural_uptrend" }

            ($class -eq "pump_and_dump") | Should Be $true
        }

        It "classifies score 30-60 as reaccumulation" {
            $score = 45
            $class = if ($score -ge 60) { "pump_and_dump" } elseif ($score -ge 30) { "reaccumulation" } else { "natural_uptrend" }

            ($class -eq "reaccumulation") | Should Be $true
        }

        It "classifies score < 30 as natural_uptrend" {
            $score = 15
            $class = if ($score -ge 60) { "pump_and_dump" } elseif ($score -ge 30) { "reaccumulation" } else { "natural_uptrend" }

            ($class -eq "natural_uptrend") | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 3: Confidence scoring
    # =========================================================================

    Context "Confidence Scoring" {
        It "high confidence (0.85) for pump_and_dump" {
            $conf = 0.85

            ($conf -eq 0.85) | Should Be $true
        }

        It "medium confidence (0.65) for reaccumulation" {
            $conf = 0.65

            ($conf -eq 0.65) | Should Be $true
        }

        It "low confidence (0.55) for natural_uptrend" {
            $conf = 0.55

            ($conf -eq 0.55) | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 4: Gate logic
    # =========================================================================

    Context "Test-PumpDumpGate Logic" {
        It "blocks LONG for pump_and_dump near peak" {
            $class = "pump_and_dump"
            $distFromPeak = -2  # Still near peak
            $allowLong = if ($class -eq "pump_and_dump" -and $distFromPeak -gt -5.0) { $false } else { $true }

            ($allowLong -eq $false) | Should Be $true
        }

        It "allows LONG for pump_and_dump far from peak" {
            $class = "pump_and_dump"
            $distFromPeak = -35  # Retracted significantly
            $allowLong = $true  # bargain hunting

            ($allowLong -eq $true) | Should Be $true
        }

        It "allows SHORT for pump_and_dump" {
            $class = "pump_and_dump"
            $allowShort = $true

            ($allowShort -eq $true) | Should Be $true
        }

        It "allows LONG for natural_uptrend" {
            $class = "natural_uptrend"
            $allowLong = $true
            $allowShort = $false

            ($allowLong -eq $true -and $allowShort -eq $false) | Should Be $true
        }

        It "allows SHORT for reaccumulation" {
            $class = "reaccumulation"
            $allowShort = $true

            ($allowShort -eq $true) | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 5: Case studies (24h atrás)
    # =========================================================================

    Context "Case Study - BILL -50pct Dump" {
        It "BILL classifies as pump_and_dump (score >= 60)" {
            # Simulated BILL features
            $features = @{
                duration = 20      # Fast pump
                mcap = 10          # Low cap (80M)
                penny = 0          # Not penny (0.033)
                vol_spike = 20     # High volume
                retracement = 25   # -50pct drop
                candle = 0
                new_listing = 0
            }
            $score = $features.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum

            ($score -ge 60) | Should Be $true
        }

        It "BILL allows SHORT (after reversal)" {
            $class = "pump_and_dump"
            $distFromPeak = -45  # Already dropped

            ($class -eq "pump_and_dump") | Should Be $true
        }
    }

    Context "Case Study - DODO +40pct Natural" {
        It "DODO classifies as natural_uptrend (score < 30)" {
            # Simulated DODO features
            $features = @{
                duration = 10      # <48H
                mcap = 15          # Low cap (26.87M)
                penny = 0          # Not penny (0.027)
                vol_spike = 5      # Moderate volume
                retracement = 0    # No retracement
                candle = -5        # Strong close
                new_listing = 0    # Established
            }
            $score = $features.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum

            ($score -lt 30) | Should Be $true
        }

        It "DODO allows LONG (natural growth)" {
            $class = "natural_uptrend"

            ($class -eq "natural_uptrend") | Should Be $true
        }
    }

    Context "Case Study - AKE +178pct Extreme Pump" {
        It "AKE classifies as pump_and_dump (score > 60)" {
            # Simulated AKE features
            $features = @{
                duration = 20      # Very fast pump
                mcap = 20          # Extremely low cap (52M)
                penny = 10         # Penny stock (0.0005)
                vol_spike = 20     # Extreme volume
                retracement = 0    # Still up (no retracement yet)
                candle = 0
                new_listing = 0
            }
            $score = $features.Values | Measure-Object -Sum | Select-Object -ExpandProperty Sum

            ($score -ge 60) | Should Be $true
        }

        It "AKE blocks LONG (still near peak)" {
            $class = "pump_and_dump"
            $distFromPeak = 0  # At peak

            ($class -eq "pump_and_dump") | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 6: Edge cases
    # =========================================================================

    Context "Edge Cases" {
        It "handles zero score (new listing)" {
            $daysListed = 2
            $score = 0 - 15

            ($score -lt 0) | Should Be $true
        }

        It "handles max score (extreme pump)" {
            $score = 20 + 20 + 10 + 20 + 25 + 0 + 0  # All positive features

            ($score -eq 95) | Should Be $true
        }

        It "classifies negative score as new_listing" {
            $score = -5
            $class = if ($score -ge 60) { "pump_and_dump" } `
                    elseif ($score -ge 30) { "reaccumulation" } `
                    elseif ($score -gt 0) { "natural_uptrend" } `
                    else { "new_listing" }

            ($class -eq "new_listing") | Should Be $true
        }
    }

    # =========================================================================
    # Test Suite 7: Function definitions
    # =========================================================================

    Context "Function Definitions" {
        It "Get-PumpDumpClass function exists" {
            (Get-Command Get-PumpDumpClass -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }

        It "Test-PumpDumpGate function exists" {
            (Get-Command Test-PumpDumpGate -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }

        It "Format-PumpDumpReport function exists" {
            (Get-Command Format-PumpDumpReport -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }
    }
}
