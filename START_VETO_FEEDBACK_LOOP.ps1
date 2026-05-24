# START_VETO_FEEDBACK_LOOP.ps1
# Inicia loop de processamento de veto feedback
# Executa continuamente a cada 30 minutos
# 2026-05-24

Write-Host "=== VETO FEEDBACK LOOP ===" -ForegroundColor Cyan
Write-Host "Processando fila de vetos a cada 30 minutos..." -ForegroundColor Yellow
Write-Host "Pressione Ctrl+C para parar" -ForegroundColor Gray
Write-Host ""

$scriptPath = "$PSScriptRoot\scripts\veto_feedback_processor.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "ERRO: Script nao encontrado: $scriptPath" -ForegroundColor Red
    exit 1
}

$iteration = 0

while ($true) {
    $iteration++
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    Write-Host "[$timestamp] Iteracao #$iteration" -ForegroundColor Cyan
    
    try {
        # Executar processador
        & $scriptPath
        
        Write-Host "  Concluido com sucesso" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERRO: $_" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "Aguardando 30 minutos ate proxima execucao..." -ForegroundColor Gray
    Write-Host ""
    
    # Aguardar 30 minutos
    Start-Sleep -Seconds 1800
}
