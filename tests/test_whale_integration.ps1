# test_whale_integration.ps1 - Teste de integracao ChainAgent + Whale Detection
# TDD: Validar que whale detection foi integrado corretamente
$ErrorActionPreference = "Stop"

Write-Host "`n=== TESTE INTEGRACAO WHALE DETECTION ===" -ForegroundColor Cyan
Write-Host "Validando que ChainAgent carrega lib_whale_detection e chama Get-RecentWhaleActivity" -ForegroundColor Yellow

# TEST 1: Verificar que lib_whale_detection foi carregado
Write-Host "`n[1/4] Verificar que lib_whale_detection.ps1 existe" -ForegroundColor Yellow
$libPath = "$PSScriptRoot\..\agents\lib_whale_detection.ps1"
if (Test-Path $libPath) {
    Write-Host "  PASS: lib_whale_detection.ps1 encontrado" -ForegroundColor Green
    $passed1 = $true
} else {
    Write-Host "  FAIL: lib_whale_detection.ps1 nao encontrado" -ForegroundColor Red
    $passed1 = $false
}

# TEST 2: Verificar que chain_agent.ps1 importa lib_whale_detection
Write-Host "`n[2/4] Verificar que chain_agent.ps1 importa lib_whale_detection" -ForegroundColor Yellow
$chainPath = "$PSScriptRoot\..\agents\chain_agent.ps1"
$chainContent = Get-Content $chainPath -Raw
if ($chainContent -match 'lib_whale_detection\.ps1') {
    Write-Host "  PASS: chain_agent.ps1 importa lib_whale_detection" -ForegroundColor Green
    $passed2 = $true
} else {
    Write-Host "  FAIL: chain_agent.ps1 NAO importa lib_whale_detection" -ForegroundColor Red
    $passed2 = $false
}

# TEST 3: Verificar que Invoke-ChainAgent chama Get-RecentWhaleActivity
Write-Host "`n[3/4] Verificar que Invoke-ChainAgent chama Get-RecentWhaleActivity" -ForegroundColor Yellow
if ($chainContent -match 'Get-RecentWhaleActivity') {
    Write-Host "  PASS: Invoke-ChainAgent chama Get-RecentWhaleActivity" -ForegroundColor Green
    $passed3 = $true
} else {
    Write-Host "  FAIL: Invoke-ChainAgent NAO chama Get-RecentWhaleActivity" -ForegroundColor Red
    $passed3 = $false
}

# TEST 4: Verificar que whale_detection esta no JSON response
Write-Host "`n[4/4] Verificar que whale_detection esta no JSON response esperado" -ForegroundColor Yellow
if ($chainContent -match '"whale_detection"') {
    Write-Host "  PASS: whale_detection esta no JSON response" -ForegroundColor Green
    $passed4 = $true
} else {
    Write-Host "  FAIL: whale_detection NAO esta no JSON response" -ForegroundColor Red
    $passed4 = $false
}

# RESUMO
Write-Host "`n=== RESUMO ===" -ForegroundColor White
$totalPassed = @($passed1, $passed2, $passed3, $passed4) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "Passed: $totalPassed/4" -ForegroundColor $(if($totalPassed -eq 4){"Green"}else{"Yellow"})
Write-Host "Failed: $(4 - $totalPassed)/4" -ForegroundColor $(if($totalPassed -eq 4){"Green"}else{"Red"})

if ($totalPassed -eq 4) {
    Write-Host "`nINTEGRACAO VALIDADA! Whale Detection integrado no ChainAgent" -ForegroundColor Green
    Write-Host "Proximo: Testar em staging com dados reais" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nINTEGRACAO INCOMPLETA" -ForegroundColor Red
    exit 1
}
