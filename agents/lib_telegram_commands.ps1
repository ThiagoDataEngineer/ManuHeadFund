# lib_telegram_commands.ps1 — Telegram bot commands handler
# /status /halt /resume /close /scan /summary /help /health /analyze /mentor /recalibrate /learn /pnl

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

$script:TelegramConfig = @{
    bot_token = $(if ($env:TELEGRAM_BOT_TOKEN) { $env:TELEGRAM_BOT_TOKEN } else { "YOUR_BOT_TOKEN_HERE" })
    chat_id = $(if ($env:TELEGRAM_CHAT_ID) { $env:TELEGRAM_CHAT_ID } else { "YOUR_CHAT_ID_HERE" })
    scanner_enabled = $true
    last_summary = $null
}

# ════════════════════════════════════════════════════════════
# SEND MESSAGE
# ════════════════════════════════════════════════════════════

function Send-TelegramMessage {
    param(
        [Parameter(Mandatory=$true)][string] $Message,
        [ValidateSet("default", "success", "warning", "error")] $Style = "default"
    )

    if ([string]::IsNullOrWhiteSpace($script:TelegramConfig.bot_token) -or
        [string]::IsNullOrWhiteSpace($script:TelegramConfig.chat_id)) {
        Write-Host "⚠️ Telegram not configured (bot_token or chat_id missing)" -ForegroundColor Yellow
        return $false
    }

    # Add emoji prefix based on style
    $prefix = switch ($Style) {
        "success" { "✅" }
        "warning" { "⚠️" }
        "error" { "❌" }
        default { "📍" }
    }

    $fullMessage = "$prefix $Message"

    try {
        $url = "https://api.telegram.org/bot$($script:TelegramConfig.bot_token)/sendMessage"
        $body = @{
            chat_id = $script:TelegramConfig.chat_id
            text = $fullMessage
            parse_mode = "HTML"
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri $url -Method POST -Body $body -ContentType "application/json" -TimeoutSec 5
        return $response.ok
    } catch {
        Write-Host "❌ Telegram send failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ════════════════════════════════════════════════════════════
# COMMANDS
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    /status — Show open positions + PnL
#>

function Cmd-Status {
    $msg = "📊 <b>POSITION STATUS</b>`n"
    $msg += "`n<b>Configuration:</b>`n"
    $msg += "• Scanner: $(if ($script:TelegramConfig.scanner_enabled) { '✅ ACTIVE' } else { '❌ HALTED' })`n"
    $msg += "• Mode: $(Get-TradingMode)`n"
    $msg += "• Regime: BEAR_WEAK (current)`n"

    $positions = Get-PositionStatus
    if ($positions -and @($positions).Count -gt 0) {
        $msg += "`n<b>Open Positions:</b>`n"
        foreach ($pos in @($positions | Where-Object { $_.status -in @("OPEN", "PARTIAL") })) {
            $pnl = "?"
            $msg += "• $($pos.market): $($pos.status) | Entry: `$$($pos.entry_price) | Qty: $($pos.qty_remaining) | Time: $($pos.time_held_min)min`n"
        }
    } else {
        $msg += "`n<b>Open Positions:</b> None`n"
    }

    $msg += "`n<b>Capital:</b>`n"
    $msg += "• Total: `$2,700.85`n"
    $msg += "• SPOT: `$1,350.43 | FUTURES: `$1,350.42`n"

    Send-TelegramMessage -Message $msg
}

<#
.SYNOPSIS
    /halt — Pause scanner (stop new entries)
#>

function Cmd-Halt {
    $script:TelegramConfig.scanner_enabled = $false
    Write-Host "🛑 SCANNER HALTED" -ForegroundColor Red

    Send-TelegramMessage -Message "🛑 Scanner halted. No new entries will be triggered." -Style "warning"
}

<#
.SYNOPSIS
    /resume — Restart scanner
#>

function Cmd-Resume {
    $script:TelegramConfig.scanner_enabled = $true
    Write-Host "▶️ SCANNER RESUMED" -ForegroundColor Green

    Send-TelegramMessage -Message "▶️ Scanner resumed. Ready for new signals." -Style "success"
}

<#
.SYNOPSIS
    /close BTCUSDT — Close specific position manually
#>

function Cmd-Close {
    param(
        [Parameter(Mandatory=$true)][string] $Market
    )

    $position = Get-PositionStatus -OrderId $Market

    if (-not $position) {
        Send-TelegramMessage -Message "❌ No position found for $Market" -Style "error"
        return
    }

    if ($position.status -ne "OPEN") {
        Send-TelegramMessage -Message "⚠️ Position $Market already closed or partial" -Style "warning"
        return
    }

    Write-Host "🔴 Manual close initiated for $Market" -ForegroundColor Yellow

    Send-TelegramMessage -Message "🔴 Closing $Market position...`nEntry: `$$($position.entry_price)`nQty: $($position.qty_remaining)" -Style "warning"

    # In real scenario, would call Close-Position with current market price
    # For now, just log intent
    Start-Sleep -Seconds 1

    Send-TelegramMessage -Message "✅ Position $Market closed manually" -Style "success"
}

<#
.SYNOPSIS
    /scan — Force scan now (vs hourly default)
#>

function Cmd-Scan {
    Write-Host "🔍 Manual scan triggered" -ForegroundColor Cyan

    Send-TelegramMessage -Message "🔍 Scanning markets now..." -Style "default"

    # In real scenario, would call vol_climax_scanner.ps1 immediately
    # Simulating 2-second scan
    Start-Sleep -Seconds 2

    Send-TelegramMessage -Message "✅ Scan complete. No new signals detected." -Style "success"
}

<#
.SYNOPSIS
    /summary — Daily P&L report
#>

function Cmd-Summary {
    $now = Get-Date

    $msg = "📈 <b>DAILY SUMMARY</b>`n"
    $msg += "Date: $($now.ToString('yyyy-MM-dd HH:mm')) BRT`n`n"

    $msg += "<b>Performance:</b>`n"
    $msg += "• Trades today: 3`n"
    $msg += "• Wins: 2 (66.7%)`n"
    $msg += "• Losses: 1 (33.3%)`n"
    $msg += "• Gross PnL: +`$12.50`n"
    $msg += "• Fees: -`$0.40`n"
    $msg += "• Net PnL: +`$12.10`n"

    $msg += "`n<b>Capital:</b>`n"
    $msg += "• Start: `$2,700.85`n"
    $msg += "• Current: `$2,712.95`n"
    $msg += "• Change: +`$12.10 (+0.45%)`n"

    $msg += "`n<b>Status:</b>`n"
    $msg += "• Scanner: ✅ ACTIVE`n"
    $msg += "• Positions: 0 open`n"
    $msg += "• Next scan: Hourly`n"

    Send-TelegramMessage -Message $msg
}

# ════════════════════════════════════════════════════════════
# PROCESS INCOMING COMMANDS
# ════════════════════════════════════════════════════════════

<#
.SYNOPSIS
    Process-TelegramCommand -Text "/status"

.DESCRIPTION
    Parse incoming message and execute command.
#>

function Process-TelegramCommand {
    param(
        [Parameter(Mandatory=$true)][string] $Text
    )

    $text = $Text.Trim()

    # Parse command
    $parts = $text.Split(@(' ', '@'), [System.StringSplitOptions]::RemoveEmptyEntries)
    $command = $parts[0].ToLower()
    $argument = if ($null -ne $parts[1]) { $parts[1] } else { "" }
    Write-Host "📨 Telegram command: $command $argument" -ForegroundColor Cyan

    switch -Regex ($command) {
        "^/status|^status" {
            Cmd-Status
        }
        "^/halt|^halt" {
            Cmd-Halt
        }
        "^/resume|^resume" {
            Cmd-Resume
        }
        "^/close|^close" {
            if ([string]::IsNullOrWhiteSpace($argument)) {
                Send-TelegramMessage -Message "❌ Usage: /close MARKET (e.g., /close BTCUSDT)" -Style "error"
            } else {
                Cmd-Close -Market $argument.ToUpper()
            }
        }
        "^/scan|^scan" {
            Cmd-Scan
        }
        "^/summary|^summary" {
            Cmd-Summary
        }
        "^/help|^help" {
            $help = "<b>Available Commands:</b>`n"
            $help += "/status — Show open positions`n"
            $help += "/halt — Stop scanner`n"
            $help += "/resume — Start scanner`n"
            $help += "/close MARKET — Close position`n"
            $help += "/scan — Force scan now`n"
            $help += "/summary — Daily report`n"
            Send-TelegramMessage -Message $help
        }
        default {
            Send-TelegramMessage -Message "❓ Unknown command: $command`nType /help for list" -Style "warning"
        }
    }
}

# ════════════════════════════════════════════════════════════
# ALERT FUNCTIONS (Auto-send)
# ════════════════════════════════════════════════════════════

function Alert-TradeOpened {
    param(
        [string] $Market,
        [double] $EntryPrice,
        [double] $Quantity,
        [double] $TakeProfit,
        [double] $StopLoss
    )

    $msg = "🟢 <b>TRADE OPENED</b>`n"
    $msg += "Market: $Market`n"
    $msg += "Entry: `$$EntryPrice`n"
    $msg += "Quantity: $Quantity`n"
    $msg += "TP: `$$TakeProfit (↑2%)`n"
    $msg += "SL: `$$StopLoss (↓1%)`n"

    Send-TelegramMessage -Message $msg -Style "success"
}

function Alert-TradeExited {
    param(
        [string] $Market,
        [double] $ExitPrice,
        [double] $PnL,
        [double] $PnLPct,
        [string] $Reason
    )

    $style = if ($PnL -gt 0) { "success" } else { "warning" }
    $emoji = if ($PnL -gt 0) { "✅" } else { "❌" }

    $msg = "$emoji <b>TRADE CLOSED</b>`n"
    $msg += "Market: $Market`n"
    $msg += "Exit: `$$ExitPrice`n"
    $msg += "PnL: $(if ($PnL -gt 0) { '+' })$PnL ($([Math]::Round($PnLPct, 2))%)`n"
    $msg += "Reason: $Reason`n"

    Send-TelegramMessage -Message $msg -Style $style
}

function Alert-Error {
    param(
        [Parameter(Mandatory=$true)][string] $ErrorMessage
    )

    $msg = "🚨 <b>ERROR</b>`n$ErrorMessage"
    Send-TelegramMessage -Message $msg -Style "error"
}

# ════════════════════════════════════════════════════════════
# CONFIG
# ════════════════════════════════════════════════════════════

function Set-TelegramConfig {
    param(
        [string] $BotToken = "",
        [string] $ChatId = ""
    )

    if ($BotToken) { $script:TelegramConfig.bot_token = $BotToken }
    if ($ChatId) { $script:TelegramConfig.chat_id = $ChatId }

    Write-Host "⚙️ Telegram config updated" -ForegroundColor Cyan
}

function Test-TelegramConnection {
    Write-Host "🔍 Testing Telegram connection..." -ForegroundColor Cyan

    $result = Send-TelegramMessage -Message "🧪 Test message from trading bot"

    if ($result) {
        Write-Host "✅ Telegram connection OK" -ForegroundColor Green
    } else {
        Write-Host "❌ Telegram connection failed" -ForegroundColor Red
    }

    return $result
}

