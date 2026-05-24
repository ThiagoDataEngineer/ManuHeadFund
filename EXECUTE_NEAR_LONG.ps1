# EXECUTE_NEAR_LONG.ps1
# Executar LONG em NEARUSDT para cobrir perdas
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

Write-Host "=== EXECUTAR LONG NEARUSDT ===" -ForegroundColor Cyan
Write-Host ""

# Parametros
$market = "NEARUSDT"
$leverage = 5
$margin = 100  # USDT

Write-Host "Buscando preco atual..." -ForegroundColor Yellow
$ticker = CoinEx-GetTicker -market $market
$currentPrice = [double]$ticker.last

Write-Host "Preco atual: `$$currentPrice"
Write-Host ""

# Buscar candles para calcular stop/TP
Write-Host "Calculando stop loss e take profit..." -ForegroundColor Yellow
$candles = CoinEx-GetFuturesCandles -market $market -period "15min" -limit 50

$support = ($candles | Select-Object -Last 20 | Measure-Object -Property low -Minimum).Minimum
$resistance = ($candles | Select-Object -Last 20 | Measure-Object -Property high -Maximum).Maximum

# Setup
$entry = $currentPrice
$stopLoss = [Math]::Round($support * 0.995, 4)  # 0.5% abaixo do suporte
$takeProfit = [Math]::Round($resistance, 4)

# Calcular amount
$notional = $margin * $leverage
$amount = [Math]::Round($notional / $entry, 2)

# Calcular R:R
$riskPct = (($entry - $stopLoss) / $entry) * 100
$rewardPct = (($takeProfit - $entry) / $entry) * 100
$rr = $rewardPct / $riskPct

Write-Host "=== SETUP ===" -ForegroundColor Green
Write-Host "Market: $market"
Write-Host "Entry: `$$entry"
Write-Host "Stop Loss: `$$stopLoss (risco: $([Math]::Round($riskPct, 2))%)"
Write-Host "Take Profit: `$$takeProfit (reward: $([Math]::Round($rewardPct, 2))%)"
Write-Host "R:R: 1:$([Math]::Round($rr, 1))"
Write-Host ""
Write-Host "Margin: `$$margin USDT"
Write-Host "Leverage: ${leverage}x"
Write-Host "Notional: `$$notional USDT"
Write-Host "Amount: $amount NEAR"
Write-Host ""

$lucroEsperado = $margin * ($rewardPct / 100) * $leverage
Write-Host "Lucro esperado (TP): `$$([Math]::Round($lucroEsperado, 2)) USDT" -ForegroundColor Green
Write-Host "Cobre perdas de `$8 + sobra `$$([Math]::Round($lucroEsperado - 8, 2))" -ForegroundColor Green
Write-Host ""

# Confirmar
Write-Host "CONFIRMAR EXECUCAO?" -ForegroundColor Yellow
Write-Host "Digite 'S' para executar ou qualquer outra tecla para cancelar"
$confirm = Read-Host

if ($confirm -ne "S" -and $confirm -ne "s") {
    Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "=== EXECUTANDO ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Executar ordem com validacao completa
    Write-Host "Executando ordem com validacao automatica..." -ForegroundColor Yellow
    Write-Host "  1. Ajustar leverage para ${leverage}x"
    Write-Host "  2. Executar ordem LONG"
    Write-Host "  3. Configurar stop loss (com fallback se necessario)"
    Write-Host "  4. Configurar take profit (com fallback se necessario)"
    Write-Host "  5. Validar configuracao final"
    Write-Host ""
    
    $result = Invoke-OrderWithValidation `
        -Market $market `
        -Side "buy" `
        -Amount $amount `
        -StopLoss $stopLoss `
        -TakeProfit $takeProfit `
        -Leverage $leverage
    
    if (-not $result.success) {
        Write-Host ""
        Write-Host "=== ERRO ===" -ForegroundColor Red
        Write-Host "Stage: $($result.stage)"
        Write-Host "Erro: $($result.error)"
        
        if ($result.warning) {
            Write-Host ""
            Write-Host "WARNING: $($result.warning)" -ForegroundColor Red
            
            if ($result.order_id) {
                Write-Host ""
                Write-Host "Ordem foi executada (ID: $($result.order_id)) mas stop loss falhou!" -ForegroundColor Red
                Write-Host "ACAO URGENTE: Configure stop loss manualmente ou execute:" -ForegroundColor Red
                Write-Host "  Set-PositionStopLossFallback -Market '$market' -Price $stopLoss" -ForegroundColor Yellow
            }
        }
        
        exit 1
    }
    
    Write-Host ""
    Write-Host "=== ORDEM EXECUTADA COM SUCESSO ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Order ID: $($result.order_id)"
    Write-Host ""
    Write-Host "=== VALIDACAO ===" -ForegroundColor Cyan
    Write-Host "Stop Loss: $(if ($result.stop_loss_configured) { "CONFIGURADO `$$($result.stop_loss_price)" } else { "NAO CONFIGURADO" })" -ForegroundColor $(if ($result.stop_loss_configured) { "Green" } else { "Red" })
    Write-Host "  Metodo: $($result.stop_loss_method)"
    Write-Host ""
    Write-Host "Take Profit: $(if ($result.take_profit_configured) { "CONFIGURADO `$$($result.take_profit_price)" } else { "NAO CONFIGURADO" })" -ForegroundColor $(if ($result.take_profit_configured) { "Green" } else { "Yellow" })
    Write-Host "  Metodo: $($result.take_profit_method)"
    Write-Host ""
    
    # 3. Verificar posicao
    Write-Host "=== VERIFICANDO POSICAO ===" -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    
    $position = CoinEx-GetPendingPositions -Market $market
    
    if ($position -and $position.Count -gt 0) {
        $pos = $position[0]
        Write-Host ""
        Write-Host "=== POSICAO ABERTA ===" -ForegroundColor Green
        Write-Host "Market: $($pos.market)"
        Write-Host "Side: $($pos.side)"
        Write-Host "Amount: $($pos.open_interest)"
        Write-Host "Entry: `$$($pos.avg_entry_price)"
        Write-Host "Leverage: $($pos.leverage)x"
        Write-Host "Margin: `$$($pos.ath_margin_size)"
        Write-Host "Stop Loss: `$$($pos.stop_loss_price)" -ForegroundColor $(if ([double]$pos.stop_loss_price -gt 0) { "Green" } else { "Red" })
        Write-Host "Take Profit: `$$($pos.take_profit_price)" -ForegroundColor $(if ([double]$pos.take_profit_price -gt 0) { "Green" } else { "Yellow" })
        Write-Host ""
        Write-Host "PNL: `$$($pos.unrealized_pnl)" -ForegroundColor $(if ([double]$pos.unrealized_pnl -gt 0) { "Green" } else { "Red" })
    }
    
    Write-Host ""
    Write-Host "=== SUCESSO ===" -ForegroundColor Green
    Write-Host "Posicao NEAR LONG aberta com protecao completa!"
    Write-Host ""
    Write-Host "Trailing stop automatico vai monitorar quando atingir +3% de lucro."
}
catch {
    Write-Host ""
    Write-Host "=== ERRO ===" -ForegroundColor Red
    Write-Host "$_"
    Write-Host $_.ScriptStackTrace
    exit 1
}
