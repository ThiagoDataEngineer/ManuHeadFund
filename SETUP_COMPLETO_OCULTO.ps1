# SETUP_COMPLETO_OCULTO.ps1
# Configurar TUDO para rodar oculto + Dashboard HTML
# 2026-05-24

Write-Host "=== SETUP COMPLETO - MODO OCULTO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configurando sistema para rodar 100% em background..." -ForegroundColor Yellow
Write-Host "Voce vai usar apenas o Dashboard HTML no navegador!" -ForegroundColor Green
Write-Host ""

# 1. Reconfigurar task existente para oculto
Write-Host "[1/4] Reconfigurando trailing stop monitor para oculto..." -ForegroundColor Cyan
& "$PSScriptRoot\RECONFIGURAR_TASK_OCULTA.ps1"

Write-Host ""
Write-Host "[2/4] Criando task para atualizar dashboard HTML automaticamente..." -ForegroundColor Cyan

# 2. Criar task para atualizar dashboard HTML a cada 5 minutos
$taskName = "CoinEx_Update_Dashboard_HTML"
$scriptPath = "$PSScriptRoot\UPDATE_DASHBOARD_HTML.ps1"
$workingDir = $PSScriptRoot

# Remover task antiga se existir
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "  Removendo task antiga..." -ForegroundColor Yellow
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
    -Hidden

# Criar principal (executar como usuario atual, SEM Interactive)
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType S4U `
    -RunLevel Limited

# Registrar task
Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Update CoinEx dashboard HTML every 5 minutes (HIDDEN)" `
    -ErrorAction Stop | Out-Null

Write-Host "  [OK] Task criada: $taskName" -ForegroundColor Green

Write-Host ""
Write-Host "[3/4] Atualizando dashboard HTML agora..." -ForegroundColor Cyan
& "$PSScriptRoot\UPDATE_DASHBOARD_HTML.ps1"

Write-Host ""
Write-Host "[4/4] Abrindo dashboard no navegador..." -ForegroundColor Cyan
Start-Sleep -Seconds 2
Start-Process "$PSScriptRoot\dashboard\index.html"

Write-Host ""
Write-Host "=== SETUP COMPLETO ===" -ForegroundColor Green
Write-Host ""
Write-Host "CONFIGURACAO:" -ForegroundColor Cyan
Write-Host "  [OK] Trailing stop monitor: OCULTO (a cada 5 min)" -ForegroundColor Green
Write-Host "  [OK] Dashboard HTML update: OCULTO (a cada 5 min)" -ForegroundColor Green
Write-Host "  [OK] Dashboard aberto no navegador" -ForegroundColor Green
Write-Host ""
Write-Host "COMO USAR:" -ForegroundColor Yellow
Write-Host "  1. Deixe o dashboard HTML aberto no navegador" -ForegroundColor White
Write-Host "  2. Ele atualiza automaticamente a cada 5 minutos" -ForegroundColor White
Write-Host "  3. Nenhuma janela do PowerShell vai aparecer!" -ForegroundColor White
Write-Host ""
Write-Host "TASKS ATIVAS:" -ForegroundColor Yellow
Write-Host "  - CoinEx_TrailingStop_Monitor (oculto)" -ForegroundColor White
Write-Host "  - CoinEx_Update_Dashboard_HTML (oculto)" -ForegroundColor White
Write-Host ""
Write-Host "ABRIR DASHBOARD MANUALMENTE:" -ForegroundColor Yellow
Write-Host "  Start-Process '$PSScriptRoot\dashboard\index.html'" -ForegroundColor Cyan
Write-Host ""
Write-Host "VER LOGS (se precisar):" -ForegroundColor Yellow
Write-Host "  Get-Content logs\trailing_stop_monitor.log -Tail 50" -ForegroundColor Cyan
Write-Host ""
Write-Host "DESABILITAR TASKS (se precisar):" -ForegroundColor Yellow
Write-Host "  Disable-ScheduledTask -TaskName 'CoinEx_TrailingStop_Monitor'" -ForegroundColor Cyan
Write-Host "  Disable-ScheduledTask -TaskName 'CoinEx_Update_Dashboard_HTML'" -ForegroundColor Cyan
Write-Host ""
