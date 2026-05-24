# PROTECT_NEAR_NOW.ps1
# URGENTE: Proteger posicao NEAR sem stop loss
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

Write-Host "=== PROTEGER NEAR URGENTE ===" -ForegroundColor Red
Write-Host ""

$market = "NEARUSDT"
$stopLossPrice = 2.35

Write-Host "Verificando posicao atual..." -ForegroundColor Yellow
$positions = CoinEx-GetPendingPositions -Market $market

if (-not $positions -or $positions.Count -eq 0) {
    Write-Host "ERRO: Posicao NEAR nao encontrada!" -ForegroundColor Red
    exit 1
}

$pos = $positions[0]
Write-Host "Posicao encontrada:"
Write-Host "  Entry: `$$($pos.avg_entry_price)"
Write-Host "  Current: `$$($pos.latest_price)"
Write-Host "  PNL: `$$($pos.unrealized_pnl) ($($pos.unrealized_pnl_rate)%)"
Write-Host "  Stop Loss: $($pos.stop_loss_price)" -ForegroundColor $(if ([double]$pos.stop_loss_price -gt 0) { "Green" } else { "Red" })
Write-Host ""

if ([double]$pos.stop_loss_price -gt 0) {
    Write-Host "Posicao JA TEM stop loss configurado: `$$($pos.stop_loss_price)" -ForegroundColor Green
    Write-Host "Nenhuma acao necessaria."
    exit 0
}

Write-Host "POSICAO SEM STOP LOSS - CONFIGURANDO AGORA!" -ForegroundColor Red
Write-Host "Stop Loss: `$$stopLossPrice"
Write-Host ""

try {
    Write-Host "Configurando stop loss com fallback..." -ForegroundColor Yellow
    $result = Set-PositionStopLossFallback -Market $market -Price $stopLossPrice -MaxRetries 3
    
    if ($result.success) {
        Write-Host ""
        Write-Host "=== SUCESSO ===" -ForegroundColor Green
        Write-Host "Stop loss configurado: `$$($result.stop_loss_price)"
        Write-Host "Metodo usado: $($result.method_used)"
        Write-Host "Tentativas: $($result.attempts)"
        Write-Host ""
        Write-Host "Posicao NEAR agora esta PROTEGIDA!" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "=== FALHA ===" -ForegroundColor Red
        Write-Host "Erro: $($result.error)"
        Write-Host "Tentativas: $($result.attempts)"
        Write-Host ""
        Write-Host "ACAO MANUAL NECESSARIA: Configure stop loss manualmente na exchange!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "=== ERRO CRITICO ===" -ForegroundColor Red
    Write-Host "$_"
    Write-Host $_.ScriptStackTrace
    Write-Host ""
    Write-Host "ACAO MANUAL NECESSARIA: Configure stop loss manualmente na exchange!" -ForegroundColor Red
    exit 1
}
