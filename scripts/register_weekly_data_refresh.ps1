# register_weekly_data_refresh.ps1 -- Agenda weekly_data_refresh.ps1 no Task Scheduler.
# Roda Domingo 02:00 BRT (antes do CoinExPromotionCron Domingo 03:00).
#
# Uso:
#   pwsh -File scripts\register_weekly_data_refresh.ps1               # registra
#   pwsh -File scripts\register_weekly_data_refresh.ps1 -Unregister   # remove
#
# Requer Windows + PS elevado (admin) pra criar/deletar tasks.

param([switch]$Unregister)

$taskName    = "CoinExWeeklyDataRefresh"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "weekly_data_refresh.ps1"

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

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`"" `
    -WorkingDirectory $projectRoot

# Sabado 22:00 BRT: zero atividade TradFi global (NYSE/Nasdaq/B3/Asia fechados desde sex 17h).
# StartBoundary deve ser FUTURO (proximo sabado 22:00 a partir de agora).
$now = Get-Date
$daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
if ($daysUntilSat -eq 0) {
    # Hoje eh sabado: se ainda nao passou 22:00, fica hoje; senao proximo sabado
    if ($now.Hour -lt 22) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
}
$startDate = $now.Date.AddDays($daysUntilSat).AddHours(22)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At $startDate
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Refresh weekly: Binance funding history + cross-asset correlation matrix" | Out-Null

$verify = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($verify) {
    Write-Host "[OK] Task '$taskName' registrada: Sabados 22:00 BRT (TradFi global fechado)" -ForegroundColor Green
    Write-Host "  Script: $cronScript"
    Write-Host "  Proxima execucao: $($verify.Triggers[0].StartBoundary)"
    exit 0
}
Write-Host "[FAIL] Task nao registrada" -ForegroundColor Red
exit 1
