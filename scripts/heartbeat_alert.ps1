#!/usr/bin/env pwsh
# heartbeat_alert.ps1
# Monitora se o sistema esta vivo (trades fechando). Le trade_outcomes do SUPABASE
# (ground-truth cloud) com fallback para o JSONL local. Antes lia so o JSONL, que
# NUNCA existe em runner cloud -> alertava "file not found" em todo ciclo (bug).
# Se nenhum trade fechou em N horas -> alerta via Telegram. exit 0 vivo / 1 alerta.

param(
    [int]$AlertThresholdHours = 6,
    [string]$JournalDir = "journal"
)

$ErrorActionPreference = "Stop"
$agentsDir = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

# Config local (Telegram) se existir
if (Test-Path (Join-Path $agentsDir "config.local.ps1")) { . (Join-Path $agentsDir "config.local.ps1") }
. (Join-Path $agentsDir "lib_heartbeat.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

function Send-HeartbeatTelegram {
    param([string]$Text)
    if ($env:TELEGRAM_BOT_TOKEN -and $env:TELEGRAM_CHAT_ID) {
        try {
            $uri  = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/sendMessage"
            $body = @{ chat_id = $env:TELEGRAM_CHAT_ID; text = $Text } | ConvertTo-Json
            Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json" | Out-Null
        } catch { Write-Host "[WARN] Telegram falhou: $_" -ForegroundColor Yellow }
    }
}

Write-Host "== HEARTBEAT CHECK -- System Alive? ==" -ForegroundColor Cyan

# 1. Coleta outcomes: Supabase primeiro (cloud), fallback JSONL local
$outcomes = @()
$source = "none"
if ($env:SUPABASE_URL -and ($env:SUPABASE_SERVICE_KEY -or $env:SUPABASE_ANON_KEY)) {
    try {
        $global:STATE_STORE_BACKEND = "supabase"
        $global:STATE_STORE_SCHEMA  = "manuheadfund"
        $outcomes = @(Get-StateRecords -Table "trade_outcomes")
        $source = "supabase"
    } catch {
        Write-Host "[WARN] Supabase trade_outcomes falhou: $_" -ForegroundColor Yellow
    }
}
if ($source -ne "supabase") {
    $tradeFile = Join-Path $JournalDir "trade_outcomes.jsonl"
    if (Test-Path $tradeFile) {
        $outcomes = @(Get-Content $tradeFile -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
        $source = "local_jsonl"
    }
}
Write-Host "Fonte: $source | outcomes: $($outcomes.Count)" -ForegroundColor Gray

# 2. Decide via nucleo puro
$latest  = Select-LatestOutcomeClosedAt -Outcomes $outcomes
$verdict = Get-HeartbeatVerdict -LatestClosedAtUtc $latest -NowUtc ([datetime]::UtcNow) -ThresholdHours $AlertThresholdHours

if (-not $verdict.alert) {
    $h = [math]::Round($verdict.hours_since, 1)
    Write-Host "[OK] Sistema vivo (ultimo trade fechado ha ${h}h, fonte=$source)" -ForegroundColor Green
    exit 0
}

# 3. Alerta
if ($verdict.reason -eq "no_trades") {
    Write-Host "[ALERT] Nenhum trade fechado registrado (fonte=$source)" -ForegroundColor Red
    Send-HeartbeatTelegram -Text ("HEARTBEAT: nenhum trade fechado em $source.`n" +
        "Pode ser sistema parado OU ainda nao fechou nenhuma posicao.`n" +
        "Verifique se o pipeline esta entrando (LIVE_MODE_ENABLED.flag).")
} else {
    $h = [math]::Round($verdict.hours_since, 1)
    Write-Host "[ALERT] Nenhum trade fechado nas ultimas ${h}h (limite ${AlertThresholdHours}h)!" -ForegroundColor Red
    Send-HeartbeatTelegram -Text ("ALERTA: nenhum trade fechado ha ${h}h (limite ${AlertThresholdHours}h, fonte=$source).")
}

# log local best-effort
try {
    $alertLog = Join-Path $JournalDir "heartbeat_alerts.jsonl"
    @{ timestamp = (Get-Date -Format 'o'); reason = $verdict.reason; hours_since = $verdict.hours_since; source = $source; alert_sent = $true } |
        ConvertTo-Json -Compress | Add-Content $alertLog
} catch {}

exit 1
