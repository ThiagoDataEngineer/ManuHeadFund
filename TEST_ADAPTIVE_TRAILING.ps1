# TEST_ADAPTIVE_TRAILING.ps1
# Testar sistema de trailing stop adaptativo
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_trailing_stop_adaptive.ps1"

Write-Host "=== TESTE: TRAILING STOP ADAPTATIVO ===" -ForegroundColor Cyan
Write-Host ""

# Buscar posicoes atuais
$positions = CoinEx-GetPendingPositions

if (-not $positions -or $positions.Count -eq 0) {
    Write-Host "Nenhuma posicao aberta para testar." -ForegroundColor Yellow
    exit 0
}

Write-Host "Testando $($positions.Count) posicao(oes)..." -ForegroundColor Yellow
Write-Host ""

foreach ($pos in $positions) {
    $market = $pos.market
    $currentPrice = [double]$pos.latest_price
    $entryPrice = [double]$pos.avg_entry_price
    $pnl = [double]$pos.unrealized_pnl_rate
    
    Write-Host "=== $market ===" -ForegroundColor Cyan
    Write-Host "  Entry: `$$entryPrice"
    Write-Host "  Current: `$$currentPrice"
    Write-Host "  PNL: $([Math]::Round($pnl,2))%"
    Write-Host ""
    
    # Testar threshold adaptativo
    Write-Host "  [1] Adaptive Threshold:" -ForegroundColor Yellow
    $threshold = Get-AdaptiveTrailingThreshold -Market $market -CurrentPrice $currentPrice
    Write-Host "    Volatility: $($threshold.volatility_class) (ATR: $($threshold.atr_pct)%)"
    Write-Host "    Threshold: $($threshold.threshold_pct)% (vs 3.0% fixo)"
    Write-Host "    Reasoning: $($threshold.reasoning)"
    
    # Comparar com threshold fixo
    $fixedThreshold = 3.0
    if ($threshold.threshold_pct -lt $fixedThreshold) {
        Write-Host "    → Trailing ativaria MAIS CEDO ($($threshold.threshold_pct)% vs $fixedThreshold%)" -ForegroundColor Green
    } elseif ($threshold.threshold_pct -gt $fixedThreshold) {
        Write-Host "    → Trailing ativaria MAIS TARDE ($($threshold.threshold_pct)% vs $fixedThreshold%)" -ForegroundColor Yellow
    } else {
        Write-Host "    → Mesmo threshold que fixo" -ForegroundColor Gray
    }
    
    Write-Host ""
    
    # Testar distancia adaptativa
    Write-Host "  [2] Adaptive Distance:" -ForegroundColor Yellow
    $distance = Get-AdaptiveTrailingDistance -Market $market -CurrentPrice $currentPrice -EntryPrice $entryPrice -CurrentPNL $pnl
    Write-Host "    Momentum: $($distance.momentum) (RSI: $($distance.momentum_score))"
    Write-Host "    Support: `$$($distance.support_price) ($($distance.support_distance)% abaixo)"
    Write-Host "    Distance: $($distance.distance_pct)% (vs 2.0% fixo)"
    Write-Host "    Reasoning: $($distance.reasoning)"
    
    # Calcular stop price com distancia adaptativa
    $stopPrice = $currentPrice * (1 - $distance.distance_pct / 100)
    Write-Host "    → Stop adaptativo: `$$([Math]::Round($stopPrice, 4))"
    
    Write-Host ""
    
    # Status de ativacao
    if ($pnl -ge $threshold.threshold_pct) {
        Write-Host "  STATUS: TRAILING ATIVADO ✅" -ForegroundColor Green
        Write-Host "    PNL $([Math]::Round($pnl,2))% >= Threshold $($threshold.threshold_pct)%"
    } else {
        $remaining = $threshold.threshold_pct - $pnl
        Write-Host "  STATUS: AGUARDANDO ATIVACAO ⏳" -ForegroundColor Yellow
        Write-Host "    Faltam $([Math]::Round($remaining,2))% para ativar trailing"
    }
    
    Write-Host ""
    Write-Host "---" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "=== RESUMO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sistema adaptativo configurado com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "Beneficios:" -ForegroundColor Yellow
Write-Host "  • Threshold dinamico baseado em volatilidade (ATR)"
Write-Host "  • Distancia ajustada por momentum (RSI) e suporte tecnico"
Write-Host "  • Protecao mais precisa para cada ativo"
Write-Host ""
Write-Host "Proximo passo: Ativar em producao no trailing_stop_monitor.ps1" -ForegroundColor Cyan
