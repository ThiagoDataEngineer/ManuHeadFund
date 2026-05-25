# scripts\setup_trailing_stop_task.ps1
# Configurar Task Scheduler para executar trailing stop monitor a cada 5 minutos
# 2026-05-24
# EXECUTAR COMO ADMINISTRADOR

$taskName = "CoinEx_TrailingStop_Monitor"
$scriptPath = (Join-Path $PSScriptRoot "trailing_stop_monitor.ps1")
$workingDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== CONFIGURAR TASK SCHEDULER ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Task Name: $taskName"
Write-Host "Script: $scriptPath"
Write-Host "Working Directory: $workingDir"
Write-Host "Frequency: Every 5 minutes"
Write-Host ""

# Verificar se script existe
if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found at $scriptPath" -ForegroundColor Red
    exit 1
}

# Verificar se jÃ¡ existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Task already exists. Removing..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Criar action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
    -WorkingDirectory $workingDir

# Criar trigger (a cada 5 minutos)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)

# Criar settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

# Criar principal (executar como usuario atual)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

# Registrar task
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Monitor trailing stops for CoinEx positions every 5 minutes" `
        -ErrorAction Stop
    
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Task '$taskName' created successfully!"
    Write-Host ""
    Write-Host "The task will run every 5 minutes starting now."
    Write-Host "Check logs at: $workingDir\logs\trailing_stop_monitor.log"
    Write-Host ""
    Write-Host "To view task: Get-ScheduledTask -TaskName '$taskName'"
    Write-Host "To disable: Disable-ScheduledTask -TaskName '$taskName'"
    Write-Host "To enable: Enable-ScheduledTask -TaskName '$taskName'"
    Write-Host "To remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
}
catch {
    Write-Host ""
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host "$_"
    exit 1
}
