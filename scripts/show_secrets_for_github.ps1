# show_secrets_for_github.ps1 - Mostra os secrets para copiar no GitHub

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SECRETS PARA GITHUB ACTIONS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Carregar credenciais
. "$PSScriptRoot\..\agents\config.local.ps1"

Write-Host "Acesse: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/secrets/actions" -ForegroundColor Yellow
Write-Host "Clique em 'New repository secret' para cada um abaixo:`n" -ForegroundColor Yellow

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SECRET 1: COINEX_ACCESS_ID" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $env:COINEX_ACCESS_ID -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SECRET 2: COINEX_SECRET_KEY" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $env:COINEX_SECRET_KEY -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SECRET 3: TELEGRAM_BOT_TOKEN" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $env:TELEGRAM_BOT_TOKEN -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SECRET 4: TELEGRAM_CHAT_ID" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host $env:TELEGRAM_CHAT_ID -ForegroundColor White
Write-Host ""

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "INSTRUÇÕES" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "1. Copie cada valor acima" -ForegroundColor Gray
Write-Host "2. No GitHub, clique 'New repository secret'" -ForegroundColor Gray
Write-Host "3. Cole o NOME exatamente como mostrado (ex: COINEX_ACCESS_ID)" -ForegroundColor Gray
Write-Host "4. Cole o VALOR correspondente" -ForegroundColor Gray
Write-Host "5. Clique 'Add secret'" -ForegroundColor Gray
Write-Host "6. Repita para os 4 secrets`n" -ForegroundColor Gray

Write-Host "Após configurar os secrets:" -ForegroundColor Yellow
Write-Host "1. Habilite GitHub Actions: https://github.com/ThiagoDataEngineer/ManuHeadFund/settings/actions" -ForegroundColor Gray
Write-Host "2. Selecione 'Allow all actions and reusable workflows'" -ForegroundColor Gray
Write-Host "3. Selecione 'Read and write permissions'" -ForegroundColor Gray
Write-Host "4. Clique 'Save'`n" -ForegroundColor Gray

Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
