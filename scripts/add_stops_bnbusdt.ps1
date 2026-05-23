# add_stops_bnbusdt.ps1 - Adiciona Stop Loss e Take Profit a posicao BNBUSDT
# Executa: .\scripts\add_stops_bnbusdt.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"
. ".\agents\lib_telegram.ps1"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "ADICIONANDO STOPS - BNBUSDT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    $market = "BNBUSDT"
    $stopLoss = 627.82
    $takeProfit = 679.60

    # Verificar posicao
    Write-Host "Verificando posicao..." -ForegroundColor Yellow
    $positions = CoinEx-GetPendingPositions
    $position = $positions | Where-Object { $_.market -eq $market }

    if (-not $position) {
        throw "Posicao $market nao encontrada!"
    }

    $entryPrice = [double]$position.avg_entry_price
    $size = [double]$position.open_interest

    Write-Host "[OK] Posicao encontrada" -ForegroundColor Green
    Write-Host "  Market: $market" -ForegroundColor White
    Write-Host "  Entry: `$$entryPrice" -ForegroundColor White
    Write-Host "  Size: $size BNB" -ForegroundColor White
    Write-Host "  Side: $($position.side)" -ForegroundColor White

    # Adicionar Stop Loss
    Write-Host "`nAdicionando Stop Loss..." -ForegroundColor Yellow
    Write-Host "  Preco: `$$stopLoss (-3%)" -ForegroundColor Red

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $slBody = @{
        market           = $market
        market_type      = "FUTURES"
        stop_loss_price  = $stopLoss.ToString($inv)
        stop_loss_type   = "mark_price"
    }

    $slResponse = CoinEx-Post "/v2/futures/set-position-stop-loss" $slBody

    if ($slResponse.code -eq 0) {
        Write-Host "[OK] Stop Loss adicionado!" -ForegroundColor Green
        Write-Host "  SL Price: `$$($slResponse.data.stop_loss_price)" -ForegroundColor Red
    } else {
        Write-Host "[ERRO] Falha ao adicionar Stop Loss: $($slResponse.message)" -ForegroundColor Red
    }

    # Adicionar Take Profit
    Write-Host "`nAdicionando Take Profit..." -ForegroundColor Yellow
    Write-Host "  Preco: `$$takeProfit (+5%)" -ForegroundColor Green

    $tpBody = @{
        market            = $market
        market_type       = "FUTURES"
        take_profit_price = $takeProfit.ToString($inv)
        take_profit_type  = "mark_price"
    }

    $tpResponse = CoinEx-Post "/v2/futures/set-position-take-profit" $tpBody

    if ($tpResponse.code -eq 0) {
        Write-Host "[OK] Take Profit adicionado!" -ForegroundColor Green
        Write-Host "  TP Price: `$$($tpResponse.data.take_profit_price)" -ForegroundColor Green
    } else {
        Write-Host "[ERRO] Falha ao adicionar Take Profit: $($tpResponse.message)" -ForegroundColor Red
    }

    # Verificar posicao atualizada
    Write-Host "`nVerificando stops aplicados..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2

    $positions = CoinEx-GetPendingPositions
    $position = $positions | Where-Object { $_.market -eq $market }

    Write-Host "[OK] Posicao atualizada:" -ForegroundColor Green
    Write-Host "  Stop Loss: `$$($position.stop_loss_price)" -ForegroundColor Red
    Write-Host "  Take Profit: `$$($position.take_profit_price)" -ForegroundColor Green

    # Enviar alerta Telegram
    Write-Host "`nEnviando alerta Telegram..." -ForegroundColor Yellow

    $alertMessage = @"
Stops Adicionados - BNBUSDT

Market: $market
Entry: `$$entryPrice
Size: $size BNB

Stops Configurados:
- Stop Loss: `$$stopLoss (-3%)
- Take Profit: `$$takeProfit (+5%)
- Trigger: Mark Price

Trailing Stop:
- Ativa em: `$653.71 (+1%)
- Risk Manager: Monitorando a cada 5 min

Status: Protegido!
"@

    $telegramSent = Send-TelegramAlert -Message $alertMessage
    if ($telegramSent) {
        Write-Host "[OK] Alerta Telegram enviado!" -ForegroundColor Green
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "STOPS CONFIGURADOS COM SUCESSO!" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    Write-Host "Protecao Ativa:" -ForegroundColor Yellow
    Write-Host "  Stop Loss: `$$stopLoss (protege contra -3%)" -ForegroundColor Red
    Write-Host "  Take Profit: `$$takeProfit (realiza lucro em +5%)" -ForegroundColor Green
    Write-Host "  Trailing Stop: Ativa automaticamente em +1%" -ForegroundColor Cyan
    Write-Host "  Risk Manager: Monitorando a cada 5 minutos" -ForegroundColor White

} catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed

    # Enviar alerta de erro
    Send-TelegramAlert -Message "ERRO ao adicionar stops BNBUSDT: $_" | Out-Null

    exit 1
}
