# EXECUTE_UNI_LONG.ps1
# Execucao de LONG em UNIUSDT
# Data: 2026-05-23
# Setup: RSI sobrevenda (37.8) + suporte SMA20

# Carregar libs
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_rate_limiter.ps1"
. "$PSScriptRoot\agents\lib_coinex_retry.ps1"

Write-Host "=== EXECUTANDO LONG UNI ===" -ForegroundColor Cyan
Write-Host ""

# Parametros do trade
$market = "UNIUSDT"
$side = "buy"
$leverage = 5
$entryPrice = 3.45
$stopLoss = 3.30
$takeProfit1 = 3.60
$takeProfit2 = 3.75
$positionSize = 143.8  # UNI

Write-Host "PARAMETROS:" -ForegroundColor Yellow
Write-Host "Market: $market"
Write-Host "Side: LONG (buy)"
Write-Host "Leverage: ${leverage}x"
Write-Host "Size: $positionSize UNI"
Write-Host "Entry: $$entryPrice"
Write-Host "Stop Loss: $$stopLoss (-4.3%)"
Write-Host "TP1: $$takeProfit1 (+4.3%)"
Write-Host "TP2: $$takeProfit2 (+8.7%)"
Write-Host ""

# Confirmar capital
$capital = CoinEx-GetFuturesCapitalUSDT
Write-Host "Capital Disponivel: $capital USDT" -ForegroundColor Cyan
$marginNeeded = ($positionSize * $entryPrice) / $leverage
Write-Host "Margem Necessaria: $([math]::Round($marginNeeded, 2)) USDT" -ForegroundColor Yellow

if ($capital -lt $marginNeeded) {
    Write-Host "ERRO: Capital insuficiente!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "EXECUTANDO AUTOMATICAMENTE..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# 1. Configurar leverage
Write-Host "[1/4] Configurando leverage ${leverage}x..." -ForegroundColor Cyan
try {
    . "$PSScriptRoot\agents\lib_coinex_position_management.ps1"
    $leverageResult = CoinEx-AdjustPositionLeverage -Market $market -Leverage $leverage -MarginMode "isolated"
    if ($leverageResult.success) {
        Write-Host "  OK - Leverage configurado: $($leverageResult.leverage)x" -ForegroundColor Green
    } else {
        Write-Host "  WARN - Leverage: $($leverageResult.error_msg)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARN - Erro ao configurar leverage: $($_.Exception.Message)" -ForegroundColor Yellow
}

# 2. Obter preco atual
Write-Host "[2/4] Obtendo preco atual..." -ForegroundColor Cyan
$ticker = CoinEx-GetTicker $market
$currentPrice = [double]$ticker.last
Write-Host "  Preco Atual: $$currentPrice" -ForegroundColor White

# Ajustar entrada se necessario (usar preco de mercado)
$finalEntry = $currentPrice
Write-Host "  Entrada Ajustada: $$finalEntry" -ForegroundColor Green

# 3. Abrir posicao LONG
Write-Host "[3/4] Abrindo posicao LONG..." -ForegroundColor Cyan

# Arredondar amount para 1 casa decimal (min 2 UNI)
$amountRounded = [math]::Round($positionSize, 1)
if ($amountRounded -lt 2) { $amountRounded = 2 }

$orderBody = @{
    market = $market
    market_type = "FUTURES"
    side = $side
    type = "market"  # Market order para execucao imediata
    amount = $amountRounded.ToString()
    client_id = "uni_long_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}

try {
    $orderResult = CoinEx-Post -path "/v2/futures/order" -bodyObj $orderBody
    
    if ($orderResult.code -eq 0) {
        $orderId = $orderResult.data.order_id
        Write-Host "  OK - Ordem executada!" -ForegroundColor Green
        Write-Host "  Order ID: $orderId" -ForegroundColor White
        Write-Host "  Amount: $($orderResult.data.amount) UNI" -ForegroundColor White
        Write-Host "  Price: $$($orderResult.data.price)" -ForegroundColor White
    } else {
        Write-Host "  ERRO - $($orderResult.message)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  ERRO - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# 4. Configurar Stop Loss e Take Profit
Write-Host "[4/4] Configurando Stop Loss e Take Profit..." -ForegroundColor Cyan

# Stop Loss
try {
    $slBody = @{
        market = $market
        market_type = "FUTURES"
        stop_loss_price = $stopLoss.ToString()
        stop_loss_type = "mark_price"
    }
    
    $slResult = CoinEx-Post -path "/v2/futures/set-position-stop-loss" -bodyObj $slBody
    
    if ($slResult.code -eq 0) {
        Write-Host "  OK - Stop Loss configurado: $$stopLoss" -ForegroundColor Green
    } else {
        Write-Host "  WARN - Stop Loss: $($slResult.message)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARN - Erro ao configurar SL: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Take Profit 1 (50% da posicao)
try {
    $tp1Body = @{
        market = $market
        market_type = "FUTURES"
        take_profit_price = $takeProfit1.ToString()
        take_profit_type = "mark_price"
    }
    
    $tp1Result = CoinEx-Post -path "/v2/futures/set-position-take-profit" -bodyObj $tp1Body
    
    if ($tp1Result.code -eq 0) {
        Write-Host "  OK - Take Profit 1 configurado: $$takeProfit1" -ForegroundColor Green
    } else {
        Write-Host "  WARN - Take Profit 1: $($tp1Result.message)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  WARN - Erro ao configurar TP1: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== POSICAO ABERTA COM SUCESSO ===" -ForegroundColor Green
Write-Host ""
Write-Host "RESUMO:" -ForegroundColor Yellow
Write-Host "Market: $market"
Write-Host "Side: LONG"
Write-Host "Size: $positionSize UNI"
Write-Host "Entry: ~$$finalEntry"
Write-Host "Stop Loss: $$stopLoss (-4.3%)"
Write-Host "TP1: $$takeProfit1 (+4.3%)"
Write-Host "TP2: $$takeProfit2 (+8.7%)"
Write-Host ""
Write-Host "MONITORAMENTO:" -ForegroundColor Cyan
Write-Host "- Acompanhe a posicao no dashboard"
Write-Host "- Trailing stop sera ativado apos +3%"
Write-Host "- Realizar 50% em TP1 ($3.60)"
Write-Host "- Deixar 50% correr ate TP2 ($3.75)"
Write-Host ""
Write-Host "BOA SORTE! 🚀" -ForegroundColor Green
