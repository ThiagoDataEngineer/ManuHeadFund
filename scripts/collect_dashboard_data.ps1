# scripts\collect_dashboard_data.ps1
# Dashboard Data Collector - CROSS-PLATFORM (Windows/Linux)
# Coleta dados e gera dashboard HTML
# 2026-05-24

$ErrorActionPreference = "Stop"

# Setup Cross-Platform
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

# Inicializar ambiente
$env = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== DASHBOARD GENERATOR START ===" -LogFile "dashboard.log"
Write-CrossPlatformLog "OS: $(if ($env.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "dashboard.log"

# Validar credenciais
if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "dashboard.log"
    exit 1
}

# Carregar bibliotecas
try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "dashboard.log"
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    Write-CrossPlatformLog "Libraries loaded" -LogFile "dashboard.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "dashboard.log"
    exit 1
}

# Executar
try {
    Write-CrossPlatformLog "--- COLLECTING DATA ---" -LogFile "dashboard.log"
    
    # Buscar posições
    $positions = @(CoinEx-GetPendingPositions)
    Write-CrossPlatformLog "Positions: $($positions.Count)" -LogFile "dashboard.log"
    
    # Calcular métricas
    $totalPnl = 0
    $totalMargin = 0
    
    foreach ($pos in $positions) {
        $totalPnl += [double]$pos.unrealized_pnl
        $totalMargin += [double]$pos.margin
    }
    
    $totalPnl = [math]::Round($totalPnl, 2)
    $totalMargin = [math]::Round($totalMargin, 2)
    $pnlPct = if ($totalMargin -gt 0) { [math]::Round(($totalPnl / $totalMargin) * 100, 2) } else { 0 }
    
    Write-CrossPlatformLog "Total PNL: `$$totalPnl ($pnlPct%)" -LogFile "dashboard.log"
    Write-CrossPlatformLog "Total Margin: `$$totalMargin" -LogFile "dashboard.log"
    
    # Gerar HTML
    Write-CrossPlatformLog "--- GENERATING HTML ---" -LogFile "dashboard.log"
    
    $dashboardPath = Join-Path $env.DashboardDir "index.html"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    
    $positionsHtml = ""
    foreach ($pos in $positions) {
        $pnl = [math]::Round([double]$pos.unrealized_pnl, 2)
        $pnlClass = if ($pnl -ge 0) { "profit" } else { "loss" }
        $side = $pos.side.ToUpper()
        $leverage = [math]::Round([double]$pos.leverage, 1)
        
        $positionsHtml += @"
        <div class="position">
            <div class="position-header">
                <strong>$($pos.market)</strong>
                <span class="leverage">${leverage}x</span>
            </div>
            <div class="position-details">
                <span>$side</span> | 
                <span>Entry: `$$($pos.avg_entry_price)</span> | 
                <span class="$pnlClass">PNL: `$$pnl</span>
            </div>
        </div>
"@
    }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Trading Dashboard</title>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="300">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Arial, sans-serif; 
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            color: #fff; 
            padding: 20px;
            min-height: 100vh;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { 
            font-size: 32px; 
            font-weight: bold;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d4ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .timestamp { 
            color: #888; 
            font-size: 14px; 
            margin-bottom: 30px;
        }
        .summary {
            background: rgba(255,255,255,0.05);
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 30px;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
        }
        .summary-item {
            text-align: center;
        }
        .summary-label {
            color: #888;
            font-size: 12px;
            text-transform: uppercase;
            margin-bottom: 5px;
        }
        .summary-value {
            font-size: 24px;
            font-weight: bold;
        }
        .positions-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 15px;
        }
        .position { 
            background: rgba(255,255,255,0.05);
            padding: 20px;
            border-radius: 10px;
            border-left: 3px solid #00d4ff;
            transition: transform 0.2s;
        }
        .position:hover {
            transform: translateY(-2px);
            background: rgba(255,255,255,0.08);
        }
        .position-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        .position-header strong {
            font-size: 18px;
        }
        .leverage {
            background: rgba(255,255,255,0.1);
            padding: 2px 8px;
            border-radius: 4px;
            font-size: 12px;
        }
        .position-details {
            color: #aaa;
            font-size: 14px;
        }
        .profit { color: #4caf50; font-weight: bold; }
        .loss { color: #f44336; font-weight: bold; }
        .footer {
            margin-top: 30px;
            text-align: center;
            color: #666;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">📊 Trading Dashboard</div>
        <div class="timestamp">Updated: $timestamp | Auto-refresh: 5min</div>
        
        <div class="summary">
            <div class="summary-item">
                <div class="summary-label">Positions</div>
                <div class="summary-value">$($positions.Count)</div>
            </div>
            <div class="summary-item">
                <div class="summary-label">Total PNL</div>
                <div class="summary-value $(if ($totalPnl -ge 0) { 'profit' } else { 'loss' })">`$$totalPnl</div>
            </div>
            <div class="summary-item">
                <div class="summary-label">PNL %</div>
                <div class="summary-value $(if ($pnlPct -ge 0) { 'profit' } else { 'loss' })">${pnlPct}%</div>
            </div>
            <div class="summary-item">
                <div class="summary-label">Total Margin</div>
                <div class="summary-value">`$$totalMargin</div>
            </div>
        </div>
        
        <div class="positions-grid">
            $positionsHtml
        </div>
        
        <div class="footer">
            ManuHeadFund Trading System | Cross-Platform Dashboard
        </div>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $dashboardPath -Encoding UTF8 -Force
    Write-CrossPlatformLog "Dashboard created: $dashboardPath" -LogFile "dashboard.log"
    
    Write-CrossPlatformLog "=== DASHBOARD GENERATOR END ===" -LogFile "dashboard.log"
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "dashboard.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "dashboard.log"
    exit 1
}
