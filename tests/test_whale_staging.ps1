# test_whale_staging.ps1 - Teste de staging com dados reais
# Valida que ChainAgent funciona end-to-end com whale detection
$ErrorActionPreference = "Stop"

Write-Host "`n=== TESTE STAGING WHALE DETECTION ===" -ForegroundColor Cyan
Write-Host "Testando ChainAgent com whale detection em ambiente real" -ForegroundColor Yellow

# Carregar dependencias
. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_claude.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_whale_detection.ps1"
. "$PSScriptRoot\..\agents\lib_cycle_mocks.ps1"
. "$PSScriptRoot\..\agents\lib_cycle_context.ps1"
. "$PSScriptRoot\..\agents\chain_agent.ps1"

Write-Host "`n[1/3] Testar Get-RecentWhaleActivity com dados reais" -ForegroundColor Yellow
try {
    $whaleData = Get-RecentWhaleActivity -MinBtc 100 -LastHours 24
    Write-Host "  Whale Detection:" -ForegroundColor White
    Write-Host "    Net Signal: $($whaleData.netSignal)" -ForegroundColor Cyan
    Write-Host "    Total BTC: $($whaleData.totalBtc)" -ForegroundColor Cyan
    Write-Host "    Score Impact: $($whaleData.scoreImpact)" -ForegroundColor Cyan
    Write-Host "    Count: $($whaleData.count)" -ForegroundColor Cyan
    Write-Host "  PASS: Get-RecentWhaleActivity funcionou" -ForegroundColor Green
    $test1 = $true
} catch {
    Write-Host "  FAIL: Get-RecentWhaleActivity falhou: $_" -ForegroundColor Red
    $test1 = $false
}

Write-Host "`n[2/3] Testar Invoke-ChainAgent com whale detection" -ForegroundColor Yellow
try {
    # Desabilitar Claude para testar fallback (mais rapido)
    $env:AGENT_CHAIN_PROVIDER = "none"
    
    $chainResult = Invoke-ChainAgent -Market "BTCUSDT"
    
    Write-Host "  ChainAgent Result:" -ForegroundColor White
    Write-Host "    chain_score: $($chainResult.chain_score)" -ForegroundColor Cyan
    Write-Host "    chain_bias: $($chainResult.chain_bias)" -ForegroundColor Cyan
    Write-Host "    whale_detection: $($chainResult.whale_detection)" -ForegroundColor Cyan
    
    if ($chainResult.whale_detection) {
        Write-Host "  PASS: whale_detection presente no resultado" -ForegroundColor Green
        $test2 = $true
    } else {
        Write-Host "  FAIL: whale_detection ausente no resultado" -ForegroundColor Red
        $test2 = $false
    }
} catch {
    Write-Host "  FAIL: Invoke-ChainAgent falhou: $_" -ForegroundColor Red
    $test2 = $false
}

Write-Host "`n[3/3] Validar que chain_score foi calculado" -ForegroundColor Yellow
if ($chainResult -and $chainResult.chain_score -ge 0 -and $chainResult.chain_score -le 100) {
    Write-Host "  PASS: chain_score valido ($($chainResult.chain_score))" -ForegroundColor Green
    $test3 = $true
} else {
    Write-Host "  FAIL: chain_score invalido" -ForegroundColor Red
    $test3 = $false
}

# RESUMO
Write-Host "`n=== RESUMO ===" -ForegroundColor White
$totalPassed = @($test1, $test2, $test3) | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
Write-Host "Passed: $totalPassed/3" -ForegroundColor $(if($totalPassed -eq 3){"Green"}else{"Yellow"})
Write-Host "Failed: $(3 - $totalPassed)/3" -ForegroundColor $(if($totalPassed -eq 3){"Green"}else{"Red"})

if ($totalPassed -eq 3) {
    Write-Host "`nSTAGING VALIDADO! Sistema funcionando end-to-end" -ForegroundColor Green
    Write-Host "Proximo: Deploy em producao" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nSTAGING FALHOU - revisar erros acima" -ForegroundColor Red
    exit 1
}
