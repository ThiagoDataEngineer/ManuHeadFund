# generate_position_dashboard.ps1 -- Gera dashboard de posicoes com metricas
# PS 5.1. UTF-8 BOM.
$scriptDir  = Split-Path $MyInvocation.MyCommand.Path -Parent
$projectDir = Split-Path $scriptDir -Parent
$agentsDir  = Join-Path $projectDir "agents"
$journalDir = Join-Path $projectDir "journal"

if (-not (Get-Command CoinEx-GetPendingPositions -EA SilentlyContinue)) {
    . (Join-Path $agentsDir "config.ps1") *>&1 | Out-Null
    . (Join-Path $agentsDir "lib_coinex.ps1") *>&1 | Out-Null
}

# ============================================================================
# Get-PositionMetrics - Coleta e calcula metricas de posicoes
# ============================================================================
function Get-PositionMetrics {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    # Posicoes abertas
    $openPos = @()
    try { $openPos = @(CoinEx-GetPendingPositions) } catch {}

    # Posicoes fechadas (via trade_outcomes.jsonl)
    $trades = @()
    $toPath = Join-Path $journalDir "trade_outcomes.jsonl"
    if (Test-Path $toPath) {
        $trades = @(Get-Content $toPath -EA SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json -EA SilentlyContinue } | Where-Object { $_ })
    }

    # Fallback: CoinEx-GetFinishedPositions se disponivel
    if ($trades.Count -eq 0 -and (Get-Command CoinEx-GetFinishedPositions -EA SilentlyContinue)) {
        try {
            $finished = CoinEx-GetFinishedPositions
            if ($finished.success -and $finished.positions) {
                $trades = @($finished.positions | ForEach-Object {
                    [PSCustomObject]@{
                        market  = $_.market
                        pnl_usd = [double]$_.realized_pnl
                        win     = [double]$_.realized_pnl -gt 0
                    }
                })
            }
        } catch {}
    }

    $wins       = @($trades | Where-Object { $_.pnl_usd -gt 0 -or $_.win })
    $losses     = @($trades | Where-Object { $_.pnl_usd -le 0 -and -not $_.win })
    $totalTrades= $trades.Count
    $winRate    = if ($totalTrades -gt 0) { [math]::Round($wins.Count * 100.0 / $totalTrades, 1) } else { 0 }
    $totalPnl   = [math]::Round(($trades | Measure-Object -Property pnl_usd -Sum).Sum, 2)
    $avgWin     = if ($wins.Count -gt 0) { [math]::Round(($wins | Measure-Object -Property pnl_usd -Average).Average, 2) } else { 0 }
    $avgLoss    = if ($losses.Count -gt 0) { [math]::Round(($losses | Measure-Object -Property pnl_usd -Average).Average, 2) } else { 0 }
    $profFactor = if ([math]::Abs($avgLoss) -gt 0) { [math]::Round($avgWin / [math]::Abs($avgLoss), 2) } else { 0 }

    # Top 5 markets by pnl
    $top5 = @($trades | Group-Object market | ForEach-Object {
        [PSCustomObject]@{ market=$_.Name; pnl=[math]::Round(($_.Group | Measure-Object -Property pnl_usd -Sum).Sum, 2) }
    } | Sort-Object pnl -Descending | Select-Object -First 5)

    # Open positions detail
    $openDetail = @($openPos | ForEach-Object {
        $entry = if ($_.avg_entry_price) { [double]$_.avg_entry_price } else { 0 }
        [PSCustomObject]@{
            market      = $_.market
            side        = $_.side
            entry_price = $entry
            pnl         = if ($_.unrealized_pnl) { [math]::Round([double]$_.unrealized_pnl, 4) } else { 0 }
            leverage    = if ($_.leverage) { $_.leverage } else { "1" }
        }
    })

    return [PSCustomObject]@{
        timestamp            = $ts
        open_positions       = $openPos.Count
        total_trades         = $totalTrades
        wins                 = $wins.Count
        losses               = $losses.Count
        win_rate             = $winRate
        total_pnl            = $totalPnl
        avg_win              = $avgWin
        avg_loss             = $avgLoss
        profit_factor        = $profFactor
        best_trade           = ($trades | Sort-Object pnl_usd -Descending | Select-Object -First 1)
        worst_trade          = ($trades | Sort-Object pnl_usd | Select-Object -First 1)
        top5_markets         = $top5
        open_positions_detail= $openDetail
    }
}

