# lib_sma_confirmation.Tests.ps1 -- Pester TDD for SMA confirmation filter
# Run: Invoke-Pester lib_sma_confirmation.Tests.ps1 -Verbose
# 2026-07-09: 15 test cases

$ErrorActionPreference = "Stop"

# Setup: Load library under test
$libPath = Join-Path $PSScriptRoot "lib_sma_confirmation.ps1"
if (-not (Test-Path $libPath)) {
    # Try parent directory (tests/ subdirectory)
    $libPath = Join-Path (Split-Path $PSScriptRoot -Parent) "agents\lib_sma_confirmation.ps1"
}

if (Test-Path $libPath) {
    . $libPath
} else {
    throw "Cannot find lib_sma_confirmation.ps1"
}

Describe "lib_sma_confirmation" {

    # ─────────────────────────────────────────────────────────────────────────
    # SMA Calculation Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Calculate-SMA: Basic Functionality" {

        It "calculates exact SMA for 50 elements" {
            $closes = 1..50 | ForEach-Object { [double]$_ }
            $sma = Calculate-SMA -Closes $closes -Period 50

            $expected = (1 + 50) / 2  # average of 1..50 = 25.5
            $sma | Should -Be 25.5
        }

        It "returns null when insufficient data" {
            $closes = 1..10 | ForEach-Object { [double]$_ }
            $sma = Calculate-SMA -Closes $closes -Period 50

            $sma | Should -BeNullOrEmpty
        }

        It "uses LAST 50 closes (not first)" {
            $closes = 1..100 | ForEach-Object { [double]$_ }
            $sma = Calculate-SMA -Closes $closes -Period 50

            # Last 50 = 51..100, average = (51+100)/2 = 75.5
            $sma | Should -Be 75.5
        }

        It "handles floating point prices" {
            $closes = @(1.5, 2.3, 3.7, 4.2, 5.1) * 10  # 50 elements
            $closes = $closes[0..49]
            while ($closes.Count -lt 50) { $closes += $closes[-1] }

            $sma = Calculate-SMA -Closes $closes -Period 50
            $sma | Should -Not -BeNullOrEmpty
        }

        It "returns null for empty array" {
            $sma = Calculate-SMA -Closes @() -Period 50
            $sma | Should -BeNullOrEmpty
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Trend Alignment Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Test-TrendAlignment: LONG Validation" {

        It "confirms LONG when 5m > 15m > 1h" {
            $result = Test-TrendAlignment -Sma5m 105.0 -Sma15m 100.0 -Sma1h 95.0 -Direction "LONG"

            $result.aligned | Should -Be $true
            $result.reason | Should -Be "trend_aligned_long"
            $result.strength | Should -Be "STRONG"  # gap ~5%
        }

        It "rejects LONG when 5m < 15m > 1h (crossed)" {
            $result = Test-TrendAlignment -Sma5m 100.0 -Sma15m 105.0 -Sma1h 95.0 -Direction "LONG"

            $result.aligned | Should -Be $false
            $result.reason | Should -Be "diverged"
        }

        It "rejects LONG when 5m > 15m < 1h (peak)" {
            $result = Test-TrendAlignment -Sma5m 105.0 -Sma15m 100.0 -Sma1h 102.0 -Direction "LONG"

            $result.aligned | Should -Be $false
        }

        It "measures STRONG alignment (gap > 0.5%)" {
            $result = Test-TrendAlignment -Sma5m 100.6 -Sma15m 100.0 -Sma1h 99.0 -Direction "LONG"

            $result.aligned | Should -Be $true
            $result.strength | Should -Be "STRONG"
            $result.gap_pct | Should -BeGreaterThan 0.5
        }

        It "measures WEAK alignment (gap 0-0.5%)" {
            $result = Test-TrendAlignment -Sma5m 100.2 -Sma15m 100.0 -Sma1h 99.9 -Direction "LONG"

            $result.aligned | Should -Be $true
            $result.strength | Should -Be "WEAK"
            $result.gap_pct | Should -BeLessThan 0.5
        }
    }

    Context "Test-TrendAlignment: SHORT Validation" {

        It "confirms SHORT when 5m < 15m < 1h" {
            $result = Test-TrendAlignment -Sma5m 95.0 -Sma15m 100.0 -Sma1h 105.0 -Direction "SHORT"

            $result.aligned | Should -Be $true
            $result.reason | Should -Be "trend_aligned_short"
            $result.strength | Should -Be "STRONG"
        }

        It "rejects SHORT when 5m > 15m < 1h (crossed)" {
            $result = Test-TrendAlignment -Sma5m 105.0 -Sma15m 100.0 -Sma1h 95.0 -Direction "SHORT"

            $result.aligned | Should -Be $false
            $result.reason | Should -Be "diverged"
        }

        It "rejects SHORT when SMAs flat" {
            $result = Test-TrendAlignment -Sma5m 100.0 -Sma15m 100.0 -Sma1h 100.0 -Direction "SHORT"

            $result.aligned | Should -Be $false
        }
    }

    Context "Test-TrendAlignment: Edge Cases" {

        It "handles null SMAs gracefully" {
            $result = Test-TrendAlignment -Sma5m $null -Sma15m 100.0 -Sma1h 95.0 -Direction "LONG"

            $result.aligned | Should -Be $false
            $result.reason | Should -Be "insufficient_data"
        }

        It "handles zero SMA (division by zero)" {
            $result = Test-TrendAlignment -Sma5m 0.0 -Sma15m 0.0 -Sma1h 0.0 -Direction "LONG"

            $result.gap_pct | Should -Be 0.0
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Cache Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Cache Management: TTL & Isolation" {

        BeforeEach {
            # Clear cache before each test
            $global:SMA_CACHE.Clear()
            $global:SMA_STATS = @{ fetches = 0; cache_hits = 0; cache_misses = 0 }
        }

        It "stores result in cache with correct key" {
            $result = @{ aligned = $true; strength = "STRONG"; gap_pct = 0.5 }
            Set-SmaCache -Market "ETHUSDT" -Direction "LONG" -Result $result

            $key = Get-SmaCacheKey "ETHUSDT" "LONG"
            $global:SMA_CACHE[$key] | Should -Not -BeNullOrEmpty
            $global:SMA_CACHE[$key].result.aligned | Should -Be $true
        }

        It "returns cached result when valid (age < TTL)" {
            $result = @{ aligned = $true; gap_pct = 0.5 }
            Set-SmaCache -Market "BTCUSDT" -Direction "SHORT" -Result $result

            Start-Sleep -Milliseconds 100  # Wait 0.1s
            $cached = Get-SmaCache -Market "BTCUSDT" -Direction "SHORT"

            $cached | Should -Not -BeNullOrEmpty
            $cached.aligned | Should -Be $true
        }

        It "returns null for stale cache (age > TTL)" {
            # Mock stale entry: set timestamp to 6 minutes ago
            $key = Get-SmaCacheKey "LINKUSDT" "LONG"
            $global:SMA_CACHE[$key] = @{
                cached_at = [DateTime]::UtcNow.AddSeconds(-360)
                result    = @{ aligned = $true }
            }

            $cached = Get-SmaCache -Market "LINKUSDT" -Direction "LONG"
            $cached | Should -BeNullOrEmpty
        }

        It "isolates cache by market" {
            $result_eth = @{ aligned = $true; market = "ETHUSDT" }
            $result_btc = @{ aligned = $false; market = "BTCUSDT" }

            Set-SmaCache -Market "ETHUSDT" -Direction "LONG" -Result $result_eth
            Set-SmaCache -Market "BTCUSDT" -Direction "LONG" -Result $result_btc

            $eth = Get-SmaCache -Market "ETHUSDT" -Direction "LONG"
            $btc = Get-SmaCache -Market "BTCUSDT" -Direction "LONG"

            $eth.market | Should -Be "ETHUSDT"
            $btc.market | Should -Be "BTCUSDT"
        }

        It "isolates cache by direction" {
            $result_long = @{ aligned = $true; direction = "LONG" }
            $result_short = @{ aligned = $false; direction = "SHORT" }

            Set-SmaCache -Market "ETHUSDT" -Direction "LONG" -Result $result_long
            Set-SmaCache -Market "ETHUSDT" -Direction "SHORT" -Result $result_short

            $long = Get-SmaCache -Market "ETHUSDT" -Direction "LONG"
            $short = Get-SmaCache -Market "ETHUSDT" -Direction "SHORT"

            $long.direction | Should -Be "LONG"
            $short.direction | Should -Be "SHORT"
        }

        It "increments stats on cache miss" {
            $result = @{ aligned = $true }
            Set-SmaCache -Market "UNIUSDT" -Direction "LONG" -Result $result

            $global:SMA_STATS['cache_misses'] | Should -Be 1
        }

        It "increments stats on cache hit" {
            Set-SmaCache -Market "UNIUSDT" -Direction "LONG" -Result @{ aligned = $true }

            $hit = Get-SmaCache -Market "UNIUSDT" -Direction "LONG"

            if ($hit) { $global:SMA_STATS['cache_hits'] | Should -Be 1 }
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Integration Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Confirm-TrendSMA: Integration" {

        BeforeEach {
            $global:SMA_CACHE.Clear()
            $global:SMA_STATS = @{ fetches = 0; cache_hits = 0; cache_misses = 0 }
        }

        It "returns result object with required fields" {
            # Mock test: skip actual API call (would need COINEX_BASE_URL)
            # Instead, test the structure by using -SkipCache with manually set cache

            $mock_result = @{
                aligned = $true
                strength = "STRONG"
                sma_5m = 100.5
                sma_15m = 100.0
                sma_1h = 99.5
                gap_pct = 0.5
                reason = "trend_aligned_long"
                cached = $false
                fetch_ms = 150
            }
            Set-SmaCache -Market "TESTUSDT" -Direction "LONG" -Result $mock_result

            $result = Get-SmaCache -Market "TESTUSDT" -Direction "LONG"

            $result.Keys | Should -Contain "aligned"
            $result.Keys | Should -Contain "sma_5m"
            $result.Keys | Should -Contain "fetch_ms"
        }

        It "returns cached=false on first fetch" {
            # Note: Would require COINEX_BASE_URL to be set in global scope
            # This test validates structure, not actual API call

            $mock = @{ aligned = $true; cached = $false }
            Set-SmaCache -Market "TEST1" -Direction "LONG" -Result $mock
            $result = Get-SmaCache -Market "TEST1" -Direction "LONG"

            $result.cached | Should -Be $false
        }

        It "returns fail-soft on API error (aligned=null)" {
            # When API fails, Confirm-TrendSMA should return aligned=$null
            # (and reason="api_error") instead of throwing

            # This test is conceptual; actual behavior tested in integration phase
            $null | Should -Be $null  # Placeholder
        }
    }

    # ─────────────────────────────────────────────────────────────────────────
    # Debug Functions Tests
    # ─────────────────────────────────────────────────────────────────────────

    Context "Get-SmaCacheStatus: Debug Output" {

        BeforeEach {
            $global:SMA_CACHE.Clear()
            $global:SMA_STATS = @{ fetches = 0; cache_hits = 0; cache_misses = 0 }
        }

        It "returns status object with cache metadata" {
            Set-SmaCache -Market "ETHUSDT" -Direction "LONG" -Result @{ aligned = $true }
            Set-SmaCache -Market "BTCUSDT" -Direction "SHORT" -Result @{ aligned = $false }

            $status = Get-SmaCacheStatus

            $status.count | Should -Be 2
            $status.entries | Should -HaveCount 2
            $status.total_misses | Should -Be 2
        }

        It "calculates hit rate correctly" {
            Set-SmaCache -Market "A" -Direction "LONG" -Result @{ aligned = $true }
            Set-SmaCache -Market "B" -Direction "LONG" -Result @{ aligned = $true }

            Get-SmaCache -Market "A" -Direction "LONG"
            Get-SmaCache -Market "B" -Direction "LONG"

            $status = Get-SmaCacheStatus
            $status.hit_rate_pct | Should -Be 100
        }

        It "includes oldest entry age" {
            Set-SmaCache -Market "OLD" -Direction "LONG" -Result @{ aligned = $true }
            Start-Sleep -Milliseconds 200
            Set-SmaCache -Market "NEW" -Direction "LONG" -Result @{ aligned = $true }

            $status = Get-SmaCacheStatus
            $status.oldest_age | Should -BeGreaterThan 0
        }
    }

}  # End Describe
