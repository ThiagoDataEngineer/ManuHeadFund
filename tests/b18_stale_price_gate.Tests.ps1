# B18 fix 2026-05-20 PM6+410min.
# Stale price detection: ticker fetched_at validado contra threshold antes de uso.

$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot "agents\lib_price_freshness.ps1")

Describe "B18 Test-PriceFresh" {
    It "ticker fresh (fetched_at 5s atras): passa" {
        $now = Get-Date
        $r = Test-PriceFresh -FetchedAt $now.AddSeconds(-5) -MaxAgeSeconds 60
        $r.is_fresh | Should Be $true
        $r.age_seconds | Should BeLessThan 10
    }
    It "ticker stale (fetched_at 120s atras com threshold 60s): FAIL" {
        $now = Get-Date
        $r = Test-PriceFresh -FetchedAt $now.AddSeconds(-120) -MaxAgeSeconds 60
        $r.is_fresh | Should Be $false
        $r.age_seconds | Should BeGreaterThan 100
    }
    It "null FetchedAt: fail-closed (NAO trata como fresh)" {
        $r = Test-PriceFresh -FetchedAt $null -MaxAgeSeconds 60
        $r.is_fresh | Should Be $false
    }
    It "threshold customizado: respeitado" {
        $now = Get-Date
        $r = Test-PriceFresh -FetchedAt $now.AddSeconds(-30) -MaxAgeSeconds 10
        $r.is_fresh | Should Be $false
    }
}

Describe "B18 Get-FreshTicker (Get-Ticker wrapper)" {
    It "retorna ticker + fetched_at + is_fresh=true em mock fresh" {
        $mockTicker = @{ last = 50000 }
        $r = New-FreshTicker -RawTicker $mockTicker
        $r.is_fresh | Should Be $true
        $r.ticker.last | Should Be 50000
        $r.fetched_at | Should Not Be $null
    }
}
