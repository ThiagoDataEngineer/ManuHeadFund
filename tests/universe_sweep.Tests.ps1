# universe_sweep.Tests.ps1 — Pester 3.x tests para lib_universe_sweep.ps1
# Cobre: Get-UniverseSnapshot, Get-TopMoversLong, Get-TopMoversShort, Get-UniverseGateStats
# Rodar: Invoke-Pester .\tests\universe_sweep.Tests.ps1 -Verbose

$global:ANTHROPIC_API_KEY           = $null
$global:COINEX_ACCESS_ID            = $null
$global:COINEX_SECRET_KEY           = $null

function Write-Host    { param() }
function Write-Warning { param() }

. "$PSScriptRoot\..\agents\lib_universe_sweep.ps1"

# ─────────────────────────────────────────────────────────────────────────────
#  Get-UniverseSnapshot
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-UniverseSnapshot" {

    Context "dataset normal" {
        It "retorna snapshot com total_pairs correto" {
            $pairs = @(
                [PSCustomObject]@{symbol="BTCUSDT"; vol_24h=1000000; change_24h=2.5; market_cap=500000000; age_days=3000; spread_pct=0.02}
                [PSCustomObject]@{symbol="ETHUSDT"; vol_24h=500000; change_24h=1.2; market_cap=200000000; age_days=2000; spread_pct=0.03}
                [PSCustomObject]@{symbol="SOLUS"; vol_24h=200000; change_24h=-0.5; market_cap=50000000; age_days=1000; spread_pct=0.05}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 2
            $snap.total_pairs | Should Be 3
        }

        It "top_long_movers limitado a N e ordenado desc" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=10; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=5; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="C"; vol_24h=100; change_24h=20; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="D"; vol_24h=100; change_24h=15; market_cap=1000; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 2
            $snap.top_long_movers.Count | Should Be 2
            $snap.top_long_movers[0].change_24h | Should Be 20
            $snap.top_long_movers[1].change_24h | Should Be 15
        }

        It "top_short_movers limitado a N e ordenado asc (mais negativo primeiro)" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=-5; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=-15; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="C"; vol_24h=100; change_24h=-3; market_cap=1000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="D"; vol_24h=100; change_24h=-10; market_cap=1000; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 2
            $snap.top_short_movers.Count | Should Be 2
            $snap.top_short_movers[0].change_24h | Should Be -15
            $snap.top_short_movers[1].change_24h | Should Be -10
        }

        It "gate_stats conta corretamente mcap_below_1m" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=500000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=3; market_cap=2000000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="C"; vol_24h=100; change_24h=1; market_cap=999999; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 10
            $snap.gate_stats.mcap_below_1m | Should Be 2
        }

        It "gate_stats conta corretamente age_below_7d" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=1000000; age_days=3; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=3; market_cap=1000000; age_days=8; spread_pct=0.01}
                [PSCustomObject]@{symbol="C"; vol_24h=100; change_24h=1; market_cap=1000000; age_days=6; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 10
            $snap.gate_stats.age_below_7d | Should Be 2
        }

        It "gate_stats conta corretamente vol_below_500k" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100000; change_24h=5; market_cap=1000000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=1000000; change_24h=3; market_cap=1000000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="C"; vol_24h=499999; change_24h=1; market_cap=1000000; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 10
            $snap.gate_stats.vol_below_500k | Should Be 2
        }

        It "gate_stats conta corretamente spread_above_5pct" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=1000000; age_days=100; spread_pct=6.5}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=3; market_cap=1000000; age_days=100; spread_pct=0.02}
                [PSCustomObject]@{symbol="C"; vol_24h=100; change_24h=1; market_cap=1000000; age_days=100; spread_pct=5.1}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 10
            $snap.gate_stats.spread_above_5pct | Should Be 2
        }

        It "snapshot_ts eh um datetime valido" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=1000000; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 10
            $snap.snapshot_ts -is [datetime] | Should Be $true
        }
    }

    Context "edge cases" {
        It "Pairs vazio retorna snapshot vazio sem erro" {
            $snap = Get-UniverseSnapshot -Pairs @() -TopN 10
            $snap.total_pairs | Should Be 0
            $snap.top_long_movers.Count | Should Be 0
            $snap.top_short_movers.Count | Should Be 0
        }

        It "pair com campos null nao quebra" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=$null; change_24h=5; market_cap=1000000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=$null; market_cap=1000000; age_days=100; spread_pct=0.01}
            )
            { Get-UniverseSnapshot -Pairs $pairs -TopN 10 } | Should Not Throw
        }

        It "N maior que total movers retorna o disponivel" {
            $pairs = @(
                [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=1000000; age_days=100; spread_pct=0.01}
                [PSCustomObject]@{symbol="B"; vol_24h=100; change_24h=3; market_cap=1000000; age_days=100; spread_pct=0.01}
            )
            $snap = Get-UniverseSnapshot -Pairs $pairs -TopN 100
            $snap.top_long_movers.Count | Should Be 2
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Get-TopMoversLong
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-TopMoversLong" {

    It "filtra change_24h positivo e ordena desc" {
        $pairs = @(
            [PSCustomObject]@{symbol="A"; change_24h=10}
            [PSCustomObject]@{symbol="B"; change_24h=-5}
            [PSCustomObject]@{symbol="C"; change_24h=20}
        )
        $result = Get-TopMoversLong -Pairs $pairs -N 2
        $result.Count | Should Be 2
        $result[0].change_24h | Should Be 20
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Get-TopMoversShort
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-TopMoversShort" {

    It "filtra change_24h negativo e ordena asc" {
        $pairs = @(
            [PSCustomObject]@{symbol="A"; change_24h=10}
            [PSCustomObject]@{symbol="B"; change_24h=-15}
            [PSCustomObject]@{symbol="C"; change_24h=-3}
        )
        $result = Get-TopMoversShort -Pairs $pairs -N 2
        $result.Count | Should Be 2
        $result[0].change_24h | Should Be -15
    }
}

# ─────────────────────────────────────────────────────────────────────────────
#  Get-UniverseGateStats
# ─────────────────────────────────────────────────────────────────────────────

Describe "Get-UniverseGateStats" {

    It "retorna PSCustomObject com todas as chaves esperadas" {
        $pairs = @(
            [PSCustomObject]@{symbol="A"; vol_24h=100; change_24h=5; market_cap=1000000; age_days=100; spread_pct=0.01}
        )
        $stats = Get-UniverseGateStats -Pairs $pairs
        $stats | Should Not Be $null
        $stats.mcap_below_1m | Should Not Be $null
        $stats.age_below_7d | Should Not Be $null
        $stats.vol_below_500k | Should Not Be $null
        $stats.spread_above_5pct | Should Not Be $null
    }
}
