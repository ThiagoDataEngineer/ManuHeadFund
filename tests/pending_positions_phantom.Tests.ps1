# pending_positions_phantom.Tests.ps1 -- TDD do bug "Market empty" (quebra a nuvem)
# CoinEx-GetPendingPositions devolvia 1 posicao-fantasma vazia (market=null) quando
# nao ha posicoes -> todo consumidor que itera .market estourava
# ("Cannot bind argument to parameter 'Market'"). Fix: filtrar entradas sem market.
# Pester 3.4 / ASCII-only.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"

Describe "CoinEx-GetPendingPositions - filtra fantasmas" {

    Context "Data com entrada vazia (causa do bug)" {

        It "filtra elemento sem market (fantasma)" {
            Mock CoinEx-Get { @{ code = 0; data = @(
                [PSCustomObject]@{ market = ""; side = $null; mark_price = $null },
                [PSCustomObject]@{ market = "HYPEUSDT"; side = "long"; mark_price = 70 }
            ) } }
            $r = @(CoinEx-GetPendingPositions)
            $r.Count | Should Be 1
            $r[0].market | Should Be "HYPEUSDT"
        }

        It "data so com fantasma = array vazio (nao quebra consumidor)" {
            Mock CoinEx-Get { @{ code = 0; data = @([PSCustomObject]@{ market = $null }) } }
            $r = @(CoinEx-GetPendingPositions)
            $r.Count | Should Be 0
        }
    }

    Context "Casos normais preservados" {

        It "2 posicoes validas = retorna as 2" {
            Mock CoinEx-Get { @{ code = 0; data = @(
                [PSCustomObject]@{ market = "BTCUSDT"; side = "long" },
                [PSCustomObject]@{ market = "ETHUSDT"; side = "short" }
            ) } }
            $r = @(CoinEx-GetPendingPositions)
            $r.Count | Should Be 2
        }

        It "data vazio = 0" {
            Mock CoinEx-Get { @{ code = 0; data = @() } }
            (@(CoinEx-GetPendingPositions)).Count | Should Be 0
        }

        It "code != 0 = 0" {
            Mock CoinEx-Get { @{ code = 1; message = "erro" } }
            (@(CoinEx-GetPendingPositions)).Count | Should Be 0
        }
    }

    Context "Nenhuma posicao com market vazio sobrevive (garantia p/ consumidores)" {

        It "todas as retornadas tem market nao-vazio" {
            Mock CoinEx-Get { @{ code = 0; data = @(
                [PSCustomObject]@{ market = "" },
                [PSCustomObject]@{ market = "SUIUSDT" },
                [PSCustomObject]@{ market = $null }
            ) } }
            $r = @(CoinEx-GetPendingPositions)
            ($r | Where-Object { -not $_.market }).Count | Should Be 0
        }
    }

    Context "2026-08-04 FIX CRITICO: paginacao default da CoinEx truncava posicoes (SOLUSDT achado real)" {

        It "chama pending-position com limit explicito (nao usa default da API)" {
            Mock CoinEx-Get { @{ code = 0; data = @() } } -ParameterFilter { $Path -like "*limit=*" }
            Mock CoinEx-Get { throw "chamada sem limit explicito -- regressao do bug de truncamento" }
            CoinEx-GetPendingPositions | Out-Null
            Assert-MockCalled CoinEx-Get -Times 1 -ParameterFilter { $Path -like "*limit=*" }
        }

        It "com 11 posicoes retornadas pela API (alem do default de 10), todas sobrevivem" {
            $onze = 1..11 | ForEach-Object { [PSCustomObject]@{ market = "COIN${_}USDT"; side = "short" } }
            Mock CoinEx-Get { @{ code = 0; data = $onze } } -ParameterFilter { $Path -like "*pending-position*" }
            $r = @(CoinEx-GetPendingPositions)
            $r.Count | Should Be 11
            ($r | Where-Object { $_.market -eq "COIN11USDT" }).Count | Should Be 1
        }
    }
}
