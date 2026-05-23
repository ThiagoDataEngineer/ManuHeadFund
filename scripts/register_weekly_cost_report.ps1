# register_weekly_cost_report.ps1 -- Domingo 23:00 BRT
param([switch]$Unregister)

$taskName = "CoinExWeeklyCostReport"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript = Join-Path $scriptRoot "weekly_provider_cost_report.ps1"
if (-not (Test-Path $cronScript)) { Write-Host "[ERROR] $cronScript ausente" -ForegroundColor Red; exit 1 }

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
if ($Unregister) { Write-Host "Task '$taskName' desregistrada" -ForegroundColor Green; exit 0 }

# Sunday 23:00 BRT
$now = Get-Date
$daysUntilSunday = (7 - [int]$now.DayOfWeek) % 7
if ($daysUntilSunday -eq 0 -and $now.Hour -ge 23) { $daysUntilSunday = 7 }
$start = $now.Date.AddDays($daysUntilSunday).AddHours(23)

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $start
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Weekly provider cost + hallucination report (Domingo 23:00 BRT)" | Out-Null

Write-Host "[OK] Task '$taskName' registrada. NextRun: $start" -ForegroundColor Green
