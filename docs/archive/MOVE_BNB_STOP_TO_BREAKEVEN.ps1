# MOVE_BNB_STOP_TO_BREAKEVEN.ps1
# URGENTE: Mover stop loss do BNB para breakeven
# Posicao atual: Entry $647.06, PNL +85%, Leverage 50x
# Stop atual: $627.82 -> Novo stop: $653.53 (breakeven + 1%)
# 2026-05-24

# Carregar libs
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_coinex_position_management.ps1"

Write-Host "=== MOVER STOP BNB PARA BREAKEVEN ===" -ForegroundColor Yellow
Write-Host ""

# Parametros
$market = "BNBUSDT"
$entryPrice = 647.06
$breakevenPrice = [Math]::Round($entryPrice * 1.01, 2)  # +1% acima do entry

Write-Host "Market: $market"
Write-Host "Entry Price: `$$entryPrice"
Write-Host "Breakeven Price (entry + 1%): `$$breakevenPrice"
Write-Host ""

# Buscar posicao atual
Write-Host "Buscando posicao atual..." -ForegroundColor Cyan
try {
    $positions = CoinEx-GetPendingPositions -Market $market
    
    if ($positions.Count -eq 0) {
        Write-Host "ERRO: Posicao $market nao encontrada!" -ForegroundColor Red
        exit 1
    }
    
    $pos = $positions[0]
    Write-Host "Posicao encontrada:" -ForegroundColor Green
    Write-Host "  Side: $($pos.side)"
    Write-Host "  Amount: $($pos.amount)"
    Write-Host "  Entry: `$$($pos.open_price)"
    Write-Host "  Mark Price: `$$($pos.latest_price)"
    Write-Host "  PNL: `$$($pos.unrealized_pnl) ($($pos.roe)%)"
    Write-Host "  Stop Loss atual: `$$($pos.stop_loss_price)"
    Write-Host ""
}
catch {
    Write-Host "ERRO ao buscar posicao: $_" -ForegroundColor Red
    exit 1
}

# Confirmar com usuario
Write-Host "ACAO: Mover stop loss de `$$($pos.stop_loss_price) para `$$breakevenPrice" -ForegroundColor Yellow
$confirm = Read-Host "Confirmar? (S/N)"

if ($confirm -ne "S" -and $confirm -ne "s") {
    Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
    exit 0
}

# Executar modificacao
Write-Host ""
Write-Host "Modificando stop loss..." -ForegroundColor Cyan

try {
    $result = CoinEx-ModifyPositionStopLoss -Market $market -Price $breakevenPrice
    
    if ($result.success) {
        Write-Host ""
        Write-Host "=== SUCESSO ===" -ForegroundColor Green
        Write-Host "Stop loss movido para: `$$($result.stop_loss_price)"
        Write-Host "Market: $($result.market)"
        Write-Host ""
        Write-Host "Posicao BNB agora esta PROTEGIDA no breakeven!" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "=== ERRO ===" -ForegroundColor Red
        Write-Host "Codigo: $($result.error_code)"
        Write-Host "Mensagem: $($result.error_msg)"
        exit 1
    }
}
catch {
    Write-Host ""
    Write-Host "=== ERRO CRITICO ===" -ForegroundColor Red
    Write-Host "$_"
    exit 1
}
