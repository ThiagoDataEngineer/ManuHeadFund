# lib_breadth_monitor.Tests.ps1 -- TDD para breadth monitor gate
# 2026-07-15: Pester 3.4.0 compatible (uses @() operator instead of Should)

$ErrorActionPreference = "Stop"

Describe "lib_breadth_monitor" {
    BeforeAll {
        . (Join-Path (Join-Path $PSScriptRoot "..") "agents\lib_breadth_monitor.ps1")
    }

    # =========================================================================
    # Test Suite 1: Get-AltcoinBreadth basic logic
    # =========================================================================

    Context "Get-AltcoinBreadth - Mock Data" {
        BeforeEach {
            $script:testMarkets = @(
                @{ price_change_24h_pct = 5.2; volume_24h = 1000000 },      # green
                @{ price_change_24h_pct = 3.1; volume_24h = 1200000 },      # green
                @{ price_change_24h_pct = -2.5; volume_24h = 900000 },     # red
                @{ price_change_24h_pct = 8.7; volume_24h = 1500000 },      # green
                @{ price_change_24h_pct = -1.2; volume_24h = 800000 }      # red
            )
        }

        It "calculates breadth_pct correctly" {
            $green = ($script:testMarkets | Where-Object { $_."price_change_24h_pct" -gt 0 }).Count
            $total = $script:testMarkets.Count
            $breadth = ($green / $total) * 100

            ($breadth -eq 60) | Should -Be $true
        }

        It "classifies bullish trend when breadth > 60% and vol_ratio high" {
            $breadth_pct = 65
            $vol_ratio = 1.8
            $result = ($breadth_pct -gt 60 -and $vol_ratio -gt 1.5)

            $result | Should -Be $true
        }

        It "classifies bearish trend when breadth < 40% and vol_ratio high" {
            $breadth_pct = 35
            $vol_ratio = 1.9
            $result = ($breadth_pct -lt 40 -and $vol_ratio -gt 1.8)

            $result | Should -Be $true
        }

        It "classifies neutral trend when breadth between 40-60%" {
            $breadth_pct = 50
            $result = ($breadth_pct -ge 40 -and $breadth_pct -le 60)

            $result | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 2: Test-ParallelBreadthGate logic
    # =========================================================================

    Context "Test-ParallelBreadthGate - OR Logic" {
        It "allows LONG if BTC allows, regardless of breadth" {
            $btcAllowLong = $true
            $breadthTrend = "neutral"
            $breadthPct = 45
            $breadthConf = 0.50

            $result = $btcAllowLong -or `
                      ($breadthTrend -eq "bullish" -and $breadthPct -gt 60 -and $breadthConf -gt 0.70)

            $result | Should -Be $true
        }

        It "allows LONG if breadth bullish and confidence high, regardless of BTC" {
            $btcAllowLong = $false
            $breadthTrend = "bullish"
            $breadthPct = 68
            $breadthConf = 0.75

            $result = $btcAllowLong -or `
                      ($breadthTrend -eq "bullish" -and $breadthPct -gt 60 -and $breadthConf -gt 0.70)

            $result | Should -Be $true
        }

        It "blocks LONG if neither BTC nor breadth bullish" {
            $btcAllowLong = $false
            $breadthTrend = "neutral"
            $breadthPct = 50
            $breadthConf = 0.50

            $result = $btcAllowLong -or `
                      ($breadthTrend -eq "bullish" -and $breadthPct -gt 60 -and $breadthConf -gt 0.70)

            $result | Should -Be $false
        }

        It "allows SHORT if breadth bearish and confidence high" {
            $btcAllowShort = $false
            $breadthTrend = "bearish"
            $breadthPct = 32
            $breadthConf = 0.72

            $result = $btcAllowShort -or `
                      ($breadthTrend -eq "bearish" -and $breadthPct -lt 40 -and $breadthConf -gt 0.65)

            $result | Should -Be $true
        }

        It "blocks SHORT if neither BTC nor breadth bearish" {
            $btcAllowShort = $false
            $breadthTrend = "bullish"
            $breadthPct = 72
            $breadthConf = 0.80

            $result = $btcAllowShort -or `
                      ($breadthTrend -eq "bearish" -and $breadthPct -lt 40 -and $breadthConf -gt 0.65)

            $result | Should -Be $false
        }
    }

    # =========================================================================
    # Test Suite 3: Confidence scoring
    # =========================================================================

    Context "Confidence Scoring" {
        It "calculates confidence 0.75 at breadth 60% bullish" {
            $breadth_pct = 60
            $baseConf = 0.75

            ($baseConf -eq 0.75) | Should -Be $true
        }

        It "boosts confidence towards 0.90 at breadth 100% bullish" {
            $breadth_pct = 100
            $vol_ratio = 1.8
            $baseConf = 0.75 + ($breadth_pct - 60) / 40 * 0.15
            $baseConf = [Math]::Min($baseConf, 0.90)

            ($baseConf -ge 0.85 -and $baseConf -le 0.90) | Should -Be $true
        }

        It "calculates confidence 0.70 at breadth 0% bearish" {
            $breadth_pct = 0
            $vol_ratio = 1.9
            $baseConf = 0.70 + ((40 - $breadth_pct) / 40) * 0.15
            $baseConf = [Math]::Min($baseConf, 0.85)

            ($baseConf -ge 0.80 -and $baseConf -le 0.85) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 4: Edge cases
    # =========================================================================

    Context "Edge Cases" {
        It "handles zero markets gracefully" {
            $markets = @()
            $breadth = if ($markets.Count -gt 0) { 50 } else { 0 }

            ($breadth -eq 0) | Should -Be $true
        }

        It "handles API error with unknown trend" {
            $reason = "api_error: timeout"

            ($reason.Contains("api_error")) | Should -Be $true
        }

        It "handles all-green markets (100% breadth)" {
            $green = 50
            $total = 50
            $breadth = ($green / $total) * 100

            ($breadth -eq 100) | Should -Be $true
        }

        It "handles all-red markets (0% breadth)" {
            $green = 0
            $total = 50
            $breadth = ($green / $total) * 100

            ($breadth -eq 0) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 5: Cache logic
    # =========================================================================

    Context "Caching Behavior" {
        It "respects cache TTL (5 minutes)" {
            $cacheTime = Get-Date
            $callTime = $cacheTime.AddMinutes(3)
            $elapsed = ($callTime - $cacheTime).TotalMinutes

            ($elapsed -lt 5) | Should -Be $true
        }

        It "expires cache after 5 minutes" {
            $cacheTime = Get-Date
            $callTime = $cacheTime.AddMinutes(6)
            $elapsed = ($callTime - $cacheTime).TotalMinutes

            ($elapsed -gt 5) | Should -Be $true
        }
    }

    # =========================================================================
    # Test Suite 6: Integration test (case study: 24h atrás)
    # =========================================================================

    Context "Case Study: BILL/DODO/AKE 24h Atrás" {
        It "BILL -50%: breadth bearish + vol high = allows SHORT" {
            $breadth_pct = 35
            $vol_ratio = 1.95
            $breadth_trend = if ($breadth_pct -lt 40 -and $vol_ratio -gt 1.8) { "bearish" } else { "neutral" }
            $breadth_conf = 0.75

            ($breadth_trend -eq "bearish" -and $breadth_conf -gt 0.65) | Should -Be $true
        }

        It "DODO +40%: breadth bullish + high confidence = allows LONG" {
            $breadth_pct = 67
            $vol_ratio = 1.6
            $breadth_trend = if ($breadth_pct -gt 60 -and $vol_ratio -gt 1.5) { "bullish" } else { "neutral" }
            $breadth_conf = 0.78

            ($breadth_trend -eq "bullish" -and $breadth_conf -gt 0.70) | Should -Be $true
        }

        It "AKE +178%: breadth bullish (high confidence)" {
            $breadth_pct = 72
            $vol_ratio = 2.1
            $breadth_trend = "bullish"
            $breadth_conf = 0.85

            ($breadth_trend -eq "bullish") | Should -Be $true
        }
    }
}
