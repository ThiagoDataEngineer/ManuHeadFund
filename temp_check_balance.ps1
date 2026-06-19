. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "Checking SPOT balance..." -ForegroundColor Cyan
$spot = CoinEx-Get "/v2/spot/balance"

if ($spot.data) {
    Write-Host "SPOT Assets with balance:" -ForegroundColor Green
    $spot.data | Where-Object { [double]$_.available -gt 0 } | ForEach-Object {
        Write-Host "  $($_.ccy): $($_.available)"
    }
} else {
    Write-Host "No SPOT balance data" -ForegroundColor Red
}
