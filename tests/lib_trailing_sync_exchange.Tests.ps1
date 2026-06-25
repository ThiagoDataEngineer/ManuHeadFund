# tests/lib_trailing_sync_exchange.Tests.ps1
# TDD: Sync-TrailingPositionsWithExchange nao deve duplicar posicao quando
# orderId rotaciona (stop antigo fechado -> reentrada com novo stop).
#
# Caso real que motivou o fix (2026-06-25): ZANOUSDT tinha um registro GEM
# fechado por stop ("stop_atingido", active=false, orderId antigo). Quando a
# corretora mostrou uma nova ordem aberta no mesmo market com orderId
# diferente, o match antigo (market+orderId) falhava e o sync criava um
# segundo registro "exchange_sync" fantasma (sem pk_id) para o MESMO market,
# quebrando o upsert Supabase (pk_id=market) e deixando a posicao real
# mal gerenciada.
#
# Pester 3.4 compativel.

$ErrorActionPreference = "Stop"

$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1")

# No-op: evita chamada real de rede durante os testes
function Send-TelegramAlertFiltered { param([string]$Message, [string]$Tier) }

Describe "Sync-TrailingPositionsWithExchange dedup" {

    BeforeEach {
        $script:testFile = Join-Path $env:TEMP "test_trailing_$(Get-Random).json"
        $global:TRAILING_FILE = $script:testFile
        $global:TRAILING_USE_STATE_STORE = $false
    }

    AfterEach {
        Remove-Item -Path $script:testFile -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name TRAILING_FILE -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name TRAILING_USE_STATE_STORE -Scope Global -ErrorAction SilentlyContinue
        Remove-Item Function:\CoinEx-GetOpenOrders -ErrorAction SilentlyContinue
    }

    Context "Posicao fechada (stop_atingido) reabre na exchange com novo orderId" {

        It "deve REATIVAR o registro existente em vez de criar duplicata" {
            $closed = [PSCustomObject]@{
                pk_id        = "ZANOUSDT"
                market       = "ZANOUSDT"
                side         = "LONG"
                entry        = 10.3505
                stop         = 10.1435
                target       = 11.3856
                orderId      = "OLD_ORDER_1"
                source       = "gem"
                mode         = "GEM"
                max_days     = 14
                dd_threshold_pct = 40.0
                phase        = 0
                peak         = 10.3505
                stopCurrent  = 10.1435
                active       = $false
                openedAt     = "2026-06-24 20:21:22"
                updatedAt    = "2026-06-24 20:21:22"
                closedAt     = "2026-06-25 00:42:10"
                closeReason  = "stop_atingido"
                exitPrice    = $null
            }
            Save-TrailingPositions @($closed)

            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market             = "ZANOUSDT"
                    order_id           = "NEW_ORDER_2"
                    side               = "buy"
                    price              = 10.2459
                    stop_price         = 9.5126
                    take_profit_price  = 10.758195
                })
            }

            Sync-TrailingPositionsWithExchange

            $positions = @(Get-TrailingPositions | Where-Object { $_.market -eq "ZANOUSDT" })
            $positions.Count | Should Be 1
            $positions[0].active | Should Be $true
            $positions[0].orderId | Should Be "NEW_ORDER_2"
            $positions[0].closeReason | Should Be $null
            $positions[0].stopCurrent | Should Be 9.5126
        }
    }

    Context "Posicao ativa com stop substituido manualmente (orderId muda, active permanece true)" {

        It "deve atualizar o registro existente sem duplicar" {
            $active = [PSCustomObject]@{
                market      = "BTCUSDT"
                side        = "LONG"
                entry       = 60000
                orderId     = "OLD_STOP_ORDER"
                phase       = 0
                peak        = 60000
                stopCurrent = 58000
                target      = 66000
                active      = $true
                openedAt    = "2026-06-24 10:00:00"
                updatedAt   = "2026-06-24 10:00:00"
            }
            Save-TrailingPositions @($active)

            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market             = "BTCUSDT"
                    order_id           = "REPLACED_STOP_ORDER"
                    side               = "buy"
                    price              = 60000
                    stop_price         = 59000
                    take_profit_price  = 66000
                })
            }

            Sync-TrailingPositionsWithExchange

            $positions = @(Get-TrailingPositions | Where-Object { $_.market -eq "BTCUSDT" })
            $positions.Count | Should Be 1
            $positions[0].orderId | Should Be "REPLACED_STOP_ORDER"
            $positions[0].stopCurrent | Should Be 59000
        }
    }

    Context "Mercado novo sem registro previo" {

        It "deve criar exatamente uma entrada nova quando gerenciada (tem SL/TP)" {
            Save-TrailingPositions @()

            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market             = "SOLUSDT"
                    order_id           = "FIRST_ORDER"
                    side               = "buy"
                    price              = 150
                    stop_price         = 142
                    take_profit_price  = 165
                })
            }

            Sync-TrailingPositionsWithExchange

            $positions = @(Get-TrailingPositions | Where-Object { $_.market -eq "SOLUSDT" })
            $positions.Count | Should Be 1
            $positions[0].source | Should Be "exchange_sync"
        }
    }

    Context "Moon bag leg presente nao deve ser confundida com a posicao primaria" {

        It "deve criar a entrada primaria separada da leg de moon bag" {
            $moonLeg = [PSCustomObject]@{
                market      = "LINKUSDT"
                side        = "LONG"
                entry       = 13.0
                orderId     = ""
                phase       = 3
                peak        = 14.0
                stopCurrent = 13.5
                target      = 20.0
                active      = $true
                moonBagKind = "moon"
                openedAt    = "2026-06-20 10:00:00"
                updatedAt   = "2026-06-20 10:00:00"
            }
            Save-TrailingPositions @($moonLeg)

            function CoinEx-GetOpenOrders {
                @([PSCustomObject]@{
                    market             = "LINKUSDT"
                    order_id           = "NEW_PRIMARY_ORDER"
                    side               = "buy"
                    price              = 13.2
                    stop_price         = 12.5
                    take_profit_price  = 16.0
                })
            }

            Sync-TrailingPositionsWithExchange

            $positions = @(Get-TrailingPositions | Where-Object { $_.market -eq "LINKUSDT" })
            $positions.Count | Should Be 2
            ($positions | Where-Object { $_.moonBagKind -eq "moon" }).Count | Should Be 1
            ($positions | Where-Object { -not $_.moonBagKind }).Count | Should Be 1
        }
    }
}
