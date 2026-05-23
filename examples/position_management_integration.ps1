# position_management_integration.ps1 - Exemplos de Integração
# Demonstra como integrar Position Management nos agents

. "$PSScriptRoot\..\agents\config.ps1"
. "$PSScriptRoot\..\agents\lib_coinex.ps1"
. "$PSScriptRoot\..\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\..\agents\lib_position_risk_manager.ps1"
. "$PSScriptRoot\..\agents\gem_executor.ps1"

# ============================================================================
# EXEMPLO 1: GEM com Trailing Stop Automático
# ============================================================================

function Example1-GemWithTrailingStop {
    Write-Host "`n=== EXEMPLO 1: GEM + Trailing Stop ===" -ForegroundColor Cyan
    
    # Simular GEM
    $gem = [PSCustomObject]@{
        market = "BTCUSDT"
        score = 75
        mode = "MOMENTUM"
        sizing = [PSCustomObject]@{
            sizing_pct = 0.02
            stop_pct = 0.50
            target_pct = 2.00
            max_days = 7
        }
        vol_data = [PSCustomObject]@{
            spike_ratio = 3.5
            spike_type = "BULLISH"
            pct_change_today = 15.2
        }
    }
    
    Write-Host "1. Executando GEM $($gem.market)..." -ForegroundColor Yellow
    $result = Invoke-GemExecute -Gem $gem -DryRun
    
    if ($result.success) {
        Write-Host "   ✓ GEM executado com sucesso" -ForegroundColor Green
        
        # Aguardar posição aparecer (em produção, seria real)
        Write-Host "2. Aguardando posição aparecer (simulado)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        
        # Ativar trailing stop
        Write-Host "3. Ativando trailing stop (ATR 2x, min 2% lucro)..." -ForegroundColor Yellow
        $trailing = Update-TrailingStop -Market $gem.market -AtrMultiplier 2.0 -MinProfitPct 2.0 -DryRun
        
        if ($trailing.success) {
            Write-Host "   ✓ Trailing stop configurado" -ForegroundColor Green
            Write-Host "     SL inicial: $($result.stop)" -ForegroundColor Gray
            Write-Host "     SL trailing: dinâmico (ATR-based)" -ForegroundColor Gray
        }
    }
}

# ============================================================================
# EXEMPLO 2: Ajuste de Leverage Pré-Trade
# ============================================================================

