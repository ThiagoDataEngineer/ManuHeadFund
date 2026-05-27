# FIX_MISSING_STOPS.ps1
# Detectar e corrigir posicoes sem stop loss
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

Write-Host "=== VERIFICAR POSICOES SEM STOP LOSS ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Buscar todas as posicoes abertas
    Write-Host "Buscando posicoes abertas..." -ForegroundColor Yellow
    $positions = CoinEx-GetPendingPositions
    
    if (-not $positions -or $positions.Count -eq 0) {
        Write-Host "Nenhuma posicao aberta encontrada." -ForegroundColor Green
        exit 0
    }
    
    Write-Host "Total de posicoes: $($positions.Count)"
    Write-Host ""
    
    # Verificar cada posicao
    $positionsWithoutStop = @()
    
    foreach ($pos in $positions) {
        $market = $pos.market
        $stopLoss = [double]$pos.stop_loss_price
        $takeProfit = [double]$pos.take_profit_price
        $pnl = [double]$pos.unrealized_pnl
        $pnlRate = [double]$pos.unrealized_pnl_rate
        
        $hasStop = $stopLoss -gt 0
        $hasTP = $takeProfit -gt 0
        
        $status = if ($hasStop -and $hasTP) { "OK" }
                  elseif ($hasStop) { "WARN (sem TP)" }
                  else { "CRITICAL (sem SL)" }
        
        $color = if ($hasStop -and $hasTP) { "Green" }
                 elseif ($hasStop) { "Yellow" }
                 else { "Red" }
        
        Write-Host "$market : $status" -ForegroundColor $color
        Write-Host "  Entry: `$$($pos.avg_entry_price)"
        Write-Host "  Current: `$$($pos.latest_price)"
        Write-Host "  PNL: `$$pnl ($pnlRate%)"
        Write-Host "  Stop Loss: $(if ($hasStop) { "`$$stopLoss" } else { "NENHUM" })"
        Write-Host "  Take Profit: $(if ($hasTP) { "`$$takeProfit" } else { "NENHUM" })"
        Write-Host ""
        
        if (-not $hasStop) {
            $positionsWithoutStop += $pos
        }
    }
    
    # Se nenhuma posicao sem stop, sair
    if ($positionsWithoutStop.Count -eq 0) {
        Write-Host "=== TODAS AS POSICOES ESTAO PROTEGIDAS ===" -ForegroundColor Green
        exit 0
    }
    
    # Alertar sobre posicoes sem stop
    Write-Host "=== ALERTA ===" -ForegroundColor Red
    Write-Host "$($positionsWithoutStop.Count) posicao(oes) SEM STOP LOSS!" -ForegroundColor Red
    Write-Host ""
    
    foreach ($pos in $positionsWithoutStop) {
        Write-Host "  - $($pos.market): Entry `$$($pos.avg_entry_price), PNL `$$($pos.unrealized_pnl)" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "DESEJA CONFIGURAR STOP LOSS AUTOMATICAMENTE?" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "O sistema vai calcular stop loss baseado em:"
    Write-Host "  - Suporte tecnico (minima das ultimas 20 velas)"
    Write-Host "  - Margem de seguranca de 0.5%"
    Write-Host ""
    Write-Host "Digite 'S' para configurar automaticamente ou 'M' para configurar manualmente"
    $choice = Read-Host
    
    if ($choice -eq "S" -or $choice -eq "s") {
        # Configurar automaticamente
        Write-Host ""
        Write-Host "=== CONFIGURANDO STOP LOSS AUTOMATICAMENTE ===" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($pos in $positionsWithoutStop) {
            $market = $pos.market
            $entry = [double]$pos.avg_entry_price
            $side = $pos.side
            
            Write-Host "Processando $market..." -ForegroundColor Yellow
            
            try {
                # Buscar candles para calcular suporte
                $candles = CoinEx-GetFuturesCandles -market $market -period "15min" -limit 50
                $support = ($candles | Select-Object -Last 20 | Measure-Object -Property low -Minimum).Minimum
                
                # Calcular stop loss
                if ($side -eq "long") {
                    $stopLoss = [Math]::Round($support * 0.995, 4)  # 0.5% abaixo do suporte
                } else {
                    # Short: stop acima da resistencia
                    $resistance = ($candles | Select-Object -Last 20 | Measure-Object -Property high -Maximum).Maximum
                    $stopLoss = [Math]::Round($resistance * 1.005, 4)  # 0.5% acima da resistencia
                }
                
                Write-Host "  Suporte: `$$support"
                Write-Host "  Stop Loss calculado: `$$stopLoss"
                
                # Configurar stop loss
                $result = Set-PositionStopLossFallback -Market $market -Price $stopLoss -MaxRetries 3
                
                if ($result.success) {
                    Write-Host "  SUCESSO: Stop loss configurado em `$$($result.stop_loss_price)" -ForegroundColor Green
                    Write-Host "  Metodo: $($result.method_used), Tentativas: $($result.attempts)"
                } else {
                    Write-Host "  FALHA: $($result.error)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "  ERRO: $_" -ForegroundColor Red
            }
            
            Write-Host ""
        }
        
        Write-Host "=== PROCESSO CONCLUIDO ===" -ForegroundColor Cyan
    }
    elseif ($choice -eq "M" -or $choice -eq "m") {
        # Configurar manualmente
        Write-Host ""
        Write-Host "=== CONFIGURACAO MANUAL ===" -ForegroundColor Cyan
        Write-Host ""
        
        foreach ($pos in $positionsWithoutStop) {
            $market = $pos.market
            $entry = [double]$pos.avg_entry_price
            $current = [double]$pos.latest_price
            
            Write-Host "$market (Entry: `$$entry, Current: `$$current)" -ForegroundColor Yellow
            Write-Host "Digite o preco do stop loss (ou 'S' para pular):"
            $input = Read-Host
            
            if ($input -eq "S" -or $input -eq "s") {
                Write-Host "  Pulado." -ForegroundColor Yellow
                Write-Host ""
                continue
            }
            
            try {
                $stopLoss = [double]$input
                
                Write-Host "  Configurando stop loss em `$$stopLoss..." -ForegroundColor Yellow
                $result = Set-PositionStopLossFallback -Market $market -Price $stopLoss -MaxRetries 3
                
                if ($result.success) {
                    Write-Host "  SUCESSO: Stop loss configurado!" -ForegroundColor Green
                } else {
                    Write-Host "  FALHA: $($result.error)" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "  ERRO: Preco invalido ou falha na API" -ForegroundColor Red
            }
            
            Write-Host ""
        }
    }
    else {
        Write-Host "Operacao cancelada." -ForegroundColor Yellow
    }
}
catch {
    Write-Host ""
    Write-Host "=== ERRO CRITICO ===" -ForegroundColor Red
    Write-Host "$_"
    Write-Host $_.ScriptStackTrace
    exit 1
}
