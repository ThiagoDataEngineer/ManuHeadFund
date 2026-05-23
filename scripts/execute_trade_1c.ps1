# execute_trade_1c.ps1 - Executa trade 1C: $50 BNBUSDT LONG
# Com novos thresholds: ATR 1.5x, MinProfit 1%

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_telegram.ps1"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "EXECUTANDO TRADE: 1C" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Configuracao
    $market = "BNBUSDT"
    $sizeUsd = 50
    $leverage = 3
    $side = "long"
    
    Write-Host "Configuracao:" -ForegroundColor Yellow
    Write-Host "  Market: $market" -ForegroundColor White
    Write-Host "  Side: $side LONG" -ForegroundColor White
    Write-Host "  Size: `$$sizeUsd USD" -ForegroundColor White
    Write-Host "  Leverage: $leverage`x" -ForegroundColor White
    
    # Buscar preco
    Write-Host "`nBuscando preco atual..." -ForegroundColor Yellow
    $ticker = CoinEx-Get "/v2/futures/ticker?market=$market"
    if ($ticker.code -ne 0) {
        throw "Falha ao buscar ticker"
    }
    
    $price = [double]$ticker.data.last
    $amount = [math]::Round($sizeUsd / $price, 4)
    
    Write-Host "  Preco: `$$price" -ForegroundColor White
    Write-Host "  Amount: $amount BNB" -ForegroundColor White
    
    # Calcular stops
    Write-Host "`nCalculando stops com NOVOS THRESHOLDS..." -ForegroundColor Yellow
    $stopLoss = [math]::Round($price * 0.97, 2)
    $takeProfit = [math]::Round($price * 1.05, 2)
    $trailingActivation = [math]::Round($price * 1.01, 2)
    
    Write-Host "  Stop Loss: `$$stopLoss (-3%)" -ForegroundColor Red
    Write-Host "  Take Profit: `$$takeProfit (+5%)" -ForegroundColor Green
    Write-Host "  Trailing Activation: `$$trailingActivation (+1%) - NOVO!" -ForegroundColor Cyan
    
    Write-Host "`nNOVOS THRESHOLDS ATIVOS:" -ForegroundColor Cyan
    Write-Host "  ATR Multiplier: 1.5x (antes: 2.0x)" -ForegroundColor White
    Write-Host "  Min Profit: 1% (antes: 2%)" -ForegroundColor White
    Write-Host "  Objetivo: Proteger lucros menores" -ForegroundColor White
    
    # Confirmacao
    Write-Host "`n========================================" -ForegroundColor Yellow
    Write-Host "CONFIRMACAO FINAL" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "Voce esta prestes a executar um trade REAL!" -ForegroundColor Red
    Write-Host "Capital em risco: `$$sizeUsd USD (1.8% do capital)" -ForegroundColor Red
    Write-Host "`nDigite 'EXECUTAR' para confirmar:" -ForegroundColor Yellow
    
    $confirmation = Read-Host
    
    if ($confirmation -ne "EXECUTAR") {
        Write-Host "`nTrade cancelado pelo usuario." -ForegroundColor Yellow
        exit 0
    }
    
    # Executar ordem
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "EXECUTANDO ORDEM..." -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Preparar parametros
    $orderParams = @{
        market = $market
        side = $side
        type = "market"
        amount = $amount.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    
    # Adicionar stop loss e take profit se fornecidos
    if ($stopLoss) {
        $orderParams['stopLoss'] = $stopLoss
    }
    if ($takeProfit) {
        $orderParams['takeProfit'] = $takeProfit
    }
    
    Write-Host "Parametros da ordem:" -ForegroundColor Yellow
    Write-Host "  Market: $($orderParams.market)" -ForegroundColor White
    Write-Host "  Side: $($orderParams.side)" -ForegroundColor White
    Write-Host "  Type: $($orderParams.type)" -ForegroundColor White
    Write-Host "  Amount: $($orderParams.amount)" -ForegroundColor White
    if ($stopLoss) { Write-Host "  Stop Loss: `$$stopLoss" -ForegroundColor Red }
    if ($takeProfit) { Write-Host "  Take Profit: `$$takeProfit" -ForegroundColor Green }
    
    $order = CoinEx-PlaceOrder `
        -market $orderParams.market `
        -side $orderParams.side `
        -type $orderParams.type `
        -amount $orderParams.amount `
        -stopLoss $stopLoss `
        -takeProfit $takeProfit
    
    if (-not $order -or $order.code -ne 0) {
        $errorMsg = if ($order) { $order.message } else { "Resposta vazia da API" }
        throw "Falha ao executar ordem: $errorMsg"
    }
    
    $orderId = $order.data.order_id
    
    Write-Host "ORDEM EXECUTADA COM SUCESSO!" -ForegroundColor Green
    Write-Host "  Order ID: $orderId" -ForegroundColor White
    Write-Host "  Market: $market" -ForegroundColor White
    Write-Host "  Side: $side" -ForegroundColor White
    Write-Host "  Entry: `$$price" -ForegroundColor White
    Write-Host "  Amount: $amount BNB" -ForegroundColor White
    
    # Aguardar posicao aparecer
    Write-Host "`nAguardando posicao aparecer na API..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    
    # Verificar posicao
    $position = CoinEx-GetPosition -market $market
    if ($position) {
        Write-Host "Posicao confirmada!" -ForegroundColor Green
        Write-Host "  Open Price: `$$($position.open_price)" -ForegroundColor White
        Write-Host "  Amount: $($position.amount)" -ForegroundColor White
        Write-Host "  Leverage: $($position.leverage)x" -ForegroundColor White
    }
    
    # Enviar alerta Telegram
    Write-Host "`nEnviando alerta Telegram..." -ForegroundColor Yellow
    
    $alertMessage = @"
🚀 TRADE EXECUTADO - LIVE

Market: $market
Side: LONG
Entry: `$$price
Size: `$$sizeUsd USD ($amount BNB)
Leverage: $leverage`x

📊 NOVOS THRESHOLDS:
- ATR Multiplier: 1.5x
- Min Profit: 1%
- Trailing ativa em: `$$trailingActivation (+1%)

🎯 Stops:
- Stop Loss: `$$stopLoss (-3%)
- Take Profit: `$$takeProfit (+5%)

Order ID: $orderId

Historico BNB: 100% WR! 🏆
"@
    
    $telegramSent = Send-TelegramAlert -Message $alertMessage
    if ($telegramSent) {
        Write-Host "Alerta Telegram enviado!" -ForegroundColor Green
    }
    
    # Atualizar dashboard
    Write-Host "`nAtualizando dashboard..." -ForegroundColor Yellow
    & "$PSScriptRoot\generate_position_dashboard.ps1" | Out-Null
    Write-Host "Dashboard atualizado!" -ForegroundColor Green
    
    # Resumo final
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TRADE COMPLETO!" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Host "Proximos passos:" -ForegroundColor Yellow
    Write-Host "1. Trailing stop ativara automaticamente em +1%" -ForegroundColor White
    Write-Host "2. Position Risk Manager rodara a cada 15 min" -ForegroundColor White
    Write-Host "3. Dashboard atualizara a cada 5 min" -ForegroundColor White
    Write-Host "4. Alertas Telegram para mudancas importantes" -ForegroundColor White
    
    Write-Host "`nMonitoramento:" -ForegroundColor Yellow
    Write-Host "- Dashboard: .\dashboard\position_metrics.html" -ForegroundColor White
    Write-Host "- Telegram: Alertas automaticos" -ForegroundColor White
    Write-Host "- Cron jobs: Rodando em background" -ForegroundColor White
    
    Write-Host "`nBOA SORTE! 🍀" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
} catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    
    # Enviar alerta de erro
    Send-TelegramAlert -Message "🚨 ERRO ao executar trade 1C: $_" | Out-Null
    
    exit 1
}
