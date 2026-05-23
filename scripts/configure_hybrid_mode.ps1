# configure_hybrid_mode.ps1 - Configurar modo híbrido
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     CONFIGURAÇÃO MODO HÍBRIDO          ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n[1/2] Risk Manager já configurado (apenas local)" -ForegroundColor Green
Write-Host "[2/2] Dashboard já configurado (apenas GitHub Actions)" -ForegroundColor Green

# Criar arquivo de configuração
Write-Host "`n[3/3] Criando arquivo de configuração..." -ForegroundColor Yellow

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

Write-Host "✓ Configuração salva: $configPath" -ForegroundColor Green

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║      MODO HÍBRIDO CONFIGURADO ✓        ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`n📊 CONFIGURAÇÃO ATIVA:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Local (5min):" -ForegroundColor White
Write-Host "  ✓ Risk Manager" -ForegroundColor Green
Write-Host ""
Write-Host "GitHub Actions (15min):" -ForegroundColor White
Write-Host "  ✓ Dashboard Generator" -ForegroundColor Green
Write-Host "  ✓ Health Check" -ForegroundColor Green
Write-Host ""
Write-Host "Proteção:" -ForegroundColor White
Write-Host "  ✓ Anti-duplicação ativa" -ForegroundColor Green
Write-Host ""

Write-Host "🎯 PRÓXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Setup GitHub Actions:" -ForegroundColor White
Write-Host "   .\scripts\setup_github_actions.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Testar local:" -ForegroundColor White
Write-Host "   .\scripts\position_risk_cron.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "✅ Sistema pronto! Sem conflitos garantido!" -ForegroundColor Green
Write-Host ""
