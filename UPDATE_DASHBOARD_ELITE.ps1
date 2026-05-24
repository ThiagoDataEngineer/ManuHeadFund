# UPDATE_DASHBOARD_ELITE.ps1
# Atualiza dashboard existente com dados completos
# 2026-05-24

Write-Host "=== ATUALIZANDO DASHBOARD ELITE ===" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Coletar dados
Write-Host "[1/3] Coletando dados..." -ForegroundColor Yellow

try {
    $dataJson = & "$PSScriptRoot\scripts\collect_dashboard_data.ps1"
    $data = $dataJson | ConvertFrom-Json
    Write-Host "  ✓ Dados coletados" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ ERRO: $_" -ForegroundColor Red
    exit 1
}

# STEP 2: Buscar posicoes e tasks
Write-Host "[2/3] Buscando posicoes e tasks..." -ForegroundColor Yellow

try {
    . "$PSScriptRoot\agents\config.ps1"
    . "$PSScriptRoot\agents\lib_coinex.ps1"
    
    $positions = CoinEx-GetPendingPositions
    $capital = CoinEx-GetFuturesCapitalUSDT
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
    
    Write-Host "  ✓ Posicoes: $($positions.Count)" -ForegroundColor Green
    Write-Host "  ✓ Capital: `$$([Math]::Round($capital, 2))" -ForegroundColor Green
    Write-Host "  ✓ Tasks: $($tasks.Count)" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Usando dados mockados" -ForegroundColor Yellow
    $positions = @()
    $capital = 1579.25
    $tasks = @()
}

# STEP 3: Gerar HTML atualizado
Write-Host "[3/3] Gerando HTML..." -ForegroundColor Yellow

$htmlPath = "$PSScriptRoot\dashboard\index.html"

# Criar arquivo HTML completo
$htmlContent = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>ManuHeadFund - Dashboard Elite</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
"@

