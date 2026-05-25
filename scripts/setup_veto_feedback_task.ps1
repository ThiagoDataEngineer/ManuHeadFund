# setup_veto_feedback_task.ps1
# Criar Task Scheduler para veto_feedback_processor.ps1
# Executa a cada 30 minutos
# 2026-05-24

$ErrorActionPreference = "Stop"

Write-Host "=== CONFIGURAR TASK: VETO FEEDBACK PROCESSOR ===" -ForegroundColor Cyan
Write-Host ""

# Parametros
$taskName = "CoinEx_VetoFeedback_Processor"
$scriptPath = (Join-Path $PSScriptRoot "veto_feedback_processor.ps1")
$workingDir = Split-Path -Parent $PSScriptRoot

# Verificar se script existe
if (-not (Test-Path $scriptPath)) {
    Write-Host "ERRO: Script nao encontrado: $scriptPath" -ForegroundColor Red
    exit 1
}

# Verificar se task ja existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existingTask) {
    Write-Host "Task '$taskName' ja existe. Removendo..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Criar action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
    -WorkingDirectory $workingDir

# Criar trigger (a cada 30 minutos)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)

# Criar settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Criar principal (usuario atual)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

# Registrar task
Write-Host "Criando task '$taskName'..." -ForegroundColor Yellow
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Processa fila de vetos e executa acoes corretivas automaticas (a cada 30min)" | Out-Null

Write-Host "Task criada com sucesso!" -ForegroundColor Green
Write-Host ""

# Verificar
$task = Get-ScheduledTask -TaskName $taskName
Write-Host "Status da task:" -ForegroundColor Cyan
Write-Host "  Nome: $($task.TaskName)"
Write-Host "  Estado: $($task.State)"
Write-Host "  Proxima execucao: $((Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime)"
Write-Host ""

# Executar agora para testar
Write-Host "Deseja executar a task agora para testar? (S/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "S" -or $response -eq "s") {
    Write-Host "Executando task..." -ForegroundColor Yellow
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 3
    
    Write-Host ""
    Write-Host "Verificando log..." -ForegroundColor Cyan
    $logFile = (Join-Path (Join-Path $workingDir "logs") "veto_feedback_processor.log")
    if (Test-Path $logFile) {
        Get-Content $logFile -Tail 20
    } else {
        Write-Host "Log ainda nao foi criado." -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "=== CONFIGURACAO CONCLUIDA ===" -ForegroundColor Green
Write-Host ""
Write-Host "A task '$taskName' esta configurada para executar a cada 30 minutos." -ForegroundColor White
Write-Host "Log: logs\veto_feedback_processor.log" -ForegroundColor Gray
