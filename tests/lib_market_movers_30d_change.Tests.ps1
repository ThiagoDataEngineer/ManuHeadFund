# lib_market_movers_30d_change.Tests.ps1 -- TDD calculo de change_30d
#
# CoinEx nao expoe "variacao 30 dias" nativa no ticker (so 24h). Get-Market30dChangeFromCandles
# calcula isso a partir de candles DIARIOS ja buscados (CoinEx-GetCandles -period "1d" -limit 31)
# -- separa o calculo puro (testavel sem rede) do fetch real (I/O).

$agentsDir = Join-Path (Split-Path -Parent $PSScriptRoot) "agents"
. (Join-Path $agentsDir "lib_market_movers.ps1")

function New-Candle {
    param([long]$Ts, [double]$Close)
    [PSCustomObject]@{ ts = $Ts; close = $Close }
}

Describe "Get-Market30dChangeFromCandles -- calculo puro (sem rede)" {

    It "calcula variacao percentual entre o candle mais antigo e o mais recente" {
        $candles = @(
            (New-Candle -Ts 1000 -Close 100)   # 30 dias atras
            (New-Candle -Ts 2000 -Close 150)   # hoje
        )
        $result = Get-Market30dChangeFromCandles -Candles $candles
        $result | Should Be 50.0
    }

    It "calcula queda (numero negativo)" {
        $candles = @(
            (New-Candle -Ts 1000 -Close 200)
            (New-Candle -Ts 2000 -Close 140)
        )
        $result = Get-Market30dChangeFromCandles -Candles $candles
        $result | Should Be -30
    }

    It "ordena por ts antes de calcular (candles fora de ordem)" {
        $candles = @(
            (New-Candle -Ts 2000 -Close 150)   # mais recente vem primeiro no array
            (New-Candle -Ts 1000 -Close 100)   # mais antigo vem depois
        )
        $result = Get-Market30dChangeFromCandles -Candles $candles
        $result | Should Be 50.0
    }

    It "usa so o primeiro e ultimo candle quando ha varios no meio" {
        $candles = @(
            (New-Candle -Ts 1000 -Close 100)
            (New-Candle -Ts 1500 -Close 999)   # ruido no meio, nao deve afetar
            (New-Candle -Ts 2000 -Close 120)
        )
        $result = Get-Market30dChangeFromCandles -Candles $candles
        $result | Should Be 20.0
    }

    It "retorna 0 com menos de 2 candles (nao quebra)" {
        (Get-Market30dChangeFromCandles -Candles @()) | Should Be 0
        (Get-Market30dChangeFromCandles -Candles @((New-Candle -Ts 1000 -Close 100))) | Should Be 0
    }

    It "retorna 0 se o candle mais antigo tem close=0 (evita divisao por zero)" {
        $candles = @(
            (New-Candle -Ts 1000 -Close 0)
            (New-Candle -Ts 2000 -Close 150)
        )
        $result = Get-Market30dChangeFromCandles -Candles $candles
        $result | Should Be 0
    }
}