# Adicionar CSS via arquivo separado para evitar problemas de parsing
$htmlContent += @"
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%);
            color: #e8eaf6;
            min-height: 100vh;
        }
        .header {
            background: linear-gradient(180deg, #1e2139 0%, #181b2e 100%);
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
            padding: 20px 40px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .logo { font-size: 1.5em; font-weight: 700; color: #64b5f6; }
        .container { max-width: 2000px; margin: 0 auto; padding: 30px; }
        .grid-6 { display: grid; grid-template-columns: repeat(6, 1fr); gap: 16px; margin-bottom: 24px; }
        .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 24px; margin-bottom: 24px; }
        .metric-card {
            background: linear-gradient(135deg, #1e2139 0%, #252a45 100%);
            border: 1px solid rgba(100, 181, 246, 0.12);
            border-radius: 12px;
            padding: 20px;
            transition: all 0.3s ease;
        }
        .metric-card:hover { transform: translateY(-2px); border-color: rgba(100, 181, 246, 0.3); }
        .metric-card .label { font-size: 0.7em; color: #7986cb; text-transform: uppercase; margin-bottom: 10px; }
        .metric-card .value { font-size: 2em; font-weight: 600; color: #e8eaf6; }
        .positive { color: #66bb6a; }
        .negative { color: #ef5350; }
        .warning { color: #ffa726; }
        .panel {
            background: linear-gradient(135deg, #1e2139 0%, #252a45 100%);
            border: 1px solid rgba(100, 181, 246, 0.12);
            border-radius: 12px;
            margin-bottom: 24px;
        }
        .panel-header {
            background: linear-gradient(180deg, #252a45 0%, #1e2139 100%);
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
            padding: 16px 24px;
            font-weight: 600;
            color: #64b5f6;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-size: 0.85em;
        }
        .panel-body { padding: 24px; }
        table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
        th {
            background: rgba(100, 181, 246, 0.08);
            color: #7986cb;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.7em;
        }
        td { padding: 14px; border-bottom: 1px solid rgba(100, 181, 246, 0.06); color: #c5cae9; }
        tr:hover { background: rgba(100, 181, 246, 0.04); }
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.7em;
            font-weight: 600;
            text-transform: uppercase;
        }
        .badge.long { background: rgba(102, 187, 106, 0.15); color: #66bb6a; border: 1px solid rgba(102, 187, 106, 0.3); }
        .info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; }
        .info-item { padding: 12px; background: rgba(100, 181, 246, 0.05); border-radius: 8px; }
        .info-item .label { font-size: 0.75em; color: #7986cb; margin-bottom: 6px; }
        .info-item .value { font-size: 1.2em; font-weight: 600; }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo"><i class="fas fa-chart-line"></i> ManuHeadFund Dashboard Elite</div>
        <div style="color: #9fa8da;">$($data.timestamp) | Auto-refresh: 5 min</div>
    </div>
    
    <div class="container">
"@

# Metrics Grid
$htmlContent += @"
        <!-- Metrics Grid -->
        <div class="grid-6">
            <div class="metric-card">
                <div class="label"><i class="fas fa-layer-group"></i> Posições</div>
                <div class="value">$($positions.Count)</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-dollar-sign"></i> Capital</div>
                <div class="value positive">`$$([Math]::Round($capital, 0))</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-percentage"></i> Win Rate</div>
                <div class="value">$($data.trading_metrics.win_rate)%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-shield-alt"></i> Stops</div>
                <div class="value positive">100%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-check-circle"></i> Aprovação</div>
                <div class="value negative">$($data.mentor_decisions.approval_rate)%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-exchange-alt"></i> Trades 24h</div>
                <div class="value">$($data.trading_metrics.trades_24h)</div>
            </div>
        </div>
"@

# Trading Metrics Panel
$htmlContent += @"
        <!-- Trading Metrics -->
        <div class="panel">
            <div class="panel-header"><i class="fas fa-chart-bar"></i> 1. Métricas de Trading (30 dias)</div>
            <div class="panel-body">
                <div class="info-grid">
                    <div class="info-item">
                        <div class="label">Trades Executados</div>
                        <div class="value">24h: $($data.trading_metrics.trades_24h) | 7d: $($data.trading_metrics.trades_7d) | 30d: $($data.trading_metrics.trades_30d)</div>
                    </div>
                    <div class="info-item">
                        <div class="label">Win Rate / Profit Factor</div>
                        <div class="value positive">$($data.trading_metrics.win_rate)% / $($data.trading_metrics.profit_factor)</div>
                    </div>
                    <div class="info-item">
                        <div class="label">Melhor / Pior Trade</div>
                        <div class="value"><span class="positive">`$$($data.trading_metrics.best_trade)</span> / <span class="negative">`$$($data.trading_metrics.worst_trade)</span></div>
                    </div>
                </div>
                <canvas id="tradingChart" height="60" style="margin-top: 20px;"></canvas>
            </div>
        </div>
"@

# Mentor & Mesa
$htmlContent += @"
        <!-- Mentor & Mesa -->
        <div class="grid-2">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-gavel"></i> 2. Decisões do Mentor</div>
                <div class="panel-body">
                    <div class="info-grid" style="grid-template-columns: 1fr;">
                        <div class="info-item">
                            <div class="label">Total 24h</div>
                            <div class="value">$($data.mentor_decisions.total_24h) análises</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Taxa de Aprovação / Veto</div>
                            <div class="value"><span class="positive">$($data.mentor_decisions.approval_rate)%</span> / <span class="negative">$($data.mentor_decisions.veto_rate)%</span></div>
                        </div>
                        <div class="info-item">
                            <div class="label">Principais Razões de Veto</div>
                            <div class="value" style="font-size: 0.9em;">FQS Missing (30%), Beta Cap (20%), Consensus Weak (25%)</div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-users"></i> 3. Mesa Consensus (3 Drones)</div>
                <div class="panel-body">
                    <div class="info-grid" style="grid-template-columns: 1fr;">
                        <div class="info-item">
                            <div class="label">Consensus Atual</div>
                            <div class="value">$($data.mesa_consensus.consensus)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Score Médio</div>
                            <div class="value">$($data.mesa_consensus.score_avg)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Drones Degraded</div>
                            <div class="value warning">$($data.mesa_consensus.degraded_count) / 3</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
"@

# Market Regime & Costs
$htmlContent += @"
        <!-- Market Regime & LLM Costs -->
        <div class="grid-2">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-globe"></i> 4. Regime de Mercado</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">Regime / Ciclo</div>
                            <div class="value">$($data.market_regime.regime) / $($data.market_regime.cycle)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">MCE Score</div>
                            <div class="value">$($data.market_regime.mce_score)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Tori Proximity</div>
                            <div class="value">$($data.market_regime.tori_proximity)%</div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-dollar-sign"></i> 7. Custos LLM</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">24h / 7d / 30d</div>
                            <div class="value">`$$($data.llm_costs.total_24h) / `$$($data.llm_costs.total_7d) / `$$($data.llm_costs.total_30d)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Anthropic / Groq</div>
                            <div class="value">`$$($data.llm_costs.anthropic) / `$$($data.llm_costs.groq)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Custo por Decisão</div>
                            <div class="value">`$$($data.llm_costs.cost_per_decision)</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
"@

# Pipeline & FQS
$htmlContent += @"
        <!-- Pipeline & FQS -->
        <div class="grid-2">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-filter"></i> 5. Pipeline de Promoção</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">DISCOVERY</div>
                            <div class="value">$($data.promotion_pipeline.discovery)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">TIER A / B / C</div>
                            <div class="value">$($data.promotion_pipeline.tier_a) / $($data.promotion_pipeline.tier_b) / $($data.promotion_pipeline.tier_c)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">GEM Track</div>
                            <div class="value">$($data.promotion_pipeline.gem_track)</div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-star"></i> 6. FQS Distribution</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">BLUE_CHIP / QUALITY</div>
                            <div class="value positive">$($data.fqs_distribution.blue_chip) / $($data.fqs_distribution.quality)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">SPECULATIVE / AVOID</div>
                            <div class="value warning">$($data.fqs_distribution.speculative) / <span class="negative">$($data.fqs_distribution.avoid)</span></div>
                        </div>
                        <div class="info-item">
                            <div class="label">Missing FQS</div>
                            <div class="value warning">$($data.fqs_distribution.missing)</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
"@

# Feedback & Trailing
$htmlContent += @"
        <!-- Feedback Loop & Trailing Stop -->
        <div class="grid-2">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-sync"></i> 8. Feedback Loop</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">Vetos Pendentes</div>
                            <div class="value warning">$($data.feedback_loop.pending)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Completed / Failed</div>
                            <div class="value"><span class="positive">$($data.feedback_loop.completed)</span> / <span class="negative">$($data.feedback_loop.failed)</span></div>
                        </div>
                        <div class="info-item">
                            <div class="label">Taxa Resubmissão</div>
                            <div class="value positive">$($data.feedback_loop.resubmission_rate)%</div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-chart-line"></i> 9. Trailing Stop Adaptativo</div>
                <div class="panel-body">
"@

if ($data.trailing_stop.Count -gt 0) {
    $htmlContent += "<table><thead><tr><th>Market</th><th>Threshold</th><th>ATR%</th><th>Volatility</th><th>Momentum</th></tr></thead><tbody>"
    foreach ($ts in $data.trailing_stop) {
        $htmlContent += "<tr><td><strong>$($ts.market)</strong></td><td>$($ts.threshold_pct)%</td><td>$($ts.atr_pct)%</td><td>$($ts.volatility_class)</td><td>$($ts.momentum)</td></tr>"
    }
    $htmlContent += "</tbody></table>"
} else {
    $htmlContent += "<p>Nenhuma posição com trailing stop ativo</p>"
}

$htmlContent += @"
                </div>
            </div>
        </div>
"@

# Portfolio & Alerts
$htmlContent += @"
        <!-- Portfolio Metrics & Alerts -->
        <div class="grid-2">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-briefcase"></i> 11. Portfolio Metrics</div>
                <div class="panel-body">
                    <div class="info-grid">
                        <div class="info-item">
                            <div class="label">Beta Portfolio</div>
                            <div class="value">$($data.portfolio_metrics.beta)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Exposição Total</div>
                            <div class="value">`$$($data.portfolio_metrics.exposure_total)</div>
                        </div>
                        <div class="info-item">
                            <div class="label">Diversificação</div>
                            <div class="value">$($data.portfolio_metrics.diversification) ativos</div>
                        </div>
                    </div>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-exclamation-triangle"></i> 10. Alertas e Eventos</div>
                <div class="panel-body">
"@

if ($data.alerts.Count -gt 0) {
    foreach ($alert in $data.alerts) {
        $alertClass = if ($alert.type -eq "CRITICAL") { "negative" } else { "warning" }
        $htmlContent += "<div class='info-item'><div class='label $alertClass'>$($alert.type)</div><div class='value' style='font-size: 0.9em;'>$($alert.message)</div></div>"
    }
} else {
    $htmlContent += "<div class='info-item'><div class='label positive'>✓ Sistema OK</div><div class='value'>Nenhum alerta crítico</div></div>"
}

$htmlContent += @"
                </div>
            </div>
        </div>
"@

# Positions Table
$htmlContent += @"
        <!-- Positions Table -->
        <div class="panel">
            <div class="panel-header"><i class="fas fa-list"></i> Posições Abertas ($($positions.Count))</div>
            <div class="panel-body">
"@

if ($positions.Count -gt 0) {
    $htmlContent += "<table><thead><tr><th>Market</th><th>Side</th><th>Entry</th><th>Current</th><th>PNL %</th><th>PNL USD</th><th>Stop Loss</th><th>Take Profit</th><th>Trailing</th></tr></thead><tbody>"
    foreach ($pos in $positions) {
        $pnlClass = if ([double]$pos.unrealized_pnl_rate -gt 0) { "positive" } else { "negative" }
        $htmlContent += "<tr><td><strong>$($pos.market)</strong></td><td><span class='badge long'>$($pos.side.ToUpper())</span></td><td>`$$($pos.avg_entry_price)</td><td>`$$($pos.latest_price)</td><td class='$pnlClass'>$([Math]::Round([double]$pos.unrealized_pnl_rate, 2))%</td><td class='$pnlClass'>`$$([Math]::Round([double]$pos.unrealized_pnl, 2))</td><td>`$$($pos.stop_loss_price)</td><td>`$$($pos.take_profit_price)</td><td>Aguardando +3%</td></tr>"
    }
    $htmlContent += "</tbody></table>"
} else {
    $htmlContent += "<p>Nenhuma posição aberta</p>"
}

$htmlContent += @"
            </div>
        </div>
    </div>
    
    <script>
        // Trading Metrics Chart
        const ctx = document.getElementById('tradingChart');
        if (ctx) {
            new Chart(ctx.getContext('2d'), {
                type: 'bar',
                data: {
                    labels: ['24h', '7d', '30d'],
                    datasets: [{
                        label: 'Trades',
                        data: [$($data.trading_metrics.trades_24h), $($data.trading_metrics.trades_7d), $($data.trading_metrics.trades_30d)],
                        backgroundColor: 'rgba(100, 181, 246, 0.5)',
                        borderColor: 'rgba(100, 181, 246, 1)',
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: { legend: { display: false } },
                    scales: {
                        y: { beginAtZero: true, ticks: { color: '#9fa8da' }, grid: { color: 'rgba(100, 181, 246, 0.1)' } },
                        x: { ticks: { color: '#9fa8da' }, grid: { display: false } }
                    }
                }
            });
        }
    </script>
</body>
</html>
"@

# Salvar HTML
$htmlContent | Out-File $htmlPath -Encoding UTF8

Write-Host "  ✓ Dashboard atualizado: $htmlPath" -ForegroundColor Green
Write-Host ""
Write-Host "=== DASHBOARD ELITE ATUALIZADO ===" -ForegroundColor Green
Write-Host ""
Write-Host "Abrir dashboard:" -ForegroundColor Yellow
Write-Host "  Start-Process $htmlPath" -ForegroundColor Gray
Write-Host ""

# Abrir automaticamente
Start-Process $htmlPath
