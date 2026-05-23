# lib_order_routed.ps1 -- Wrapper unified de order placement (spot vs futures).
#
# Apos lib_market_router decidir Route, callers chamam Invoke-OrderRouted
# em vez de CoinEx-PlaceOrder/CoinEx-PlaceSpotOrder direto.
#
# Routing:
#   "futures" -> CoinEx-PlaceOrder + stop/target nativo via stop_loss/take_profit
#   "spot"    -> CoinEx-PlaceSpotOrder (stop/target sao monitorados off-chain pelo trailing)
#   "none"    -> throw (caller deve verificar antes)
#
# Wire futuro: gem_executor e orchestrator legacy usam isso pra routing transparente.


function Invoke-OrderRouted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Route,     # "futures" | "spot" | "none"
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,      # "buy" | "sell"
        [Parameter(Mandatory)] [string] $Type,      # "limit" | "market"
        [double] $Amount = 0,
        [double] $Price = 0,
        [double] $QuoteAmountUsd = 0,               # so usado em spot market BUY
        [double] $StopLoss = 0,                     # so usado em futures
        [double] $Target = 0,                       # so usado em futures
        [string] $StpMode = "ct"
    )
    if ($Route -eq "none" -or [string]::IsNullOrEmpty($Route)) {
        throw "Invoke-OrderRouted: Route 'none' invalido ou ausente. Caller deve verificar disponibilidade antes."
    }
    if ($Route -eq "futures") {
        $sl = if ($StopLoss -gt 0) { $StopLoss } else { $null }
        $tp = if ($Target -gt 0) { $Target } else { $null }
        $pr = if ($Price -gt 0) { $Price } else { $null }
        return CoinEx-PlaceOrder $Market $Side $Type $Amount $pr $sl $tp $StpMode
    }
    if ($Route -eq "spot") {
        return CoinEx-PlaceSpotOrder -Market $Market -Side $Side -Type $Type `
                                     -Amount $Amount -Price $Price `
                                     -QuoteAmountUsd $QuoteAmountUsd -StpMode $StpMode
    }
    throw "Invoke-OrderRouted: Route invalido '$Route' (esperado futures|spot|none)"
}
