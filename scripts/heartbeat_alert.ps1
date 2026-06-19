#!/usr/bin/env pwsh
# heartbeat_alert.ps1
# Monitora se sistema está vivo (trades sendo executados)
# Roda a cada hora — se 0 trades em 6h, alerta via Telegram

param(
    [int]$AlertThresholdHours = 6,
    [string]$JournalDir = "journal"
)

# Load config
. agents/config.local.ps1

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  HEARTBEAT CHECK — System Alive?                         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check last trade
$tradeFile = "$JournalDir/trade_outcomes.jsonl"
if (-not (Test-Path $tradeFile)) {
    Write-Host "[ALERT] trade_outcomes.jsonl não encontrado" -ForegroundColor Red
    exit 1
}

$trades = @()
Get-Content $tradeFile | ForEach-Object {
    if ($_) { $trades += ($_ | ConvertFrom-Json) }
}

if ($trades.Count -eq 0) {
    Write-Host "[ALERT] Nenhum trade registrado" -ForegroundColor Red
    exit 1
}

# Get last trade timestamp
$lastTrade = $trades[-1]
$lastTradeTime = [datetime]::Parse($lastTrade.entry_date)
$now = [datetime]::UtcNow
$hoursSinceLastTrade = ($now - $lastTradeTime).TotalHours

Write-Host "Último trade: $($lastTrade.market) em $($lastTrade.entry_date)" -ForegroundColor Gray
Write-Host "Horas desde: $([math]::Round($hoursSinceLastTrade, 1))h" -ForegroundColor Gray
Write-Host ""

# Check if alert needed
if ($hoursSinceLastTrade -gt $AlertThresholdHours) {
    Write-Host "[ALERT] Nenhum trade nos últimos $AlertThresholdHours horas!" -ForegroundColor Red
    Write-Host ""

    # Send Telegram alert
    if ($env:TELEGRAM_BOT_TOKEN -and $env:TELEGRAM_CHAT_ID) {
        $message = "🚨 ALERTA: Sistema parado!`n" +
                   "Nenhum trade nos últimos $AlertThresholdHours horas`n" +
                   "Último trade: $($lastTrade.market) às $($lastTrade.entry_date)`n" +
                   "`nVerifique logs: $tradeFile"

        try {
            $uri = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/sendMessage"
            $body = @{
                chat_id = $env:TELEGRAM_CHAT_ID
                text = $message
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json" | Out-Null
            Write-Host "✓ Alerta enviado via Telegram" -ForegroundColor Yellow
        } catch {
            Write-Host "✗ Falha ao enviar Telegram: $_" -ForegroundColor Red
        }
    }

    # Log alert
    $alertLog = "$JournalDir/heartbeat_alerts.jsonl"
    $alertEntry = @{
        timestamp = (Get-Date -Format 'o')
        hours_since_trade = [math]::Round($hoursSinceLastTrade, 1)
        last_trade_market = $lastTrade.market
        last_trade_time = $lastTrade.entry_date
        alert_sent = $true
    } | ConvertTo-Json

    Add-Content $alertLog $alertEntry
    Write-Host "✓ Alerta registrado em $alertLog" -ForegroundColor Yellow

    exit 1
} else {
    Write-Host "[OK] Sistema vivo" -ForegroundColor Green
    Write-Host "  Último trade: $([math]::Round($hoursSinceLastTrade, 1)) horas atrás" -ForegroundColor Gray
    exit 0
}
