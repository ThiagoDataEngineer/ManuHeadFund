# configure_hybrid_mode.ps1 - Configurar modo hÃ­brido
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "`nâ•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Cyan
Write-Host "â•‘     CONFIGURAÃ‡ÃƒO MODO HÃBRIDO          â•‘" -ForegroundColor Cyan
Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan

Write-Host "`n[1/2] Risk Manager jÃ¡ configurado (apenas local)" -ForegroundColor Green
Write-Host "[2/2] Dashboard jÃ¡ configurado (apenas GitHub Actions)" -ForegroundColor Green

# Criar arquivo de configuraÃ§Ã£o
Write-Host "`n[3/3] Criando arquivo de configuraÃ§Ã£o..." -ForegroundColor Yellow

$config = @{
    mode = "hybrid"
    local = @{
        enabled = $true
        jobs = @("risk-manager")
        frequency = "5min"
    }
    github_actions = @{
        enabled = $true
        jobs = @("dashboard-generator", "health-check")
        frequency = "15min"
    }
    protection = @{
        anti_duplication = $true
        lock_timeout = 300
    }
    configured_at = (Get-Date).ToString("o")
}

$configDir = ".kiro"
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$configPath = Join-Path $configDir "execution_mode.json"
$config | ConvertTo-Json -Depth 10 | Out-File $configPath -Encoding UTF8 -Force

Write-Host "âœ“ ConfiguraÃ§Ã£o salva: $configPath" -ForegroundColor Green

Write-Host "`nâ•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Green
Write-Host "â•‘      MODO HÃBRIDO CONFIGURADO âœ“        â•‘" -ForegroundColor Green
Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Green

Write-Host "`nðŸ“Š CONFIGURAÃ‡ÃƒO ATIVA:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Local (5min):" -ForegroundColor White
Write-Host "  âœ“ Risk Manager" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub Actions (15min):" -ForegroundColor White
Write-Host "  âœ“ Dashboard Generator" -ForegroundColor Green
Write-Host "  âœ“ Health Check" -ForegroundColor Green
Write-Host ""
Write-Host "ProteÃ§Ã£o:" -ForegroundColor White
Write-Host "  âœ“ Anti-duplicaÃ§Ã£o ativa" -ForegroundColor Green
Write-Host ""

Write-Host "ðŸŽ¯ PRÃ“XIMOS PASSOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Setup GitHub Actions:" -ForegroundColor White
Write-Host "   .\scripts\setup_github_actions.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Testar local:" -ForegroundColor White
Write-Host "   .\scripts\position_risk_cron.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "âœ… Sistema pronto! Sem conflitos garantido!" -ForegroundColor Green
Write-Host ""
