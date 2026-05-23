# generate_dashboard_ultimate.ps1 - Dashboard Ultimate ManuHeadFund
# Design profissional + Charts + Historico + Telegram
# Rodar: .\scripts\generate_dashboard_ultimate.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"
. ".\agents\lib_telegram.ps1"

# ============================================================================
# Get-CompleteMetrics - Coleta TODAS as metricas
# ============================================================================

function Get-CompleteMetrics {
    try {
        Write-Host "  [1/5] Posicoes abertas..." -ForegroundColor Gray
        $openPositions = CoinEx-GetPendingPositions
        
        $openCount = if ($openPositions) {
            if ($openPositions -is [array]) { $openPositions.Count } else { 1 }
        } else { 0 }
        
        Write-Host "  [2/5] Historico de trades..." -ForegroundColor Gray
        $history = CoinEx-GetFinishedPositions -Limit 100
        $positions = if ($history.success) { $history.positions } else { @() }
        
        Write-Host "  [3/5] Capital..." -ForegroundColor Gray
        $capital = CoinEx-GetFuturesCapitalUSDT
        
        Write-Host "  [4/5] Calculando metricas..." -ForegroundColor Gray
        
        # Metricas basicas
        $wins = ($positions | Where-Object { [double]$_.realized_pnl -gt 0 }).Count
        $losses = ($positions | Where-Object { [double]$_.realized_pnl -lt 0 }).Count
        $totalTrades = $positions.Count
        
        $realizedPnl = ($positions | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
        
        $winRate = if ($totalTrades -gt 0) {
            [math]::Round(($wins / $totalTrades) * 100, 1)
        } else { 0 }
        
        # PnL nao realizado
        $unrealizedPnl = 0
        if ($openCount -gt 0) {
            $posArray = if ($openPositions -is [array]) { $openPositions } else { @($openPositions) }
            $unrealizedPnl = ($posArray | ForEach-Object { [double]$_.unrealized_pnl } | Measure-Object -Sum).Sum
        }
        
        # Sharpe Ratio
        $returns = $positions | ForEach-Object {
            $pnl = [double]$_.realized_pnl
            $margin = if ($_.margin_avbl) { [double]$_.margin_avbl } else { 100 }
            if ($margin -gt 0) { ($pnl / $margin) * 100 } else { 0 }
        }
        
        $avgReturn = if ($returns.Count -gt 0) { ($returns | Measure-Object -Average).Average } else { 0 }
        $stdDev = if ($returns.Count -gt 1) {
            [math]::Sqrt((($returns | ForEach-Object { [math]::Pow($_ - $avgReturn, 2) } | Measure-Object -Sum).Sum) / ($returns.Count - 1))
        } else { 1 }
        
        $sharpeRatio = if ($stdDev -gt 0) { [math]::Round($avgReturn / $stdDev, 2) } else { 0 }
        
        # Max Drawdown
        $equity = 1000.0
        $peak = $equity
        $maxDrawdown = 0.0
        
        foreach ($pos in $positions) {
            $pnl = [double]$pos.realized_pnl
            $equity += $pnl
            if ($equity -gt $peak) { $peak = $equity }
            $drawdown = if ($peak -gt 0) { (($peak - $equity) / $peak) * 100 } else { 0 }
            if ($drawdown -gt $maxDrawdown) { $maxDrawdown = $drawdown }
        }
        
        # Profit Factor
        $grossProfit = ($positions | Where-Object { [double]$_.realized_pnl -gt 0 } | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
        $grossLoss = [math]::Abs(($positions | Where-Object { [double]$_.realized_pnl -lt 0 } | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum)
        
        $profitFactor = if ($grossLoss -gt 0) { [math]::Round($grossProfit / $grossLoss, 2) } else { 0 }
        
        Write-Host "  [5/5] Trailing stop metrics..." -ForegroundColor Gray
        
        # Trailing stop metrics
        $trailingMetrics = $null
        if ($openCount -gt 0) {
            $pos = if ($openPositions -is [array]) { $openPositions[0] } else { $openPositions }
            
            $entryPrice = [double]$pos.avg_entry_price
            $ticker = CoinEx-GetTickerFresh -market $pos.market
            $currentPrice = [double]$ticker.ticker.last
            
            $profitPct = if ($pos.side -eq "long") {
                (($currentPrice - $entryPrice) / $entryPrice) * 100
            } else {
                (($entryPrice - $currentPrice) / $entryPrice) * 100
            }
            
            $trailingActivated = $profitPct -gt 3.0
            
            $currentStop = if ($trailingActivated) {
                if ($pos.side -eq "long") {
                    $currentPrice * 0.97
                } else {
                    $currentPrice * 1.03
                }
            } else {
                if ($pos.side -eq "long") {
                    $entryPrice * 0.97
                } else {
                    $entryPrice * 1.03
                }
            }
            
            $lockedProfitPct = if ($trailingActivated) {
                if ($pos.side -eq "long") {
                    (($currentStop - $entryPrice) / $entryPrice) * 100
                } else {
                    (($entryPrice - $currentStop) / $entryPrice) * 100
                }
            } else {
                -3.0
            }
            
            $trailingMetrics = @{
                entry_price = [math]::Round($entryPrice, 2)
                current_price = [math]::Round($currentPrice, 2)
                profit_pct = [math]::Round($profitPct, 2)
                current_stop = [math]::Round($currentStop, 2)
                trailing_activated = $trailingActivated
                locked_profit_pct = [math]::Round($lockedProfitPct, 2)
            }
        }
        
        # Ultimos 10 trades para historico
        $recentTrades = $positions | Select-Object -First 10
        
        return [PSCustomObject]@{
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            open_positions = $openCount
            open_positions_detail = $openPositions
            total_trades = $totalTrades
            wins = $wins
            losses = $losses
            win_rate = $winRate
            realized_pnl = [math]::Round($realizedPnl, 2)
            unrealized_pnl = [math]::Round($unrealizedPnl, 2)
            total_pnl = [math]::Round($realizedPnl + $unrealizedPnl, 2)
            capital = [math]::Round($capital, 2)
            sharpe_ratio = $sharpeRatio
            max_drawdown = [math]::Round($maxDrawdown, 2)
            profit_factor = $profitFactor
            trailing_metrics = $trailingMetrics
            recent_trades = $recentTrades
        }
    }
    catch {
        Write-Host "Erro: $_" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# Generate-UltimateHTML - HTML completo com charts e historico
# ============================================================================

function Generate-UltimateHTML {
    param($Metrics)
    
    if (-not $Metrics) {
        return "<html><body><h1>Erro ao carregar metricas</h1></body></html>"
    }
    
    # Preparar dados para charts
    $winsData = $Metrics.wins
    $lossesData = $Metrics.losses
    
    # PnL trend (ultimos 10 trades)
    $pnlTrendLabels = ""
    $pnlTrendData = ""
    
    if ($Metrics.recent_trades -and $Metrics.recent_trades.Count -gt 0) {
        $labels = @()
        $data = @()
        
        foreach ($trade in $Metrics.recent_trades) {
            $labels += "`"$($trade.market)`""
            $data += [math]::Round([double]$trade.realized_pnl, 2)
        }
        
        $pnlTrendLabels = $labels -join ","
        $pnlTrendData = $data -join ","
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>ManuHeadFund - Trading Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: "Inter", sans-serif;
            background: linear-gradient(135deg, #1a1d29 0%, #252936 100%);
            color: #e4e7eb;
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1600px; margin: 0 auto; }
        .header {
            background: linear-gradient(135deg, #00d4aa 0%, #00a896 100%);
            padding: 30px 40px;
            border-radius: 20px;
            margin-bottom: 30px;
            box-shadow: 0 10px 40px rgba(0, 212, 170, 0.3);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { font-size: 2.5em; font-weight: 700; color: #1a1d29; letter-spacing: -1px; }
        .header .timestamp { font-size: 0.9em; color: #1a1d29; opacity: 0.8; }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: #252936;
            padding: 25px;
            border-radius: 15px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            transition: all 0.3s ease;
        }
        .metric-card:hover {
            transform: translateY(-5px);
            border-color: #00d4aa;
            box-shadow: 0 10px 30px rgba(0, 212, 170, 0.2);
        }
        .metric-card .icon { font-size: 2em; margin-bottom: 15px; opacity: 0.8; }
        .metric-card .label {
            font-size: 0.85em;
            color: #9ca3af;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 600;
            margin-bottom: 10px;
        }
        .metric-card .value { font-size: 2.5em; font-weight: 700; color: #e4e7eb; line-height: 1; }
        .metric-card.success .value { color: #00c853; }
        .metric-card.danger .value { color: #ff1744; }
        .metric-card.warning .value { color: #ffc107; }
        .metric-card.accent .value { color: #00d4aa; }
        .section {
            background: #252936;
            padding: 30px;
            border-radius: 15px;
            border: 1px solid rgba(255, 255, 255, 0.05);
            margin-bottom: 30px;
        }
        .section h2 {
            font-size: 1.5em;
            font-weight: 600;
            color: #00d4aa;
            margin-bottom: 25px;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 15px; text-align: left; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }
        th {
            background: rgba(0, 212, 170, 0.1);
            color: #00d4aa;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.85em;
            letter-spacing: 1px;
        }
        tr:hover { background: rgba(255, 255, 255, 0.02); }
        .badge {
            display: inline-block;
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
            text-transform: uppercase;
        }
        .badge.long { background: rgba(0, 200, 83, 0.2); color: #00c853; }
        .badge.short { background: rgba(255, 23, 68, 0.2); color: #ff1744; }
        .positive { color: #00c853; font-weight: 600; }
        .negative { color: #ff1744; font-weight: 600; }
        .trailing-indicator {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            padding: 8px 16px;
            background: rgba(0, 212, 170, 0.1);
            border: 1px solid #00d4aa;
            border-radius: 10px;
            font-size: 0.9em;
            font-weight: 600;
            color: #00d4aa;
        }
        .pulse { animation: pulse 2s ease-in-out infinite; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .charts-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 30px;
            margin-top: 20px;
        }
        .chart-container { background: rgba(0, 0, 0, 0.2); padding: 20px; border-radius: 10px; }
        .chart-container h3 { text-align: center; margin-bottom: 15px; color: #9ca3af; font-size: 1.1em; }
        @media (max-width: 768px) {
            .metrics-grid, .charts-grid { grid-template-columns: 1fr; }
            .header { flex-direction: column; text-align: center; gap: 15px; }
            .header h1 { font-size: 1.8em; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div>
                <h1><i class="fas fa-chart-line"></i> ManuHeadFund</h1>
                <div>Professional Trading Dashboard</div>
            </div>
            <div class="timestamp"><i class="far fa-clock"></i> $($Metrics.timestamp)</div>
        </div>
"@
    
    return $html
}
