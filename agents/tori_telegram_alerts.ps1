# tori_telegram_alerts.ps1 - Telegram alert formatter for Tori Daemon
#
# Formats and sends alerts for:
# 1. New setups (confluence ≥ 80)
# 2. Setup closed (target hit or stop)
# 3. 4-hour summary reports
# 4. Daily performance dashboard
#
# Integration: lib_telegram.ps1 for send/format utilities
# PS 5.1 compatible, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:TELEGRAM_CHAT_ID = $env:TELEGRAM_CHAT_ID
$script:TELEGRAM_BOT_TOKEN = $env:TELEGRAM_BOT_TOKEN
$script:TELEGRAM_ENABLE = $true

# Alert thresholds
$script:MIN_SCORE_ALERT = 80
$script:MIN_RR_ALERT = 2.5

# ============================================================================
# HELPER: Format large numbers
# ============================================================================

function Format-Number {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [double]$Value,

        [Parameter(Mandatory=$false)]
        [int]$Decimals = 2
    )

    if ($Value -gt 1000000) {
        return "$([Math]::Round($Value / 1000000, $Decimals))M"
    }
    elseif ($Value -gt 1000) {
        return "$([Math]::Round($Value / 1000, $Decimals))K"
    }
    else {
        return [Math]::Round($Value, $Decimals).ToString()
    }
}

# ============================================================================
# ALERT TYPE 1: NEW SETUP ALERT
# ============================================================================

function Format-NewSetupAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    # Map signal strings to labels
    $signalEmoji = @{
        "VOLUME_CLIMAX" = "[VOL]"
        "RSI_EXTREME" = "[RSI]"
        "FRACTAL_BULLISH" = "[FB]"
        "FRACTAL_BEARISH" = "[FBR]"
        "CHOCH" = "[CHOCH]"
        "VOLUME_PROFILE" = "[VP]"
    }

    $signals = $Setup.signals_fired -split "\|"
    $signalList = @()

    foreach ($signal in $signals) {
        $signal = $signal.Trim()
        if ($signal -ne "") {
            $emoji = "[OK]"
            foreach ($key in $signalEmoji.Keys) {
                if ($signal -match $key) {
                    $emoji = $signalEmoji[$key]
                    break
                }
            }
            $signalList += "$emoji $signal"
        }
    }

    $trendEmoji = if ($Setup.trend_type -eq "LONG") { "[LONG]" } else { "[SHORT]" }
    $scoreColor = if ($Setup.confidence_score -ge 90) { "[HOT]" } else { "[STAR]" }

    $message = @"
$trendEmoji NEW SETUP - $($Setup.pair) [$($Setup.timeframe)]
$($Setup.trend_type) Entry

$scoreColor Confidence: $($Setup.confidence_score)/100
[ENTRY] Entry: $(Format-Number $Setup.entry_price)
[STOP] Stop: $(Format-Number $Setup.stop_loss)
[TARGET] Target: $(Format-Number $Setup.target_price)
[RR] R:R: $([Math]::Round($Setup.rr_ratio, 2))x
[RSI] RSI: $([Math]::Round($Setup.rsi, 0))

Signals:
$($signalList -join "`n")

ID: $($Setup.id)
Time: $(Get-Date $Setup.timestamp -Format "HH:mm:ss UTC")
"@

    return $message
}

# ============================================================================
# ALERT TYPE 2: SETUP CLOSED - TARGET HIT
# ============================================================================

function Format-TargetHitAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    $trendEmoji = if ($Setup.trend_type -eq "LONG") { "[LONG]" } else { "[SHORT]" }

    $holdTime = if ($Setup.closed_time -and $Setup.timestamp) {
        $duration = [DateTime]::Parse($Setup.closed_time) - [DateTime]::Parse($Setup.timestamp)
        if ($duration.TotalHours -ge 1) {
            "$([Math]::Round($duration.TotalHours, 1))h"
        } else {
            "$([Math]::Round($duration.TotalMinutes, 0))m"
        }
    } else {
        "N/A"
    }

    $message = @"
[WIN] SETUP CLOSED - TARGET HIT
$trendEmoji $($Setup.pair) [$($Setup.timeframe)]

Entry: $(Format-Number $Setup.entry_price)
Exit: $(Format-Number $Setup.target_price)
Profit: +$(Format-Number $Setup.unrealized_pnl) USDT
Profit %: +$([Math]::Round(($Setup.unrealized_pnl / $Setup.entry_price * 100), 1))%
Hold Time: $holdTime

R:R Achieved: $([Math]::Round($Setup.rr_ratio, 2))x
Time: $(Get-Date -Format "HH:mm:ss UTC")
"@

    return $message
}

# ============================================================================
# ALERT TYPE 3: SETUP CLOSED - STOP HIT
# ============================================================================

function Format-StopHitAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    $trendEmoji = if ($Setup.trend_type -eq "LONG") { "[LONG]" } else { "[SHORT]" }

    $holdTime = if ($Setup.closed_time -and $Setup.timestamp) {
        $duration = [DateTime]::Parse($Setup.closed_time) - [DateTime]::Parse($Setup.timestamp)
        if ($duration.TotalHours -ge 1) {
            "$([Math]::Round($duration.TotalHours, 1))h"
        } else {
            "$([Math]::Round($duration.TotalMinutes, 0))m"
        }
    } else {
        "N/A"
    }

    $message = @"
