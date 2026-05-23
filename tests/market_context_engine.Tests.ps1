# market_context_engine.Tests.ps1 -- TDD MCE
# Pester 3.x. UTF-8 BOM.

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "lib_market_context_engine.ps1")

Describe "Get-DowFactor" {
    It "Monday retorna 1.2 (melhor)" {
        $dt = [datetime]"2026-05-18 10:00"   # Monday
        (Get-DowFactor -DateBrt $dt) | Should Be 1.2
    }
    It "Thursday retorna 0.4 (pior)" {
        $dt = [datetime]"2026-05-21 10:00"   # Thursday
        (Get-DowFactor -DateBrt $dt) | Should Be 0.4
    }
    It "Saturday retorna 0.7 (weekend)" {
        $dt = [datetime]"2026-05-16 10:00"   # Saturday
        (Get-DowFactor -DateBrt $dt) | Should Be 0.7
    }
}

Describe "Get-SeasonalFactor" {
    It "Maio retorna 0.5 (Sell in May)" {
        $dt = [datetime]"2026-05-18 10:00"
        (Get-SeasonalFactor -DateBrt $dt) | Should Be 0.5
    }
    It "Novembro retorna 1.5 (melhor mes)" {
        $dt = [datetime]"2026-11-18 10:00"
        (Get-SeasonalFactor -DateBrt $dt) | Should Be 1.5
    }
    It "Setembro retorna 0.4 (pior mes)" {
        $dt = [datetime]"2026-09-18 10:00"
        (Get-SeasonalFactor -DateBrt $dt) | Should Be 0.4
    }
}

Describe "Get-HalvingFactor" {
    It "Mes 13 pos-halving (2025-05-19) retorna 1.5 (blow-off)" {
        $dt = ([datetime]"2024-04-19").AddMonths(13).AddDays(1)   # mes 13
        $f = Get-HalvingFactor -DateBrt $dt
        $f | Should Be 1.5
    }
    It "Mes 22 pos-halving retorna 0.7 (distribuicao)" {
        $dt = ([datetime]"2024-04-19").AddMonths(22).AddDays(1)
        $f = Get-HalvingFactor -DateBrt $dt
        $f | Should Be 0.7
    }
    It "Mes 24 (Maio 2026, atual) retorna 0.7 (distribuicao/topo)" {
        $dt = [datetime]"2026-05-18 10:00"   # Real: 24.93 meses pos-halving (floor 24)
        $f = Get-HalvingFactor -DateBrt $dt
        $f | Should Be 0.7
    }
    It "Mes 3 pos-halving retorna 0.8 (acumulacao)" {
        $dt = [datetime]"2024-07-18 10:00"
        $f = Get-HalvingFactor -DateBrt $dt
        $f | Should Be 0.8
    }
}

Describe "Get-SessionFactor" {
    It "11h BRT (golden hours) retorna 1.0" {
        $dt = [datetime]"2026-05-18 11:00"
        (Get-SessionFactor -DateBrt $dt) | Should Be 1.0
    }
    It "03h BRT (madrugada) retorna 0.4" {
        $dt = [datetime]"2026-05-18 03:00"
        (Get-SessionFactor -DateBrt $dt) | Should Be 0.4
    }
    It "22h BRT (asia open) retorna 0.6" {
        $dt = [datetime]"2026-05-18 22:00"
        (Get-SessionFactor -DateBrt $dt) | Should Be 0.6
    }
}

Describe "Get-MacroEventFactor" {
    It "FOMC day retorna 0.0 (BLOCK)" {
        $dt = [datetime]"2026-06-17 14:00"   # FOMC date
        (Get-MacroEventFactor -DateBrt $dt) | Should Be 0.0
    }
    It "FOMC day +1 retorna 0.0 (still blocked)" {
        $dt = [datetime]"2026-06-18 14:00"
        (Get-MacroEventFactor -DateBrt $dt) | Should Be 0.0
    }
    It "Dia normal retorna 1.0" {
        $dt = [datetime]"2026-05-20 11:00"   # Wednesday random
        (Get-MacroEventFactor -DateBrt $dt) | Should Be 1.0
    }
}

Describe "Get-RegimeFactor" {
    It "BULL_STRONG retorna 1.5" {
        (Get-RegimeFactor -Regime "BULL_STRONG") | Should Be 1.5
    }
    It "BEAR_WEAK retorna 0.2" {
        (Get-RegimeFactor -Regime "BEAR_WEAK") | Should Be 0.2
    }
    It "regime null/desconhecido retorna 0.5 (defensivo)" {
        (Get-RegimeFactor -Regime $null) | Should Be 0.5
        (Get-RegimeFactor -Regime "XYZ") | Should Be 0.5
    }
}

Describe "Get-ContextScore" {
    It "produto correto: Mon May 11h BULL_STRONG (mes 24 atual) = 0.63" {
        $dt = [datetime]"2026-05-18 11:00"
        $r = Get-ContextScore -DateBrt $dt -Regime "BULL_STRONG"
        # dow=1.2 x season=0.5 x halving=0.7 x session=1.0 x macro=1.0 x regime=1.5 = 0.63
        $r.score | Should Be 0.63
    }
    It "Mon Nov 11h BULL_STRONG mes 18 ideal = altissimo" {
        $dt = ([datetime]"2024-04-19").AddMonths(18)   # Out 2025
        # forca segunda 11h
        while ($dt.DayOfWeek -ne "Monday") { $dt = $dt.AddDays(1) }
        $dt = $dt.Date.AddHours(11)
        $r = Get-ContextScore -DateBrt $dt -Regime "BULL_STRONG"
        $r.score | Should BeGreaterThan 1.0
    }
    It "FOMC day forca score 0 mesmo se outros factors bons" {
        $dt = [datetime]"2026-06-17 11:00"  # Wed Jun FOMC
        $r = Get-ContextScore -DateBrt $dt -Regime "BULL_STRONG"
        $r.score | Should Be 0.0
    }
}

Describe "Test-ContextAllowsTrade" {
    It "Mon May 11h BULL_STRONG (mes 25 atual) -> PAPER_ONLY (defensivo)" {
        $dt = [datetime]"2026-05-18 11:00"
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_STRONG"
        $r.action -in @("PAPER_ONLY","LIVE_REDUCED") | Should Be $true
    }
    It "score <0.20 -> action=BLOCK" {
        $dt = [datetime]"2026-05-21 03:00"   # Thu 03h May (worst)
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BEAR_WEAK"
        $r.action | Should Be "BLOCK"
    }
    It "score >=1.0 -> action=LIVE_FULL (cenario ideal Nov bull blow-off)" {
        $dt = ([datetime]"2024-04-19").AddMonths(18)
        while ($dt.DayOfWeek -ne "Monday") { $dt = $dt.AddDays(1) }
        $dt = $dt.Date.AddHours(11)
        $r = Test-ContextAllowsTrade -DateBrt $dt -Regime "BULL_STRONG"
        $r.action | Should Be "LIVE_FULL"
    }
}
