# generate_dashboard_elite.ps1 - Dashboard Elite ManuHeadFund
# Design inspirado em Bloomberg Terminal + Hedge Funds
# Color Scheme: Amber on Black (profissional)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

# Carregar proteÃ§Ã£o anti-duplicaÃ§Ã£o
. ".\scripts\check_execution_mode.ps1"

# Executar com proteÃ§Ã£o (LOCAL ou GITHUB ACTIONS)
Invoke-SafeJob -JobName "dashboard-generator" -PreferredMode "both" -ScriptBlock {

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"
. ".\agents\lib_telegram.ps1"

# Reutilizar funcoes do dashboard pro
. ".\scripts\generate_dashboard_pro.ps1"

# ============================================================================
# Generate-EliteHTML - HTML com design Bloomberg-inspired
# ============================================================================

function Generate-EliteHTML {
    param($Metrics)
    
    if (-not $Metrics) {
        return "<html><body><h1>Erro ao carregar metricas</h1></body></html>"
    }
    
    # Preparar dados
    $timestamp = $Metrics.timestamp
    $openPos = $Metrics.open_positions
    $totalPnl = $Metrics.total_pnl
    $winRate = $Metrics.win_rate
    $capital = $Metrics.capital
    $sharpe = $Metrics.sharpe_ratio
    $maxDD = $Metrics.max_drawdown
    $profitFactor = $Metrics.profit_factor
    
    $pnlSign = if ($totalPnl -gt 0) { "+" } else { "" }
    $pnlColor = if ($totalPnl -gt 0) { "#00FF00" } elseif ($totalPnl -lt 0) { "#FF0000" } else { "#FFB84D" }
    
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>ManuHeadFund | Trading Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%);
            color: #e8eaf6;
            padding: 0;
            min-height: 100vh;
            overflow-x: hidden;
        }
        .header {
            background: linear-gradient(180deg, #1e2139 0%, #181b2e 100%);
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
            padding: 20px 40px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 0 2px 12px rgba(0, 0, 0, 0.3);
        }
        .header .logo {
            font-size: 1.3em;
            font-weight: 600;
            color: #64b5f6;
            letter-spacing: 0.5px;
        }
        .header .timestamp {
            font-size: 0.85em;
            color: #9fa8da;
            font-weight: 400;
        }
        .container { max-width: 1800px; margin: 0 auto; padding: 30px; }

        /* Metrics Grid - Refinitiv Style */
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(6, 1fr);
            gap: 16px;
            margin-bottom: 24px;
        }
        .metric-card {
            background: linear-gradient(135deg, #1e2139 0%, #252a45 100%);
            border: 1px solid rgba(100, 181, 246, 0.12);
            border-radius: 8px;
            padding: 20px;
            transition: all 0.3s ease;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }
        .metric-card:hover {
            border-color: rgba(100, 181, 246, 0.3);
            transform: translateY(-2px);
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.3);
        }
        .metric-card .label {
            font-size: 0.7em;
            color: #7986cb;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
            font-weight: 500;
        }
        .metric-card .value {
            font-size: 2em;
            font-weight: 600;
            color: #e8eaf6;
            line-height: 1.2;
        }
        .metric-card.positive .value { color: #66bb6a; }
        .metric-card.negative .value { color: #ef5350; }
        .metric-card.warning .value { color: #ffa726; }
        .metric-card.info .value { color: #42a5f5; }

        /* Panel - Professional Style */
        .panel {
            background: linear-gradient(135deg, #1e2139 0%, #252a45 100%);
            border: 1px solid rgba(100, 181, 246, 0.12);
            border-radius: 8px;
            margin-bottom: 24px;
            overflow: hidden;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
        }
        .panel-header {
            background: linear-gradient(180deg, #252a45 0%, #1e2139 100%);
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
            padding: 16px 24px;
            font-size: 0.85em;
            font-weight: 600;
            color: #64b5f6;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .panel-body {
            padding: 24px;
        }

        /* Table - Financial Terminal Style */
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }
        th {
            background: rgba(100, 181, 246, 0.08);
            color: #7986cb;
            padding: 14px 16px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-size: 0.75em;
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
        }
        td {
            padding: 16px;
            border-bottom: 1px solid rgba(100, 181, 246, 0.06);
            color: #c5cae9;
        }
        tr:hover {
            background: rgba(100, 181, 246, 0.04);
        }

        /* Badge - Subtle Professional */
        .badge {
            display: inline-block;
            padding: 5px 12px;
            border-radius: 4px;
            font-size: 0.75em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .badge.long {
            background: rgba(102, 187, 106, 0.15);
            color: #66bb6a;
            border: 1px solid rgba(102, 187, 106, 0.3);
        }
        .badge.short {
            background: rgba(239, 83, 80, 0.15);
            color: #ef5350;
            border: 1px solid rgba(239, 83, 80, 0.3);
        }

        /* Status Colors - Professional */
        .status-positive { color: #66bb6a; font-weight: 600; }
        .status-negative { color: #ef5350; font-weight: 600; }
        .status-neutral { color: #9fa8da; font-weight: 600; }

        /* Trailing Indicator - Elegant */
        .trailing-active {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 6px 14px;
            background: rgba(102, 187, 106, 0.15);
            color: #66bb6a;
            border: 1px solid rgba(102, 187, 106, 0.3);
            border-radius: 4px;
            font-size: 0.75em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .trailing-active i {
            animation: pulse 2s ease-in-out infinite;
        }
        .trailing-waiting {
            color: #5c6bc0;
            font-size: 0.75em;
            text-transform: uppercase;
            font-weight: 500;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }

        /* Charts Container */
        .charts-container {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 24px;
        }
        .chart-panel {
            background: linear-gradient(135deg, #1e2139 0%, #252a45 100%);
            border: 1px solid rgba(100, 181, 246, 0.12);
            border-radius: 8px;
            padding: 24px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
        }
        .chart-panel h3 {
            color: #64b5f6;
            font-size: 0.85em;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 20px;
            font-weight: 600;
        }

        /* Empty State */
        .empty-state {
            text-align: center;
            padding: 80px 40px;
            color: #5c6bc0;
        }
        .empty-state i {
            font-size: 3.5em;
            margin-bottom: 20px;
            display: block;
            opacity: 0.4;
        }
        .empty-state p {
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 500;
        }

        /* Responsive */
        @media (max-width: 1200px) {
            .metrics-grid { grid-template-columns: repeat(3, 1fr); }
            .charts-container { grid-template-columns: 1fr; }
        }
        @media (max-width: 768px) {
            .metrics-grid { grid-template-columns: repeat(2, 1fr); }
            .header { flex-direction: column; gap: 10px; text-align: center; padding: 20px; }
            .container { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">ManuHeadFund</div>
        <div class="timestamp">$timestamp UTC</div>
    </div>
    
    <div class="container">
        <!-- Metrics Grid -->
        <div class="metrics-grid">
            <div class="metric-card info">
                <div class="label">Open Positions</div>
                <div class="value">$openPos</div>
            </div>
            <div class="metric-card $(if($totalPnl -gt 0){'positive'}elseif($totalPnl -lt 0){'negative'}else{''})">
                <div class="label">Total P&L</div>
                <div class="value">$pnlSign`$$totalPnl</div>
            </div>
            <div class="metric-card $(if($winRate -ge 50){'positive'}elseif($winRate -ge 40){'warning'}else{'negative'})">
                <div class="label">Win Rate</div>
                <div class="value">$winRate%</div>
            </div>
            <div class="metric-card">
                <div class="label">Available Capital</div>
                <div class="value">`$$capital</div>
            </div>
            <div class="metric-card $(if($sharpe -gt 1){'positive'}elseif($sharpe -gt 0){'warning'}else{'negative'})">
                <div class="label">Sharpe Ratio</div>
                <div class="value">$sharpe</div>
            </div>
            <div class="metric-card $(if($maxDD -lt 10){'positive'}elseif($maxDD -lt 20){'warning'}else{'negative'})">
                <div class="label">Max Drawdown</div>
                <div class="value">$maxDD%</div>
            </div>
        </div>
"@
    
    # Continue building HTML (nÃ£o retornar ainda)
    
    # Open Positions Table
        if ($Metrics.open_positions -gt 0) {
            $html += @"
        
        <!-- Open Positions -->
        <div class="panel">
            <div class="panel-header">Open Positions</div>
            <div class="panel-body">
                <table>
                    <thead>
                        <tr>
                            <th>Market</th>
                            <th>Side</th>
                            <th>Entry Price</th>
                            <th>Current Price</th>
                            <th>P&L %</th>
                            <th>Unrealized P&L</th>
                            <th>Leverage</th>
                            <th>Trailing Stop</th>
                        </tr>
                    </thead>
                    <tbody>
"@
            
            $posArray = if ($Metrics.open_positions_detail -is [array]) {
                $Metrics.open_positions_detail
            } else {
                @($Metrics.open_positions_detail)
            }
            
            foreach ($pos in $posArray) {
                $market = $pos.market
                $side = $pos.side.ToUpper()
                $entryPrice = [math]::Round([double]$pos.avg_entry_price, 2)
                
                $ticker = CoinEx-GetTickerFresh -market $market
                $currentPrice = [math]::Round([double]$ticker.ticker.last, 2)
                
                $pnlPct = if ($pos.side -eq "long") {
                    (($currentPrice - $entryPrice) / $entryPrice) * 100
                } else {
                    (($entryPrice - $currentPrice) / $entryPrice) * 100
                }
                $pnlPct = [math]::Round($pnlPct, 2)
                
                $unrealizedPnl = [math]::Round([double]$pos.unrealized_pnl, 2)
                $leverage = $pos.leverage
                
                $pnlClass = if ($pnlPct -gt 0) { "status-positive" } else { "status-negative" }
                $sideClass = if ($pos.side -eq "long") { "long" } else { "short" }
                
                # Trailing indicator
                $trailing = Calculate-TrailingStopMetrics -Position $pos
                $trailingHtml = if ($trailing.trailing_activated) {
                    "<span class='trailing-active'><i class='fas fa-chart-line'></i> Trailing +$($trailing.locked_profit_pct)%</span>"
                } else {
                    "<span class='trailing-waiting'>Waiting +3%</span>"
                }
                
                $html += @"
                        <tr>
                            <td><strong>$market</strong></td>
                            <td><span class='badge $sideClass'>$side</span></td>
                            <td>`$$entryPrice</td>
                            <td>`$$currentPrice</td>
                            <td class='$pnlClass'>$pnlPct%</td>
                            <td class='$pnlClass'>`$$unrealizedPnl</td>
                            <td>$leverageÃ—</td>
                            <td>$trailingHtml</td>
                        </tr>
"@
            }
            
            $html += @"
                    </tbody>
                </table>
            </div>
        </div>
"@
        } else {
            $html += @"
        
        <!-- No Positions -->
        <div class="panel">
            <div class="panel-header">Open Positions</div>
            <div class="panel-body">
                <div class="empty-state">
                    <i class="fas fa-chart-line"></i>
                    <p>No Open Positions</p>
                </div>
            </div>
        </div>
"@
        }
        
        # Charts
        $html += @"
        
        <!-- Performance Charts -->
        <div class="panel">
            <div class="panel-header">Performance Analytics</div>
            <div class="panel-body">
                <div class="charts-container">
                    <div class="chart-panel">
                        <h3>Win/Loss Distribution</h3>
                        <canvas id="winLossChart"></canvas>
                    </div>
                    <div class="chart-panel">
                        <h3>Risk Metrics</h3>
                        <canvas id="metricsChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        // Chart.js Professional Theme
        Chart.defaults.color = '#9fa8da';
        Chart.defaults.borderColor = 'rgba(100, 181, 246, 0.1)';
        Chart.defaults.font.family = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
        
        // Win/Loss Chart
        const winLossCtx = document.getElementById('winLossChart').getContext('2d');
        new Chart(winLossCtx, {
            type: 'doughnut',
            data: {
                labels: ['Wins', 'Losses'],
                datasets: [{
                    data: [$($Metrics.wins), $($Metrics.losses)],
                    backgroundColor: [
                        'rgba(102, 187, 106, 0.8)',
                        'rgba(239, 83, 80, 0.8)'
                    ],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            color: '#9fa8da',
                            font: { size: 12, weight: '500' },
                            padding: 20,
                            usePointStyle: true,
                            pointStyle: 'circle'
                        }
                    },
                    title: {
                        display: true,
                        text: 'Win Rate: $($Metrics.win_rate)%',
                        color: '#64b5f6',
                        font: { size: 14, weight: '600' },
                        padding: { top: 10, bottom: 20 }
                    }
                }
            }
        });
        
        // Metrics Bar Chart
        const metricsCtx = document.getElementById('metricsChart').getContext('2d');
        new Chart(metricsCtx, {
            type: 'bar',
            data: {
                labels: ['Profit Factor', 'Sharpe Ratio', 'Max Drawdown'],
                datasets: [{
                    label: 'Value',
                    data: [$($Metrics.profit_factor), $($Metrics.sharpe_ratio), $($Metrics.max_drawdown)],
                    backgroundColor: [
                        'rgba(66, 165, 245, 0.7)',
                        'rgba(102, 187, 106, 0.7)',
                        'rgba(239, 83, 80, 0.7)'
                    ],
                    borderWidth: 0,
                    borderRadius: 4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            color: '#9fa8da',
                            font: { size: 11 }
                        },
                        grid: {
                            color: 'rgba(100, 181, 246, 0.08)',
                            drawBorder: false
                        }
                    },
                    x: {
                        ticks: {
                            color: '#9fa8da',
                            font: { size: 10, weight: '500' }
                        },
                        grid: { display: false }
                    }
                }
            }
        });
    </script>
</body>
</html>
"@
    
    return $html
}

try {
    Write-Host "`n=== MANUHEADFUND ELITE TERMINAL ===" -ForegroundColor Yellow
    
    # Coletar metricas (reutilizar funcao do dashboard pro)
    Write-Host "Coletando metricas..." -ForegroundColor Gray
    $metrics = Get-DashboardMetrics
    
    if (-not $metrics) {
        Write-Host "[X] Falha ao coletar metricas" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Metricas coletadas" -ForegroundColor Green
    
    # Gerar HTML Elite
    Write-Host "Gerando Elite Terminal..." -ForegroundColor Gray
    $html = Generate-EliteHTML -Metrics $metrics
    
    # Salvar
    $dashboardDir = Join-Path $PSScriptRoot "..\dashboard"
    if (-not (Test-Path $dashboardDir)) {
        New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null
    }
    
    $outputPath = Join-Path $dashboardDir "index.html"
    [System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "[OK] Elite Terminal gerado: $outputPath" -ForegroundColor Green
    
    # Enviar snapshot do dashboard para Telegram
    Write-Host "[TELEGRAM] Enviando snapshot do dashboard..." -ForegroundColor Yellow
    Telegram-SendDashboardSnapshot -Metrics $metrics
    
    # Telegram alerts
    if ($metrics.open_positions -gt 0 -and $metrics.trailing_metrics -and $metrics.trailing_metrics.trailing_activated) {
        $cacheFile = Join-Path $dashboardDir ".cache\trailing_alert.txt"
        $sendAlert = $true
        
        if (Test-Path $cacheFile) {
            $lastAlert = Get-Content $cacheFile -Raw
            if ($lastAlert -eq $metrics.trailing_metrics.current_stop.ToString()) {
                $sendAlert = $false
            }
        }
        
        if ($sendAlert) {
            Write-Host "[TELEGRAM] Enviando alerta de trailing..." -ForegroundColor Yellow
            
            $pos = if ($metrics.open_positions_detail -is [array]) {
                $metrics.open_positions_detail[0]
            } else {
                $metrics.open_positions_detail
            }
            
            Telegram-SendTrailingActivated -Position @{
                market = $pos.market
                entry_price = $metrics.trailing_metrics.entry_price
                current_price = $metrics.trailing_metrics.current_price
                profit_pct = $metrics.trailing_metrics.profit_pct
                new_stop = $metrics.trailing_metrics.current_stop
                locked_profit_pct = $metrics.trailing_metrics.locked_profit_pct
            }
            
            $cacheDir = Join-Path $dashboardDir ".cache"
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            $metrics.trailing_metrics.current_stop.ToString() | Out-File -FilePath $cacheFile -Force
        }
    }
    
    Write-Host "`n=== COMPLETO ===" -ForegroundColor Green
    
} catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

} # Fim do Invoke-SafeJob
