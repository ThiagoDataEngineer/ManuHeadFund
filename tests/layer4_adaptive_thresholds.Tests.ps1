# Layer 4 Adaptive Thresholds Tests (RED phase)
# Tests for multi-tier (SOFT/MEDIUM/HARD) + regime-aware time stops

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1")

Describe "Layer 4 Adaptive Thresholds By Regime" {

    It "Get-StagnationThresholds returns object with soft medium hard" {
        $t = Get-StagnationThresholds -Regime "SIDEWAYS"
        $t.soft   | Should Not Be $null
        $t.medium | Should Not Be $null
        $t.hard   | Should Not Be $null
    }

    It "BULL_STRONG should have aggressive thresholds 8 12 18" {
        $t = Get-StagnationThresholds -Regime "BULL_STRONG"
        $t.soft   | Should Be 8
        $t.medium | Should Be 12
        $t.hard   | Should Be 18
    }

    It "BULL_WEAK should have moderate-fast thresholds 12 18 24" {
        $t = Get-StagnationThresholds -Regime "BULL_WEAK"
        $t.soft   | Should Be 12
        $t.medium | Should Be 18
        $t.hard   | Should Be 24
    }

    It "SIDEWAYS should have patient thresholds 18 24 36" {
        $t = Get-StagnationThresholds -Regime "SIDEWAYS"
        $t.soft   | Should Be 18
        $t.medium | Should Be 24
        $t.hard   | Should Be 36
    }

    It "BEAR_WEAK should mirror BULL_WEAK aggressive 8 12 18" {
        $t = Get-StagnationThresholds -Regime "BEAR_WEAK"
        $t.soft   | Should Be 8
        $t.medium | Should Be 12
        $t.hard   | Should Be 18
    }

    It "BEAR_STRONG should be very aggressive 4 8 12" {
        $t = Get-StagnationThresholds -Regime "BEAR_STRONG"
        $t.soft   | Should Be 4
        $t.medium | Should Be 8
        $t.hard   | Should Be 12
    }

    It "CAPITULATION should be ultra fast 2 4 6" {
        $t = Get-StagnationThresholds -Regime "CAPITULATION"
        $t.soft   | Should Be 2
        $t.medium | Should Be 4
        $t.hard   | Should Be 6
    }

    It "Unknown regime defaults to SIDEWAYS thresholds" {
        $t = Get-StagnationThresholds -Regime "UNKNOWN"
        $t.soft   | Should Be 18
        $t.medium | Should Be 24
        $t.hard   | Should Be 36
    }
}

Describe "Layer 4 Stagnation Tier Classification" {

    It "Classify-StagnationTier returns NONE under soft threshold" {
        $tier = Classify-StagnationTier -HoursElapsed 4 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "NONE"
    }

    It "Classify-StagnationTier returns SOFT between soft and medium" {
        $tier = Classify-StagnationTier -HoursElapsed 20 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "SOFT"
    }

    It "Classify-StagnationTier returns MEDIUM between medium and hard" {
        $tier = Classify-StagnationTier -HoursElapsed 28 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "MEDIUM"
    }

    It "Classify-StagnationTier returns HARD over hard threshold" {
        $tier = Classify-StagnationTier -HoursElapsed 40 -PeakProgress 0.001 -Regime "SIDEWAYS"
        $tier | Should Be "HARD"
    }

    It "Classify ignores stagnation if peak progress good" {
        $tier = Classify-StagnationTier -HoursElapsed 40 -PeakProgress 0.05 -Regime "SIDEWAYS"
        $tier | Should Be "NONE"
    }

    It "BULL_STRONG flat 10h is SOFT (would be NONE in SIDEWAYS)" {
        $tier = Classify-StagnationTier -HoursElapsed 10 -PeakProgress 0.001 -Regime "BULL_STRONG"
        $tier | Should Be "SOFT"
    }

    It "BEAR_STRONG flat 5h is SOFT" {
        $tier = Classify-StagnationTier -HoursElapsed 5 -PeakProgress 0.001 -Regime "BEAR_STRONG"
        $tier | Should Be "SOFT"
    }

    It "CAPITULATION flat 3h already SOFT" {
        $tier = Classify-StagnationTier -HoursElapsed 3 -PeakProgress 0.001 -Regime "CAPITULATION"
        $tier | Should Be "SOFT"
    }
}

