# SETUP_COMPLETO_OCULTO_ADMIN.ps1
# Executar setup como administrador automaticamente
# 2026-05-24

# Verificar se esta rodando como admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "=== ELEVANDO PRIVILEGIOS ===" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Abrindo como Administrador..." -ForegroundColor Cyan
    Write-Host "Clique em 'Sim' na janela que vai aparecer!" -ForegroundColor Yellow
    Write-Host ""
    
    # Reexecutar como admin
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\SETUP_COMPLETO_OCULTO.ps1`"" -Verb RunAs
    exit
}

# Se chegou aqui, ja esta como admin
& "$PSScriptRoot\SETUP_COMPLETO_OCULTO.ps1"

Write-Host ""
Write-Host "Pressione Enter para fechar..." -ForegroundColor Gray
Read-Host
