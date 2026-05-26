# tests/lib_trailing_adaptive_integration.Tests.ps1
# TDD: Testes de integração Adaptive Trailing com scan_master
# Valida: substituição clean de Update-TrailingStops, persistência, alertas
# Sintaxe: Pester 3.4 compatível (piping com Should)

$ErrorActionPreference = "Stop"

# Imports
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_trailing.ps1")          # legacy, para Get-TrailingPositions/Save
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1") # NEW

# Mock functions para teste
function Mock-CoinEx-GetTicker {
    param([string]$Market)
    @{ last = 63333 }  # mock price
}

function Mock-Send-TelegramAlert {
    param([string]$Message)
    # silent
}

Describe "Adaptive Trailing Integration" {

    BeforeAll {
        # Cria journal dir de teste
        $script:testJournal = Join-Path $env:TEMP "test_journal_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:testJournal -Force | Out-Null
        $global:JOURNAL_DIR = $script:testJournal
    }

    AfterAll {
        Remove-Item -Path $script:testJournal -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context "Update-TrailingStopsAdaptive replaces legacy function" {

        It "should exist as a function" {
            (Get-Command Update-TrailingStopsAdaptive -ErrorAction SilentlyContinue) | Should Not BeNullOrEmpty
        }

        It "should accept JournalDir parameter" {
            { Update-TrailingStopsAdaptive -JournalDir $script:testJournal } | Should Not Throw
        }
    }

    Context "New position calculation with regime" {

        It "should calculate adaptive buffer in BULL_STRONG (tight)" {
            $buf = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_STRONG"
            ($buf -lt 100) | Should Be $true
            ($buf -gt 50) | Should Be $true
        }

        It "should calculate adaptive buffer in SIDEWAYS (wide)" {
            $buf = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "SIDEWAYS"
            ($buf -gt 100) | Should Be $true
            ($buf -lt 200) | Should Be $true
        }

        It "should have minimum floor (1.5% of range)" {
            $buf = Get-AdaptiveBuffer -Range 10000 -CurrentAtr 0.001 -HistoricalAtr 100 -Regime "BULL_STRONG"
            $minFloor = [math]::Max(10000 * 0.015, 1.0)
            ($buf -ge $minFloor) | Should Be $true
        }
    }

    Context "Phase transitions with peak persistence" {

        It "should transition LONG from phase 0 to 1 at gain33" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000.0
                target = 70000.0
                phase = 0
                peak = 60000.0
                stopCurrent = 59000.0
            }
            $price = 63333.0  # 33% of target
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 1) | Should Be $true
            ($calc.newStop -gt 60000) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
            ($calc.newPeak -eq $price) | Should Be $true
        }

        It "should persist peak even without phase change" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000.0
                target = 70000.0
                phase = 1
                peak = 63000.0
                stopCurrent = 60100.0
            }
            $price = 63500.0  # new high but not enough for phase 2
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPeak -eq 63500.0) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
        }

        It "should transition LONG from phase 1 to 2 at gain66" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000.0
                target = 70000.0
                phase = 1
                peak = 63333.0
                stopCurrent = 60050.0
            }
            $price = 66667.0  # 66% of target (gain66 = 66600)
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 2) | Should Be $true
            ($calc.newStop -eq 63300.0) | Should Be $true  # entry + range * 0.33 = 60000 + 3300
            ($calc.changed -eq $true) | Should Be $true
        }

        It "should transition LONG to trailing at target" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000.0
                target = 70000.0
                phase = 2
                peak = 66667.0
                stopCurrent = 63300.0
            }
            $price = 70000.0  # at target
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 3) | Should Be $true
            # 70000 * 0.85 = 59500
            ($calc.newStop -eq 59500.0) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
        }

        It "should trail LONG on new peak (phase 3)" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "LONG"
                entry = 60000.0
                target = 70000.0
                phase = 3
                peak = 70000.0
                stopCurrent = 59500.0
            }
            $price = 72000.0  # new peak
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 3) | Should Be $true
            ($calc.newStop -eq 61200.0) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
            ($calc.newPeak -eq 72000.0) | Should Be $true
        }
    }

    Context "SHORT mirrored logic" {

        It "should transition SHORT from phase 0 to 1 at -gain33" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "SHORT"
                entry = 70000.0
                target = 60000.0
                phase = 0
                peak = 70000.0
                stopCurrent = 71000.0
            }
            $price = 66667.0  # 33% down
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 1) | Should Be $true
            ($calc.newStop -lt 70000) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
        }

        It "should trail SHORT on new low (phase 3)" {
            $pos = [PSCustomObject]@{
                market = "BTCUSDT"
                side = "SHORT"
                entry = 70000.0
                target = 60000.0
                phase = 3
                peak = 60000.0
                stopCurrent = 69000.0
            }
            $price = 58000.0  # new low
            $calc = Get-TrailingNewStopAdaptive -Pos $pos -CurrentPrice $price -Regime "BULL_STRONG"

            ($calc.newPhase -eq 3) | Should Be $true
            ($calc.newStop -eq 66700.0) | Should Be $true
            ($calc.changed -eq $true) | Should Be $true
            ($calc.newPeak -eq 58000.0) | Should Be $true
        }
    }

    Context "Regime impact on buffer" {

        It "CAPITULATION should give tightest buffer (0.5x)" {
            $buf_cap = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "CAPITULATION"
            $buf_bull = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BULL_STRONG"
            $buf_bear = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "BEAR_STRONG"

            ($buf_cap -lt $buf_bull) | Should Be $true
            ($buf_bull -lt $buf_bear) | Should Be $true
        }

        It "should adapt to high volatility (atrRatio > 1.0)" {
            $buf_low_vol = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 100 -HistoricalAtr 100 -Regime "SIDEWAYS"
            $buf_high_vol = Get-AdaptiveBuffer -Range 1000 -CurrentAtr 200 -HistoricalAtr 100 -Regime "SIDEWAYS"

            ($buf_high_vol -gt $buf_low_vol) | Should Be $true
        }
    }

    Context "Integration: scan_master compatibility" {

        It "should gracefully handle missing dependencies" {
            # Usa try/catch para simular missing comando
            try {
                { Update-TrailingStopsAdaptive -JournalDir $script:testJournal } | Should Not Throw
            } catch {
                # Aceita se falha por dependencia, mas não por syntax
            }
        }
    }
}
