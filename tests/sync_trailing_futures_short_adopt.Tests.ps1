# tests/sync_trailing_futures_short_adopt.Tests.ps1
# TDD (2026-07-07): Sync-TrailingPositionsWithExchange deve adotar TODA posicao
# FUTURES — inclusive SHORT sem stop (ex.: WLDUSDT sl=0, que ficava fora do
# trailing pelo guard $isManaged pensado so pra holdings passivos SPOT).
#
# Regras:
#  - FUTURES sem stop -> adotada; stop protetivo DIRECIONAL (SHORT acima, LONG abaixo).
#  - SPOT sem SL/TP  -> continua PULADA (holding passivo: PAXG/CET nao viram trailing).
#  - FUTURES/SPOT com stop real -> adotada usando o stop da corretora.
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1")

# No-op: evita chamada real de rede durante os testes
function Send-TelegramAlertFiltered { param([string]$Message, [string]$Tier) }

Describe "Sync-TrailingPositionsWithExchange adota FUTURES (inclusive SHORT sem stop)" {

    BeforeEach {
        $script:testFile = Join-Path $env:TEMP "test_trailing_$(Get-Random).json"
        $global:TRAILING_FILE = $script:testFile
        $global:TRAILING_USE_STATE_STORE = $false
        Save-TrailingPositions @()
    }

    AfterEach {
        Remove-Item -Path $script:testFile -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name TRAILING_FILE -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
        Remove-Item Function:\CoinEx-GetOpenOrders -ErrorAction SilentlyContinue
    }

    Context "FUTURES SHORT sem stop (caso WLDUSDT sl=0)" {

        It "deve adotar como SHORT com stop protetivo ACIMA da entrada" {
            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market            = "WLDUSDT"
                    position_type     = "FUTURES"
                    order_id          = "WLD1"
                    side              = "sell"
                    price             = 0.389701
                    stop_price        = $null
                    take_profit_price = $null
                })
            }

            Sync-TrailingPositionsWithExchange

            $p = @(Get-TrailingPositions | Where-Object { $_.market -eq "WLDUSDT" })
            $p.Count | Should Be 1
            $p[0].side | Should Be "SHORT"
            $p[0].source | Should Be "exchange_sync"
            # Stop protetivo direcional: SHORT -> 5% ACIMA da entrada.
            $p[0].stopCurrent | Should Be ([math]::Round(0.389701 * 1.05, 8))
            ($p[0].stopCurrent -gt $p[0].entry) | Should Be $true
            # Target SHORT abaixo da entrada.
            ($p[0].target -lt $p[0].entry) | Should Be $true
        }
    }

    Context "FUTURES LONG sem stop" {

        It "deve adotar como LONG com stop protetivo ABAIXO da entrada" {
            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market            = "AAVEUSDT"
                    position_type     = "FUTURES"
                    order_id          = "AAVE1"
                    side              = "buy"
                    price             = 100.0
                    stop_price        = $null
                    take_profit_price = $null
                })
            }

            Sync-TrailingPositionsWithExchange

            $p = @(Get-TrailingPositions | Where-Object { $_.market -eq "AAVEUSDT" })
            $p.Count | Should Be 1
            $p[0].side | Should Be "LONG"
            $p[0].stopCurrent | Should Be ([math]::Round(100.0 * 0.95, 8))
            ($p[0].stopCurrent -lt $p[0].entry) | Should Be $true
        }
    }

    Context "SPOT sem SL/TP (holding passivo)" {

        It "deve PULAR — nao registra PAXG/CET passivos" {
            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market            = "PAXGUSDT"
                    position_type     = "SPOT"
                    order_id          = ""
                    side              = "buy"
                    price             = 4520.0
                    stop_price        = $null
                    take_profit_price = $null
                })
            }

            Sync-TrailingPositionsWithExchange

            $p = @(Get-TrailingPositions | Where-Object { $_.market -eq "PAXGUSDT" })
            $p.Count | Should Be 0
        }
    }

    Context "FUTURES com stop real na corretora" {

        It "deve adotar usando o stop da corretora (sem recalcular)" {
            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market            = "WAVESUSDT"
                    position_type     = "FUTURES"
                    order_id          = "WAVES1"
                    side              = "buy"
                    price             = 0.27
                    stop_price        = 0.2452
                    take_profit_price = 0.32
                })
            }

            Sync-TrailingPositionsWithExchange

            $p = @(Get-TrailingPositions | Where-Object { $_.market -eq "WAVESUSDT" })
            $p.Count | Should Be 1
            $p[0].stopCurrent | Should Be 0.2452
            $p[0].target | Should Be 0.32
        }
    }
}
