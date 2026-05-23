# hit_rate.Tests.ps1 — Pester 3.x tests para lib_hit_rate.ps1
# Cobre: Compare-ScannerVsUniverse, Get-HitRateMetrics
# Rodar: Invoke-Pester .\tests\hit_rate.Tests.ps1 -Verbose

$global:ANTHROPIC_API_KEY           = $null
$global:COINEX_ACCESS_ID            = $null
$global:COINEX_SECRET_KEY           = $null

function Write-Host    { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_hit_rate.ps1"

# ─────────────────────────────────────────────────────────────────────────────
#  Compare-ScannerVsUniverse
# ─────────────────────────────────────────────────────────────────────────────

Describe "Compare-ScannerVsUniverse" {

    Context "matching rates" {
        It "100% caught: 10/10 movers detectados" {
            $scanner = @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J")
            $movers = @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.caught_by_scanner | Should Be 10
            $result.total_movers | Should Be 10
            $result.hit_rate_pct | Should Be 100
            $result.missed.Count | Should Be 0
        }

        It "0% caught: 0/10 nenhum detectado" {
            $scanner = @("X", "Y", "Z")
            $movers = @("A", "B", "C", "D", "E")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.caught_by_scanner | Should Be 0
            $result.total_movers | Should Be 5
            $result.hit_rate_pct | Should Be 0
            $result.missed.Count | Should Be 5
        }

        It "30% caught: 3/10 detectados" {
            $scanner = @("A", "B", "C")
            $movers = @("A", "B", "C", "D", "E", "F", "G", "H", "I", "J")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.caught_by_scanner | Should Be 3
            $result.total_movers | Should Be 10
            $result.hit_rate_pct | Should Be 30
            $result.missed.Count | Should Be 7
        }

        It "missed array contem os pares não detectados" {
            $scanner = @("A", "B")
            $movers = @("A", "B", "X", "Y")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.missed -contains "x" | Should Be $true
            $result.missed -contains "y" | Should Be $true
            $result.missed -contains "a" | Should Be $false
        }
    }

    Context "direction labels" {
        It "LONG direction é preservado" {
            $scanner = @("A")
            $movers = @("B")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.direction | Should Be "LONG"
        }

        It "SHORT direction é preservado" {
            $scanner = @("A")
            $movers = @("B")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "SHORT"
            $result.direction | Should Be "SHORT"
        }
    }

    Context "edge cases" {
        It "universe vazio retorna hit_rate_pct 0" {
            $scanner = @("A", "B")
            $movers = @()
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.hit_rate_pct | Should Be 0
            $result.total_movers | Should Be 0
        }

        It "scanner vazio mas universe com movers" {
            $scanner = @()
            $movers = @("A", "B", "C")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.caught_by_scanner | Should Be 0
            $result.total_movers | Should Be 3
            $result.missed.Count | Should Be 3
        }

        It "case-insensitive matching" {
            $scanner = @("btc", "eth")
            $movers = @("BTC", "ETH", "SOL")
            $result = Compare-ScannerVsUniverse -ScannerTopN $scanner -UniverseMovers $movers -Direction "LONG"
            $result.caught_by_scanner | Should Be 2
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Get-HitRateMetrics
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-HitRateMetrics" {

    It "agrega LONG e SHORT comparisons em estrutura unica" {
        $longComp = [PSCustomObject]@{
            total_movers      = 10
            caught_by_scanner = 9
            hit_rate_pct      = 90
            missed            = @("X")
            direction         = "LONG"
        }
        $shortComp = [PSCustomObject]@{
            total_movers      = 5
            caught_by_scanner = 2
            hit_rate_pct      = 40
            missed            = @("A", "B", "C")
            direction         = "SHORT"
        }
        $metrics = Get-HitRateMetrics -LongComparison $longComp -ShortComparison $shortComp
        $metrics | Should Not Be $null
        $metrics.long_hit_rate_pct | Should Be 90
        $metrics.short_hit_rate_pct | Should Be 40
    }

    It "retorna PSCustomObject com campos combinados" {
        $longComp = [PSCustomObject]@{
            total_movers      = 10
            caught_by_scanner = 5
            hit_rate_pct      = 50
            missed            = @()
            direction         = "LONG"
        }
        $shortComp = [PSCustomObject]@{
            total_movers      = 10
            caught_by_scanner = 5
            hit_rate_pct      = 50
            missed            = @()
            direction         = "SHORT"
        }
        $metrics = Get-HitRateMetrics -LongComparison $longComp -ShortComparison $shortComp
        $metrics.long_hit_rate_pct | Should Not Be $null
        $metrics.short_hit_rate_pct | Should Not Be $null
    }
}
