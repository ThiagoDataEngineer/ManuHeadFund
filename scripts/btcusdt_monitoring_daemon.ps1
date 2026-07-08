#requires -Version 5.1
<#
  BTCUSDT MONITORING DAEMON (24/7)

  Runs continuous tight monitoring for BTCUSDT (10x leverage)
  - Checks price every 30 seconds
  - Alerts on critical thresholds
  - Auto-creates new log file daily
  - Respects heartbeat protocol
#>

param(
  [string]$ConfigPath = ".\agents\config.ps1"
)

if (Test-Path $ConfigPath) { . $ConfigPath }

$logDir = ".\journal\btcusdt_monitoring"
if (-not (Test-Path $logDir)) {
  New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$pidFile = ".\journal\.btcusdt_monitoring.pid"
$heartbeatFile = ".\journal\.btcusdt_monitoring.heartbeat"

# Write PID
@{
  pid = $PID
  startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
  hostname = $env:COMPUTERNAME
} | ConvertTo-Json | Set-Content $pidFile

# Configuration
$config = @{
  entry = 63093.0
  sl = 58045.0
  exitDown = 61500.0      # HARD FLOOR - EXIT IMMEDIATELY
  exitUp = 63500.0        # BREAKOUT confirmation
  liquidation = 57069.05
  leverage = 10.0
  intervalSeconds = 30
  heartbeatIntervalSeconds = 300
  alertWebhook = $null    # Could add Telegram/webhook here
}

function Write-Log {
  param([string]$msg, [string]$level = "INFO")
  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
  $logFile = Join-Path $logDir "btcusdt_$(Get-Date -Format 'yyyyMMdd').log"
  $logMsg = "[$timestamp] [$level] $msg"
  Write-Host $logMsg
  Add-Content $logFile $logMsg -Force
}

function Update-Heartbeat {
  @{
    lastCheck = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    status = "monitoring"
    ticksProcessed = $script:tickCount
  } | ConvertTo-Json | Set-Content $heartbeatFile
}

Write-Log "BTCUSDT Monitoring Daemon Started"
Write-Host "🟢 BTCUSDT Monitoring Daemon RUNNING`n"

$script:tickCount = 0
$lastHeartbeat = Get-Date

while ($true) {
  $script:tickCount++

  # Heartbeat every 5 minutes
  $now = Get-Date
  if (($now - $lastHeartbeat).TotalSeconds -ge $config.heartbeatIntervalSeconds) {
    Update-Heartbeat
    $lastHeartbeat = $now
  }

  # TODO: Fetch real price from CoinEx API
  # $btcTicker = Get-BTC-Ticker
  # $price = $btcTicker.last

  # For production: replace with real API call
  $price = $config.entry + (Get-Random -Minimum -200 -Maximum 100)

  $priceDelta = $price - $config.entry
  $priceDeltaPct = ($priceDelta / $config.entry) * 100

  # CRITICAL: Price below exit floor
  if ($price -lt $config.exitDown) {
    Write-Log "🚨 CRITICAL: Price $price < EXIT DOWN $($config.exitDown). CLOSE IMMEDIATELY!" "CRITICAL"
    Write-Host "🚨 🚨 🚨 BTCUSDT BREAK BELOW EXIT FLOOR! CLOSE NOW! 🚨 🚨 🚨" -ForegroundColor Red

    # Alert via webhook if configured
    if ($config.alertWebhook) {
      # Invoke-WebRequest -Uri $config.alertWebhook -Method Post -Body @{ alert = "BTCUSDT EXIT CRITICAL" }
    }
  }

  # WARNING: Big move
  if ([math]::Abs($priceDeltaPct) -gt 1.5) {
    Write-Log "⚠️  BIG MOVE: Price $price ($([math]::Round($priceDeltaPct, 2))%)" "WARNING"
  }

  # BREAKOUT: Confirmed move up
  if ($price -gt $config.exitUp) {
    Write-Log "📈 BREAKOUT: Price $price > $($config.exitUp)" "INFO"
  }

  # Normal tick
  Write-Log "TICK $($script:tickCount) | Price: $price | Delta: $([math]::Round($priceDeltaPct, 2))%"

  Start-Sleep -Seconds $config.intervalSeconds
}
