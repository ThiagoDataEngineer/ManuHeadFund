# lib_position_protection_source_instrumentation.Tests.ps1 -- TDD 2026-08-04.
#
# Owner pediu (apos estudar o Evolution Engine junto) instrumentacao de
# sl_source/tp_source/stop_pct_used ANTES de qualquer auto-calibragem --
# hoje impossivel medir se stop fixo por Mode ou pivot estrutural
# (Get-StructuralStopTarget) rende melhor, porque a origem real (fixed_pct
# vs structural) so ia pro Write-Verbose e se perdia. Este teste cobre o
# ramo de Repair-PositionProtection que persiste no journal (EnableTrailing
# $true), que os testes existentes (target_mode) nunca exercitam
# (EnableTrailing sempre $false la).
#
# Pester 3.4 / ASCII-only. Isola $global:JOURNAL_DIR (ver
# feedback_test_isolation_leaks_to_real_production_file -- nunca reusar o
# journal real desta maquina).

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

. (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
. (Join-Path $agentsDir "lib_position_protection.ps1")

# Mocks DEPOIS do dot-source (mesmo padrao ja documentado em
# lib_position_protection_target_mode.Tests.ps1 -- mock ANTES seria
# sobrescrito pela definicao real).
function CoinEx-GetPendingPositions {
    param([string]$Market)
    @([PSCustomObject]@{ avg_entry_price = 100.0; side = "long" })
}
function Get-MarketPrecision { param($Market, $MarketType) [PSCustomObject]@{ quote_ccy_precision = 4 } }
function Set-PositionProtection {
    param($Market, $StopLoss, $TakeProfit, $MaxRetries)
    [PSCustomObject]@{ success = $true; sl_set = $true; tp_set = $true; reason = "protected" }
}

Describe "Repair-PositionProtection -- instrumentacao sl_source/tp_source/stop_pct_used no journal" {

    $script:prevJournalDir = $global:JOURNAL_DIR

    BeforeEach {
        $script:tmp = Join-Path $env:TEMP ("pp_instr_$([guid]::NewGuid())")
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $global:JOURNAL_DIR = $tmp
    }

    AfterEach {
        $global:JOURNAL_DIR = $script:prevJournalDir
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "sem pivot estrutural (candles vazios) -- grava sl_source=fixed_pct e stop_pct_used correto" {
        function CoinEx-GetFuturesCandles { param($Market, $Period, $Limit) @() }
        function Get-TrailingPositions { @() }

        $tpPath = Join-Path $tmp "trailing_positions.json"
        @([PSCustomObject]@{ market = "TESTUSDT"; active = $true; stop = 0; target = 0 }) `
            | ConvertTo-Json -Depth 6 | Set-Content $tpPath -Encoding utf8

        $r = Repair-PositionProtection -Market "TESTUSDT" -StopPct 0.08 -TargetPct 0.32 -EnableTrailing $true
        $r.success | Should Be $true

        $saved = (Get-Content $tpPath -Raw | ConvertFrom-Json)[0]
        $saved.sl_source | Should Be "fixed_pct"
        $saved.tp_source | Should Be "fixed_pct"
        # LONG entry=100, StopPct=0.08 -> stop=92, stop_pct_used=(100-92)/100=0.08
        [math]::Round([double]$saved.stop_pct_used, 4) | Should Be 0.08
    }

    It "com pivot estrutural achado -- grava tp_source=structural (fixture so tem resistencia perto, nao suporte)" {
        # Mesmo formato de candles ja usado em lib_position_protection_target_mode.Tests.ps1
        # (resistencia proxima o suficiente em 120 pra Get-StructuralStopTarget
        # aceitar como TP; nao ha suporte proximo o suficiente abaixo de 100
        # nesta fixture, entao sl_source fica fixed_pct -- confirmado rodando
        # Get-StructuralStopTarget direto com os mesmos candles).
        function CoinEx-GetFuturesCandles {
            param($Market, $Period, $Limit)
            $candles = @()
            for ($i = 0; $i -lt 13; $i++) {
                $p = 84 + ($i * 1.0)
                $candles += [PSCustomObject]@{ open=$p; high=($p+1); low=($p-0.5); close=($p+0.5); volume=1000 }
            }
            $candles += [PSCustomObject]@{ open=97;   high=98;   low=97;   close=97.5; volume=1000 }
            $candles += [PSCustomObject]@{ open=97;   high=97.5; low=96;   close=96.5; volume=1000 }
            $candles += [PSCustomObject]@{ open=96.5; high=98;   low=96;   close=97.5; volume=1000 }
            $candles += [PSCustomObject]@{ open=98;    high=101; low=98;   close=100;   volume=1000 }
            $candles += [PSCustomObject]@{ open=100;   high=102; low=99;   close=100.5; volume=1000 }
            $candles += [PSCustomObject]@{ open=100.5; high=101; low=99.5; close=100;   volume=1000 }
            $candles += [PSCustomObject]@{ open=100; high=101; low=99;  close=100; volume=1000 }
            $candles += [PSCustomObject]@{ open=100; high=115; low=99;  close=110; volume=1000 }
            $candles += [PSCustomObject]@{ open=110; high=120; low=109; close=118; volume=1000 }
            $candles += [PSCustomObject]@{ open=118; high=119; low=100; close=101; volume=1000 }
            for ($i = 0; $i -lt 4; $i++) {
                $candles += [PSCustomObject]@{ open=100; high=100.5; low=99.5; close=100; volume=1000 }
            }
            return $candles
        }
        function Get-TrailingPositions { @() }

        $tpPath = Join-Path $tmp "trailing_positions.json"
        @([PSCustomObject]@{ market = "TESTUSDT"; active = $true; stop = 0; target = 0 }) `
            | ConvertTo-Json -Depth 6 | Set-Content $tpPath -Encoding utf8

        $r = Repair-PositionProtection -Market "TESTUSDT" -StopPct 0.08 -TargetPct 0.32 -EnableTrailing $true
        $r.success | Should Be $true

        $saved = (Get-Content $tpPath -Raw | ConvertFrom-Json)[0]
        $saved.sl_source | Should Be "fixed_pct"
        $saved.tp_source | Should Be "structural"
        $saved.PSObject.Properties['stop_pct_used'] | Should Not BeNullOrEmpty
    }

    It "registro pre-existente SEM os campos novos (posicao antiga) nao quebra -- Add-Member -Force cobre" {
        function CoinEx-GetFuturesCandles { param($Market, $Period, $Limit) @() }
        function Get-TrailingPositions { @() }

        $tpPath = Join-Path $tmp "trailing_positions.json"
        # Simula registro legado: sem sl_source/tp_source/stop_pct_used (campos
        # nao existiam antes deste fix).
        '[{"market":"TESTUSDT","active":true,"stop":0,"target":0}]' | Set-Content $tpPath -Encoding utf8

        { Repair-PositionProtection -Market "TESTUSDT" -StopPct 0.08 -TargetPct 0.32 -EnableTrailing $true } | Should Not Throw

        $saved = (Get-Content $tpPath -Raw | ConvertFrom-Json)[0]
        $saved.sl_source | Should Be "fixed_pct"
    }
}
