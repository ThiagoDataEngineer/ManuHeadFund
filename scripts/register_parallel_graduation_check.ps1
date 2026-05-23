# register_parallel_graduation_check.ps1 -- Agenda parallel_health_check daily 02:30 BRT.
# Quando criterios passarem 7d consecutivos -> auto-enable -Parallel default.

param([switch]$Unregister)

$taskName    = "CoinExParallelGraduation"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "parallel_health_check.ps1"

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

# Daily 02:30 BRT (entre data refresh 22h sabado e promotion cron 03h domingo,
# e em dias uteis tambem). StartBoundary FUTURO obrigatorio.
$now = Get-Date
$startDate = if ($now.Hour -lt 2 -or ($now.Hour -eq 2 -and $now.Minute -lt 30)) {
    $now.Date.AddHours(2).AddMinutes(30)
} else {
    $now.Date.AddDays(1).AddHours(2).AddMinutes(30)
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`" -Enable" `
    -WorkingDirectory $projectRoot

$trigger = New-ScheduledTaskTrigger -Daily -At $startDate
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Daily audit: auto-enable -Parallel quando 5 criterios passarem" | Out-Null

$verify = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($verify) {
    Write-Host "[OK] Task '$taskName' registrada: daily 02:30 BRT" -ForegroundColor Green
    Write-Host "  Comportamento: roda parallel_health_check -Enable; se 5 criterios passarem, cria flag automaticamente"
    Write-Host "  Manual override: .\scripts\parallel_health_check.ps1 -Enable (a qualquer momento)"
    Write-Host "  Disable:         .\scripts\parallel_health_check.ps1 -Disable"
    Write-Host "  Proximo run: $((Get-ScheduledTaskInfo $verify).NextRunTime)"
    exit 0
}
Write-Host "[FAIL] Task nao registrada" -ForegroundColor Red
exit 1
