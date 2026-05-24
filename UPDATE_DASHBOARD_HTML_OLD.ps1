# UPDATE_DASHBOARD_HTML.ps1
# Atualizar dashboard HTML com dados reais da API
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

Write-Host "=== ATUALIZANDO DASHBOARD HTML ===" -ForegroundColor Cyan
Write-Host ""

try {
    # Buscar dados reais
    Write-Host "Buscando posicoes..." -ForegroundColor Yellow
    $positions = CoinEx-GetPendingPositions
    
    Write-Host "Buscando capital..." -ForegroundColor Yellow
    $capital = CoinEx-GetFuturesCapitalUSDT
    
    # Calcular metricas
    $totalPnl = 0
    $positionsHtml = ""
    $positionsWithoutStop = 0
    
    if ($positions -and $positions.Count -gt 0) {
        foreach ($pos in $positions) {
            $market = $pos.market
            $side = $pos.side
            $entry = [double]$pos.avg_entry_price
            $current = [double]$pos.latest_price
            $pnl = [double]$pos.unrealized_pnl
            $pnlRate = [double]$pos.unrealized_pnl_rate
            $leverage = $pos.leverage
            $stopLoss = [double]$pos.stop_loss_price
            
            $totalPnl += $pnl
            
            $sideClass = if ($side -eq "long") { "long" } else { "short" }
            $pnlClass = if ($pnl -gt 0) { "status-positive" } elseif ($pnl -lt 0) { "status-negative" } else { "status-neutral" }
            
            $trailingStatus = if ($pnlRate -ge 3) {
                "<span class='trailing-active'><i class='fas fa-chart-line'></i> ACTIVE</span>"
            } else {
                "<span class='trailing-waiting'>Waiting +3%</span>"
            }
            
            if ($stopLoss -le 0) {
                $positionsWithoutStop++
                $trailingStatus = "<span class='status-negative'><i class='fas fa-exclamation-triangle'></i> NO STOP LOSS</span>"
            }
            
            $positionsHtml += @"
                        <tr>
                            <td><strong>$market</strong></td>
                            <td><span class='badge $sideClass'>$($side.ToUpper())</span></td>
                            <td>`$$([Math]::Round($entry, 2))</td>
                            <td>`$$([Math]::Round($current, 2))</td>
                            <td class='$pnlClass'>$([Math]::Round($pnlRate, 2))%</td>
                            <td class='$pnlClass'>`$$([Math]::Round($pnl, 2))</td>
                            <td>${leverage}x</td>
                            <td>$trailingStatus</td>
                        </tr>
"@
        }
    } else {
        $positionsHtml = @"
                        <tr>
                            <td colspan='8' style='text-align: center; padding: 40px; color: #5c6bc0;'>
                                <i class='fas fa-inbox' style='font-size: 2em; display: block; margin-bottom: 10px; opacity: 0.4;'></i>
                                No open positions
                            </td>
                        </tr>
"@
    }
    
    $posCount = if ($positions) { $positions.Count } else { 0 }
    $totalPnlClass = if ($totalPnl -gt 0) { "positive" } elseif ($totalPnl -lt 0) { "negative" } else { "" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Gerar HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>CoinEx Trading Dashboard</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #0a0e27 0%, #1a1f3a 100%);
            color: #e8eaf6;
            padding: 0;
            min-height: 100vh;
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
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
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
        .panel-body { padding: 24px; }
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
        tr:hover { background: rgba(100, 181, 246, 0.04); }
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
        .status-positive { color: #66bb6a; font-weight: 600; }
        .status-negative { color: #ef5350; font-weight: 600; }
        .status-neutral { color: #9fa8da; font-weight: 600; }
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
        .trailing-waiting {
            color: #5c6bc0;
            font-size: 0.75em;
            text-transform: uppercase;
            font-weight: 500;
        }
        @media (max-width: 1200px) {
            .metrics-grid { grid-template-columns: repeat(2, 1fr); }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo">CoinEx Trading Dashboard</div>
        <div class="timestamp">$timestamp UTC</div>
    </div>
    
    <div class="container">
        <div class="metrics-grid">
            <div class="metric-card info">
                <div class="label">Open Positions</div>
                <div class="value">$posCount</div>
            </div>
            <div class="metric-card $totalPnlClass">
                <div class="label">Total P&L</div>
                <div class="value">`$$([Math]::Round($totalPnl, 2))</div>
            </div>
            <div class="metric-card">
                <div class="label">Available Capital</div>
                <div class="value">`$$([Math]::Round($capital, 2))</div>
            </div>
            <div class="metric-card $(if ($positionsWithoutStop -gt 0) { 'warning' } else { 'positive' })">
                <div class="label">Positions Without Stop</div>
                <div class="value">$positionsWithoutStop</div>
            </div>
        </div>
        
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
$positionsHtml
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</body>
</html>
"@
    
    # Salvar HTML
    $htmlPath = "$PSScriptRoot\dashboard\index.html"
    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    
    Write-Host ""
    Write-Host "=== DASHBOARD ATUALIZADO ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Arquivo: $htmlPath" -ForegroundColor Cyan
    Write-Host "Posicoes: $posCount" -ForegroundColor White
    Write-Host "PNL Total: `$$([Math]::Round($totalPnl, 2))" -ForegroundColor $(if ($totalPnl -gt 0) { "Green" } else { "Red" })
    Write-Host "Capital: `$$([Math]::Round($capital, 2))" -ForegroundColor White
    Write-Host "Sem Stop Loss: $positionsWithoutStop" -ForegroundColor $(if ($positionsWithoutStop -gt 0) { "Red" } else { "Green" })
    Write-Host ""
    Write-Host "Abrir no navegador:" -ForegroundColor Yellow
    Write-Host "  file:///$($htmlPath.Replace('\', '/'))" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Ou execute:" -ForegroundColor Yellow
    Write-Host "  Start-Process '$htmlPath'" -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "=== ERRO ===" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
