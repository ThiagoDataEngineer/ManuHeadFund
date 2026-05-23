# generate_position_dashboard.ps1 - Gera dashboard HTML de métricas
# Rodar: .\scripts\generate_position_dashboard.ps1
# Output: .\dashboard\position_metrics.html

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"

# ============================================================================
# Get-PositionMetrics - Coleta métricas de posições
# ============================================================================

function Get-PositionMetrics {
    try {
        # 1. Posições abertas
        $openPositions = CoinEx-GetPendingPositions
        $openCount = if ($openPositions) { $openPositions.Count } else { 0 }
        
        # 2. Histórico de posições (últimas 100)
        $history = CoinEx-GetFinishedPositions -Limit 100
        $positions = if ($history.success) { $history.positions } else { @() }
        
        # 3. Calcular métricas
        $wins = 0
        $losses = 0
        $totalPnl = 0
        $totalTrades = $positions.Count
        
        $bestTrade = $null
        $worstTrade = $null
        $maxPnl = [double]::MinValue
        $minPnl = [double]::MaxValue
        
        foreach ($pos in $positions) {
            $pnl = [double]$pos.pnl
            $totalPnl += $pnl
            
            if ($pnl -gt 0) { $wins++ }
            else { $losses++ }
            
            if ($pnl -gt $maxPnl) {
                $maxPnl = $pnl
                $bestTrade = $pos
            }
            
            if ($pnl -lt $minPnl) {
                $minPnl = $pnl
                $worstTrade = $pos
            }
        }
        
        $winRate = if ($totalTrades -gt 0) {
            [math]::Round(($wins / $totalTrades) * 100, 1)
        } else { 0 }
        
        $avgWin = if ($wins -gt 0) {
            [math]::Round(($positions | Where-Object { [double]$_.pnl -gt 0 } | Measure-Object -Property { [double]$_.pnl } -Average).Average, 2)
        } else { 0 }
        
        $avgLoss = if ($losses -gt 0) {
            [math]::Round(($positions | Where-Object { [double]$_.pnl -lt 0 } | Measure-Object -Property { [double]$_.pnl } -Average).Average, 2)
        } else { 0 }
        
        $profitFactor = if ($avgLoss -ne 0) {
            [math]::Round([math]::Abs($avgWin / $avgLoss), 2)
        } else { 0 }
        
        # 4. Métricas por market
        $marketStats = @{}
        foreach ($pos in $positions) {
            $market = $pos.market
            if (-not $marketStats.ContainsKey($market)) {
                $marketStats[$market] = @{
                    trades = 0
                    wins = 0
                    pnl = 0
                }
            }
            
            $marketStats[$market].trades++
            if ([double]$pos.pnl -gt 0) { $marketStats[$market].wins++ }
            $marketStats[$market].pnl += [double]$pos.pnl
        }
        
        # 5. Top 5 markets
        $top5Markets = $marketStats.GetEnumerator() |
            Sort-Object { $_.Value.pnl } -Descending |
            Select-Object -First 5
        
        return [PSCustomObject]@{
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            open_positions = $openCount
            total_trades = $totalTrades
            wins = $wins
            losses = $losses
            win_rate = $winRate
            total_pnl = [math]::Round($totalPnl, 2)
            avg_win = $avgWin
            avg_loss = $avgLoss
            profit_factor = $profitFactor
            best_trade = $bestTrade
            worst_trade = $worstTrade
            top5_markets = $top5Markets
            open_positions_detail = $openPositions
        }
    }
    catch {
        Write-Host "Erro ao coletar métricas: $_" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# Generate-HTML - Gera HTML do dashboard
# ============================================================================

function Generate-HTML {
    param($Metrics)
    
    if (-not $Metrics) {
        return "<html><body><h1>Erro ao carregar métricas</h1></body></html>"
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>Position Management Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 30px;
            text-align: center;
        }
        
        .header h1 {
            color: #667eea;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header .timestamp {
            color: #666;
            font-size: 0.9em;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: white;
            padding: 25px;
            border-radius: 15px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 10px 25px rgba(0,0,0,0.15);
        }
        
        .metric-card .label {
            font-size: 0.9em;
            color: #666;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        
        .metric-card .value {
            font-size: 2.5em;
            font-weight: bold;
            color: #667eea;
        }
        
        .metric-card.positive .value {
            color: #10b981;
        }
        
        .metric-card.negative .value {
            color: #ef4444;
        }
        
        .section {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        .section h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.8em;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th, td {
            padding: 15px;
            text-align: left;
            border-bottom: 1px solid #e5e7eb;
        }
        
        th {
            background: #f9fafb;
            color: #667eea;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85em;
            letter-spacing: 1px;
        }
        
        tr:hover {
            background: #f9fafb;
        }
        
        .positive {
            color: #10b981;
            font-weight: bold;
        }
        
        .negative {
            color: #ef4444;
            font-weight: bold;
        }
        
        .badge {
            display: inline-block;
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        
        .badge.long {
            background: #d1fae5;
            color: #065f46;
        }
        
        .badge.short {
            background: #fee2e2;
            color: #991b1b;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 30px;
            font-size: 0.9em;
        }
        
        @media (max-width: 768px) {
            .metrics-grid {
                grid-template-columns: 1fr;
            }
            
            .header h1 {
                font-size: 1.8em;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Position Management Dashboard</h1>
            <div class="timestamp">Última atualização: $($Metrics.timestamp)</div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="label">Posições Abertas</div>
                <div class="value">$($Metrics.open_positions)</div>
            </div>
            
            <div class="metric-card">
                <div class="label">Total de Trades</div>
                <div class="value">$($Metrics.total_trades)</div>
            </div>
            
            <div class="metric-card positive">
                <div class="label">Win Rate</div>
                <div class="value">$($Metrics.win_rate)%</div>
            </div>
            
            <div class="metric-card $(if($Metrics.total_pnl -gt 0){'positive'}else{'negative'})">
                <div class="label">PnL Total</div>
                <div class="value">$$($Metrics.total_pnl)</div>
            </div>
            
            <div class="metric-card positive">
                <div class="label">Wins</div>
                <div class="value">$($Metrics.wins)</div>
            </div>
            
            <div class="metric-card negative">
                <div class="label">Losses</div>
                <div class="value">$($Metrics.losses)</div>
            </div>
            
            <div class="metric-card positive">
                <div class="label">Avg Win</div>
                <div class="value">$$($Metrics.avg_win)</div>
            </div>
            
            <div class="metric-card negative">
                <div class="label">Avg Loss</div>
                <div class="value">$$($Metrics.avg_loss)</div>
            </div>
            
            <div class="metric-card">
                <div class="label">Profit Factor</div>
                <div class="value">$($Metrics.profit_factor)x</div>
            </div>
        </div>
        
        <div class="section">
            <h2>🏆 Top 5 Markets</h2>
            <table>
                <thead>
                    <tr>
                        <th>Market</th>
                        <th>Trades</th>
                        <th>Wins</th>
                        <th>Win Rate</th>
                        <th>PnL</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    foreach ($market in $Metrics.top5_markets) {
        $winRate = if ($market.Value.trades -gt 0) {
            [math]::Round(($market.Value.wins / $market.Value.trades) * 100, 1)
        } else { 0 }
        
        $pnlClass = if ($market.Value.pnl -gt 0) { "positive" } else { "negative" }
        
        $html += @"
                    <tr>
                        <td><strong>$($market.Key)</strong></td>
                        <td>$($market.Value.trades)</td>
                        <td>$($market.Value.wins)</td>
                        <td>$winRate%</td>
                        <td class="$pnlClass">$$([math]::Round($market.Value.pnl, 2))</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>📈 Posições Abertas</h2>
"@
    
    if ($Metrics.open_positions -gt 0) {
        $html += @"
            <table>
                <thead>
                    <tr>
                        <th>Market</th>
                        <th>Side</th>
                        <th>Entry</th>
                        <th>Current</th>
                        <th>PnL%</th>
                        <th>Leverage</th>
                        <th>Liquidation</th>
                    </tr>
                </thead>
                <tbody>
"@
        
        foreach ($pos in $Metrics.open_positions_detail) {
            $entryPrice = [double]$pos.open_price
            $currentPrice = [double]$pos.latest_price
            $liqPrice = [double]$pos.liquidation_price
            
            $pnlPct = if ($pos.side -eq "long") {
                (($currentPrice - $entryPrice) / $entryPrice) * 100
            } else {
                (($entryPrice - $currentPrice) / $entryPrice) * 100
            }
            
            $pnlClass = if ($pnlPct -gt 0) { "positive" } else { "negative" }
            $sideClass = if ($pos.side -eq "long") { "long" } else { "short" }
            
            $html += @"
                    <tr>
                        <td><strong>$($pos.market)</strong></td>
                        <td><span class="badge $sideClass">$($pos.side.ToUpper())</span></td>
                        <td>$$entryPrice</td>
                        <td>$$currentPrice</td>
                        <td class="$pnlClass">$([math]::Round($pnlPct, 2))%</td>
                        <td>$($pos.leverage)x</td>
                        <td>$$liqPrice</td>
                    </tr>
"@
        }
        
        $html += @"
                </tbody>
            </table>
"@
    } else {
        $html += "<p style='text-align: center; color: #666; padding: 40px;'>Nenhuma posição aberta no momento</p>"
    }
    
    $html += @"
        </div>
        
        <div class="section">
            <h2>🎯 Melhores e Piores Trades</h2>
            <table>
                <thead>
                    <tr>
                        <th>Tipo</th>
                        <th>Market</th>
                        <th>Side</th>
                        <th>Entry</th>
                        <th>Exit</th>
                        <th>PnL</th>
                    </tr>
                </thead>
                <tbody>
"@
    
    if ($Metrics.best_trade) {
        $bt = $Metrics.best_trade
        $html += @"
                    <tr>
                        <td><strong style="color: #10b981;">🏆 MELHOR</strong></td>
                        <td><strong>$($bt.market)</strong></td>
                        <td><span class="badge $(if($bt.side -eq 'long'){'long'}else{'short'})">$($bt.side.ToUpper())</span></td>
                        <td>$$($bt.entry_price)</td>
                        <td>$$($bt.exit_price)</td>
                        <td class="positive">+$$($bt.pnl)</td>
                    </tr>
"@
    }
    
    if ($Metrics.worst_trade) {
        $wt = $Metrics.worst_trade
        $html += @"
                    <tr>
                        <td><strong style="color: #ef4444;">💔 PIOR</strong></td>
                        <td><strong>$($wt.market)</strong></td>
                        <td><span class="badge $(if($wt.side -eq 'long'){'long'}else{'short'})">$($wt.side.ToUpper())</span></td>
                        <td>$$($wt.entry_price)</td>
                        <td>$$($wt.exit_price)</td>
                        <td class="negative">$$($wt.pnl)</td>
                    </tr>
"@
    }
    
    $html += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>🤖 Position Management Dashboard | Auto-refresh a cada 5 minutos</p>
            <p>Criado com TDD rigoroso | 2026-05-23</p>
        </div>
    </div>
</body>
</html>
"@
    
    return $html
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n=== GERANDO DASHBOARD ===" -ForegroundColor Cyan
    
    # 1. Coletar métricas
    Write-Host "Coletando métricas..." -ForegroundColor Yellow
    $metrics = Get-PositionMetrics
    
    if (-not $metrics) {
        Write-Host "✗ Falha ao coletar métricas" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✓ Métricas coletadas" -ForegroundColor Green
    Write-Host "  Posições abertas: $($metrics.open_positions)" -ForegroundColor Gray
    Write-Host "  Total trades: $($metrics.total_trades)" -ForegroundColor Gray
    Write-Host "  Win rate: $($metrics.win_rate)%" -ForegroundColor Gray
    Write-Host "  PnL total: $$($metrics.total_pnl)" -ForegroundColor Gray
    
    # 2. Gerar HTML
    Write-Host "`nGerando HTML..." -ForegroundColor Yellow
    $html = Generate-HTML -Metrics $metrics
    
    # 3. Salvar arquivo
    $dashboardDir = Join-Path $PSScriptRoot "..\dashboard"
    if (-not (Test-Path $dashboardDir)) {
        New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null
    }
    
    $outputPath = Join-Path $dashboardDir "position_metrics.html"
    $html | Out-File -FilePath $outputPath -Encoding UTF8 -Force
    
    Write-Host "✓ Dashboard gerado: $outputPath" -ForegroundColor Green
    
    # 4. Abrir no navegador (opcional)
    if ($args -contains "-Open") {
        Start-Process $outputPath
        Write-Host "✓ Dashboard aberto no navegador" -ForegroundColor Green
    }
    
    Write-Host "`n=== COMPLETO ===" -ForegroundColor Cyan
    
} catch {
    Write-Host "`n✗ ERRO: $_" -ForegroundColor Red
    exit 1
}
