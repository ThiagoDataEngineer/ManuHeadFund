. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "Debugging open positions..." -ForegroundColor Cyan

$openOrders = CoinEx-GetOpenOrders

Write-Host "Total positions: $($openOrders.Count)" -ForegroundColor Green

if ($openOrders.Count -gt 0) {
    Write-Host "`nFirst position properties:" -ForegroundColor Yellow
    $openOrders[0] | Get-Member | Select-Object -First 20

    Write-Host "`nFirst position values:" -ForegroundColor Yellow
    $openOrders[0] | Format-Table -Property * -AutoSize
}

Write-Host "`nAll markets:" -ForegroundColor Cyan
$openOrders | ForEach-Object {
    $market_field = if ($_.instrument_id) { $_.instrument_id }
                   elseif ($_.market) { $_.market }
                   elseif ($_.pair) { $_.pair }
                   else { "UNKNOWN" }
    Write-Host "  Market field: $market_field (qty: $($_.quantity ?? $_.size), entry: $($_.entry_price ?? $_.price))"
}
