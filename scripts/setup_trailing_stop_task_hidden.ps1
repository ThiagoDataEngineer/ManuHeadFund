# scripts\setup_trailing_stop_task_hidden.ps1
# Configurar Task Scheduler para executar trailing stop monitor OCULTO (sem janela)
# 2026-05-24
# EXECUTAR COMO ADMINISTRADOR

$taskName = "CoinEx_TrailingStop_Monitor"
$scriptPath = "$PSScriptRoot\trailing_stop_monitor.ps1"
$workingDir = Split-Path -Parent $PSScriptRoot

Write-Host "=== CONFIGURAR TASK SCHEDULER (OCULTO) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Task Name: $taskName"
Write-Host "Script: $scriptPath"
Write-Host "Working Directory: $workingDir"
Write-Host "Frequency: Every 5 minutes"
Write-Host "Window: HIDDEN (sem janela)" -ForegroundColor Green
Write-Host ""

# Verificar se script existe
if (-not (Test-Path $scriptPath)) {
    Write-Host "ERROR: Script not found at $scriptPath" -ForegroundColor Red
    exit 1
}

# Verificar se já existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Task already exists. Removing..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Criar action COM -WindowStyle Hidden
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
    -WorkingDirectory $workingDir

# Criar trigger (a cada 5 minutos)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)

# Criar settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew `
    -Hidden  # Task oculta na lista

# Criar principal (executar como usuario atual, SEM Interactive)
# S4U (Service For User) permite rodar sem janela
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

# Registrar task
try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Monitor trailing stops for CoinEx positions every 5 minutes (HIDDEN)" `
        -ErrorAction Stop
    
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Task '$taskName' created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "CONFIGURACAO:" -ForegroundColor Cyan
    Write-Host "  - Executa a cada 5 minutos"
    Write-Host "  - Roda OCULTO (sem janela)" -ForegroundColor Green
    Write-Host "  - Logs em: $workingDir\logs\trailing_stop_monitor.log"
    Write-Host ""
    Write-Host "COMANDOS UTEIS:" -ForegroundColor Yellow
    Write-Host "  Ver task:     Get-ScheduledTask -TaskName '$taskName'"
    Write-Host "  Desabilitar:  Disable-ScheduledTask -TaskName '$taskName'"
    Write-Host "  Habilitar:    Enable-ScheduledTask -TaskName '$taskName'"
    Write-Host "  Remover:      Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false"
    Write-Host ""
    Write-Host "  Ver logs:     Get-Content logs\trailing_stop_monitor.log -Tail 50"
    Write-Host "  Ver logs ao vivo: Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait"
}
catch {
    Write-Host ""
    Write-Host "=== ERROR ===" -ForegroundColor Red
    Write-Host "$_"
    exit 1
}
