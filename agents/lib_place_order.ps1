# lib_place_order.ps1 — SPOT + FUTURES trade execution
# Idempotent, retry-safe, fill-validated

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:PlaceOrderConfig = @{
    max_retries = 3
    retry_delay_ms = 1000
    timeout_sec = 10
    min_fill_pct = 0.95  # Accept 95%+ fills
    trading_enabled = $true  # Set to $false for dry-run
}

# ════════════════════════════════════════════════════════════
# MAIN: Place order on SPOT or FUTURES
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Place-Order -Market "BTCUSDT" -Market "SPOT" -Side "BUY" -Quantity 0.01 -Price 50000

.DESCRIPTION
    Execute order idempotently (client_id dedupes retries)
    Returns: @{ status, order_id, filled, avg_price, client_id }
#>

function Place-Order {
    param(
        [Parameter(Mandatory=$true)][string] $Market,      # BTCUSDT
        [Parameter(Mandatory=$true)][ValidateSet("SPOT", "FUTURES")] $Type,
        [Parameter(Mandatory=$true)][ValidateSet("BUY", "SELL")] $Side,
        [Parameter(Mandatory=$true)][double] $Quantity,    # 0.01 BTC
        [Parameter(Mandatory=$true)][double] $Price,       # 50000 USDT
        [string] $ClientId = ""                             # UUID for dedup
    )

    # Generate client_id if not provided (for idempotency)
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $ClientId = "order_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Minimum 1000 -Maximum 9999)"
    }

    Write-Host "📍 Place-Order: $Market $Type $Side qty=$Quantity@$Price (client_id=$ClientId)" -ForegroundColor Cyan

    if (-not $script:PlaceOrderConfig.trading_enabled) {
        Write-Host "  ⚠️ PAPER MODE: Order not actually submitted" -ForegroundColor Yellow
        return @{
            status = "PAPER"
            market = $Market
            type = $Type
            side = $Side
            quantity = $Quantity
            price = $Price
            filled = $Quantity
            avg_price = $Price
            client_id = $ClientId
            is_paper = $true
        }
    }

    # Retry loop
    for ($attempt = 1; $attempt -le $script:PlaceOrderConfig.max_retries; $attempt++) {
        try {
            Write-Host "  [Attempt $attempt/$($script:PlaceOrderConfig.max_retries)]" -ForegroundColor Gray

            # Select endpoint based on type
            $endpoint = if ($Type -eq "SPOT") {
                "https://api.coinex.com/v2/spot/orders"
            } else {
                "https://api.coinex.com/v2/futures/orders"
            }

            # Build request body
            $body = @{
                market = $Market
                side = $Side.ToLower()
                type = "limit"
                quantity = $Quantity
                price = $Price
                client_id = $ClientId
            } | ConvertTo-Json

            Write-Host "    POST $endpoint" -ForegroundColor Gray

            # Submit order
            $response = Invoke-RestMethod -Uri $endpoint `
                -Method POST `
                -Body $body `
                -ContentType "application/json" `
                -TimeoutSec $script:PlaceOrderConfig.timeout_sec `
                -ErrorAction Stop

            # Check response
            if ($response.code -eq 0 -and $response.data) {
                $orderId = $response.data.order_id
                Write-Host "    ✅ Order submitted: $orderId" -ForegroundColor Green

                # Wait for fill + validate
                $fillStatus = Wait-OrderFill -Market $Market -OrderId $orderId -Type $Type
                if ($fillStatus.filled_amount -gt 0) {
                    Write-Host "    ✅ Filled: $($fillStatus.filled_amount) @ $($fillStatus.avg_price)" -ForegroundColor Green
                    return @{
                        status = "FILLED"
                        market = $Market
                        type = $Type
                        side = $Side
                        quantity = $Quantity
                        price = $Price
                        filled = $fillStatus.filled_amount
                        avg_price = $fillStatus.avg_price
                        order_id = $orderId
                        client_id = $ClientId
                        is_paper = $false
                    }
                } else {
                    Write-Host "    ⚠️ Order not filled yet, status: $($fillStatus.status)" -ForegroundColor Yellow
                }
            } elseif ($response.code -eq 429) {
                # Rate limited, retry
                Write-Host "    ⚠️ Rate limited (429), retry..." -ForegroundColor Yellow
                Start-Sleep -Milliseconds $script:PlaceOrderConfig.retry_delay_ms
                continue
            } else {
                Write-Host "    ❌ API error: $($response.message)" -ForegroundColor Red
                return @{
                    status = "ERROR"
                    error = $response.message
                    client_id = $ClientId
                }
            }
        } catch {
            Write-Host "    ❌ Exception: $($_.Exception.Message)" -ForegroundColor Red
            if ($attempt -lt $script:PlaceOrderConfig.max_retries) {
                Start-Sleep -Milliseconds $script:PlaceOrderConfig.retry_delay_ms
            }
        }
    }

    return @{
        status = "FAILED_RETRIES"
        market = $Market
        client_id = $ClientId
        attempts = $script:PlaceOrderConfig.max_retries
    }
}

# ════════════════════════════════════════════════════════════
# HELPER: Wait for order fill
# ════════════════════════════════════════════════════════════

function Wait-OrderFill {
    param(
        [string] $Market,
        [string] $OrderId,
        [ValidateSet("SPOT", "FUTURES")] $Type,
        [int] $MaxWaitSec = 30
    )

    $endpoint = if ($Type -eq "SPOT") {
        "https://api.coinex.com/v2/spot/order/$OrderId"
    } else {
        "https://api.coinex.com/v2/futures/order/$OrderId"
    }

    $startTime = Get-Date
    while ((Get-Date) - $startTime -lt (New-TimeSpan -Seconds $MaxWaitSec)) {
        try {
            $resp = Invoke-RestMethod -Uri $endpoint -Method GET -TimeoutSec 5 -ErrorAction Stop
            if ($resp.code -eq 0 -and $resp.data) {
                $order = $resp.data
                $filled = [double]($order.filled_amount ?? 0)
                $status = $order.status

                if ($status -eq "filled" -or $filled -ge ($order.quantity * $script:PlaceOrderConfig.min_fill_pct)) {
                    return @{
                        status = $status
                        filled_amount = $filled
                        avg_price = [double]($order.avg_price ?? 0)
                    }
                }
            }
        } catch {}

        Start-Sleep -Milliseconds 500
    }

    return @{
        status = "timeout"
        filled_amount = 0
        avg_price = 0
    }
}

# ════════════════════════════════════════════════════════════
# CANCEL order (cleanup on exit)
# ════════════════════════════════════════════════════════════

function Cancel-Order {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][string] $OrderId,
        [ValidateSet("SPOT", "FUTURES")] $Type = "SPOT"
    )

    Write-Host "🔴 Cancel-Order: $Market $OrderId" -ForegroundColor Yellow

    $endpoint = if ($Type -eq "SPOT") {
        "https://api.coinex.com/v2/spot/orders/$OrderId"
    } else {
        "https://api.coinex.com/v2/futures/orders/$OrderId"
    }

    try {
        $response = Invoke-RestMethod -Uri $endpoint -Method DELETE -TimeoutSec 5 -ErrorAction Stop
        if ($response.code -eq 0) {
            Write-Host "  ✅ Cancelled: $OrderId" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "  ❌ Cancel failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    return $false
}

# ════════════════════════════════════════════════════════════
# ENABLE/DISABLE trading
# ════════════════════════════════════════════════════════════

function Set-TradingMode {
    param(
        [Parameter(Mandatory=$true)][ValidateSet("LIVE", "PAPER")] $Mode
    )

    $script:PlaceOrderConfig.trading_enabled = ($Mode -eq "LIVE")
    Write-Host "🔄 Trading mode: $Mode" -ForegroundColor Cyan
}

function Get-TradingMode {
    if ($script:PlaceOrderConfig.trading_enabled) {
        return "LIVE"
    } else {
        return "PAPER"
    }
}

