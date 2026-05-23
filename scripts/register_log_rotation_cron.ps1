# register_log_rotation_cron.ps1 -- B5 fix 2026-05-20 PM6.
# Agenda rotate_logs.ps1 daily 03:30 BRT (apos daily_daemon_restart 03:00).
#
# Uso:
#   pwsh -File scripts\register_log_rotation_cron.ps1
#   pwsh -File scripts\register_log_rotation_cron.ps1 -Unregister

param([switch]$Unregister)

$taskName    = "CoinExLogRotation"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript  = Join-Path $scriptRoot "rotate_logs.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removendo task existente '$taskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

if ($Unregister) {
    Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green
    exit 0
}

$action  = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At 3:30am
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Task '$taskName' agendada daily 03:30 local." -ForegroundColor Green
