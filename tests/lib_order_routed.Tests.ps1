# lib_order_routed.Tests.ps1 -- TDD pra Invoke-OrderRouted (spot vs futures unified).
# Pester 3.x.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentsDir = Join-Path (Split-Path $here -Parent) "agents"

# Mock CoinEx functions BEFORE dot-source
$script:lastCallPlaceFutures = $null
$script:lastCallPlaceSpot = $null

function CoinEx-PlaceOrder { param($market, $side, $type, $amount, $price=$null, $stopLoss=$null, $takeProfit=$null, [string]$StpMode = "ct")
    $script:lastCallPlaceFutures = @{
        market=$market; side=$side; type=$type; amount=$amount; price=$price
        stopLoss=$stopLoss; takeProfit=$takeProfit
    }
    return @{ order_id = "FUT123"; market = $market }
}
function CoinEx-PlaceSpotOrder {
    param($Market, $Side, $Type, $Amount, $Price=0, $QuoteAmountUsd=0, $StpMode="ct")
    $script:lastCallPlaceSpot = @{
        market=$Market; side=$Side; type=$Type; amount=$Amount
        price=$Price; quote=$QuoteAmountUsd
    }
    return @{ order_id = "SPOT456"; market = $Market }
}

. (Join-Path $agentsDir "lib_order_routed.ps1")


Describe "Invoke-OrderRouted - basic routing" {
    BeforeEach {
        $script:lastCallPlaceFutures = $null
        $script:lastCallPlaceSpot = $null
    }

    It "Route 'futures' chama CoinEx-PlaceOrder" {
        $r = Invoke-OrderRouted -Route "futures" -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 50000
        $script:lastCallPlaceFutures | Should Not Be $null
        $script:lastCallPlaceFutures.market | Should Be "BTCUSDT"
        $script:lastCallPlaceFutures.price | Should Be 50000
        $script:lastCallPlaceSpot | Should Be $null
        $r.order_id | Should Be "FUT123"
    }

    It "Route 'spot' chama CoinEx-PlaceSpotOrder" {
        $r = Invoke-OrderRouted -Route "spot" -Market "BTCUSDT" -Side "buy" -Type "limit" -Amount 0.001 -Price 50000
        $script:lastCallPlaceSpot | Should Not Be $null
        $script:lastCallPlaceSpot.market | Should Be "BTCUSDT"
        $script:lastCallPlaceFutures | Should Be $null
        $r.order_id | Should Be "SPOT456"
    }

    It "Route 'none' lanca excecao" {
        $threw = $false
        try { Invoke-OrderRouted -Route "none" -Market "X" -Side "buy" -Type "limit" -Amount 1 -Price 1 } catch { $threw = $true }
        $threw | Should Be $true
    }

    It "Spot market BUY com QuoteAmountUsd" {
        $r = Invoke-OrderRouted -Route "spot" -Market "BTCUSDT" -Side "buy" -Type "market" -Amount 0 -QuoteAmountUsd 100
        $script:lastCallPlaceSpot.quote | Should Be 100
        $script:lastCallPlaceSpot.type | Should Be "market"
    }

    It "Futures com stop/target propaga" {
        Invoke-OrderRouted -Route "futures" -Market "INJUSDT" -Side "buy" -Type "limit" -Amount 10 -Price 5 -StopLoss 4.5 -Target 7
        $script:lastCallPlaceFutures.stopLoss | Should Be 4.5
        $script:lastCallPlaceFutures.takeProfit | Should Be 7
    }
}
