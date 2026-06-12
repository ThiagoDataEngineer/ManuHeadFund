# lib_telegram_alerts_simple.ps1 — Simple Telegram Alerting
# Send alerts via Telegram Bot API
# 2026-06-09

# ════════════════════════════════════════════════════════════
# CONFIG — Set your values here
# ════════════════════════════════════════════════════════════

$script:TelegramConfig = @{
    enabled = $true
    bot_token = ""  # Your bot token from @BotFather
    chat_id = ""    # Your chat ID (get via /start on bot)
    api_url = "https://api.telegram.org/bot"
}

# ════════════════════════════════════════════════════════════
# Main: Send Telegram message
# ════════════════════════════════════════════════════════════

function Send-TelegramAlert {
    param(
        [Parameter(Mandatory=$true)][string] $Message,
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")][string] $Type = "INFO"
    )

    if (-not $script:TelegramConfig.enabled) {
        return $false
    }

    # Check if configured
    if (-not $script:TelegramConfig.bot_token -or -not $script:TelegramConfig.chat_id) {
        Write-Host "⚠️ Telegram not configured. Set bot_token and chat_id in lib_telegram_alerts_simple.ps1" -ForegroundColor Yellow
        return $false
    }

    # Format message with icon
    $icon = switch ($Type) {
        "SUCCESS" { "✅" }
        "WARNING" { "⚠️" }
        "ERROR" { "❌" }
        default { "ℹ️" }
    }

    $formatted_msg = "$icon $Message"

    try {
        # Build API URL
        $url = "$($script:TelegramConfig.api_url)$($script:TelegramConfig.bot_token)/sendMessage"

        # Build payload
        $body = @{
            chat_id = $script:TelegramConfig.chat_id
            text = $formatted_msg
            parse_mode = "HTML"
        } | ConvertTo-Json

        # Send
        $response = Invoke-RestMethod -Uri $url `
            -Method POST `
            -Body $body `
            -ContentType "application/json" `
            -TimeoutSec 5 `
            -ErrorAction Stop

        if ($response.ok) {
            Write-Host "📤 Telegram sent: $Type" -ForegroundColor Cyan
            return $true
        } else {
            Write-Host "❌ Telegram failed: $($response.description)" -ForegroundColor Red
            return $false
        }

    } catch {
        Write-Host "❌ Telegram error: $_" -ForegroundColor Red
        return $false
    }
}

# ════════════════════════════════════════════════════════════
# Setup: Configure Telegram
# ════════════════════════════════════════════════════════════

function Set-TelegramConfig {
    param(
        [Parameter(Mandatory=$true)][string] $BotToken,
        [Parameter(Mandatory=$true)][string] $ChatId
    )

    $script:TelegramConfig.bot_token = $BotToken
    $script:TelegramConfig.chat_id = $ChatId
    $script:TelegramConfig.enabled = $true

    Write-Host "✅ Telegram configured" -ForegroundColor Green
    Write-Host "   Bot: $($BotToken.Substring(0, 10))..." -ForegroundColor Gray
    Write-Host "   Chat: $ChatId" -ForegroundColor Gray

    # Test
    Send-TelegramAlert -Message "🧪 Telegram connection test" -Type "INFO"
}

# ════════════════════════════════════════════════════════════
# Helpers: Specific message types
# ════════════════════════════════════════════════════════════

function Send-TelegramTrade {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][string] $Strategy,
        [Parameter(Mandatory=$true)][double] $EntryPrice,
        [Parameter(Mandatory=$true)][double] $Target
    )

    $msg = @"
📈 TRADE OPENED

Market: <b>$Market</b>
Strategy: <b>$Strategy</b>
Entry: <b>${EntryPrice:F8}</b>
Target: <b>${Target:F8}</b>

Time: $(Get-Date -Format 'HH:mm:ss')
"@

    Send-TelegramAlert -Message $msg -Type "SUCCESS"
}

function Send-TelegramClose {
    param(
        [Parameter(Mandatory=$true)][string] $Market,
        [Parameter(Mandatory=$true)][double] $PnL,
        [Parameter(Mandatory=$true)][string] $Reason
    )

    $icon = if ($PnL -ge 0) { "✅" } else { "❌" }
    $msg = @"
$icon TRADE CLOSED

Market: <b>$Market</b>
PnL: <b>$$PnL</b>
Reason: <b>$Reason</b>

Time: $(Get-Date -Format 'HH:mm:ss')
"@

    $type = if ($PnL -ge 0) { "SUCCESS" } else { "WARNING" }
    Send-TelegramAlert -Message $msg -Type $type
}

# ════════════════════════════════════════════════════════════
# Status
# ════════════════════════════════════════════════════════════

function Show-TelegramStatus {
    Write-Host ""
    Write-Host "📱 TELEGRAM STATUS" -ForegroundColor Cyan
    Write-Host "   Enabled: $(if ($script:TelegramConfig.enabled) { 'YES ✅' } else { 'NO ❌' })" -ForegroundColor Gray
    if ($script:TelegramConfig.bot_token) {
        Write-Host "   Bot: Configured ✅" -ForegroundColor Gray
    } else {
        Write-Host "   Bot: NOT CONFIGURED ⚠️" -ForegroundColor Yellow
    }
    if ($script:TelegramConfig.chat_id) {
        Write-Host "   Chat: Configured ✅" -ForegroundColor Gray
    } else {
        Write-Host "   Chat: NOT CONFIGURED ⚠️" -ForegroundColor Yellow
    }
    Write-Host ""
}