# ============================================================================
# Generate-HTML - Gera HTML do dashboard
# ============================================================================
function Generate-HTML {
    param([PSCustomObject]$Metrics)
    $ts      = if ($Metrics.timestamp)  { $Metrics.timestamp } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
    $opens   = if ($Metrics.open_positions)  { $Metrics.open_positions }  else { 0 }
    $trades  = if ($Metrics.total_trades)    { $Metrics.total_trades }    else { 0 }
    $wr      = if ($Metrics.win_rate)        { $Metrics.win_rate }        else { 0 }
    $pnl     = if ($Metrics.total_pnl)      { $Metrics.total_pnl }       else { 0 }
    $pnlSign = if ([double]$pnl -ge 0) { "positive" } else { "negative" }
    $wrSign  = if ([double]$wr -ge 50) { "positive" } else { "negative" }

    $posRows = ""
    if ($Metrics.open_positions_detail) {
        foreach ($p in @($Metrics.open_positions_detail)) {
            $pnlClass = if ($p.pnl -ge 0) { "positive" } else { "negative" }
            $pnlStr   = if ($p.pnl -ge 0) { "+$($p.pnl)" } else { "$($p.pnl)" }
            $posRows += "<tr><td><strong>$($p.market)</strong></td><td><span class='badge $($p.side)'>$($p.side.ToUpper())</span></td><td>`$$($p.entry_price)</td><td>--</td><td class='$pnlClass'>$pnlStr%</td><td>$($p.leverage)x</td><td>`$0</td></tr>"
        }
    }
    if (-not $posRows) { $posRows = "<tr><td colspan='7' style='text-align:center;color:#888'>Nenhuma posicao aberta</td></tr>" }

    $topRows = ""
    if ($Metrics.top5_markets) {
        foreach ($m in @($Metrics.top5_markets)) {
            $c = if ($m.pnl -ge 0) { "positive" } else { "negative" }
            $topRows += "<tr><td>$($m.market)</td><td class='$c'>`$$($m.pnl)</td></tr>"
        }
    }

    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="refresh" content="300">
  <title>Dashboard de Analise - Position Metrics</title>
  <link rel="stylesheet" href="shared.css">
  <style>
    :root { --bg-primary:#0d1117; --bg-card:#1c2128; --accent:#58a6ff; --success:#3fb950; --danger:#f85149; --text:#c9d1d9; --muted:#8b949e; --border:#30363d; }
    body { background:var(--bg-primary); color:var(--text); font-family:'Segoe UI',sans-serif; padding:16px; }
    .header-content { display:flex; justify-content:space-between; align-items:center; padding:12px 0; border-bottom:1px solid var(--border); }
    .logo { font-size:1.3em; font-weight:700; color:var(--accent); }
    .nav-menu a { margin-left:12px; color:var(--muted); text-decoration:none; }
    .timestamp { color:var(--muted); font-size:.82em; }
    .container { margin-top:16px; }
    .metrics-grid { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin-bottom:16px; }
    .metric-card { background:var(--bg-card); border:1px solid var(--border); border-radius:8px; padding:14px; }
    .metric-card .label { color:var(--muted); font-size:.75em; text-transform:uppercase; margin-bottom:4px; }
    .metric-card .value { font-size:1.5em; font-weight:700; }
    .positive { color:var(--success); }
    .negative { color:var(--danger); }
    .panel { background:#161b22; border:1px solid var(--border); border-radius:8px; padding:16px; margin-bottom:12px; }
    .panel-header { font-weight:600; color:var(--accent); margin-bottom:10px; }
    .panel-body table { width:100%; border-collapse:collapse; font-size:.875em; }
    th { color:var(--muted); text-align:left; padding:6px; border-bottom:1px solid var(--border); }
    td { padding:6px; border-bottom:1px solid #21262d; }
    .badge { display:inline-block; padding:2px 8px; border-radius:12px; font-size:.72em; font-weight:600; }
    .badge.long  { background:#238636; color:var(--success); }
    .badge.short { background:#b91c1c; color:var(--danger); }
  </style>
</head>
<body>
<div class="header">
  <div class="header-content">
    <div>
      <div class="logo">Dashboard de Analise - Position Metrics</div>
      <div class="nav-menu">
        <a href="elite.html">Elite</a>
        <a href="index.html">Operacional</a>
        <a href="position_metrics.html" class="active">Analise</a>
      </div>
    </div>
    <div class="timestamp">Ultima atualizacao: $ts | Auto-refresh: 5 min</div>
  </div>
</div>

<div class="container">
  <div class="metrics-grid">
    <div class="metric-card">
      <div class="label">Posicoes Abertas</div>
      <div class="value">$opens</div>
    </div>
    <div class="metric-card">
      <div class="label">Total de Trades</div>
      <div class="value">$trades</div>
    </div>
    <div class="metric-card $wrSign">
      <div class="label">Win Rate</div>
      <div class="value">$wr%</div>
    </div>
    <div class="metric-card $pnlSign">
      <div class="label">PnL Total</div>
      <div class="value">`$$pnl</div>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">Posicoes Abertas ($opens)</div>
    <div class="panel-body">
    <table>
      <thead><tr><th>Market</th><th>Side</th><th>Entry</th><th>Current</th><th>PnL%</th><th>Leverage</th><th>Liquidation</th></tr></thead>
      <tbody>$posRows</tbody>
    </table>
    </div>
  </div>

  <div class="panel">
    <div class="panel-header">Top 5 Markets por PnL</div>
    <div class="panel-body">
    <table><thead><tr><th>Market</th><th>PnL</th></tr></thead><tbody>$topRows</tbody></table>
    </div>
  </div>
</div>
</body>
</html>
"@
}
