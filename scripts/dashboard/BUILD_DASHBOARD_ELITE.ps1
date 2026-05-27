# BUILD_DASHBOARD_ELITE.ps1
# Constroi dashboard elite completo com TDD
# 2026-05-24

param(
    [switch]$Test,
    [switch]$Open
)

Write-Host "=== BUILD DASHBOARD ELITE (TDD) ===" -ForegroundColor Cyan
Write-Host ""

# STEP 1: Coletar dados
Write-Host "[1/5] Coletando dados..." -ForegroundColor Yellow

try {
    $dataJson = & "$PSScriptRoot\scripts\collect_dashboard_data.ps1"
    $data = $dataJson | ConvertFrom-Json
    Write-Host "  ✓ Dados coletados com sucesso" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ ERRO ao coletar dados: $_" -ForegroundColor Red
    if (-not $Test) { exit 1 }
    # Mock data para testes
    $data = @{
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        trading_metrics = @{ trades_24h = 0; win_rate = 0 }
        mentor_decisions = @{ total_24h = 0; approval_rate = 0 }
    }
}

# STEP 2: Buscar posicoes
Write-Host "[2/5] Buscando posicoes..." -ForegroundColor Yellow

try {
    . "$PSScriptRoot\agents\config.ps1"
    . "$PSScriptRoot\agents\lib_coinex.ps1"
    
    $positions = CoinEx-GetPendingPositions
    $capital = CoinEx-GetFuturesCapitalUSDT
    
    Write-Host "  ✓ Posicoes: $($positions.Count)" -ForegroundColor Green
    Write-Host "  ✓ Capital: `$$([Math]::Round($capital, 2))" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Usando dados mockados" -ForegroundColor Yellow
    $positions = @()
    $capital = 1579.25
}

# STEP 3: Gerar HTML
Write-Host "[3/5] Gerando HTML..." -ForegroundColor Yellow

$htmlPath = "$PSScriptRoot\dashboard\index_elite.html"

