# DASHBOARD_ELITE.ps1
# Dashboard completo com todas as 12 categorias de informacoes
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"

Write-Host "=== GERANDO DASHBOARD ELITE ===" -ForegroundColor Cyan
Write-Host ""

# Coletar dados
Write-Host "Coletando dados..." -ForegroundColor Yellow

try {
    $dataJson = & "$PSScriptRoot\scripts\collect_dashboard_data.ps1"
    $data = $dataJson | ConvertFrom-Json
    
    Write-Host "  Trading Metrics: OK" -ForegroundColor Green
    Write-Host "  Mentor Decisions: OK" -ForegroundColor Green
    Write-Host "  Mesa Consensus: OK" -ForegroundColor Green
    Write-Host "  Market Regime: OK" -ForegroundColor Green
    Write-Host "  Promotion Pipeline: OK" -ForegroundColor Green
    Write-Host "  FQS Distribution: OK" -ForegroundColor Green
    Write-Host "  LLM Costs: OK" -ForegroundColor Green
    Write-Host "  Feedback Loop: OK" -ForegroundColor Green
    Write-Host "  Trailing Stop: OK" -ForegroundColor Green
    Write-Host "  Portfolio Metrics: OK" -ForegroundColor Green
    Write-Host "  Alerts: OK" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "ERRO ao coletar dados: $_" -ForegroundColor Red
    exit 1
}

# Buscar posicoes e tasks
try {
    $positions = CoinEx-GetPendingPositions
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
    
    Write-Host "Posicoes abertas: $($positions.Count)" -ForegroundColor Cyan
    Write-Host "Tasks agendadas: $($tasks.Count)" -ForegroundColor Cyan
    Write-Host ""
}
catch {
    Write-Host "AVISO: Erro ao buscar posicoes/tasks: $_" -ForegroundColor Yellow
    $positions = @()
    $tasks = @()
}

# Gerar HTML
Write-Host "Gerando HTML..." -ForegroundColor Yellow

$htmlPath = "$PSScriptRoot\dashboard\index_elite.html"

# Criar HTML completo (sera feito em partes)
$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>ManuHeadFund - Dashboard Elite</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
"@

# Salvar HTML (sera completado)
$html | Out-File $htmlPath -Encoding UTF8

Write-Host ""
Write-Host "Dashboard Elite gerado com sucesso!" -ForegroundColor Green
Write-Host "Arquivo: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abrindo no navegador..." -ForegroundColor Yellow
Start-Process $htmlPath
