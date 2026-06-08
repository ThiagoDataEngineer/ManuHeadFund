# Ativar GEM STRATEGIES em LIVE mode
. agents/lib_gem_router.ps1
Set-RouterMode -Mode "LIVE"
Show-RouterStatus

Write-Host "`n✅ GEM STRATEGIES LIVE ACTIVATED!" -ForegroundColor Green
Write-Host "   - PULL_BACK_RECOVERY: Detectando e operando LONGS" -ForegroundColor Green
Write-Host "   - DISTRIBUTION_SHORT: Detectando e operando SHORTS" -ForegroundColor Green
Write-Host "   - Capital: $2,750 alocado" -ForegroundColor Green
Write-Host "   - Monitoramento: Telegram alerts ativado" -ForegroundColor Green
