# ATUALIZAR_DASHBOARD_AGORA.ps1
# Atualiza dashboard com dados reais
# 2026-05-24

Write-Host "=== ATUALIZANDO DASHBOARD ===" -ForegroundColor Cyan

# Coletar dados
Write-Host "Coletando dados..." -ForegroundColor Yellow
$dataJson = & "$PSScriptRoot\scripts\collect_dashboard_data.ps1"
$data = $dataJson | ConvertFrom-Json

# Buscar posicoes
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
$positions = CoinEx-GetPendingPositions
$capital = CoinEx-GetFuturesCapitalUSDT

Write-Host "Dados coletados com sucesso!" -ForegroundColor Green
Write-Host "  Posicoes: $($positions.Count)" -ForegroundColor Cyan
Write-Host "  Capital: `$$([Math]::Round($capital, 2))" -ForegroundColor Cyan
Write-Host ""

# Atualizar HTML usando script Python
Write-Host "Gerando HTML..." -ForegroundColor Yellow

$htmlPath = "$PSScriptRoot\dashboard\index.html"

# Backup do HTML atual
if (Test-Path $htmlPath) {
    Copy-Item $htmlPath "$htmlPath.bak" -Force
    Write-Host "Backup criado: index.html.bak" -ForegroundColor Gray
}

# Gerar novo HTML via script externo
& "$PSScriptRoot\scripts\generate_dashboard_html.ps1" -Data $data -Positions $positions -Capital $capital -OutputPath $htmlPath

Write-Host ""
Write-Host "Dashboard atualizado!" -ForegroundColor Green
Write-Host "Arquivo: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Abrindo no navegador..." -ForegroundColor Yellow
Start-Process $htmlPath
