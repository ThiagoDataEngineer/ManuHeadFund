# count_transition_up_mon_progress.Tests.ps1 - Pester 3.x - TDD strict
#
# PHASE 1 - RED: 15 testes escritos ANTES da implementacao.
#
# Cobertura:
#   - Test-DayIsMondayBRT (UTC -> BRT conversion, edge cases)
#   - Get-TransitionUpMonTrades (filtro regime + direction + DoW + SinceDate)
#   - Measure-SubsetupMetrics (exp, pf, wr, lista vazia)
#   - Format-ProgressReport (status VIABLE / NEEDS_MORE_DATA, missing count)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$here\..\scripts\count_transition_up_mon_progress.ps1"

function Write-Host { param($Object, $ForegroundColor) }
function Write-Warning { param($Message) }

function New-FakeTrade {
    param(
        [string]$EntryTs = "2024-06-17T12:00:00+00:00",   # Mon 12:00 UTC = Mon 09:00 BRT
        [string]$Regime = "TRANSITION_UP",
        [string]$Direction = "LONG",
        [double]$ResultR = 1.0
    )
    [PSCustomObject]@{
        entry_ts  = $EntryTs
        regime    = $Regime
        direction = $Direction
        result_r  = $ResultR
    }
}

# ============================================================================
# GRUPO A - Test-DayIsMondayBRT (edge cases UTC -> BRT)
# ============================================================================

Describe "Test-DayIsMondayBRT - casos basicos" {
    It "T1 retorna true para Mon 12:00 UTC (Mon 09:00 BRT)" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-17T12:00:00+00:00") | Should Be $true
    }
    It "T2 retorna false para Tue 12:00 UTC (Tue 09:00 BRT)" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-18T12:00:00+00:00") | Should Be $false
    }
    It "T3 retorna false para Sun 12:00 UTC (Sun 09:00 BRT)" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-16T12:00:00+00:00") | Should Be $false
    }
}

Describe "Test-DayIsMondayBRT - edges UTC/BRT" {
    It "T4 Mon 02:00 UTC = Sun 23:00 BRT -> false" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-17T02:00:00+00:00") | Should Be $false
    }
    It "T5 Tue 02:00 UTC = Mon 23:00 BRT -> true" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-18T02:00:00+00:00") | Should Be $true
    }
    It "T6 Mon 03:00 UTC = Mon 00:00 BRT -> true" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-17T03:00:00+00:00") | Should Be $true
    }
    It "T7 Aceita formato Z (UTC explicito)" {
        (Test-DayIsMondayBRT -Timestamp "2024-06-17T12:00:00Z") | Should Be $true
    }
}

# ============================================================================
# GRUPO B - Get-TransitionUpMonTrades
# ============================================================================

Describe "Get-TransitionUpMonTrades - filtros" {
    It "T8 inclui apenas regime TRANSITION_UP" {
        $trades = @(
            (New-FakeTrade -Regime "TRANSITION_UP"),
            (New-FakeTrade -Regime "BULL_STRONG"),
            (New-FakeTrade -Regime "BEAR_WEAK")
        )
        $r = @(Get-TransitionUpMonTrades -Trades $trades)
        $r.Count | Should Be 1
        $r[0].regime | Should Be "TRANSITION_UP"
    }

    It "T9 inclui apenas direction LONG (exclui SHORT)" {
        $trades = @(
            (New-FakeTrade -Direction "LONG"),
            (New-FakeTrade -Direction "SHORT")
        )
        $r = @(Get-TransitionUpMonTrades -Trades $trades)
        $r.Count | Should Be 1
        $r[0].direction | Should Be "LONG"
    }

    It "T10 inclui apenas trades em Mon BRT" {
        $trades = @(
            (New-FakeTrade -EntryTs "2024-06-17T12:00:00+00:00"),  # Mon BRT
            (New-FakeTrade -EntryTs "2024-06-18T12:00:00+00:00"),  # Tue BRT
            (New-FakeTrade -EntryTs "2024-06-18T02:00:00+00:00")   # Mon 23h BRT (Tue 02h UTC)
        )
        $r = @(Get-TransitionUpMonTrades -Trades $trades)
        $r.Count | Should Be 2
    }

    It "T11 SinceDate filtra trades anteriores" {
        $trades = @(
            (New-FakeTrade -EntryTs "2022-06-20T12:00:00+00:00"),  # Mon 2022
            (New-FakeTrade -EntryTs "2024-06-17T12:00:00+00:00")   # Mon 2024
        )
        $since = [DateTime]::Parse("2023-01-01T00:00:00Z").ToUniversalTime()
        $r = @(Get-TransitionUpMonTrades -Trades $trades -SinceDate $since)
        $r.Count | Should Be 1
        $r[0].entry_ts | Should Be "2024-06-17T12:00:00+00:00"
    }
}

# ============================================================================
# GRUPO C - Measure-SubsetupMetrics
# ============================================================================

Describe "Measure-SubsetupMetrics - calculos" {
    It "T12 lista vazia retorna zeros" {
        $m = Measure-SubsetupMetrics -Trades @()
        $m.trades | Should Be 0
        $m.exp | Should Be 0
        $m.pf | Should Be 0
        $m.wr | Should Be 0
    }

    It "T13 calcula exp como media dos result_r" {
        $trades = @(
            (New-FakeTrade -ResultR 1.0),
            (New-FakeTrade -ResultR 2.0),
            (New-FakeTrade -ResultR -1.0)
        )
        $m = Measure-SubsetupMetrics -Trades $trades
        $m.trades | Should Be 3
        # mean = (1+2-1)/3 = 0.6667
        ($m.exp) | Should BeGreaterThan 0.66
        ($m.exp) | Should BeLessThan 0.67
    }

    It "T14 calcula pf como gross_profit / gross_loss" {
        $trades = @(
            (New-FakeTrade -ResultR 2.0),
            (New-FakeTrade -ResultR 3.0),
            (New-FakeTrade -ResultR -1.0)
        )
        $m = Measure-SubsetupMetrics -Trades $trades
        # gp = 5, gl = 1, pf = 5
        $m.pf | Should Be 5
    }
}

# ============================================================================
# GRUPO D - Format-ProgressReport
# ============================================================================

Describe "Format-ProgressReport - status e missing" {
    It "T15 status VIABLE quando count >= target" {
        $metrics = [PSCustomObject]@{ trades=30; exp=1.0; pf=2.0; wr=60.0 }
        $r = Format-ProgressReport -Count 30 -Target 30 -Metrics $metrics
        $r.status | Should Be "VIABLE"
        $r.missing | Should Be 0
    }

    It "T16 status NEEDS_MORE_DATA quando count < target" {
        $metrics = [PSCustomObject]@{ trades=25; exp=0.98; pf=2.5; wr=58.0 }
        $r = Format-ProgressReport -Count 25 -Target 30 -Metrics $metrics
        $r.status | Should Be "NEEDS_MORE_DATA"
        $r.missing | Should Be 5
    }

    It "T17 missing eh max(0, target - count)" {
        $metrics = [PSCustomObject]@{ trades=50; exp=1.0; pf=2.0; wr=60.0 }
        $r = Format-ProgressReport -Count 50 -Target 30 -Metrics $metrics
        $r.missing | Should Be 0
    }
}
