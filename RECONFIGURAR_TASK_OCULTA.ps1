# RECONFIGURAR_TASK_OCULTA.ps1
# Reconfigurar task existente para rodar OCULTA (sem janela)
# 2026-05-24

Write-Host "=== RECONFIGURAR TASK PARA RODAR OCULTA ===" -ForegroundColor Cyan
Write-Host ""

$taskName = "CoinEx_TrailingStop_Monitor"

# Verificar se task existe
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if (-not $existingTask) {
    Write-Host "Task '$taskName' nao encontrada!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Execute primeiro:" -ForegroundColor Yellow
    Write-Host "  .\scripts\setup_trailing_stop_task_hidden.ps1"
    exit 1
}

Write-Host "Task encontrada. Status: $($existingTask.State)" -ForegroundColor Green
Write-Host ""
Write-Host "Removendo task antiga..." -ForegroundColor Yellow

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
    Write-Host "Task removida." -ForegroundColor Green
}
catch {
    Write-Host "ERRO ao remover task: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Criando nova task OCULTA..." -ForegroundColor Yellow
Write-Host ""

# Executar setup com configuracao oculta
& "$PSScriptRoot\scripts\setup_trailing_stop_task_hidden.ps1"
