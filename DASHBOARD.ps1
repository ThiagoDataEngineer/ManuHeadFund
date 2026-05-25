# DASHBOARD.ps1 - Launcher para Dashboards
# Uso: .\DASHBOARD.ps1 [elite|ops|analise]
param(
    [Parameter(Position=0)]
    [ValidateSet('elite', 'ops', 'analise', '')]
    [string]$Dashboard = 'elite'
)

Write-Host "`n=== DASHBOARD LAUNCHER ===" -ForegroundColor Cyan

# Mapear dashboard para arquivo HTML
$dashboardFiles = @{
    'elite' = 'elite.html'
    'ops' = 'index.html'
    'analise' = 'position_metrics.html'
}

$htmlFile = $dashboardFiles[$Dashboard]

# Coletar dados (apenas para elite e ops que usam data.js)
if ($Dashboard -in @('elite', 'ops')) {
    Write-Host "[1/2] Coletando dados..." -ForegroundColor Yellow
    $data = .\scripts\collect_dashboard_data.ps1 | ConvertFrom-Json
    Write-Host "  OK" -ForegroundColor Green

    # Criar arquivo JS completo
    Write-Host "[2/2] Gerando dashboard..." -ForegroundColor Yellow
$jsContent = @"
const data = $($data | ConvertTo-Json -Depth 10);
window.onload = function() {
    document.getElementById('trades30d').textContent = data.trading_metrics.trades_30d;
    document.getElementById('winRate').textContent = data.trading_metrics.win_rate + '%';
    document.getElementById('profitFactor').textContent = data.trading_metrics.profit_factor;
    document.getElementById('approvalRate').textContent = data.mentor_decisions.approval_rate + '%';
    document.getElementById('consensus').textContent = data.mesa_consensus.consensus;
    document.getElementById('regime').textContent = data.market_regime.regime.replace('_', ' ');
    document.getElementById('trades24h').textContent = data.trading_metrics.trades_24h;
    document.getElementById('trades7d').textContent = data.trading_metrics.trades_7d;
    document.getElementById('bestTrade').textContent = '$' + data.trading_metrics.best_trade;
    document.getElementById('worstTrade').textContent = '$' + data.trading_metrics.worst_trade;
    document.getElementById('sharpe').textContent = data.trading_metrics.sharpe_ratio;
    document.getElementById('mentorTotal').textContent = data.mentor_decisions.total_24h;
    document.getElementById('mentorApproval').textContent = data.mentor_decisions.approval_rate + '%';
    document.getElementById('mentorVeto').textContent = data.mentor_decisions.veto_rate + '%';
    document.getElementById('mesaScore').textContent = data.mesa_consensus.score_avg;
    document.getElementById('mesaDegraded').textContent = data.mesa_consensus.degraded_count;
    document.getElementById('marketCycle').textContent = data.market_regime.cycle;
    document.getElementById('mceScore').textContent = data.market_regime.mce_score;
    document.getElementById('cost24h').textContent = '$' + data.llm_costs.total_24h;
    document.getElementById('cost30d').textContent = '$' + data.llm_costs.total_30d;
    document.getElementById('costPerDecision').textContent = '$' + data.llm_costs.cost_per_decision;
    document.getElementById('beta').textContent = data.portfolio_metrics.beta;
    document.getElementById('exposure').textContent = '$' + data.portfolio_metrics.exposure_total;
    document.getElementById('diversification').textContent = data.portfolio_metrics.diversification;
    let trailingHtml = '<table><tr><th>Market</th><th>Threshold</th><th>Volatility</th><th>Momentum</th></tr>';
    data.trailing_stop.forEach(t => {
        trailingHtml += '<tr><td>' + t.market + '</td><td>' + t.threshold_pct + '%</td><td>' + t.volatility_class + '</td><td>' + t.momentum + '</td></tr>';
    });
    trailingHtml += '</table>';
    document.getElementById('trailingTable').innerHTML = trailingHtml;
};
"@
    $jsContent | Out-File "dashboard\data.js" -Encoding UTF8
    Write-Host "  OK" -ForegroundColor Green

    # Resumo (apenas para elite)
    if ($Dashboard -eq 'elite') {
        Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
        Write-Host "Trading: $($data.trading_metrics.trades_30d) trades | WR $($data.trading_metrics.win_rate)%"
        Write-Host "Mentor: $($data.mentor_decisions.approval_rate)% aprovacao | $($data.mentor_decisions.veto_rate)% veto"
        Write-Host "Mesa: $($data.mesa_consensus.consensus) | Score $($data.mesa_consensus.score_avg)"
        Write-Host "Regime: $($data.market_regime.regime) - $($data.market_regime.cycle)"
        Write-Host "Portfolio: Beta $($data.portfolio_metrics.beta) | $($data.portfolio_metrics.diversification) posicoes"
        Write-Host "Trailing: $($data.trailing_stop.Count) posicoes monitoradas"
    }
}

# Abrir dashboard selecionado
Write-Host "`nAbrindo dashboard: $Dashboard..." -ForegroundColor Yellow
Start-Process "dashboard\$htmlFile"
Write-Host "`n=== PRONTO ===" -ForegroundColor Green
Write-Host "`nDashboards disponíveis:" -ForegroundColor Cyan
Write-Host "  .\DASHBOARD.ps1 elite    - Dashboard Elite (11 categorias)" -ForegroundColor White
Write-Host "  .\DASHBOARD.ps1 ops      - Dashboard Operacional (posições + tasks)" -ForegroundColor White
Write-Host "  .\DASHBOARD.ps1 analise  - Dashboard de Análise (métricas)" -ForegroundColor White
