# register_daily_digest.ps1 -- Agenda daily_summary_digest 23:55 BRT

param([switch]$Unregister)

$taskName    = "CoinExDailyDigest"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript  = Join-Path $scriptRoot "daily_summary_digest.ps1"

if (-not (Test-Path $cronScript)) { Write-Host "[ERROR] $cronScript ausente" -ForegroundColor Red; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
if ($Unregister) { Write-Host "Task '$taskName' desregistrada" -ForegroundColor Green; exit 0 }

# 23:55 daily
$now = Get-Date
$start = if ($now.Hour -lt 23 -or ($now.Hour -eq 23 -and $now.Minute -lt 55)) {
    $now.Date.AddHours(23).AddMinutes(55)
} else {
    $now.Date.AddDays(1).AddHours(23).AddMinutes(55)
}
$trigger = New-ScheduledTaskTrigger -Daily -At $start
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Daily summary digest 23:55 BRT (Mentor stats, drawdown, crons, missing cmds)" | Out-Null

Write-Host "[OK] Task '$taskName' registrada. NextRun: $start" -ForegroundColor Green
