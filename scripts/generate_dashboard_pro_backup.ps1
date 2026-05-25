# generate_dashboard_pro.ps1 - Dashboard Profissional ManuHeadFund
# Design moderno, metricas avancadas, Telegram integration
# Rodar: .\scripts\generate_dashboard_pro.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"
. ".\agents\lib_telegram.ps1"

# ============================================================================
# Calculate-AdvancedMetrics - Metricas avancadas
# ============================================================================

function Calculate-AdvancedMetrics {
    param($Positions)
    
    if ($Positions.Count -eq 0) {
        return @{
            sharpe_ratio = 0
            max_drawdown = 0
            profit_factor = 0
            avg_win_loss_ratio = 0
        }
    }
    
    # Calcular retornos
    $returns = $Positions | ForEach-Object {
        $pnl = [double]$_.realized_pnl
        $margin = [double]$_.margin_avbl
        if ($margin -gt 0) { ($pnl / $margin) * 100 } else { 0 }
    }
    
    # Sharpe Ratio (simplificado, sem risk-free rate)
    $avgReturn = ($returns | Measure-Object -Average).Average
    $stdDev = if ($returns.Count -gt 1) {
        [math]::Sqrt((($returns | ForEach-Object { [math]::Pow($_ - $avgReturn, 2) } | Measure-Object -Sum).Sum) / ($returns.Count - 1))
    } else { 1 }
    
    $sharpeRatio = if ($stdDev -gt 0) {
        [math]::Round($avgReturn / $stdDev, 2)
    } else { 0 }
    
    # Max Drawdown
    $equity = 1000.0
    $peak = $equity
    $maxDrawdown = 0.0
    
    foreach ($pos in $Positions) {
        $pnl = [double]$pos.realized_pnl
        $equity += $pnl
        
        if ($equity -gt $peak) {
            $peak = $equity
        }
        
        $drawdown = if ($peak -gt 0) { (($peak - $equity) / $peak) * 100 } else { 0 }
        if ($drawdown -gt $maxDrawdown) {
            $maxDrawdown = $drawdown
        }
    }
    
    # Profit Factor
    $grossProfit = ($Positions | Where-Object { [double]$_.realized_pnl -gt 0 } | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
    $grossLoss = [math]::Abs(($Positions | Where-Object { [double]$_.realized_pnl -lt 0 } | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum)
    
    $profitFactor = if ($grossLoss -gt 0) {
        [math]::Round($grossProfit / $grossLoss, 2)
    } else { 0 }
    
    # Avg Win/Loss Ratio
    $wins = $Positions | Where-Object { [double]$_.realized_pnl -gt 0 }
    $losses = $Positions | Where-Object { [double]$_.realized_pnl -lt 0 }
    
    $avgWin = if ($wins.Count -gt 0) {
        ($wins | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Average).Average
    } else { 0 }
    
    $avgLoss = if ($losses.Count -gt 0) {
        [math]::Abs(($losses | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Average).Average)
    } else { 1 }
    
    $avgWinLossRatio = if ($avgLoss -gt 0) {
        [math]::Round($avgWin / $avgLoss, 2)
    } else { 0 }
    
    return @{
        sharpe_ratio = $sharpeRatio
        max_drawdown = [math]::Round($maxDrawdown, 2)
        profit_factor = $profitFactor
        avg_win_loss_ratio = $avgWinLossRatio
    }
}

# ============================================================================
# Calculate-TrailingStopMetrics - Metricas de trailing stop
# ============================================================================

function Calculate-TrailingStopMetrics {
    param($Position)
    
    if (-not $Position) {
        return $null
    }
    
    $entryPrice = [double]$Position.avg_entry_price
    $ticker = CoinEx-GetTickerFresh -market $Position.market
    $currentPrice = [double]$ticker.ticker.last
    
    $profitPct = if ($Position.side -eq "long") {
        (($currentPrice - $entryPrice) / $entryPrice) * 100
    } else {
        (($entryPrice - $currentPrice) / $entryPrice) * 100
    }
    
    $initialStopPct = 3.0  # -3%
    $trailingPct = 3.0     # 3% trailing
    
    $initialStop = if ($Position.side -eq "long") {
        $entryPrice * (1 - ($initialStopPct / 100))
    } else {
        $entryPrice * (1 + ($initialStopPct / 100))
    }
    
    $trailingActivated = $profitPct -gt $trailingPct
    
    $currentStop = if ($trailingActivated) {
        if ($Position.side -eq "long") {
            $currentPrice * (1 - ($trailingPct / 100))
        } else {
            $currentPrice * (1 + ($trailingPct / 100))
        }
    } else {
        $initialStop
    }
    
    $lockedProfitPct = if ($trailingActivated) {
        if ($Position.side -eq "long") {
            (($currentStop - $entryPrice) / $entryPrice) * 100
        } else {
            (($entryPrice - $currentStop) / $entryPrice) * 100
        }
    } else {
        -$initialStopPct
    }
    
    return @{
        entry_price = [math]::Round($entryPrice, 2)
        current_price = [math]::Round($currentPrice, 2)
        profit_pct = [math]::Round($profitPct, 2)
        initial_stop = [math]::Round($initialStop, 2)
        current_stop = [math]::Round($currentStop, 2)
        trailing_activated = $trailingActivated
        locked_profit_pct = [math]::Round($lockedProfitPct, 2)
        max_profit_pct = [math]::Round($profitPct, 2)
    }
}

# ============================================================================
# Get-DashboardMetrics - Coleta todas as metricas
# ============================================================================

function Get-DashboardMetrics {
    try {
        # 1. Posicoes abertas
        $openPositions = CoinEx-GetPendingPositions
        
        $openCount = if ($openPositions) {
            if ($openPositions -is [array]) {
                $openPositions.Count
            } else {
                1
            }
        } else {
            0
        }
        
        # 2. Historico
        $history = CoinEx-GetFinishedPositions -Limit 100
        $positions = if ($history.success) { $history.positions } else { @() }
        
        # 3. Metricas basicas
        $wins = ($positions | Where-Object { [double]$_.realized_pnl -gt 0 }).Count
        $losses = ($positions | Where-Object { [double]$_.realized_pnl -lt 0 }).Count
        $totalTrades = $positions.Count
        
        $totalPnl = ($positions | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
        
        $winRate = if ($totalTrades -gt 0) {
            [math]::Round(($wins / $totalTrades) * 100, 1)
        } else { 0 }
        
        # 4. Metricas avancadas
        $advanced = Calculate-AdvancedMetrics -Positions $positions
        
        # 5. Trailing stop metrics (se houver posicao aberta)
        $trailingMetrics = $null
        if ($openCount -gt 0) {
            $pos = if ($openPositions -is [array]) { $openPositions[0] } else { $openPositions }
            $trailingMetrics = Calculate-TrailingStopMetrics -Position $pos
        }
        
        # 6. Capital
        $capital = CoinEx-GetFuturesCapitalUSDT
        
        # 7. PnL nao realizado
        $unrealizedPnl = 0
        if ($openCount -gt 0) {
            $posArray = if ($openPositions -is [array]) { $openPositions } else { @($openPositions) }
            $unrealizedPnl = ($posArray | ForEach-Object { [double]$_.unrealized_pnl } | Measure-Object -Sum).Sum
        }
        
        return [PSCustomObject]@{
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            open_positions = $openCount
            open_positions_detail = $openPositions
            total_trades = $totalTrades
            wins = $wins
            losses = $losses
            win_rate = $winRate
            realized_pnl = [math]::Round($totalPnl, 2)
            unrealized_pnl = [math]::Round($unrealizedPnl, 2)
            total_pnl = [math]::Round($totalPnl + $unrealizedPnl, 2)
            capital = [math]::Round($capital, 2)
            sharpe_ratio = $advanced.sharpe_ratio
            max_drawdown = $advanced.max_drawdown
            profit_factor = $advanced.profit_factor
            avg_win_loss_ratio = $advanced.avg_win_loss_ratio
            trailing_metrics = $trailingMetrics
        }
    }
    catch {
        Write-Host "Erro ao coletar metricas: $_" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# Generate-ProfessionalHTML - Gera HTML com design profissional
# ============================================================================

function Generate-ProfessionalHTML {
    param($Metrics)
    
    if (-not $Metrics) {
        return "<html><body><h1>Erro ao carregar metricas</h1></body></html>"
    }
    
    $sb = [System.Text.StringBuilder]::new()
    
    # HTML Header
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="pt-BR">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('    <meta charset="UTF-8">')
    [void]$sb.AppendLine('    <meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine('    <meta http-equiv="refresh" content="300">')
    [void]$sb.AppendLine('    <title>ManuHeadFund - Trading Dashboard</title>')
    [void]$sb.AppendLine('    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">')
    [void]$sb.AppendLine('    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">')
    [void]$sb.AppendLine('    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>')
    
    # CSS Styles
    [void]$sb.AppendLine('    <style>')
    [void]$sb.AppendLine('        * { margin: 0; padding: 0; box-sizing: border-box; }')
    [void]$sb.AppendLine('        body {')
    [void]$sb.AppendLine('            font-family: "Inter", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;')
    [void]$sb.AppendLine('            background: linear-gradient(135deg, #1a1d29 0%, #252936 100%);')
    [void]$sb.AppendLine('            color: #e4e7eb;')
    [void]$sb.AppendLine('            padding: 20px;')
    [void]$sb.AppendLine('            min-height: 100vh;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .container { max-width: 1600px; margin: 0 auto; }')
    [void]$sb.AppendLine('        .header {')
    [void]$sb.AppendLine('            background: linear-gradient(135deg, #00d4aa 0%, #00a896 100%);')
    [void]$sb.AppendLine('            padding: 30px 40px;')
    [void]$sb.AppendLine('            border-radius: 20px;')
    [void]$sb.AppendLine('            margin-bottom: 30px;')
    [void]$sb.AppendLine('            box-shadow: 0 10px 40px rgba(0, 212, 170, 0.3);')
    [void]$sb.AppendLine('            display: flex;')
    [void]$sb.AppendLine('            justify-content: space-between;')
    [void]$sb.AppendLine('            align-items: center;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .header h1 {')
    [void]$sb.AppendLine('            font-size: 2.5em;')
    [void]$sb.AppendLine('            font-weight: 700;')
    [void]$sb.AppendLine('            color: #1a1d29;')
    [void]$sb.AppendLine('            letter-spacing: -1px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .header .timestamp {')
    [void]$sb.AppendLine('            font-size: 0.9em;')
    [void]$sb.AppendLine('            color: #1a1d29;')
    [void]$sb.AppendLine('            opacity: 0.8;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .metrics-grid {')
    [void]$sb.AppendLine('            display: grid;')
    [void]$sb.AppendLine('            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));')
    [void]$sb.AppendLine('            gap: 20px;')
    [void]$sb.AppendLine('            margin-bottom: 30px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .metric-card {')
    [void]$sb.AppendLine('            background: #252936;')
    [void]$sb.AppendLine('            padding: 25px;')
    [void]$sb.AppendLine('            border-radius: 15px;')
    [void]$sb.AppendLine('            border: 1px solid rgba(255, 255, 255, 0.05);')
    [void]$sb.AppendLine('            transition: all 0.3s ease;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .metric-card:hover {')
    [void]$sb.AppendLine('            transform: translateY(-5px);')
    [void]$sb.AppendLine('            border-color: #00d4aa;')
    [void]$sb.AppendLine('            box-shadow: 0 10px 30px rgba(0, 212, 170, 0.2);')
    [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        .metric-card .icon {')
        [void]$sb.AppendLine('            font-size: 2em;')
        [void]$sb.AppendLine('            margin-bottom: 15px;')
        [void]$sb.AppendLine('            opacity: 0.8;')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        .metric-card .label {')
        [void]$sb.AppendLine('            font-size: 0.85em;')
        [void]$sb.AppendLine('            color: #9ca3af;')
        [void]$sb.AppendLine('            text-transform: uppercase;')
        [void]$sb.AppendLine('            letter-spacing: 1px;')
        [void]$sb.AppendLine('            font-weight: 600;')
        [void]$sb.AppendLine('            margin-bottom: 10px;')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        .metric-card .value {')
        [void]$sb.AppendLine('            font-size: 2.5em;')
        [void]$sb.AppendLine('            font-weight: 700;')
        [void]$sb.AppendLine('            color: #e4e7eb;')
        [void]$sb.AppendLine('            line-height: 1;')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        .metric-card.success .value { color: #00c853; }')
        [void]$sb.AppendLine('        .metric-card.danger .value { color: #ff1744; }')
        [void]$sb.AppendLine('        .metric-card.warning .value { color: #ffc107; }')
        [void]$sb.AppendLine('        .metric-card.accent .value { color: #00d4aa; }')
        [void]$sb.AppendLine('        .section {')
        [void]$sb.AppendLine('            background: #252936;')
        [void]$sb.AppendLine('            padding: 30px;')
        [void]$sb.AppendLine('            border-radius: 15px;')
        [void]$sb.AppendLine('            border: 1px solid rgba(255, 255, 255, 0.05);')
        [void]$sb.AppendLine('            margin-bottom: 30px;')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        .section h2 {')
        [void]$sb.AppendLine('            font-size: 1.5em;')
        [void]$sb.AppendLine('            font-weight: 600;')
        [void]$sb.AppendLine('            color: #00d4aa;')
        [void]$sb.AppendLine('            margin-bottom: 25px;')
        [void]$sb.AppendLine('            display: flex;')
        [void]$sb.AppendLine('            align-items: center;')
        [void]$sb.AppendLine('            gap: 10px;')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        table { width: 100%; border-collapse: collapse; }')
        [void]$sb.AppendLine('        th, td { padding: 15px; text-align: left; border-bottom: 1px solid rgba(255, 255, 255, 0.05); }')
        [void]$sb.AppendLine('        th { background: rgba(0, 212, 170, 0.1); color: #00d4aa; font-weight: 600; text-transform: uppercase; font-size: 0.85em; letter-spacing: 1px; }')
        [void]$sb.AppendLine('        tr:hover { background: rgba(255, 255, 255, 0.02); }')
        [void]$sb.AppendLine('        .badge { display: inline-block; padding: 6px 14px; border-radius: 20px; font-size: 0.85em; font-weight: 600; text-transform: uppercase; }')
        [void]$sb.AppendLine('        .badge.long { background: rgba(0, 200, 83, 0.2); color: #00c853; }')
        [void]$sb.AppendLine('        .badge.short { background: rgba(255, 23, 68, 0.2); color: #ff1744; }')
        [void]$sb.AppendLine('        .positive { color: #00c853; font-weight: 600; }')
        [void]$sb.AppendLine('        .negative { color: #ff1744; font-weight: 600; }')
        [void]$sb.AppendLine('        .trailing-indicator { display: inline-flex; align-items: center; gap: 8px; padding: 8px 16px; background: rgba(0, 212, 170, 0.1); border: 1px solid #00d4aa; border-radius: 10px; font-size: 0.9em; font-weight: 600; color: #00d4aa; }')
        [void]$sb.AppendLine('        .pulse { animation: pulse 2s ease-in-out infinite; }')
        [void]$sb.AppendLine('        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }')
        [void]$sb.AppendLine('        @media (max-width: 768px) { .metrics-grid { grid-template-columns: 1fr; } .header { flex-direction: column; text-align: center; gap: 15px; } .header h1 { font-size: 1.8em; } }')
        [void]$sb.AppendLine('    </style>')

    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('    <div class="container">')
    
    # Header
    [void]$sb.AppendLine('        <div class="header">')
    [void]$sb.AppendLine('            <div>')
    [void]$sb.AppendLine('                <h1><i class="fas fa-chart-line"></i> ManuHeadFund</h1>')
    [void]$sb.AppendLine('                <div>Professional Trading Dashboard</div>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine("            <div class='timestamp'><i class='far fa-clock'></i> $($Metrics.timestamp)</div>")
    [void]$sb.AppendLine('        </div>')
    
    # Metrics Grid
    [void]$sb.AppendLine('        <div class="metrics-grid">')
    
    # Open Positions
    $posClass = if ($Metrics.open_positions -gt 0) { "accent" } else { "" }
    [void]$sb.AppendLine("            <div class='metric-card $posClass'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-briefcase"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Open Positions</div>')
    [void]$sb.AppendLine("                <div class='value'>$($Metrics.open_positions)</div>")
    [void]$sb.AppendLine('            </div>')
    
    # Total PnL
    $pnlClass = if ($Metrics.total_pnl -gt 0) { "success" } elseif ($Metrics.total_pnl -lt 0) { "danger" } else { "" }
    $pnlSign = if ($Metrics.total_pnl -gt 0) { "+" } else { "" }
    [void]$sb.AppendLine("            <div class='metric-card $pnlClass'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-dollar-sign"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Total PnL</div>')
    [void]$sb.AppendLine("                <div class='value'>$pnlSign`$$($Metrics.total_pnl)</div>")
    [void]$sb.AppendLine('            </div>')
    
    # Win Rate
    $wrClass = if ($Metrics.win_rate -ge 50) { "success" } elseif ($Metrics.win_rate -ge 40) { "warning" } else { "danger" }
    [void]$sb.AppendLine("            <div class='metric-card $wrClass'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-percentage"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Win Rate</div>')
    [void]$sb.AppendLine("                <div class='value'>$($Metrics.win_rate)%</div>")
    [void]$sb.AppendLine('            </div>')
    
    # Capital
    [void]$sb.AppendLine("            <div class='metric-card'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-wallet"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Capital</div>')
    [void]$sb.AppendLine("                <div class='value'>`$$($Metrics.capital)</div>")
    [void]$sb.AppendLine('            </div>')
    
    # Sharpe Ratio
    $srClass = if ($Metrics.sharpe_ratio -gt 1) { "success" } elseif ($Metrics.sharpe_ratio -gt 0) { "warning" } else { "danger" }
    [void]$sb.AppendLine("            <div class='metric-card $srClass'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-chart-area"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Sharpe Ratio</div>')
    [void]$sb.AppendLine("                <div class='value'>$($Metrics.sharpe_ratio)</div>")
    [void]$sb.AppendLine('            </div>')
    
    # Max Drawdown
    $ddClass = if ($Metrics.max_drawdown -lt 10) { "success" } elseif ($Metrics.max_drawdown -lt 20) { "warning" } else { "danger" }
    [void]$sb.AppendLine("            <div class='metric-card $ddClass'>")
    [void]$sb.AppendLine('                <div class="icon"><i class="fas fa-arrow-down"></i></div>')
    [void]$sb.AppendLine('                <div class="label">Max Drawdown</div>')
    [void]$sb.AppendLine("                <div class='value'>$($Metrics.max_drawdown)%</div>")
    [void]$sb.AppendLine('            </div>')
    
    [void]$sb.AppendLine('        </div>')
    
    return $sb.ToString()
}

# ============================================================================
# Generate-OpenPositionsSection - Secao de posicoes abertas
# ============================================================================

function Generate-OpenPositionsSection {
    param($Metrics)
    
    $sb = [System.Text.StringBuilder]::new()
    
    [void]$sb.AppendLine('        <div class="section">')
    [void]$sb.AppendLine('            <h2><i class="fas fa-chart-line"></i> Open Positions</h2>')
    
    if ($Metrics.open_positions -gt 0) {
        [void]$sb.AppendLine('            <table>')
        [void]$sb.AppendLine('                <thead>')
        [void]$sb.AppendLine('                    <tr>')
        [void]$sb.AppendLine('                        <th>Market</th>')
        [void]$sb.AppendLine('                        <th>Side</th>')
        [void]$sb.AppendLine('                        <th>Entry</th>')
        [void]$sb.AppendLine('                        <th>Current</th>')
        [void]$sb.AppendLine('                        <th>PnL%</th>')
        [void]$sb.AppendLine('                        <th>Unrealized</th>')
        [void]$sb.AppendLine('                        <th>Leverage</th>')
        [void]$sb.AppendLine('                        <th>Trailing</th>')
        [void]$sb.AppendLine('                    </tr>')
        [void]$sb.AppendLine('                </thead>')
        [void]$sb.AppendLine('                <tbody>')
        
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
            
            $pnlClass = if ($pnlPct -gt 0) { "positive" } else { "negative" }
            $sideClass = if ($pos.side -eq "long") { "long" } else { "short" }
            
            # Trailing stop indicator
            $trailing = Calculate-TrailingStopMetrics -Position $pos
            $trailingHtml = if ($trailing.trailing_activated) {
                "<span class='trailing-indicator pulse'><i class='fas fa-rocket'></i> TRAILING +$($trailing.locked_profit_pct)%</span>"
            } else {
                "<span style='color: #9ca3af;'>Waiting +3%</span>"
            }
            
            [void]$sb.AppendLine('                    <tr>')
            [void]$sb.AppendLine("                        <td><strong>$market</strong></td>")
            [void]$sb.AppendLine("                        <td><span class='badge $sideClass'>$side</span></td>")
            [void]$sb.AppendLine("                        <td>`$$entryPrice</td>")
            [void]$sb.AppendLine("                        <td>`$$currentPrice</td>")
            [void]$sb.AppendLine("                        <td class='$pnlClass'>$pnlPct%</td>")
            [void]$sb.AppendLine("                        <td class='$pnlClass'>`$$unrealizedPnl</td>")
            [void]$sb.AppendLine("                        <td>$leverage`x</td>")
            [void]$sb.AppendLine("                        <td>$trailingHtml</td>")
            [void]$sb.AppendLine('                    </tr>')
        }
        
        [void]$sb.AppendLine('                </tbody>')
        [void]$sb.AppendLine('            </table>')
    } else {
        [void]$sb.AppendLine('            <p style="text-align: center; color: #9ca3af; padding: 40px;">')
        [void]$sb.AppendLine('                <i class="fas fa-inbox" style="font-size: 3em; margin-bottom: 20px; display: block;"></i>')
        [void]$sb.AppendLine('                No open positions')
        [void]$sb.AppendLine('            </p>')
    }
    
    [void]$sb.AppendLine('        </div>')
    
    return $sb.ToString()
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n=== MANUHEADFUND DASHBOARD ===" -ForegroundColor Cyan
    
    # 1. Coletar metricas
    Write-Host "Coletando metricas..." -ForegroundColor Yellow
    $metrics = Get-DashboardMetrics
    
    if (-not $metrics) {
        Write-Host "[X] Falha ao coletar metricas" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Metricas coletadas" -ForegroundColor Green
    Write-Host "  Posicoes abertas: $($metrics.open_positions)" -ForegroundColor Gray
    Write-Host "  Total PnL: `$$($metrics.total_pnl)" -ForegroundColor Gray
    Write-Host "  Win rate: $($metrics.win_rate)%" -ForegroundColor Gray
    Write-Host "  Sharpe ratio: $($metrics.sharpe_ratio)" -ForegroundColor Gray
    
    # 2. Gerar HTML
    Write-Host "`nGerando HTML..." -ForegroundColor Yellow
    $html = Generate-ProfessionalHTML -Metrics $metrics
    $html += Generate-OpenPositionsSection -Metrics $metrics
    
    # Fechar HTML
    $html += "`n    </div>`n</body>`n</html>"
    
    # 3. Salvar arquivo
    $dashboardDir = Join-Path $PSScriptRoot "..\dashboard"
    if (-not (Test-Path $dashboardDir)) {
        New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null
    }
    
    $outputPath = Join-Path $dashboardDir "index.html"
    [System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "[OK] Dashboard gerado: $outputPath" -ForegroundColor Green
    
    # 4. Telegram alerts (se configurado)
    if ($metrics.open_positions -gt 0 -and $metrics.trailing_metrics.trailing_activated) {
        # Verificar se trailing foi ativado recentemente
        $cacheFile = Join-Path $dashboardDir ".cache\trailing_alert.txt"
        $sendAlert = $true
        
        if (Test-Path $cacheFile) {
            $lastAlert = Get-Content $cacheFile -Raw
            if ($lastAlert -eq $metrics.trailing_metrics.current_stop.ToString()) {
                $sendAlert = $false
            }
        }
        
        if ($sendAlert) {
            Write-Host "`n[TELEGRAM] Enviando alerta de trailing stop..." -ForegroundColor Yellow
            
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
            
            # Salvar cache
            $cacheDir = Join-Path $dashboardDir ".cache"
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            $metrics.trailing_metrics.current_stop.ToString() | Out-File -FilePath $cacheFile -Force
        }
    }
    
    Write-Host "`n=== COMPLETO ===" -ForegroundColor Cyan
    
} catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