[LOSS] SETUP STOPPED
$trendEmoji $($Setup.pair) [$($Setup.timeframe)]

Entry: $(Format-Number $Setup.entry_price)
Stop Hit: $(Format-Number $Setup.stop_loss)
Loss: -$(Format-Number $Setup.risk_usdt) USDT
Loss %: -$([Math]::Round(($Setup.risk_usdt / $Setup.entry_price * 100), 1))%
Hold Time: $holdTime

Time: $(Get-Date -Format "HH:mm:ss UTC")
"@

    return $message
}

# ============================================================================
# ALERT TYPE 4: 4-HOUR SUMMARY REPORT
# ============================================================================

function Format-SummaryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$ActiveSetups,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$RecentClosedTrades,

        [Parameter(Mandatory=$true)]
        [hashtable]$PerformanceMetrics
    )

    $totalPnL = 0.0
    $winCount = 0
    $lossCount = 0

    foreach ($trade in $RecentClosedTrades) {
        if ($trade.unrealized_pnl -gt 0) {
            $winCount += 1
        } else {
            $lossCount += 1
        }
        $totalPnL += $trade.unrealized_pnL
    }

    $totalTrades = $winCount + $lossCount
    $winRate = if ($totalTrades -gt 0) { ($winCount / $totalTrades * 100) } else { 0 }

    $topGainer = $RecentClosedTrades | Sort-Object -Property unrealized_pnl -Descending | Select-Object -First 1
    $topGainerDisplay = if ($topGainer) {
        "$($topGainer.pair) +$(Format-Number $topGainer.unrealized_pnl)"
    } else {
        "None"
    }

    $activeByType = $ActiveSetups | Group-Object -Property trend_type
    $longCount = ($activeByType | Where-Object { $_.Name -eq "LONG" } | Select-Object -ExpandProperty Count) -as [int]
    $shortCount = ($activeByType | Where-Object { $_.Name -eq "SHORT" } | Select-Object -ExpandProperty Count) -as [int]

    $avgConfidence = if ($ActiveSetups.Count -gt 0) {
        ($ActiveSetups | Measure-Object -Property confidence_score -Average).Average
    } else {
        0
    }

    $message = @"
[SUMMARY] SCAN SUMMARY - 4-HOUR CYCLE
=====================================

[ACTIVE] Active Setups: $($ActiveSetups.Count)
  [LONG] LONG: $longCount
  [SHORT] SHORT: $shortCount
  [SCORE] Avg Score: $([Math]::Round($avgConfidence, 0))/100

[TRADES] Recent Trades: $totalTrades
  [WIN] Wins: $winCount
  [LOSS] Losses: $lossCount
  [WR] Win Rate: $([Math]::Round($winRate, 1))%

[PNL] P&L (Last 4h): $([math]::Round($totalPnL, 2)) USDT
[TOP] Top Gainer: $topGainerDisplay

[PAIRS] Pairs Scanned: $($PerformanceMetrics.pairs_analyzed)
[SCANS] Scans Completed: $($PerformanceMetrics.total_scans)

Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")
"@

    return $message
}

# ============================================================================
# HELPER: SEND MESSAGE TO TELEGRAM
# ============================================================================

function Send-TelegramMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [string]$ChatId = $script:TELEGRAM_CHAT_ID,

        [Parameter(Mandatory=$false)]
        [string]$BotToken = $script:TELEGRAM_BOT_TOKEN
    )

    if (-not $script:TELEGRAM_ENABLE) {
        Write-Host "Telegram disabled, message not sent"
        return
    }

    if (-not $ChatId -or -not $BotToken) {
        Write-Host "Telegram not configured (TELEGRAM_CHAT_ID or TELEGRAM_BOT_TOKEN missing)"
        return
    }

    try {
        $uri = "https://api.telegram.org/bot${BotToken}/sendMessage"

        $body = @{
            chat_id = $ChatId
            text = $Message
            parse_mode = "HTML"
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json" -TimeoutSec 10

        if ($response.ok) {
            Write-Host "Message sent to Telegram"
            return $true
        } else {
            Write-Host "Telegram error: $($response.description)"
            return $false
        }
    } catch {
        Write-Host "Failed to send Telegram message: $_"
        return $false
    }
}

# ============================================================================
# PUBLIC INTERFACE: Alert dispatchers
# ============================================================================

function Send-NewSetupAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    $message = Format-NewSetupAlert -Setup $Setup
    Send-TelegramMessage -Message $message
}

function Send-TargetHitAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    $message = Format-TargetHitAlert -Setup $Setup
    Send-TelegramMessage -Message $message
}

function Send-StopHitAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$Setup
    )

    $message = Format-StopHitAlert -Setup $Setup
    Send-TelegramMessage -Message $message
}

function Send-SummaryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$ActiveSetups,

        [Parameter(Mandatory=$true)]
        [PSObject[]]$RecentClosedTrades,

        [Parameter(Mandatory=$true)]
        [hashtable]$PerformanceMetrics
    )

    $message = Format-SummaryReport -ActiveSetups $ActiveSetups -RecentClosedTrades $RecentClosedTrades -PerformanceMetrics $PerformanceMetrics
    Send-TelegramMessage -Message $message
}

