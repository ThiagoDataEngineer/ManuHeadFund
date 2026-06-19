. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1

Write-Host "=== TESTING SPOT STOP ORDER API ===" -ForegroundColor Cyan
Write-Host ""

# Test data
$market = "BASEDUSDT"
$trigger_price = 0.0718  # 2% below entry 0.073285
$amount = 248.280485     # BASED qty from earlier

$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Test different payloads
$tests = @(
    @{
        name = "Test 1: limit + trigger_price + ccy"
        body = @{
            market        = $market
            market_type   = "SPOT"
            side          = "sell"
            type          = "limit"
            amount        = $amount.ToString($inv)
            price         = $trigger_price.ToString($inv)
            trigger_price = $trigger_price.ToString($inv)
            trigger_type  = "price_less_equal"
            ccy           = "BASED"
        }
    }
    @{
        name = "Test 2: stop-limit (no type field)"
        body = @{
            market        = $market
            side          = "sell"
            amount        = $amount.ToString($inv)
            price         = $trigger_price.ToString($inv)
            trigger_price = $trigger_price.ToString($inv)
            trigger_type  = "price_less_equal"
        }
    }
    @{
        name = "Test 3: simple stop (no price)"
        body = @{
            market        = $market
            side          = "sell"
            amount        = $amount.ToString($inv)
            trigger_price = $trigger_price.ToString($inv)
            trigger_type  = "price_less_equal"
        }
    }
)

foreach ($test in $tests) {
    Write-Host ">>> $($test.name)" -ForegroundColor Yellow
    Write-Host "Payload:" -ForegroundColor Gray
    $test.body | ConvertTo-Json | Write-Host
    Write-Host ""

    try {
        $result = CoinEx-Post "/v2/spot/stop-order" $test.body
        if ($result.code -eq 0) {
            Write-Host "✅ SUCCESS!" -ForegroundColor Green
            Write-Host "Order ID: $($result.data.stop_order_id)" -ForegroundColor Green
            Write-Host $result | ConvertTo-Json | Write-Host
        } else {
            Write-Host "❌ API Error: $($result.code) - $($result.message)" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Exception: $_" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "─" * 60
    Write-Host ""
}
