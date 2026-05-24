# SETUP_FINAL_COMPLETO.ps1
# Setup final: Dashboard completo + Tasks ocultas
# EXECUTAR COMO ADMINISTRADOR

Write-Host "=== SETUP FINAL COMPLETO ===" -ForegroundColor Cyan
Write-Host ""

# Verificar admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Execute como ADMINISTRADOR!" -ForegroundColor Red
    Read-Host "Pressione Enter"
    exit 1
}

# 1. Atualizar task do dashboard para usar versão completa
Write-Host "[1/2] Atualizando task do dashboard..." -ForegroundColor Yellow

$taskName = "CoinEx_Update_Dashboard_HTML"
$scriptPath = "$PSScriptRoot\UPDATE_DASHBOARD_COMPLETO.ps1"

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" `
        -WorkingDirectory $PSScriptRoot
    
    Set-ScheduledTask -TaskName $taskName -Action $action | Out-Null
    Write-Host "  [OK] Task atualizada para dashboard completo" -ForegroundColor Green
} else {
    Write-Host "  [AVISO] Task nao encontrada, criando..." -ForegroundColor Yellow
    
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -Hidden
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" -WorkingDirectory $PSScriptRoot
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Update CoinEx dashboard HTML (COMPLETE)" | Out-Null
    Write-Host "  [OK] Task criada" -ForegroundColor Green
}

# 2. Atualizar dashboard agora
Write-Host ""
Write-Host "[2/2] Atualizando dashboard..." -ForegroundColor Yellow
& "$PSScriptRoot\UPDATE_DASHBOARD_COMPLETO.ps1"

Write-Host ""
Write-Host "=== SETUP COMPLETO ===" -ForegroundColor Green
Write-Host ""
Write-Host "DASHBOARD COMPLETO:" -ForegroundColor Cyan
Write-Host "  [OK] Posicoes com PNL" -ForegroundColor Green
Write-Host "  [OK] Tasks agendadas com status" -ForegroundColor Green
Write-Host "  [OK] Logs do sistema (ultimas 50 linhas)" -ForegroundColor Green
Write-Host "  [OK] Metricas completas" -ForegroundColor Green
Write-Host "  [OK] Auto-refresh a cada 5 minutos" -ForegroundColor Green
Write-Host ""
Write-Host "Abrir dashboard:" -ForegroundColor Yellow
Write-Host "  Start-Process '$PSScriptRoot\dashboard\index.html'" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pressione Enter para fechar..." -ForegroundColor Gray
Read-Host