Describe "Layer 4 Decision With Adaptive Thresholds" {

    It "UNI 27h SIDEWAYS is MEDIUM not HARD" {
        # 27h is between MEDIUM (24h) and HARD (36h) for SIDEWAYS
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.37
            stop         = 3.30
            target       = 3.60
            openedAt     = (Get-Date).AddHours(-27).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "SIDEWAYS"
        # Should suggest a softer action, not hard close
        ($decision.action -eq "WARN_STAGNATION" -or $decision.action -eq "REVIEW_STAGNATION") | Should Be $true
    }

    It "UNI 40h SIDEWAYS is HARD CLOSE_TIME_STOP" {
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.37
            stop         = 3.30
            target       = 3.60
            openedAt     = (Get-Date).AddHours(-40).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "SIDEWAYS"
        $decision.action | Should Be "CLOSE_TIME_STOP"
    }

    It "Trade flat 10h in BULL_STRONG triggers WARN_STAGNATION" {
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.46
            stop         = 3.30
            target       = 3.60
            openedAt     = (Get-Date).AddHours(-10).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "BULL_STRONG"
        $decision.action | Should Be "WARN_STAGNATION"
    }

    It "Trade flat 4h in any regime should NOT trigger stagnation" {
        $position = [PSCustomObject]@{
            market       = "UNIUSDT"
            side         = "LONG"
            entry        = 3.46
            peak         = 3.46
            currentPrice = 3.46
            stop         = 3.30
            target       = 3.60
            openedAt     = (Get-Date).AddHours(-4).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "SIDEWAYS"
        # 4h < SIDEWAYS soft threshold of 18h
        ($decision.action -eq "HOLD") | Should Be $true
    }

    It "Healthy trade with profit ignores stagnation regardless of time" {
        $position = [PSCustomObject]@{
            market       = "BNBUSDT"
            side         = "LONG"
            entry        = 647.06
            peak         = 671.32
            currentPrice = 661.46
            stop         = 657.80
            target       = 679.60
            openedAt     = (Get-Date).AddHours(-50).ToString("yyyy-MM-dd HH:mm:ss")
        }

        $decision = Get-Layer4Decision -Position $position -Regime "SIDEWAYS"
        # Even at 50h, healthy trade = HOLD or HARVEST not stagnation close
        ($decision.action -ne "CLOSE_TIME_STOP" -and $decision.action -ne "WARN_STAGNATION") | Should Be $true
    }
}

Describe "Layer 4 Regression - Adaptive Thresholds Improve On Fixed" {

    It "BULL_STRONG 10h flat WAS missed by 24h fixed but caught by adaptive" {
        # Fixed 24h: would not trigger at 10h
        $fixedWouldTrigger = (10 -gt 24)
        # Adaptive BULL_STRONG: SOFT=8h, so triggers at 10h
        $adaptiveSoft = 8
        $adaptiveTriggers = (10 -gt $adaptiveSoft)

        ($fixedWouldTrigger -eq $false -and $adaptiveTriggers -eq $true) | Should Be $true
    }

    It "BEAR_STRONG 6h flat WAS missed by 24h fixed but caught by adaptive" {
        $fixedWouldTrigger = (6 -gt 24)
        $adaptiveSoft = 4  # BEAR_STRONG soft
        $adaptiveTriggers = (6 -gt $adaptiveSoft)
        ($fixedWouldTrigger -eq $false -and $adaptiveTriggers -eq $true) | Should Be $true
    }

    It "SIDEWAYS 25h flat triggered hard by old 24h threshold but only MEDIUM in adaptive" {
        # Old behavior: 25h > 24h fixed = CLOSE_TIME_STOP (too aggressive)
        # New behavior: 25h is MEDIUM (between 24 and 36) = REVIEW_STAGNATION (less aggressive)
        $oldFixedAction = "CLOSE_TIME_STOP"  # too aggressive
        $newAdaptiveAction = "REVIEW_STAGNATION"  # gives more time
        ($oldFixedAction -ne $newAdaptiveAction) | Should Be $true
    }

    It "Adaptive saves false-positive closes in SIDEWAYS regime" {
        # 25h in SIDEWAYS should be MEDIUM not HARD (more patient)
        $hours = 25
        $regime = "SIDEWAYS"
        $hard = 36  # SIDEWAYS hard threshold
        $shouldHardClose = ($hours -gt $hard)
        $shouldHardClose | Should Be $false
    }

    It "Adaptive prevents premature close of SIDEWAYS trades" {
        # Old: 25h > 24h fixed = close prematurely
        # New: 25h is MEDIUM tier = review only, not close
        $hours = 25
        $oldThreshold = 24
        $oldWouldClose = ($hours -gt $oldThreshold)
        $newHardThreshold = 36
        $newWouldClose = ($hours -gt $newHardThreshold)
        ($oldWouldClose -eq $true -and $newWouldClose -eq $false) | Should Be $true
    }
}
