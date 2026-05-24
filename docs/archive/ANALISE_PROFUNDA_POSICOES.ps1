# ANALISE_PROFUNDA_POSICOES.ps1
# Análise técnica profunda de cada posição + validação do motor
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_trailing_stop_intelligent.ps1"

Write-Host "=== ANALISE PROFUNDA DAS POSICOES ===" -ForegroundColor Cyan
Write-Host "Objetivo: Validar motor de trailing stop e identificar melhorias"
Write-Host ""

# Buscar todas as posições
$positions = CoinEx-GetPendingPositions

Write-Host "Total posicoes: $($positions.Count)"
Write-Host ""

$analysis = @()

foreach ($pos in $positions) {
    $market = $pos.market
    
    Write-Host "=== ANALISANDO $market ===" -ForegroundColor Yellow
    Write-Host ""
    
    # Dados da posição
    $entry = [double]$pos.avg_entry_price
    $leverage = [int]$pos.leverage
    $side = $pos.side
    $stopLoss = [double]$pos.stop_loss_price
    $takeProfit = [double]$pos.take_profit_price
    $margin = [double]$pos.ath_margin_size
    $pnl = [double]$pos.unrealized_pnl
    
    # Preço atual
    $ticker = CoinEx-GetTicker -market $market
    $current = [double]$ticker.last
    $markPrice = [double]$ticker.mark_price
    
    # PNL %
    $pnlPct = if ($side -eq "long") {
        (($current - $entry) / $entry) * 100
    } else {
        (($entry - $current) / $entry) * 100
    }
    
    Write-Host "Posicao:"
    Write-Host "  Entry: `$$entry"
    Write-Host "  Current: `$$current"
    Write-Host "  Mark: `$$markPrice"
    Write-Host "  PNL: $([Math]::Round($pnlPct, 2))% (`$$([Math]::Round($pnl, 2)))"
    Write-Host "  Leverage: ${leverage}x"
    Write-Host "  Margin: `$$margin"
    Write-Host "  Stop Loss: `$$stopLoss"
    Write-Host "  Take Profit: `$$takeProfit"
    Write-Host ""
    
    # Buscar candles para análise técnica
    try {
        Write-Host "Analise Tecnica:" -ForegroundColor Cyan
        
        # Candles 15min
        $candles15m = CoinEx-GetFuturesCandles -market $market -period "15min" -limit 50
        
        # Candles 1h para contexto maior
        $candles1h = CoinEx-GetFuturesCandles -market $market -period "1hour" -limit 50
        
        # ATR (volatilidade)
        $atr15m = Calculate-ATR -Candles $candles15m -Period 14
        $atrPct = ($atr15m / $current) * 100
        
        Write-Host "  ATR(14) 15min: `$$([Math]::Round($atr15m, 6)) ($([Math]::Round($atrPct, 2))%)"
        
        # RSI
        $closes = $candles15m | Select-Object -Last 14 | ForEach-Object { $_.close }
        $gains = @()
        $losses = @()
        
        for ($i = 1; $i -lt $closes.Count; $i++) {
            $diff = $closes[$i] - $closes[$i-1]
            if ($diff -gt 0) {
                $gains += $diff
                $losses += 0
            } else {
                $gains += 0
                $losses += [Math]::Abs($diff)
            }
        }
        
        $avgGain = ($gains | Measure-Object -Average).Average
        $avgLoss = ($losses | Measure-Object -Average).Average
        
        if ($avgLoss -gt 0) {
            $rs = $avgGain / $avgLoss
            $rsi = 100 - (100 / (1 + $rs))
        } else {
            $rsi = 100
        }
        
        Write-Host "  RSI(14) 15min: $([Math]::Round($rsi, 2))"
        
        # SMAs
        $sma20_15m = ($candles15m | Select-Object -Last 20 | Measure-Object -Property close -Average).Average
        $sma50_15m = ($candles15m | Select-Object -Last 50 | Measure-Object -Property close -Average).Average
        $sma20_1h = ($candles1h | Select-Object -Last 20 | Measure-Object -Property close -Average).Average
        
        $distSma20 = (($current - $sma20_15m) / $sma20_15m) * 100
        $distSma50 = (($current - $sma50_15m) / $sma50_15m) * 100
        
        Write-Host "  SMA20 15min: `$$([Math]::Round($sma20_15m, 4)) (dist: $([Math]::Round($distSma20, 2))%)"
        Write-Host "  SMA50 15min: `$$([Math]::Round($sma50_15m, 4)) (dist: $([Math]::Round($distSma50, 2))%)"
        Write-Host "  SMA20 1h: `$$([Math]::Round($sma20_1h, 4))"
        
        # Suportes e Resistências
        $supports = Find-SupportLevels -Candles $candles15m -LookbackPeriod 20
        $support = if ($supports.Count -gt 0) { $supports[0] } else { 0 }
        
        $resistance = ($candles15m | Select-Object -Last 20 | Measure-Object -Property high -Maximum).Maximum
        
        if ($support -gt 0) {
            $distSupport = (($current - $support) / $support) * 100
            Write-Host "  Suporte: `$$([Math]::Round($support, 4)) (dist: $([Math]::Round($distSupport, 2))%)"
        }
        
        $distResistance = (($resistance - $current) / $current) * 100
        Write-Host "  Resistencia: `$$([Math]::Round($resistance, 4)) (dist: $([Math]::Round($distResistance, 2))%)"
        
        # Volume profile (últimos 20 candles)
        $avgVol = ($candles15m | Select-Object -Last 20 | Measure-Object -Property volume -Average).Average
        $currentVol = $candles15m[-1].volume
        $volRatio = $currentVol / $avgVol
        
        Write-Host "  Volume ratio: $([Math]::Round($volRatio, 2))x (current vs avg)"
        
        Write-Host ""
        
        # Avaliar trailing stop
        Write-Host "Avaliacao Trailing Stop:" -ForegroundColor Cyan
        
        $trailingCalc = Calculate-TrailingStopPrice `
            -Position $pos `
            -Candles $candles15m `
            -CurrentStopLoss $stopLoss `
            -MinProfitPctToActivate 3.0
        
        Write-Host "  Should update: $($trailingCalc.should_update)"
        Write-Host "  Reason: $($trailingCalc.reason)"
        Write-Host "  Current stop: `$$stopLoss"
        Write-Host "  Calculated stop: `$$($trailingCalc.new_stop_price)"
        Write-Host "  Trailing %: $($trailingCalc.trailing_pct)%"
        Write-Host ""
        
        # Distância do stop atual
        $distStop = if ($side -eq "long") {
            (($current - $stopLoss) / $current) * 100
        } else {
            (($stopLoss - $current) / $current) * 100
        }
        
        Write-Host "  Distancia do stop: $([Math]::Round($distStop, 2))%"
        
        # Avaliar qualidade do stop
        $stopQuality = ""
        if ($distStop -lt 0.5) {
            $stopQuality = "MUITO APERTADO (risco de stop prematuro)"
            Write-Host "  Qualidade: $stopQuality" -ForegroundColor Red
        } elseif ($distStop -lt 1.5) {
            $stopQuality = "APERTADO (pode ser acionado por ruido)"
            Write-Host "  Qualidade: $stopQuality" -ForegroundColor Yellow
        } elseif ($distStop -lt 3) {
            $stopQuality = "ADEQUADO (protege sem ser prematuro)"
            Write-Host "  Qualidade: $stopQuality" -ForegroundColor Green
        } else {
            $stopQuality = "LARGO (muito risco)"
            Write-Host "  Qualidade: $stopQuality" -ForegroundColor Yellow
        }
        
        Write-Host ""
        
        # Recomendação
        Write-Host "Recomendacao:" -ForegroundColor Cyan
        
        $recommendation = ""
        $action = ""
        
        # Lógica de recomendação
        if ($pnlPct -lt -2 -and $distStop -lt 1) {
            $recommendation = "FECHAR - Perda significativa e stop muito próximo"
            $action = "close"
        } elseif ($pnlPct -lt -1 -and $rsi -lt 30) {
            $recommendation = "AGUARDAR - Sobrevenda, pode reverter"
            $action = "hold"
        } elseif ($pnlPct -gt 3 -and $rsi -gt 70) {
            $recommendation = "PROTEGER - Mover stop para breakeven ou trailing"
            $action = "protect"
        } elseif ($pnlPct -gt 1 -and $pnlPct -lt 3) {
            $recommendation = "MONITORAR - Próximo de ativar trailing (+3%)"
            $action = "monitor"
        } elseif ($distStop -lt 0.5) {
            $recommendation = "AJUSTAR STOP - Muito apertado, dar mais espaço"
            $action = "adjust_stop"
        } elseif ($pnlPct -gt 5) {
            $recommendation = "REALIZAR PARCIAL - Lucro significativo"
            $action = "take_partial"
        } else {
            $recommendation = "AGUARDAR - Setup em desenvolvimento"
            $action = "hold"
        }
        
        Write-Host "  $recommendation" -ForegroundColor $(
            if ($action -eq "close") { "Red" }
            elseif ($action -eq "protect" -or $action -eq "take_partial") { "Green" }
            elseif ($action -eq "adjust_stop") { "Yellow" }
            else { "Cyan" }
        )
        
        Write-Host ""
        Write-Host "---" -ForegroundColor Gray
        Write-Host ""
        
        # Armazenar análise
        $analysis += [PSCustomObject]@{
            market = $market
            entry = $entry
            current = $current
            pnl_pct = [Math]::Round($pnlPct, 2)
            pnl_usd = [Math]::Round($pnl, 2)
            leverage = $leverage
            rsi = [Math]::Round($rsi, 2)
            atr_pct = [Math]::Round($atrPct, 2)
            dist_sma20 = [Math]::Round($distSma20, 2)
            dist_stop = [Math]::Round($distStop, 2)
            stop_quality = $stopQuality
            recommendation = $recommendation
            action = $action
            trailing_should_update = $trailingCalc.should_update
            trailing_reason = $trailingCalc.reason
        }
        
    } catch {
        Write-Host "Erro na analise: $_" -ForegroundColor Red
        Write-Host ""
    }
}

# Resumo geral
Write-Host "=== RESUMO GERAL ===" -ForegroundColor Cyan
Write-Host ""

$totalPnl = ($analysis | Measure-Object -Property pnl_usd -Sum).Sum
Write-Host "PNL Total: `$$([Math]::Round($totalPnl, 2))"
Write-Host ""

Write-Host "Acoes Recomendadas:" -ForegroundColor Yellow
$analysis | ForEach-Object {
    $color = if ($_.action -eq "close") { "Red" }
             elseif ($_.action -eq "protect" -or $_.action -eq "take_partial") { "Green" }
             elseif ($_.action -eq "adjust_stop") { "Yellow" }
             else { "Cyan" }
    
    Write-Host "  $($_.market.PadRight(12)) | " -NoNewline
    Write-Host "$($_.recommendation)" -ForegroundColor $color
}

Write-Host ""

# Exportar para análise
$analysis | Export-Csv -Path "analise_posicoes_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" -NoTypeInformation
Write-Host "Analise exportada para CSV" -ForegroundColor Green
