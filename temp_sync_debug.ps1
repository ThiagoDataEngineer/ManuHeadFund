. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "=== DEBUG SYNC_AND_FIX_TP ===" -ForegroundColor Cyan

# Get one position
$openOrders = CoinEx-GetOpenOrders
$based = $openOrders | Where-Object { $_.market -eq 'BASEDUSDT' } | Select-Object -First 1

if ($based) {
    Write-Host "Position found:" -ForegroundColor Green
    Write-Host "  Market: $($based.market)"
    Write-Host "  Entry: $($based.price)"
    Write-Host "  Qty: $($based.amount)"

    $entry = [double]$based.price
    $size = [double]$based.amount
    $sl = [math]::Round($entry * 0.98, 4)

    Write-Host ""
    Write-Host "Will create SL order:" -ForegroundColor Yellow
    Write-Host "  Market: BASEDUSDT"
    Write-Host "  Side: sell"
    Write-Host "  TriggerPrice: $sl"
    Write-Host "  Amount: $size"
    Write-Host ""

    # Try directly
    Write-Host "Calling CoinEx-PlaceSpotStopOrder..." -ForegroundColor Gray
    try {
        # Enable debug
        $global:DEBUG_COINEX = $true

        $result = CoinEx-PlaceSpotStopOrder `
            -Market "BASEDUSDT" `
            -Side "sell" `
            -TriggerPrice $sl `
            -Amount $size

        Write-Host "Result:" -ForegroundColor Green
        $result | ConvertTo-Json | Write-Host
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
} else {
    Write-Host "BASED position not found" -ForegroundColor Red
}
