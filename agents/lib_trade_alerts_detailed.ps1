# lib_trade_alerts_detailed.ps1 — Detailed Telegram alerts for entry/exit
# 2026-07-03: User gets full visibility (auto-execute + alerts)

function Send-TradeEntryAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $StopPrice,
        [Parameter(Mandatory)] [double] $TargetPrice,
        [Parameter(Mandatory)] [double] $SizeUsd,
        [string] $Reason = "quality_gate",
        [string] $Carteira = "SPOT"
    )

    $emoji = if ($Direction -eq "LONG") { "🟢" } else { "🔴" }
    $riskReward = if ($StopPrice -gt 0 -and $TargetPrice -gt 0) {
        $riskPct = [math]::Abs(($EntryPrice - $StopPrice) / $EntryPrice * 100)
        $rewardPct = [math]::Abs(($TargetPrice - $EntryPrice) / $EntryPrice * 100)
        [math]::Round($rewardPct / [math]::Max($riskPct, 0.1), 1)
    } else {
        0
    }

    $message = @"
$emoji <b>$Direction</b> <b>$Market</b>

📊 <b>Entry</b>: $EntryPrice
🛑 <b>Stop</b>: $StopPrice
🎯 <b>Target</b>: $TargetPrice
💰 <b>Size</b>: $$SizeUsd
📈 <b>R:R</b>: 1:$riskReward
🏦 <b>Carteira</b>: $Carteira
📌 <b>Reason</b>: $Reason

⚡ <i>Auto-executed (no approval needed)</i>
"@

    try {
        Send-TelegramAlert -Message $message -ParseMode HTML | Out-Null
    }
    catch {
        # Silent fail
    }
}

function Send-TradeExitAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Direction,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $ExitPrice,
        [Parameter(Mandatory)] [double] $PnlPercent,
        [Parameter(Mandatory)] [string] $ExitReason,
        [Parameter(Mandatory)] [double] $SizeUsd
    )

    $emoji = if ($PnlPercent -ge 0) { "✅" } else { "❌" }
    $gainLoss = if ($PnlPercent -ge 0) { "GAIN" } else { "LOSS" }
    # PS 5.1: format com sinal via -f (sintaxe ${var:spec} nao existe em PowerShell)
    $pnlFmt = "{0:+0.0;-0.0;+0.0}" -f $PnlPercent

    $message = @"
$emoji <b>$Direction CLOSED</b> <b>$Market</b>

📊 <b>Entry</b>: $EntryPrice
📍 <b>Exit</b>: $ExitPrice
📈 <b>P&L</b>: <b>$pnlFmt%</b> ($gainLoss)
💰 <b>Size</b>: $$SizeUsd
📌 <b>Reason</b>: $ExitReason

✨ <i>Trade closed</i>
"@

    try {
        Send-TelegramAlert -Message $message -ParseMode HTML | Out-Null
    }
    catch {
        # Silent fail
    }
}

function Send-PortfolioSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int] $OpenTrades,
        [Parameter(Mandatory)] [double] $TotalOpenPnL,
        [Parameter(Mandatory)] [double] $TodayPnL,
        [Parameter(Mandatory)] [string] $Regime
    )

    $emoji = if ($TotalOpenPnL -ge 0) { "📈" } else { "📉" }
    $todayEmoji = if ($TodayPnL -ge 0) { "✅" } else { "⚠️" }
    $openFmt = "{0:+0.00;-0.00;+0.00}" -f $TotalOpenPnL
    $todayFmt = "{0:+0.00;-0.00;+0.00}" -f $TodayPnL

    $message = @"
$emoji <b>PORTFOLIO SNAPSHOT</b>

📊 <b>Open Trades</b>: $OpenTrades
💼 <b>Open P&L</b>: $openFmt%
📅 <b>Today P&L</b>: $todayEmoji $todayFmt%
🔄 <b>Regime</b>: $Regime

🤖 <i>Auto-trading active</i>
"@

    try {
        Send-TelegramAlert -Message $message -ParseMode HTML | Out-Null
    }
    catch {
        # Silent fail
    }
}

# Export by dot-source
