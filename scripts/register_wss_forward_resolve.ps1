# register_wss_forward_resolve.ps1 -- Agenda cron_wss_forward_resolve.ps1.
# Roda Sabados 23:00 BRT (apos CoinExWeeklyDataRefresh 22:00 + WeeklyCostReport 23:00).
#
# Caminho 2 (2026-05-23): completa loop de forward validation —
# pending signals resolved + audit alert TG se hit_rate >=60% (confirmed)
# ou <=30% (refuted) sobre n>=10.
#
# Uso:
#   pwsh -File scripts\register_wss_forward_resolve.ps1               # registra
#   pwsh -File scripts\register_wss_forward_resolve.ps1 -Unregister   # remove
#   pwsh -File scripts\register_wss_forward_resolve.ps1 -DryRun       # show what would be done
#
# Requer Windows + PS elevado (admin) pra criar/deletar tasks.

param(
    [switch]$Unregister,
    [switch]$DryRun
)

$taskName    = "CoinExWssForwardResolve"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "cron_wss_forward_resolve.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

# Idempotente: remove existente antes de re-registrar
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    if ($DryRun) {
        Write-Host "[DRYRUN] Removeria task existente '$taskName'" -ForegroundColor Cyan
    } else {
        Write-Host "Removendo task existente '$taskName'..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}
if ($Unregister) {
    if ($DryRun) {
        Write-Host "[DRYRUN] Operacao seria desregistrar." -ForegroundColor Cyan
    } else {
        Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green
    }
    exit 0
}

# Calcula proximo Sabado 23:00 BRT
$now = Get-Date
$daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
if ($daysUntilSat -eq 0) {
    if ($now.Hour -lt 23) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
}
$startDate = $now.Date.AddDays($daysUntilSat).AddHours(23)

if ($DryRun) {
    Write-Host "[DRYRUN] Registraria CoinExWssForwardResolve:" -ForegroundColor Cyan
    Write-Host "  Script: $cronScript"
    Write-Host "  Trigger: Weekly Saturday 23:00 BRT"
    Write-Host "  Proxima execucao: $startDate"
    Write-Host "  Slot: apos CoinExWeeklyDataRefresh 22:00 + WeeklyCostReport 23:55"
    exit 0
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`"" `
    -WorkingDirectory $projectRoot

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At $startDate
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Weekly: resolve pending WSS forward signals + TG audit alert se hit_rate confirma/refuta thesis (n>=10)" | Out-Null
} catch {
    Write-Host "[FAIL] Register exception: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$verify = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($verify) {
    Write-Host "[OK] Task '$taskName' registrada: Sabados 23:00 BRT" -ForegroundColor Green
    Write-Host "  Script: $cronScript"
    Write-Host "  Proxima execucao: $($verify.Triggers[0].StartBoundary)"
    Write-Host "  Audit threshold: hit_rate>=60% confirma | <=30% refuta | 30-60% inconclusive"
    exit 0
}
Write-Host "[FAIL] Task nao registrada (verify returned null)" -ForegroundColor Red
exit 1
