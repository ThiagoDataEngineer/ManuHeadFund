# register_staleness_audit.ps1 -- Cron Mon 02:00 BRT staleness audit weekly.

param([switch]$Unregister, [switch]$DryRun)

$taskName    = "CoinExStalenessAudit"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "cron_staleness_audit.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    if ($DryRun) {
        Write-Host "[DRYRUN] Removeria '$taskName'" -ForegroundColor Cyan
    } else {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Existing task removida" -ForegroundColor Yellow
    }
}
if ($Unregister) {
    Write-Host "[OK] Unregistered" -ForegroundColor Green
    exit 0
}

# Proximo segunda 02:00 BRT
$now = Get-Date
$daysUntilMon = (1 - [int]$now.DayOfWeek + 7) % 7
if ($daysUntilMon -eq 0 -and $now.Hour -ge 2) { $daysUntilMon = 7 }
$startDate = $now.Date.AddDays($daysUntilMon).AddHours(2)

if ($DryRun) {
    Write-Host "[DRYRUN] Registraria $($taskName): Mondays 02:00 BRT, next=$startDate" -ForegroundColor Cyan
    exit 0
}

$argStr = '-NoProfile -ExecutionPolicy Bypass -File "' + $cronScript + '" -SendTg'
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $argStr `
    -WorkingDirectory $projectRoot

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At $startDate
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable -AllowStartIfOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$userId = "$($env:USERDOMAIN)\$($env:USERNAME)"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal `
        -Description "Weekly Mon 02:00 BRT: capital drift + staleness audit + TG alert HIGH" | Out-Null
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$v = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($v) {
    Write-Host "[OK] $taskName registrada: $($v.Triggers[0].StartBoundary)" -ForegroundColor Green
    exit 0
}
exit 1
