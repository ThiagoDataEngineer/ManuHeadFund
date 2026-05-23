# register_daemon_restart.ps1 -- Agenda daily_daemon_restart 03:00 BRT (rolling)

param([switch]$Unregister)

$taskName = "CoinExDaemonRestart"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript = Join-Path $scriptRoot "daily_daemon_restart.ps1"
if (-not (Test-Path $cronScript)) { Write-Host "[ERROR] $cronScript ausente" -ForegroundColor Red; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
if ($Unregister) { Write-Host "Task '$taskName' desregistrada" -ForegroundColor Green; exit 0 }

# 03:00 BRT daily (entre PromotionCron 02:00 e KellyGraduation 02:35)
$now = Get-Date
$start = if ($now.Hour -lt 3) {
    $now.Date.AddHours(3)
} else {
    $now.Date.AddDays(1).AddHours(3)
}
$trigger = New-ScheduledTaskTrigger -Daily -At $start
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Daily rolling restart de daemons 03:00 BRT (anti-drift)" | Out-Null

Write-Host "[OK] Task '$taskName' registrada. NextRun: $start" -ForegroundColor Green
