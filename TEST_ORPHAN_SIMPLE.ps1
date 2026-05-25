# TEST_ORPHAN_SIMPLE.ps1
# Teste simplificado de detecção de órfãs
$ErrorActionPreference = "Stop"

# Carregar libs
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_trailing.ps1"
. "$PSScriptRoot\agents\lib_trailing_orphan_detection.ps1"

Write-Host "=== TESTE: DETECCAO DE ORFAS ===" -ForegroundColor Cyan
Write-Host ""

try {
    # 1. Estado inicial
    Write-Host "1. ESTADO INICIAL" -ForegroundColor Yellow
    $localBefore = @(Get-TrailingPositions | Where-Object { $_.active })
    Write-Host "   Posicoes locais ativas: $($localBefore.Count)" -ForegroundColor White
    Write-Host ""
    
    # 2. Posições na exchange
    Write-Host "2. POSICOES NA EXCHANGE" -ForegroundColor Yellow
    $exchangePositions = @(CoinEx-GetPendingPositions)
    Write-Host "   Posicoes na exchange: $($exchangePositions.Count)" -ForegroundColor White
    
    if ($exchangePositions.Count -eq 0) {
        Write-Host "   Nenhuma posicao aberta." -ForegroundColor Yellow
        exit 0
    }
    
    foreach ($pos in $exchangePositions) {
        Write-Host "     - $($pos.market) | Entry: $($pos.avg_entry_price)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # 3. Detectar órfãs
    Write-Host "3. DETECTAR ORFAS" -ForegroundColor Yellow
    $orphans = @(Detect-OrphanPositions)
    Write-Host "   Orfas detectadas: $($orphans.Count)" -ForegroundColor White
    
    if ($orphans.Count -eq 0) {
        Write-Host "   Todas as posicoes ja estao registradas!" -ForegroundColor Green
        exit 0
    }
    
    foreach ($orphan in $orphans) {
        Write-Host "     - $($orphan.market) | Entry: $($orphan.avg_entry_price)" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # 4. Sincronizar
    Write-Host "4. SINCRONIZAR ORFAS" -ForegroundColor Yellow
    $syncResult = Sync-OrphanPositions
    
    if ($syncResult.success) {
        Write-Host "   SUCESSO!" -ForegroundColor Green
        Write-Host "   Total na exchange: $($syncResult.total_exchange)" -ForegroundColor White
        Write-Host "   Orfas detectadas: $($syncResult.orphans_detected)" -ForegroundColor White
        Write-Host "   Registradas: $($syncResult.registered)" -ForegroundColor Green
        Write-Host "   Erros: $($syncResult.errors)" -ForegroundColor White
    } else {
        Write-Host "   ERRO: $($syncResult.error)" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    
    # 5. Estado final
    Write-Host "5. ESTADO FINAL" -ForegroundColor Yellow
    $localAfter = @(Get-TrailingPositions | Where-Object { $_.active })
    Write-Host "   Posicoes locais ativas: $($localAfter.Count)" -ForegroundColor White
    Write-Host ""
    
    Write-Host "=== TESTE CONCLUIDO ===" -ForegroundColor Cyan
    Write-Host "Sistema sincronizado com sucesso!" -ForegroundColor Green
    
} catch {
    Write-Host ""
    Write-Host "ERRO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
