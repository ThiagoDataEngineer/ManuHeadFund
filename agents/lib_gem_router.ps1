# lib_gem_router.ps1 — GEM ROUTER & EXECUTOR
# Rota sinais de PULL_BACK / DISTRIBUTION para LIVE execution
# 2026-06-09

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:RouterConfig = @{
    trading_mode = "PAPER"  # Change to LIVE when ready
    max_position_pct = 0.003  # 0.3% per trade
    max_concurrent = 3
    use_telegram = $true
}

# ════════════════════════════════════════════════════════════
# MAIN: Route and execute signal
# ════════════════════════════════════════════════════════════

function Invoke-GemRouter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][PSCustomObject] $Signal
    )

    Write-Host "`n🚀 GEM ROUTER — Executing $($Signal.strategy) on $($Signal.market)" -ForegroundColor Cyan

    # Load required libraries
    . (Join-Path $PSScriptRoot "lib_place_order.ps1") 2>$null
    . (Join-Path $PSScriptRoot "lib_telegram_commands.ps1") 2>$null

    # Validate signal
    $validation = Test-SignalValidity -Signal $Signal
    if (-not $validation.valid) {
        Write-Host "❌ Signal validation failed: $($validation.reason)" -ForegroundColor Red
        return @{ executed = $false; reason = $validation.reason }
    }

    # Get current mode
    $mode = Get-TradingMode

    if ($mode -eq "PAPER") {
        # Paper trade mode
        return Invoke-PaperExecution -Signal $Signal
    } else {
        # LIVE execution
        return Invoke-LiveExecution -Signal $Signal
    }
}

# ════════════════════════════════════════════════════════════
# PAPER EXECUTION (safe testing)
# ════════════════════════════════════════════════════════════

function Invoke-PaperExecution {
    param([PSCustomObject] $Signal)

    Write-Host "📝 [PAPER MODE] Simulating $($Signal.strategy)..." -ForegroundColor Yellow

    $execution = @{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        market = $Signal.market
        strategy = $Signal.strategy
        mode = "PAPER"
        entry_price = $Signal.entry_price
        stop_loss = $Signal.stop_loss
        target = $Signal.target
        position_size = Get-PositionSize -Signal $Signal
        executed = $true
        order_id = "PAPER_$(Get-Random -Minimum 100000 -Maximum 999999)"
        notes = "Paper simulation - no real capital"
    }

    # Log to journal
    $execution | ConvertTo-Json | Add-Content -Path "journal/paper_trades_live.jsonl"

    # Telegram alert
    if ($script:RouterConfig.use_telegram) {
        Send-TelegramAlert -Type "PAPER_TRADE" -Signal $Signal -Execution $execution
    }

    Write-Host "✅ Paper trade logged: $($execution.order_id)" -ForegroundColor Green

    return $execution
}

# ════════════════════════════════════════════════════════════
# LIVE EXECUTION (real trading)
# ════════════════════════════════════════════════════════════

function Invoke-LiveExecution {
    param([PSCustomObject] $Signal)

    Write-Host "⚠️ [LIVE MODE] Executing real trade..." -ForegroundColor Red

    # Calculate position size
    $position_size = Get-PositionSize -Signal $Signal

    try {
        # Place order via CoinEx API
        if ($Signal.strategy -eq "PULL_BACK_RECOVERY") {
            $order_result = Place-Order `
                -Market $Signal.market `
                -Type "SPOT" `
                -Side "BUY" `
                -Quantity $position_size `
                -Price $Signal.entry_price

        } elseif ($Signal.strategy -eq "DISTRIBUTION_SHORT") {
            $order_result = Place-Order `
                -Market $Signal.market `
                -Type "FUTURES" `
                -Side "SELL" `
                -Quantity $position_size `
                -Price $Signal.entry_price
        }

        if ($order_result.status -eq "FILLED") {
            # Success
            $execution = @{
                timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                market = $Signal.market
                strategy = $Signal.strategy
                mode = "LIVE"
                entry_price = $order_result.avg_price
                stop_loss = $Signal.stop_loss
                target = $Signal.target
                position_size = $order_result.filled
                executed = $true
                order_id = $order_result.order_id
                client_id = $order_result.client_id
            }

            # Log to journal
            $execution | ConvertTo-Json | Add-Content -Path "journal/live_trades.jsonl"

            # Telegram alert
            if ($script:RouterConfig.use_telegram) {
                Send-TelegramAlert -Type "LIVE_TRADE_OPENED" -Signal $Signal -Execution $execution
            }

            Write-Host "✅ LIVE trade executed: $($execution.order_id)" -ForegroundColor Green

            return $execution

        } else {
            # Failed
            Write-Host "❌ Order failed: $($order_result.status) - $($order_result.error)" -ForegroundColor Red

            if ($script:RouterConfig.use_telegram) {
                Send-TelegramAlert -Type "TRADE_ERROR" -Message "Order failed on $($Signal.market): $($order_result.error)"
            }

            return @{ executed = $false; reason = $order_result.error }
        }

    } catch {
        Write-Host "❌ Exception during execution: $_" -ForegroundColor Red

        if ($script:RouterConfig.use_telegram) {
            Send-TelegramAlert -Type "TRADE_EXCEPTION" -Message "Error on $($Signal.market): $_"
        }

        return @{ executed = $false; reason = $_.Exception.Message }
    }
}