function Example2-DynamicLeverage {
    Write-Host "`n=== EXEMPLO 2: Leverage Dinâmico ===" -ForegroundColor Cyan
    
    $market = "ETHUSDT"
    
    Write-Host "1. Analisando volatilidade de $market..." -ForegroundColor Yellow
    
    # Ajustar leverage baseado em volatilidade
    $leverage = Adjust-LeverageByVolatility -Market $market -MaxLeverage 10 -MinLeverage 3 -DryRun
    
    if ($leverage.success) {
        Write-Host "   ✓ Leverage otimizado" -ForegroundColor Green
        Write-Host "     ATR%: $([math]::Round($leverage.atr_pct, 2))%" -ForegroundColor Gray
        Write-Host "     Leverage: $($leverage.new_leverage)x" -ForegroundColor Gray
        
        # Agora abrir posição com leverage otimizado
        Write-Host "2. Abrindo posição com leverage $($leverage.new_leverage)x..." -ForegroundColor Yellow
        Write-Host "   (simulado - em produção usaria CoinEx-PlaceFuturesOrder)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# EXEMPLO 3: Proteção Contínua de Posições
# ============================================================================

function Example3-ContinuousProtection {
    Write-Host "`n=== EXEMPLO 3: Proteção Contínua ===" -ForegroundColor Cyan
    
    Write-Host "Simulando loop de proteção (3 iterações)..." -ForegroundColor Yellow
    
    for ($i = 1; $i -le 3; $i++) {
        Write-Host "`n--- Iteração $i ---" -ForegroundColor DarkCyan
        
        # Scan completo
        $scan = Invoke-PositionRiskScan -DryRun
        
        if ($scan.success) {
            Write-Host "✓ Scan completo: $($scan.positions_scanned) posições" -ForegroundColor Green
            
            # Resumo de ações
            $actions = 0
            foreach ($r in $scan.results) {
                if ($r.trailing_stop.success) { $actions++ }
                if ($r.leverage_adjust.success) { $actions++ }
                if ($r.liq_protection.success) { $actions++ }
            }
            
            if ($actions -gt 0) {
                Write-Host "  → $actions ações tomadas" -ForegroundColor Yellow
            } else {
                Write-Host "  → Nenhuma ação necessária (tudo OK)" -ForegroundColor DarkGray
            }
        }
        
        if ($i -lt 3) {
            Write-Host "Aguardando 5 segundos..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
        }
    }
    
    Write-Host "`n✓ Loop de proteção completo" -ForegroundColor Green
    Write-Host "  Em produção, rodaria indefinidamente via cron" -ForegroundColor DarkGray
}

# ============================================================================
# EXEMPLO 4: Gestão Manual de Posição Específica
# ============================================================================

function Example4-ManualPositionManagement {
    Write-Host "`n=== EXEMPLO 4: Gestão Manual ===" -ForegroundColor Cyan
    
    $market = "BTCUSDT"
    
    Write-Host "Cenário: Posição LONG BTC com lucro de 5%" -ForegroundColor Yellow
    Write-Host ""
    
    # 1. Mover SL para breakeven
    Write-Host "1. Movendo SL para breakeven (proteger capital)..." -ForegroundColor Yellow
    Write-Host "   CoinEx-ModifyPositionStopLoss -Market $market -Price 100000" -ForegroundColor DarkGray
    Write-Host "   ✓ SL movido de 95000 → 100000 (breakeven)" -ForegroundColor Green
    
    # 2. Ajustar TP para resistência
    Write-Host "`n2. Ajustando TP para resistência em 110000..." -ForegroundColor Yellow
    Write-Host "   CoinEx-ModifyPositionTakeProfit -Market $market -Price 110000" -ForegroundColor DarkGray
    Write-Host "   ✓ TP ajustado de 105000 → 110000" -ForegroundColor Green
    
    # 3. Reduzir leverage (mercado ficou volátil)
    Write-Host "`n3. Reduzindo leverage (volatilidade aumentou)..." -ForegroundColor Yellow
    Write-Host "   CoinEx-AdjustPositionLeverage -Market $market -Leverage 5" -ForegroundColor DarkGray
    Write-Host "   ✓ Leverage reduzido de 10x → 5x" -ForegroundColor Green
    
    # 4. Adicionar margin (preço caiu, próximo de SL)
    Write-Host "`n4. Adicionando margin (preço se aproximou do SL)..." -ForegroundColor Yellow
    Write-Host "   CoinEx-AdjustPositionMargin -Market $market -Amount 50 -Type add" -ForegroundColor DarkGray
    Write-Host "   ✓ Margin adicionado: +50 USDT" -ForegroundColor Green
    Write-Host "   → Liquidation price: 92000 → 90000" -ForegroundColor Gray
}

# ============================================================================
# EXEMPLO 5: Analytics de Performance
# ============================================================================

function Example5-PerformanceAnalytics {
    Write-Host "`n=== EXEMPLO 5: Analytics de Performance ===" -ForegroundColor Cyan
    
    Write-Host "Buscando histórico de posições..." -ForegroundColor Yellow
    
    # Buscar últimas 50 posições
    $history = CoinEx-GetFinishedPositions -Limit 50
    
    if ($history.success -and $history.positions.Count -gt 0) {
        Write-Host "✓ $($history.positions.Count) posições encontradas" -ForegroundColor Green
        
        # Calcular métricas
        $wins = 0
        $losses = 0
        $totalPnl = 0
        
        foreach ($pos in $history.positions) {
            $pnl = [double]$pos.pnl
            $totalPnl += $pnl
            
            if ($pnl -gt 0) { $wins++ }
            else { $losses++ }
        }
        
        $winRate = if (($wins + $losses) -gt 0) {
            [math]::Round(($wins / ($wins + $losses)) * 100, 1)
        } else { 0 }
        
        Write-Host "`nMétricas:" -ForegroundColor Cyan
        Write-Host "  Trades: $($history.positions.Count)" -ForegroundColor White
        Write-Host "  Wins: $wins" -ForegroundColor Green
        Write-Host "  Losses: $losses" -ForegroundColor Red
        Write-Host "  Win Rate: $winRate%" -ForegroundColor Yellow
        Write-Host "  PnL Total: $([math]::Round($totalPnl, 2)) USDT" -ForegroundColor $(if($totalPnl -gt 0){"Green"}else{"Red"})
        
        # Top 3 melhores trades
        Write-Host "`nTop 3 Melhores Trades:" -ForegroundColor Cyan
        $top3 = $history.positions | Sort-Object { [double]$_.pnl } -Descending | Select-Object -First 3
        foreach ($t in $top3) {
            Write-Host "  $($t.market): +$($t.pnl) USDT ($($t.side))" -ForegroundColor Green
        }
        
        # Top 3 piores trades
        Write-Host "`nTop 3 Piores Trades:" -ForegroundColor Cyan
        $bottom3 = $history.positions | Sort-Object { [double]$_.pnl } | Select-Object -First 3
        foreach ($t in $bottom3) {
            Write-Host "  $($t.market): $($t.pnl) USDT ($($t.side))" -ForegroundColor Red
        }
    } else {
        Write-Host "✗ Nenhuma posição encontrada" -ForegroundColor Yellow
    }
}

# ============================================================================
# MENU PRINCIPAL
# ============================================================================

function Show-Menu {
    Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   POSITION MANAGEMENT - EXEMPLOS DE INTEGRAÇÃO        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. GEM com Trailing Stop Automático" -ForegroundColor White
    Write-Host "2. Ajuste de Leverage Dinâmico" -ForegroundColor White
    Write-Host "3. Proteção Contínua (Loop)" -ForegroundColor White
    Write-Host "4. Gestão Manual de Posição" -ForegroundColor White
    Write-Host "5. Analytics de Performance" -ForegroundColor White
    Write-Host "6. Rodar TODOS os exemplos" -ForegroundColor Yellow
    Write-Host "0. Sair" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          POSITION MANAGEMENT INTEGRATION               ║" -ForegroundColor Cyan
Write-Host "║                                                        ║" -ForegroundColor Cyan
Write-Host "║  Exemplos práticos de integração com agents           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

while ($true) {
    Show-Menu
    $choice = Read-Host "Escolha uma opção"
    
    switch ($choice) {
        "1" { Example1-GemWithTrailingStop }
        "2" { Example2-DynamicLeverage }
        "3" { Example3-ContinuousProtection }
        "4" { Example4-ManualPositionManagement }
        "5" { Example5-PerformanceAnalytics }
        "6" {
            Example1-GemWithTrailingStop
            Example2-DynamicLeverage
            Example3-ContinuousProtection
            Example4-ManualPositionManagement
            Example5-PerformanceAnalytics
        }
        "0" {
            Write-Host "`nAté logo!" -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "`n✗ Opção inválida" -ForegroundColor Red
        }
    }
    
    if ($choice -eq "0") { break }
    
    Write-Host "`nPressione ENTER para continuar..." -ForegroundColor DarkGray
    Read-Host
}
