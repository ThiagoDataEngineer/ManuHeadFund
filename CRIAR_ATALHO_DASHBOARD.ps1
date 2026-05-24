# CRIAR_ATALHO_DASHBOARD.ps1
# Criar atalho do dashboard na area de trabalho
# 2026-05-24

Write-Host "=== CRIAR ATALHO DO DASHBOARD ===" -ForegroundColor Cyan
Write-Host ""

$desktopPath = [Environment]::GetFolderPath("Desktop")
$dashboardPath = "$PSScriptRoot\dashboard\index.html"
$shortcutPath = "$desktopPath\CoinEx Dashboard.url"

# Criar arquivo .url (atalho web)
$urlContent = @"
[InternetShortcut]
URL=file:///$($dashboardPath.Replace('\', '/'))
IconIndex=0
"@

$urlContent | Out-File -FilePath $shortcutPath -Encoding ASCII

Write-Host "[OK] Atalho criado na area de trabalho!" -ForegroundColor Green
Write-Host ""
Write-Host "Arquivo: $shortcutPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Agora voce pode:" -ForegroundColor Yellow
Write-Host "  1. Clicar no atalho 'CoinEx Dashboard' na area de trabalho" -ForegroundColor White
Write-Host "  2. Dashboard abre no navegador" -ForegroundColor White
Write-Host "  3. Atualiza automaticamente a cada 5 minutos" -ForegroundColor White
Write-Host ""