# ════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════

function Test-SignalValidity {
    param([PSCustomObject] $Signal)

    # Validate required fields
    $required_fields = @("market", "strategy", "entry_price", "stop_loss", "target", "confidence")
    $missing = @($required_fields | Where-Object { -not $Signal.$_ })

    if ($missing) {
        return @{ valid = $false; reason = "Missing fields: $($missing -join ', ')" }
    }

    # Validate logic
    if ($Signal.strategy -eq "PULL_BACK_RECOVERY") {
        if ($Signal.entry_price -gt $Signal.target) {
            return @{ valid = $false; reason = "LONG entry > target (invalid)" }
        }
        if ($Signal.entry_price -lt $Signal.stop_loss) {
            return @{ valid = $false; reason = "LONG entry < stop loss (invalid)" }
        }
    }

    if ($Signal.strategy -eq "DISTRIBUTION_SHORT") {
        if ($Signal.entry_price -lt $Signal.target) {
            return @{ valid = $false; reason = "SHORT entry < target (invalid)" }
        }
        if ($Signal.entry_price -gt $Signal.stop_loss) {
            return @{ valid = $false; reason = "SHORT entry > stop loss (invalid)" }
        }
    }

    return @{ valid = $true }
}

function Get-PositionSize {
    param([PSCustomObject] $Signal)

    # Get current capital
    . (Join-Path $PSScriptRoot "lib_hybrid_orchestrator.ps1") 2>$null
    $capital = Get-DynamicCapital

    if ($Signal.strategy -eq "PULL_BACK_RECOVERY") {
        $size_usd = $capital.spot_capital * 0.003
    } else {
        $size_usd = $capital.futures_capital * 0.002
    }

    # Convert to asset quantity
    $quantity = $size_usd / $Signal.entry_price

    return $quantity
}

function Send-TelegramAlert {
    param(
        [string] $Type,
        [PSCustomObject] $Signal,
        [PSCustomObject] $Execution,
        [string] $Message
    )

    # Call lib_telegram_commands functions
    if ($Type -eq "PAPER_TRADE") {
        $msg = "📝 PAPER: $($Signal.market) $($Signal.strategy) @ $($Signal.entry_price)"
    } elseif ($Type -eq "LIVE_TRADE_OPENED") {
        $msg = "🚀 LIVE: $($Signal.market) $($Signal.strategy) @ $($Execution.entry_price) | ID: $($Execution.order_id)"
    } elseif ($Type -eq "TRADE_ERROR") {
        $msg = "❌ ERROR: $Message"
    } else {
        $msg = $Message
    }

    # Send via Telegram (if configured)
    Write-Host "   [TG] $msg" -ForegroundColor Cyan
}

# ════════════════════════════════════════════════════════════
# STATUS & CONFIG
# ════════════════════════════════════════════════════════════

function Show-RouterStatus {
    Write-Host "`n📊 GEM ROUTER STATUS" -ForegroundColor Cyan
    Write-Host "   Trading Mode: $(Get-TradingMode)" -ForegroundColor Gray
    Write-Host "   Max Concurrent: $($script:RouterConfig.max_concurrent)" -ForegroundColor Gray
    Write-Host "   Max Position: $($script:RouterConfig.max_position_pct * 100)%" -ForegroundColor Gray
    Write-Host "   Telegram: $(if ($script:RouterConfig.use_telegram) { 'Enabled' } else { 'Disabled' })" -ForegroundColor Gray
    Write-Host ""
}

function Set-RouterMode {
    param(
        [ValidateSet("PAPER", "LIVE")][string] $Mode
    )

    $script:RouterConfig.trading_mode = $Mode
    Set-TradingMode -Mode $Mode

    Write-Host "✅ Router mode set to: $Mode" -ForegroundColor Green
}
