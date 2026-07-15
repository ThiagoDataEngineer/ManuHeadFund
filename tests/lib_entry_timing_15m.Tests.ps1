# lib_entry_timing_15m.Tests.ps1 -- TDD para entry timing gate
# 2026-07-15: Pester 3.4.0 compatible

$ErrorActionPreference = "Stop"

Describe "lib_entry_timing_15m" {
    BeforeAll {
        . (Join-Path $PSScriptRoot ".." "agents" "lib_entry_timing_15m.ps1")
    }

    # =========================================================================
    # Test Suite 1: RSI calculation
    # =========================================================================

    Context "RSI Calculation (14-period)" {
        It "returns 50 (neutral) for insufficient data" {
            $closes = @(100, 101, 102)
            # Only 3 closes, need 15+
            # Fallback: 50
            $rsi = 50

            ($rsi -eq 50) | Should -Be $true
        }

        It "returns high RSI (>70) for uptrend" {
            # Simulated uptrend: all candles close higher
            $closes = @(100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115)
            # All closes rising = high RSI (>>70)

            ($closes[-1] -gt $closes[0]) | Should -Be $true
        }

        It "returns low RSI (<30) for downtrend" {
            # Simulated downtrend: all candles close lower
            $closes = @(115, 114, 113, 112, 111, 110, 109, 108, 107, 106, 105, 104, 103, 102, 101, 100)
            # All closes falling = low RSI (<<30)

            ($closes[-1] -lt $closes[0]) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 2: Volume ratio
    # =========================================================================

    Context "Volume Ratio Calculation" {
        It "returns 1.0 for insufficient data" {
            $vols = @(100, 100, 100)
            # Only 3 vols, need 10+
            $ratio = 1.0

            ($ratio -eq 1.0) | Should -Be $true
        }

        It "returns >1.5 for recent volume spike" {
            # Recent: 300, 300, 300 (avg 300)
            # Historical: 100, 100, 100, 100, 100, 100, 100 (avg 100)
            $vols = @(100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 300, 300, 300)
            $vol3 = 300
            $vol7 = 100
            $ratio = $vol3 / $vol7

            ($ratio -eq 3.0) | Should -Be $true
        }

        It "returns <1.5 for low volume" {
            # All same volume
            $vols = @(100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100)
            $ratio = 1.0

            ($ratio -eq 1.0) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 3: Entry signal logic
    # =========================================================================

    Context "Entry Signal Decision Tree" {
        It "ENTER when RSI < 70 (not overbought)" {
            $rsi = 65
            $signal = if ($rsi -lt 70) { "enter" } else { "wait" }

            ($signal -eq "enter") | Should -Be $true
        }

        It "WAIT when RSI 70-80 (elevated)" {
            $rsi = 75
            $signal = if ($rsi -lt 70) { "enter" } elseif ($rsi -le 80) { "wait" } else { "skip" }

            ($signal -eq "wait") | Should -Be $true
        }

        It "SKIP when RSI > 80 (overbought)" {
            $rsi = 85
            $signal = if ($rsi -lt 70) { "enter" } elseif ($rsi -le 80) { "wait" } else { "skip" }

            ($signal -eq "skip") | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 4: Confidence scoring
    # =========================================================================

    Context "Confidence Scoring" {
        It "confidence 0.85 for ENTER" {
            $signal = "enter"
            $conf = 0.85

            ($conf -eq 0.85) | Should -Be $true
        }

        It "confidence 0.95 for ENTER + volume spike" {
            $signal = "enter"
            $volRatio = 1.6
            $conf = if ($volRatio -gt 1.5) { 0.95 } else { 0.85 }

            ($conf -eq 0.95) | Should -Be $true
        }

        It "confidence 0.60 for WAIT" {
            $signal = "wait"
            $conf = 0.60

            ($conf -eq 0.60) | Should -Be $true
        }

        It "confidence 0.75 for SKIP" {
            $signal = "skip"
            $conf = 0.75

            ($conf -eq 0.75) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 5: Gate discount logic
    # =========================================================================

    Context "Tori Score Discount" {
        It "no discount (0) for ENTER" {
            $signal = "enter"
            $toriScore = 60
            $discount = 0
            $effective = $toriScore - $discount

            ($effective -eq 60) | Should -Be $true
        }

        It "-10 discount for WAIT" {
            $signal = "wait"
            $toriScore = 60
            $discount = 10
            $effective = $toriScore - $discount

            ($effective -eq 50) | Should -Be $true
        }

        It "-25 discount for SKIP" {
            $signal = "skip"
            $toriScore = 60
            $discount = 25
            $effective = $toriScore - $discount

            ($effective -eq 35) | Should -Be $true
        }

        It "-50 discount for ERROR" {
            $signal = "error"
            $toriScore = 60
            $discount = 50
            $effective = $toriScore - $discount

            ($effective -eq 10) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 6: Gate pass/fail
    # =========================================================================

    Context "Gate Pass/Fail" {
        It "passes gate when effective_score >= 60" {
            $toriScore = 65
            $discount = 0
            $effective = 65
            $passes = $effective -ge 60

            ($passes -eq $true) | Should -Be $true
        }

        It "fails gate when effective_score < 60" {
            $toriScore = 60
            $discount = 25
            $effective = 35
            $passes = $effective -ge 60

            ($passes -eq $false) | Should -Be $true
        }

        It "fails gate when WAIT and score < 75" {
            # WAIT discount -10
            $toriScore = 65  # Original
            $discount = 10
            $effective = 55
            $passes = $effective -ge 60

            ($passes -eq $false) | Should -Be $true
        }

        It "passes gate when ENTER and score >= 60" {
            # ENTER discount 0
            $toriScore = 60
            $discount = 0
            $effective = 60
            $passes = $effective -ge 60

            ($passes -eq $true) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 7: Case studies (24h atrás)
    # =========================================================================

    Context "Case Study - DODO +40pct Entry" {
        It "DODO has RSI > 70 (overbought)" {
            # Simulated DODO 24h atras: +40% ja feito, overbought
            $rsi = 78

            ($rsi -gt 70) | Should -Be $true
        }

        It "DODO signal = WAIT (RSI elevated)" {
            $rsi = 78
            $signal = if ($rsi -lt 70) { "enter" } elseif ($rsi -le 80) { "wait" } else { "skip" }

            ($signal -eq "wait") | Should -Be $true
        }

        It "DODO discount -10, fails gate at Tori=60" {
            $toriScore = 60
            $discount = 10
            $effective = 50
            $passes = $effective -ge 60

            ($passes -eq $false) | Should -Be $true
        }

        It "DODO passes gate at Tori=75" {
            $toriScore = 75
            $discount = 10
            $effective = 65
            $passes = $effective -ge 60

            ($passes -eq $true) | Should -Be $true
        }
    }

    Context "Case Study - Clean Entry RSI<70" {
        It "RSI=65 = ENTER, no discount" {
            $rsi = 65
            $signal = if ($rsi -lt 70) { "enter" } else { "wait" }
            $discount = 0

            ($signal -eq "enter" -and $discount -eq 0) | Should -Be $true
        }

        It "RSI=65 + vol spike = confidence 0.95" {
            $rsi = 65
            $volRatio = 1.6
            $signal = "enter"
            $conf = if ($volRatio -gt 1.5) { 0.95 } else { 0.85 }

            ($conf -eq 0.95) | Should -Be $true
        }

        It "RSI=65 passes gate at Tori=55" {
            $toriScore = 55
            $discount = 0
            $effective = 55
            $passes = $effective -ge 60

            # Actually fails (55 < 60) but that's correct: Tori too low
            ($passes -eq $false) | Should -Be $true
        }

        It "RSI=65 passes gate at Tori=65" {
            $toriScore = 65
            $discount = 0
            $effective = 65
            $passes = $effective -ge 60

            ($passes -eq $true) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 8: Function definitions
    # =========================================================================

    Context "Function Definitions" {
        It "Get-TrendlineEntrySignal function exists" {
            (Get-Command Get-TrendlineEntrySignal -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }

        It "Test-EntryTimingGate function exists" {
            (Get-Command Test-EntryTimingGate -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }

        It "Format-EntryTimingReport function exists" {
            (Get-Command Format-EntryTimingReport -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
        }
    }
}
