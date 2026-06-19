. agents/config.local.ps1
. agents/config.ps1

$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Test STOP ORDER API for SPOT
Write-Host "Testing CoinEx SPOT Stop Order API..." -ForegroundColor Cyan

$market = "BASEDUSDT"
$trigger_price = 0.0718
$amount = 248.280485

# Tentativa 1: Com price e trigger_price
$body1 = @{
    market        = $market
    market_type   = "SPOT"
    side          = "sell"
    type          = "limit"
    amount        = $amount.ToString($inv)
    price         = $trigger_price.ToString($inv)
    trigger_price = $trigger_price.ToString($inv)
    trigger_type  = "price_less_equal"
} | ConvertTo-Json

Write-Host "Tentativa 1 (limit + trigger):" -ForegroundColor Yellow
Write-Host $body1
Write-Host ""

# Tentativa 2: Sem type, só stop_limit
$body2 = @{
    market        = $market
    market_type   = "SPOT"
    side          = "sell"
    amount        = $amount.ToString($inv)
    price         = $trigger_price.ToString($inv)
    trigger_price = $trigger_price.ToString($inv)
    trigger_type  = "price_less_equal"
} | ConvertTo-Json

Write-Host "Tentativa 2 (sem type):" -ForegroundColor Yellow
Write-Host $body2
Write-Host ""

# Tentativa 3: Com ccy
$body3 = @{
    market        = $market
    side          = "sell"
    amount        = $amount.ToString($inv)
    price         = $trigger_price.ToString($inv)
    trigger_price = $trigger_price.ToString($inv)
    trigger_type  = "price_less_equal"
    ccy           = "BASED"
} | ConvertTo-Json

Write-Host "Tentativa 3 (com ccy, sem market_type):" -ForegroundColor Yellow
Write-Host $body3
