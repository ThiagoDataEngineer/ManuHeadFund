# generate_position_dashboard_v2.ps1 - Dashboard HTML com UTF-8 correto
# Rodar: .\scripts\generate_position_dashboard_v2.ps1
# Output: .\dashboard\position_metrics.html

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"

# ============================================================================
# Get-PositionMetrics - Coleta metricas de posicoes
# ============================================================================

function Get-PositionMetrics {
    try {
        # 1. Posicoes abertas
        $openPositions = CoinEx-GetPendingPositions
        
        # FIX: Contar corretamente (pode ser array ou objeto unico)
        $openCount = if ($openPositions) {
            if ($openPositions -is [array]) {
                $openPositions.Count
            } else {
                1  # Objeto unico = 1 posicao
            }
        } else {
            0
        }
        
        # 2. Historico de posicoes (ultimas 100)
        $history = CoinEx-GetFinishedPositions -Limit 100
        $positions = if ($history.success) { $history.positions } else { @() }
        
        # 3. Calcular metricas
        $wins = 0
        $losses = 0
        $totalPnl = 0
        $totalTrades = $positions.Count
        
        $bestTrade = $null
        $worstTrade = $null
        $maxPnl = [double]::MinValue
        $minPnl = [double]::MaxValue
        
        foreach ($pos in $positions) {
            $pnl = [double]$pos.realized_pnl
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
        
        $winningTrades = $positions | Where-Object { [double]$_.realized_pnl -gt 0 }
        $losingTrades = $positions | Where-Object { [double]$_.realized_pnl -lt 0 }
        
        $avgWin = if ($wins -gt 0 -and $winningTrades) {
            $sum = ($winningTrades | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
            [math]::Round($sum / $wins, 2)
        } else { 0 }
        
        $avgLoss = if ($losses -gt 0 -and $losingTrades) {
            $sum = ($losingTrades | ForEach-Object { [double]$_.realized_pnl } | Measure-Object -Sum).Sum
            [math]::Round($sum / $losses, 2)
        } else { 0 }
        
        $profitFactor = if ($avgLoss -ne 0) {
            [math]::Round([math]::Abs($avgWin / $avgLoss), 2)
        } else { 0 }
        
        # 4. Metricas por market
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
            if ([double]$pos.realized_pnl -gt 0) { $marketStats[$market].wins++ }
            $marketStats[$market].pnl += [double]$pos.realized_pnl
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
        Write-Host "Erro ao coletar metricas: $_" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# Generate-HTML - Gera HTML do dashboard
# ============================================================================

function Generate-HTML {
    param($Metrics)
    
    if (-not $Metrics) {
        return "<html><body><h1>Erro ao carregar metricas</h1></body></html>"
    }
    
    $timestamp = $Metrics.timestamp
    $openPos = $Metrics.open_positions
    $totalTrades = $Metrics.total_trades
    $winRate = $Metrics.win_rate
    $totalPnl = $Metrics.total_pnl
    $wins = $Metrics.wins
    $losses = $Metrics.losses
    $avgWin = $Metrics.avg_win
    $avgLoss = $Metrics.avg_loss
    $profitFactor = $Metrics.profit_factor
    
    $pnlClass = if ($totalPnl -gt 0) { "positive" } else { "negative" }
    
    # Build HTML sections
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="pt-BR">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('    <meta charset="UTF-8">')
    [void]$sb.AppendLine('    <meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine('    <meta http-equiv="refresh" content="300">')
    [void]$sb.AppendLine('    <title>Position Management Dashboard</title>')
    [void]$sb.AppendLine('    <style>')
    [void]$sb.AppendLine('        body { font-family: Arial, sans-serif; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 20px; }')
    [void]$sb.AppendLine('        .container { max-width: 1400px; margin: 0 auto; }')
    [void]$sb.AppendLine('        .header { background: white; padding: 30px; border-radius: 15px; margin-bottom: 30px; text-align: center; }')
    [void]$sb.AppendLine('        .header h1 { color: #667eea; font-size: 2.5em; }')
    [void]$sb.AppendLine('        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }')
    [void]$sb.AppendLine('        .metric-card { background: white; padding: 25px; border-radius: 15px; }')
    [void]$sb.AppendLine('        .metric-card .label { font-size: 0.9em; color: #666; text-transform: uppercase; }')
    [void]$sb.AppendLine('        .metric-card .value { font-size: 2.5em; font-weight: bold; color: #667eea; }')
    [void]$sb.AppendLine('        .metric-card.positive .value { color: #10b981; }')
    [void]$sb.AppendLine('        .metric-card.negative .value { color: #ef4444; }')
    [void]$sb.AppendLine('        .section { background: white; padding: 30px; border-radius: 15px; margin-bottom: 30px; }')
    [void]$sb.AppendLine('        .section h2 { color: #667eea; margin-bottom: 20px; }')
    [void]$sb.AppendLine('        table { width: 100%; border-collapse: collapse; }')
    [void]$sb.AppendLine('        th, td { padding: 15px; text-align: left; border-bottom: 1px solid #e5e7eb; }')
    [void]$sb.AppendLine('        th { background: #f9fafb; color: #667eea; font-weight: 600; }')
    [void]$sb.AppendLine('        .positive { color: #10b981; font-weight: bold; }')
    [void]$sb.AppendLine('        .negative { color: #ef4444; font-weight: bold; }')
    [void]$sb.AppendLine('        .badge { display: inline-block; padding: 5px 12px; border-radius: 20px; font-size: 0.85em; font-weight: 600; }')
    [void]$sb.AppendLine('        .badge.long { background: #d1fae5; color: #065f46; }')
    [void]$sb.AppendLine('        .badge.short { background: #fee2e2; color: #991b1b; }')
    [void]$sb.AppendLine('    </style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('    <div class="container">')
    [void]$sb.AppendLine('        <div class="header">')
    [void]$sb.AppendLine("            <h1>Position Management Dashboard</h1>")
    [void]$sb.AppendLine("            <div>Ultima atualizacao: $timestamp</div>")
    [void]$sb.AppendLine('        </div>')
    
    # Metrics grid
    [void]$sb.AppendLine('        <div class="metrics-grid">')
    [void]$sb.AppendLine('            <div class="metric-card">')
    [void]$sb.AppendLine('                <div class="label">Posicoes Abertas</div>')
    [void]$sb.AppendLine("                <div class='value'>$openPos</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <div class="metric-card">')
    [void]$sb.AppendLine('                <div class="label">Total de Trades</div>')
    [void]$sb.AppendLine("                <div class='value'>$totalTrades</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('            <div class="metric-card positive">')
    [void]$sb.AppendLine('                <div class="label">Win Rate</div>')
    [void]$sb.AppendLine("                <div class='value'>$winRate%</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine("            <div class='metric-card $pnlClass'>")
    [void]$sb.AppendLine('                <div class="label">PnL Total</div>')
    [void]$sb.AppendLine("                <div class='value'>`$$totalPnl</div>")
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </div>')
    
    # Open positions section
    [void]$sb.AppendLine('        <div class="section">')
    [void]$sb.AppendLine('            <h2>Posicoes Abertas</h2>')
    
    if ($Metrics.open_positions -gt 0) {
        [void]$sb.AppendLine('            <table>')
        [void]$sb.AppendLine('                <thead>')
        [void]$sb.AppendLine('                    <tr>')
        [void]$sb.AppendLine('                        <th>Market</th>')
        [void]$sb.AppendLine('                        <th>Side</th>')
        [void]$sb.AppendLine('                        <th>Entry</th>')
        [void]$sb.AppendLine('                        <th>Current</th>')
        [void]$sb.AppendLine('                        <th>PnL%</th>')
        [void]$sb.AppendLine('                        <th>Leverage</th>')
        [void]$sb.AppendLine('                        <th>Liquidation</th>')
        [void]$sb.AppendLine('                    </tr>')
        [void]$sb.AppendLine('                </thead>')
        [void]$sb.AppendLine('                <tbody>')
        
        # FIX: Garantir que seja array para iteracao
        $positionsArray = if ($Metrics.open_positions_detail -is [array]) {
            $Metrics.open_positions_detail
        } else {
            @($Metrics.open_positions_detail)
        }
        
        foreach ($pos in $positionsArray) {
            $market = $pos.market
            $side = $pos.side.ToUpper()
            
            # FIX: Usar avg_entry_price (nao open_price)
            $entryPrice = [math]::Round([double]$pos.avg_entry_price, 4)
            
            # FIX: Buscar preco atual via ticker (nao latest_price)
            $ticker = CoinEx-GetTickerFresh -market $market
            $currentPrice = [math]::Round([double]$ticker.ticker.last, 4)
            
            # FIX: Usar liq_price (nao liquidation_price)
            $liqPrice = [math]::Round([double]$pos.liq_price, 4)
            
            $leverage = $pos.leverage
            
            $pnlPct = if ($pos.side -eq "long") {
                (($currentPrice - $entryPrice) / $entryPrice) * 100
            } else {
                (($entryPrice - $currentPrice) / $entryPrice) * 100
            }
            $pnlPct = [math]::Round($pnlPct, 2)
            
            $pnlClass = if ($pnlPct -gt 0) { "positive" } else { "negative" }
            $sideClass = if ($pos.side -eq "long") { "long" } else { "short" }
            
            [void]$sb.AppendLine('                    <tr>')
            [void]$sb.AppendLine("                        <td><strong>$market</strong></td>")
            [void]$sb.AppendLine("                        <td><span class='badge $sideClass'>$side</span></td>")
            [void]$sb.AppendLine("                        <td>`$$entryPrice</td>")
            [void]$sb.AppendLine("                        <td>`$$currentPrice</td>")
            [void]$sb.AppendLine("                        <td class='$pnlClass'>$pnlPct%</td>")
            [void]$sb.AppendLine("                        <td>$leverage`x</td>")
            [void]$sb.AppendLine("                        <td>`$$liqPrice</td>")
            [void]$sb.AppendLine('                    </tr>')
        }
        
        [void]$sb.AppendLine('                </tbody>')
        [void]$sb.AppendLine('            </table>')
    } else {
        [void]$sb.AppendLine('            <p style="text-align: center; color: #666; padding: 40px;">Nenhuma posicao aberta no momento</p>')
    }
    
    [void]$sb.AppendLine('        </div>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')
    
    return $sb.ToString()
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n=== GERANDO DASHBOARD V2 ===" -ForegroundColor Cyan
    
    # 1. Coletar metricas
    Write-Host "Coletando metricas..." -ForegroundColor Yellow
    $metrics = Get-PositionMetrics
    
    if (-not $metrics) {
        Write-Host "[X] Falha ao coletar metricas" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Metricas coletadas" -ForegroundColor Green
    Write-Host "  Posicoes abertas: $($metrics.open_positions)" -ForegroundColor Gray
    Write-Host "  Total trades: $($metrics.total_trades)" -ForegroundColor Gray
    Write-Host "  Win rate: $($metrics.win_rate)%" -ForegroundColor Gray
    Write-Host "  PnL total: `$$($metrics.total_pnl)" -ForegroundColor Gray
    
    # 2. Gerar HTML
    Write-Host "`nGerando HTML..." -ForegroundColor Yellow
    $html = Generate-HTML -Metrics $metrics
    
    # 3. Salvar arquivo com UTF-8
    $dashboardDir = Join-Path $PSScriptRoot "..\dashboard"
    if (-not (Test-Path $dashboardDir)) {
        New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null
    }
    
    $outputPath = Join-Path $dashboardDir "position_metrics.html"
    
    # Salvar com UTF-8 (sem BOM)
    [System.IO.File]::WriteAllText($outputPath, $html, [System.Text.UTF8Encoding]::new($false))
    
    Write-Host "[OK] Dashboard gerado: $outputPath" -ForegroundColor Green
    
    Write-Host "`n=== COMPLETO ===" -ForegroundColor Cyan
    
} catch {
    Write-Host "`nERRO: $_" -ForegroundColor Red
    exit 1
}
