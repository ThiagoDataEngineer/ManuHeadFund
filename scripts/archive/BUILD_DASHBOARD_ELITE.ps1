# BUILD_DASHBOARD_ELITE.ps1 -- Gera dashboard\elite.html
# PS 5.1. UTF-8 BOM.
$scriptDir    = Split-Path $MyInvocation.MyCommand.Path -Parent
$dashboardDir = Join-Path $scriptDir "dashboard"
$dataFile     = Join-Path $dashboardDir "dashboard_data.json"
$outputFile   = Join-Path $dashboardDir "elite.html"

if (-not (Test-Path $dashboardDir)) { New-Item -ItemType Directory -Path $dashboardDir -Force | Out-Null }

$data = $null
if (Test-Path $dataFile) {
    try { $data = Get-Content $dataFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
}

$ts        = if ($data -and $data.generated_at)   { $data.generated_at.Substring(0,19) -replace 'T',' ' } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
$trades7d  = if ($data -and $data.trading_metrics) { $data.trading_metrics.trades_7d } else { 0 }
$trades30d = if ($data -and $data.trading_metrics) { $data.trading_metrics.trades_30d } else { 0 }
$winRate   = if ($data -and $data.trading_metrics) { [math]::Round($data.trading_metrics.win_rate * 100, 1) } else { 0 }
$totalPnl  = if ($data -and $data.trading_metrics) { [math]::Round($data.trading_metrics.total_pnl, 2) } else { 0 }
$regime    = if ($data -and $data.market_regime)   { $data.market_regime.regime } else { "N/A" }
$openPos   = if ($data -and $data.portfolio_metrics){ $data.portfolio_metrics.open_positions } else { 0 }
$llmCost   = if ($data -and $data.llm_costs)       { $data.llm_costs.today_usd } else { 0 }

$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="refresh" content="300">
  <title>ManuHeadFund Elite Dashboard</title>
  <link rel="stylesheet" href="shared.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    :root {
      --bg-primary:#0d1117; --bg-secondary:#161b22; --bg-card:#1c2128;
      --accent:#58a6ff; --success:#3fb950; --warning:#d29922; --danger:#f85149;
      --text-primary:#c9d1d9; --text-muted:#8b949e; --border:#30363d;
    }
    * { box-sizing:border-box; margin:0; padding:0; }
    body { background:var(--bg-primary); color:var(--text-primary); font-family:'Segoe UI',system-ui,sans-serif; padding:16px; }
    .header { display:flex; justify-content:space-between; align-items:center; padding:12px 0 16px; border-bottom:1px solid var(--border); margin-bottom:20px; }
    .logo { font-size:1.4em; font-weight:700; color:var(--accent); }
    .timestamp { color:var(--text-muted); font-size:.82em; }
    .metrics-grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(160px,1fr)); gap:12px; margin-bottom:20px; }
    .grid-6 { grid-template-columns:repeat(6,1fr); }
    .metric-card { background:var(--bg-card); border:1px solid var(--border); border-radius:8px; padding:14px; }
    .metric-card .label { color:var(--text-muted); font-size:.75em; text-transform:uppercase; letter-spacing:.05em; margin-bottom:6px; }
    .metric-card .value { font-size:1.5em; font-weight:700; }
    .positive { color:var(--success); }
    .negative { color:var(--danger); }
    .neutral  { color:var(--warning); }
    .panel { background:var(--bg-secondary); border:1px solid var(--border); border-radius:8px; padding:16px; margin-bottom:16px; }
    .panel-header { font-weight:600; color:var(--accent); margin-bottom:12px; font-size:1em; }
    table { width:100%; border-collapse:collapse; font-size:.875em; }
    th { text-align:left; color:var(--text-muted); padding:8px 6px; border-bottom:1px solid var(--border); font-weight:500; }
    td { padding:8px 6px; border-bottom:1px solid #21262d; }
    .badge { display:inline-block; padding:2px 8px; border-radius:12px; font-size:.72em; font-weight:600; }
    .badge-long  { background:#238636; color:#3fb950; }
    .badge-short { background:#b91c1c; color:#f85149; }
    .chart-container { position:relative; height:200px; }
    .decision-row { display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid #21262d; font-size:.875em; }
  </style>
</head>
<body>

<div class="header">
  <div>
    <div class="logo"><i class="fas fa-chart-bar"></i> ManuHeadFund Elite</div>
    <div class="timestamp"><i class="far fa-clock"></i> Ultima atualizacao: $ts | Auto-refresh: 5 min</div>
  </div>
</div>

<div class="metrics-grid grid-6">
  <div class="metric-card">
    <div class="label"><i class="fas fa-exchange-alt"></i> Trades 7d</div>
    <div class="value">$trades7d</div>
  </div>
  <div class="metric-card">
    <div class="label"><i class="fas fa-calendar"></i> Trades 30d</div>
    <div class="value">$trades30d</div>
  </div>
  <div class="metric-card $(if ([double]$winRate -ge 50) {'positive'} else {'negative'})">
    <div class="label"><i class="fas fa-percentage"></i> Win Rate</div>
    <div class="value">$winRate%</div>
  </div>
  <div class="metric-card $(if ([double]$totalPnl -ge 0) {'positive'} else {'negative'})">
    <div class="label"><i class="fas fa-dollar-sign"></i> PnL Total</div>
    <div class="value">`$$totalPnl</div>
  </div>
  <div class="metric-card neutral">
    <div class="label"><i class="fas fa-globe"></i> Regime</div>
    <div class="value" style="font-size:1em">$regime</div>
  </div>
  <div class="metric-card">
    <div class="label"><i class="fas fa-robot"></i> LLM Custo</div>
    <div class="value">`$$llmCost</div>
  </div>
</div>

<div class="panel">
  <div class="panel-header"><i class="fas fa-chart-line"></i> Métricas de Trading</div>
  <div class="metrics-grid" style="grid-template-columns:repeat(3,1fr)">
    <div class="metric-card"><div class="label">Trades 7d</div><div class="value">$trades7d</div></div>
    <div class="metric-card"><div class="label">Trades 30d</div><div class="value">$trades30d</div></div>
    <div class="metric-card $(if ([double]$winRate -ge 50) {'positive'} else {'negative'})"><div class="label">Win Rate</div><div class="value">$winRate%</div></div>
  </div>
  <div class="chart-container" style="margin-top:12px">
    <canvas id="pnlChart"></canvas>
  </div>
</div>

<div class="panel">
  <div class="panel-header"><i class="fas fa-brain"></i> Decisões do Mentor</div>
  <div class="decision-row"><span>Aguardando dados do ciclo atual...</span><span class="neutral">--</span></div>
</div>

<div class="panel">
  <div class="panel-header"><i class="fas fa-table"></i> Mesa Consensus</div>
  <p style="color:var(--text-muted);font-size:.875em">Regime atual: <strong style="color:var(--warning)">$regime</strong></p>
</div>

<div class="panel">
  <div class="panel-header"><i class="fas fa-list"></i> Posições Abertas ($openPos)</div>
  <table>
    <thead>
      <tr><th>Market</th><th>Side</th><th>Entry</th><th>Current</th><th>PnL%</th><th>SL</th></tr>
    </thead>
    <tbody>
      <tr><td colspan="6" style="color:var(--text-muted);text-align:center;padding:20px">Nenhuma posicao aberta</td></tr>
    </tbody>
  </table>
</div>

<script>
const ctx = document.getElementById('pnlChart');
if (ctx) {
  new Chart(ctx, {
    type: 'line',
    data: {
      labels: ['30d','25d','20d','15d','10d','5d','hoje'],
      datasets: [{
        label: 'PnL Acumulado',
        data: [0, 0, 0, 0, 0, 0, $totalPnl],
        borderColor: '$(if ([double]$totalPnl -ge 0) { '#3fb950' } else { '#f85149' })',
        tension: 0.3,
        fill: false
      }]
    },
    options: { responsive:true, maintainAspectRatio:false, plugins:{ legend:{ display:false } }, scales:{ y:{ grid:{ color:'#30363d' }, ticks:{ color:'#8b949e' } }, x:{ grid:{ color:'#30363d' }, ticks:{ color:'#8b949e' } } } }
  });
}
</script>

</body>
</html>
"@

[System.IO.File]::WriteAllText($outputFile, $html, [System.Text.Encoding]::UTF8)
Write-Host "Elite dashboard gerado: $outputFile ($([int]((Get-Item $outputFile).Length / 1024))KB)"