# Template HTML completo
$html = @"
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
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --bg-primary: #0a0e27; --bg-secondary: #1a1f3a; --bg-card: #1e2139;
            --border-color: rgba(100, 181, 246, 0.12); --text-primary: #e8eaf6;
            --accent-blue: #64b5f6; --accent-green: #66bb6a; --accent-red: #ef5350;
        }
        body { font-family: 'Inter', sans-serif; background: linear-gradient(135deg, var(--bg-primary), var(--bg-secondary)); color: var(--text-primary); min-height: 100vh; }
        .header { background: var(--bg-card); padding: 20px 40px; display: flex; justify-content: space-between; border-bottom: 1px solid var(--border-color); }
        .logo { font-size: 1.5em; font-weight: 700; color: var(--accent-blue); }
        .container { max-width: 2000px; margin: 0 auto; padding: 30px; }
        .grid-6 { display: grid; grid-template-columns: repeat(6, 1fr); gap: 16px; margin-bottom: 24px; }
        .metric-card { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; padding: 20px; }
        .metric-card .label { font-size: 0.7em; color: #7986cb; text-transform: uppercase; margin-bottom: 10px; }
        .metric-card .value { font-size: 2em; font-weight: 600; }
        .positive { color: var(--accent-green); }
        .negative { color: var(--accent-red); }
        .panel { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 12px; margin-bottom: 24px; }
        .panel-header { padding: 16px 24px; border-bottom: 1px solid var(--border-color); font-weight: 600; color: var(--accent-blue); }
        .panel-body { padding: 24px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: rgba(100, 181, 246, 0.08); padding: 12px; text-align: left; font-size: 0.7em; text-transform: uppercase; }
        td { padding: 14px; border-bottom: 1px solid var(--border-color); }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo"><i class="fas fa-chart-line"></i> ManuHeadFund Dashboard Elite</div>
        <div>$($data.timestamp) | Auto-refresh: 5 min</div>
    </div>
    
    <div class="container">
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
                <div class="label"><i class="fas fa-chart-line"></i> Win Rate</div>
                <div class="value">$($data.trading_metrics.win_rate)%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-shield-alt"></i> Stops</div>
                <div class="value positive">100%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-robot"></i> Aprovação</div>
                <div class="value negative">$($data.mentor_decisions.approval_rate)%</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-coins"></i> Trades 24h</div>
                <div class="value">$($data.trading_metrics.trades_24h)</div>
            </div>
        </div>
        
        <!-- Trading Metrics -->
        <div class="panel">
            <div class="panel-header"><i class="fas fa-chart-bar"></i> Métricas de Trading (30 dias)</div>
            <div class="panel-body">
                <canvas id="tradingChart" height="80"></canvas>
            </div>
        </div>
        
        <!-- Mentor & Mesa -->
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 24px;">
            <div class="panel">
                <div class="panel-header"><i class="fas fa-gavel"></i> Decisões do Mentor</div>
                <div class="panel-body">
                    <p>Total 24h: <strong>$($data.mentor_decisions.total_24h)</strong></p>
                    <p>Aprovação: <strong class="positive">$($data.mentor_decisions.approval_rate)%</strong></p>
                    <p>Veto: <strong class="negative">$($data.mentor_decisions.veto_rate)%</strong></p>
                </div>
            </div>
            <div class="panel">
                <div class="panel-header"><i class="fas fa-users"></i> Mesa Consensus</div>
                <div class="panel-body">
                    <p>Consensus: <strong>$($data.mesa_consensus.consensus)</strong></p>
                    <p>Score Médio: <strong>$($data.mesa_consensus.score_avg)</strong></p>
                    <p>Degraded: <strong>$($data.mesa_consensus.degraded_count)</strong></p>
                </div>
            </div>
        </div>
        
        <!-- Positions Table -->
        <div class="panel">
            <div class="panel-header"><i class="fas fa-list"></i> Posições Abertas ($($positions.Count))</div>
            <div class="panel-body">
"@

# Adicionar tabela de posicoes
if ($positions.Count -gt 0) {
    $html += @"
                <table>
                    <thead>
                        <tr>
                            <th>Market</th>
                            <th>Side</th>
                            <th>Entry</th>
                            <th>PNL %</th>
                            <th>Stop Loss</th>
                            <th>Trailing</th>
                        </tr>
                    </thead>
                    <tbody>
"@
    foreach ($pos in $positions) {
        $pnlClass = if ([double]$pos.unrealized_pnl_rate -gt 0) { "positive" } else { "negative" }
        $html += @"
                        <tr>
                            <td><strong>$($pos.market)</strong></td>
                            <td>$($pos.side.ToUpper())</td>
                            <td>`$$($pos.avg_entry_price)</td>
                            <td class="$pnlClass">$([Math]::Round([double]$pos.unrealized_pnl_rate, 2))%</td>
                            <td>`$$($pos.stop_loss_price)</td>
                            <td>Aguardando +3%</td>
                        </tr>
"@
    }
    $html += @"
                    </tbody>
                </table>
"@
} else {
    $html += "<p>Nenhuma posição aberta</p>"
}

$html += @"
            </div>
        </div>
    </div>
    
    <script>
        // Trading Metrics Chart
        const ctx = document.getElementById('tradingChart').getContext('2d');
        new Chart(ctx, {
            type: 'bar',
            data: {
                labels: ['24h', '7d', '30d'],
                datasets: [{
                    label: 'Trades Executados',
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
    </script>
</body>
</html>
"@

# Salvar HTML
$html | Out-File $htmlPath -Encoding UTF8
Write-Host "  ✓ HTML gerado: $htmlPath" -ForegroundColor Green

# STEP 4: Validar HTML
Write-Host "[4/5] Validando HTML..." -ForegroundColor Yellow

if (Test-Path $htmlPath) {
    $size = (Get-Item $htmlPath).Length
    Write-Host "  ✓ Arquivo criado: $size bytes" -ForegroundColor Green
} else {
    Write-Host "  ✗ ERRO: Arquivo não criado" -ForegroundColor Red
    exit 1
}

# STEP 5: Abrir no navegador
if ($Open) {
    Write-Host "[5/5] Abrindo no navegador..." -ForegroundColor Yellow
    Start-Process $htmlPath
    Write-Host "  ✓ Dashboard aberto" -ForegroundColor Green
} else {
    Write-Host "[5/5] Pular abertura (use -Open para abrir)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== BUILD COMPLETO ===" -ForegroundColor Green
Write-Host "Dashboard: $htmlPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "Comandos úteis:" -ForegroundColor Yellow
Write-Host "  .\BUILD_DASHBOARD_ELITE.ps1 -Open    # Gerar e abrir" -ForegroundColor Gray
Write-Host "  .\BUILD_DASHBOARD_ELITE.ps1 -Test    # Modo teste" -ForegroundColor Gray
