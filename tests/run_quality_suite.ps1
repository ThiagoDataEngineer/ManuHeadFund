# tests\run_quality_suite.ps1
# Runner agregador dos testes de qualidade (trailing stale price + telegram).
# 2026-05-29

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot

$tests = @(
    'test_trailing_stale_price.ps1',
    'test_telegram_quality.ps1',
    'test_telegram_dedup_integration.ps1',
    'test_telegram_dedup_persist.ps1',
    'test_auto_market_analysis.ps1'
)

$allPass = $true
foreach ($t in $tests) {
    Write-Host ""
    Write-Host "### $t" -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here $t)
    if ($LASTEXITCODE -ne 0) { $allPass = $false }
}

Write-Host ""
if ($allPass) {
    Write-Host "==================================="
    Write-Host " TODOS OS TESTES PASSARAM" -ForegroundColor Green
    Write-Host "==================================="
    exit 0
} else {
    Write-Host "==================================="
    Write-Host " HOUVE FALHAS" -ForegroundColor Red
    Write-Host "==================================="
    exit 1
}
