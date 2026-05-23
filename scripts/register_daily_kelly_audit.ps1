# register_daily_kelly_audit.ps1 -- Agenda daily 02:35 BRT.
param([switch]$Unregister)

$taskName = "CoinExKellyGraduation"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript = Join-Path $scriptRoot "daily_kelly_audit.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red; exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }
if ($Unregister) { Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green; exit 0 }

$now = Get-Date
$startDate = if ($now.Hour -lt 2 -or ($now.Hour -eq 2 -and $now.Minute -lt 35)) {
    $now.Date.AddHours(2).AddMinutes(35)
} else {
    $now.Date.AddDays(1).AddHours(2).AddMinutes(35)
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`"" `
    -WorkingDirectory $projectRoot

$trigger = New-ScheduledTaskTrigger -Daily -At $startDate
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Daily Kelly graduation audit: auto-enable USE_KELLY_SIZING quando criterios passam" | Out-Null

$verify = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($verify) {
    Write-Host "[OK] Task '$taskName' registrada: daily 02:35 BRT" -ForegroundColor Green
    Write-Host "  Proximo: $((Get-ScheduledTaskInfo $verify).NextRunTime)"
    exit 0
}
Write-Host "[FAIL] Task nao registrada" -ForegroundColor Red
exit 1
