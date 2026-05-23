# register_hourly_heartbeat.ps1 -- Cron hourly que envia watch_status snapshot ao TG.
#
# Resolve UX gap: scan_master em DAILY sleep 1440min nao envia heartbeat por 24h.
# User percebia sistema "morto". Este cron desacopla heartbeat do scan cycle.
#
# Uso:
#   pwsh -File scripts\register_hourly_heartbeat.ps1            # registra
#   pwsh -File scripts\register_hourly_heartbeat.ps1 -Unregister # remove

param([switch]$Unregister)

$taskName    = "CoinExHourlyHeartbeat"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript  = Join-Path $scriptRoot "watch_status.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
if ($Unregister) {
    Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green; exit 0
}

# Hourly trigger, starting em 5min
$startDate = (Get-Date).AddMinutes(5)
$trigger = New-ScheduledTaskTrigger -Once -At $startDate -RepetitionInterval (New-TimeSpan -Hours 1)
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`" -Telegram"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Hourly heartbeat (watch_status.ps1 -Telegram) -- desacoplado de scan cycle" | Out-Null

$task = Get-ScheduledTask -TaskName $taskName
Write-Host "[OK] Task '$taskName' registrada. Proxima execucao: $startDate" -ForegroundColor Green
Write-Host "  Acao: $($task.Actions.Execute) $($task.Actions.Arguments)" -ForegroundColor DarkGray
