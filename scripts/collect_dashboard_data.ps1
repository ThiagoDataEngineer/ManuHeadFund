# scripts\collect_dashboard_data.ps1
# Dashboard Data Collector - CROSS-PLATFORM (Windows/Linux)
# Versao 2.0 - Dashboard completo com dados reais da CoinEx
# 2026-05-25

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir   = Join-Path $projectRoot "agents"

. (Join-Path $agentsDir "lib_cross_platform.ps1")

$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

$cpEnv = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== DASHBOARD v2 START ===" -LogFile "dashboard.log"

if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "dashboard.log"
    exit 1
}

try {
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
} catch {
    Write-CrossPlatformLog "ERROR loading libs: $_" -Level ERROR -LogFile "dashboard.log"
    exit 1
}

try {
    # ── Dados da API ──────────────────────────────────────────────────────────
    $positions   = @(CoinEx-GetPendingPositions)
    $spotCap     = 0; $futuresCap = 0
    try { $spotCap    = [math]::Round([double](CoinEx-GetSpotCapitalUSDT), 2)    } catch {}
    try { $futuresCap = [math]::Round([double](CoinEx-GetFuturesCapitalUSDT), 2) } catch {}
    $totalCap = [math]::Round($spotCap + $futuresCap, 2)

    # ── Calcular métricas ─────────────────────────────────────────────────────
    $totalPnl    = 0
    $totalMargin = 0

    $posData = @()
    foreach ($pos in $positions) {
        $pnl      = [math]::Round([double]$pos.unrealized_pnl, 2)
        $margin   = [math]::Round([double]$pos.margin, 2)
        $leverage = [math]::Round([double]$pos.leverage, 0)
        $entry    = [math]::Round([double]$pos.avg_entry_price, 4)
        $side     = $pos.side.ToUpper()

        # Preço atual via ticker
        $currentPrice = 0
        try {
            $ticker = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/ticker?market=$($pos.market)" -Method GET -ErrorAction Stop
            if ($ticker.code -eq 0) { $currentPrice = [math]::Round([double]$ticker.data[0].last, 4) }
        } catch {}

        # PNL%
        $pnlPct = if ($margin -gt 0) { [math]::Round(($pnl / $margin) * 100, 2) } else { 0 }

        # Stop loss
        $stopLoss = 0
        try { $stopLoss = [math]::Round([double]$pos.stop_loss_price, 4) } catch {}

        # Distancia do stop (%)
        $stopDist = 0
        if ($stopLoss -gt 0 -and $currentPrice -gt 0) {
            $stopDist = [math]::Round([math]::Abs(($currentPrice - $stopLoss) / $currentPrice) * 100, 2)
        }

        $totalPnl    += $pnl
        $totalMargin += $margin

        $posData += [PSCustomObject]@{
            market       = $pos.market
            side         = $side
            leverage     = $leverage
            entry        = $entry
            currentPrice = $currentPrice
            pnl          = $pnl
            pnlPct       = $pnlPct
            margin       = $margin
            stopLoss     = $stopLoss
            stopDist     = $stopDist
        }
    }

    $totalPnl    = [math]::Round($totalPnl, 2)
    $totalMargin = [math]::Round($totalMargin, 2)
    $totalPnlPct = if ($totalMargin -gt 0) { [math]::Round(($totalPnl / $totalMargin) * 100, 2) } else { 0 }

    Write-CrossPlatformLog "Positions: $($posData.Count) | PNL: $totalPnl ($totalPnlPct%) | Capital: $totalCap" -LogFile "dashboard.log"

    # ── Gerar cards de posição ────────────────────────────────────────────────
    $positionsHtml = ""
    if ($posData.Count -eq 0) {
        $positionsHtml = '<div class="no-positions">Nenhuma posicao aberta</div>'
    }

    foreach ($p in $posData) {
        $pnlClass    = if ($p.pnl -ge 0) { "profit" } else { "loss" }
        $pnlSign     = if ($p.pnl -ge 0) { "+" } else { "" }
        $sideClass   = if ($p.side -eq "LONG") { "side-long" } else { "side-short" }
        $borderColor = if ($p.pnl -ge 0) { "#4caf50" } else { "#f44336" }
        $stopHtml    = if ($p.stopLoss -gt 0) { "<span class='detail-item'><span class='detail-label'>Stop</span><span class='detail-val loss'>`$$($p.stopLoss) (-$($p.stopDist)%)</span></span>" } else { "<span class='detail-item'><span class='detail-label'>Stop</span><span class='detail-val loss'>SEM STOP</span></span>" }
        $priceHtml   = if ($p.currentPrice -gt 0) { "`$$($p.currentPrice)" } else { "N/A" }

        $positionsHtml += @"
        <div class="position-card" style="border-left-color: $borderColor">
            <div class="pos-header">
                <div class="pos-market">$($p.market -replace 'USDT$','')<span class="pos-quote">/USDT</span></div>
                <div class="pos-badges">
                    <span class="badge $sideClass">$($p.side)</span>
                    <span class="badge badge-lev">${$p.leverage}x</span>
                </div>
            </div>
            <div class="pos-pnl $pnlClass">${pnlSign}$($p.pnl) <span class="pnl-pct">(${pnlSign}$($p.pnlPct)%)</span></div>
            <div class="pos-details">
                <span class="detail-item"><span class="detail-label">Entry</span><span class="detail-val">`$$($p.entry)</span></span>
                <span class="detail-item"><span class="detail-label">Atual</span><span class="detail-val">$priceHtml</span></span>
                <span class="detail-item"><span class="detail-label">Margem</span><span class="detail-val">`$$($p.margin)</span></span>
                $stopHtml
            </div>
        </div>
"@
    }

    # ── Timestamp e status ────────────────────────────────────────────────────
    $timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    $pnlSummaryClass = if ($totalPnl -ge 0) { "profit" } else { "loss" }
    $pnlSign     = if ($totalPnl -ge 0) { "+" } else { "" }

    # ── HTML completo ─────────────────────────────────────────────────────────
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="300">
    <title>ManuHeadFund | Dashboard</title>
    <style>
        :root {
            --bg:       #0d1117;
            --bg2:      #161b22;
            --bg3:      #21262d;
            --border:   #30363d;
            --text:     #e6edf3;
            --muted:    #8b949e;
            --green:    #3fb950;
            --red:      #f85149;
            --blue:     #58a6ff;
            --yellow:   #d29922;
            --purple:   #bc8cff;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1100px; margin: 0 auto; }

        /* Header */
        .header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 24px;
            padding-bottom: 16px;
            border-bottom: 1px solid var(--border);
        }
        .header-title {
            font-size: 22px;
            font-weight: 700;
            color: var(--blue);
            letter-spacing: -0.5px;
        }
        .header-title span { color: var(--muted); font-weight: 400; font-size: 14px; margin-left: 8px; }
        .header-time { color: var(--muted); font-size: 12px; text-align: right; }
        .live-dot {
            display: inline-block;
            width: 8px; height: 8px;
            background: var(--green);
            border-radius: 50%;
            margin-right: 6px;
            animation: pulse 2s infinite;
        }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.4} }

        /* Summary cards */
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 12px;
            margin-bottom: 24px;
        }
        .summary-card {
            background: var(--bg2);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 16px;
        }
        .summary-label {
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            color: var(--muted);
            margin-bottom: 8px;
        }
        .summary-value {
            font-size: 26px;
            font-weight: 700;
            line-height: 1;
        }
        .summary-sub { font-size: 12px; color: var(--muted); margin-top: 4px; }

        /* Positions */
        .section-title {
            font-size: 14px;
            font-weight: 600;
            color: var(--muted);
            text-transform: uppercase;
            letter-spacing: 0.5px;
            margin-bottom: 12px;
        }
        .positions-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 12px;
        }
        .position-card {
            background: var(--bg2);
            border: 1px solid var(--border);
            border-left: 3px solid var(--blue);
            border-radius: 8px;
            padding: 16px;
            transition: background 0.15s;
        }
        .position-card:hover { background: var(--bg3); }
        .pos-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        .pos-market {
            font-size: 18px;
            font-weight: 700;
        }
        .pos-quote { font-size: 12px; color: var(--muted); font-weight: 400; }
        .pos-badges { display: flex; gap: 6px; }
        .badge {
            font-size: 11px;
            font-weight: 600;
            padding: 2px 8px;
            border-radius: 4px;
        }
        .side-long  { background: rgba(63,185,80,0.15);  color: var(--green); }
        .side-short { background: rgba(248,81,73,0.15);  color: var(--red);   }
        .badge-lev  { background: rgba(88,166,255,0.15); color: var(--blue);  }
        .pos-pnl {
            font-size: 22px;
            font-weight: 700;
            margin-bottom: 12px;
        }
        .pnl-pct { font-size: 14px; font-weight: 400; }
        .pos-details {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 8px;
        }
        .detail-item { display: flex; flex-direction: column; }
        .detail-label { font-size: 10px; color: var(--muted); text-transform: uppercase; margin-bottom: 2px; }
        .detail-val { font-size: 13px; font-weight: 500; }

        /* Colors */
        .profit { color: var(--green); }
        .loss   { color: var(--red);   }
        .neutral { color: var(--muted); }

        /* No positions */
        .no-positions {
            background: var(--bg2);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 40px;
            text-align: center;
            color: var(--muted);
            font-size: 14px;
        }

        /* Footer */
        .footer {
            margin-top: 32px;
            padding-top: 16px;
            border-top: 1px solid var(--border);
            display: flex;
            justify-content: space-between;
            align-items: center;
            color: var(--muted);
            font-size: 11px;
        }

        /* Mobile */
        @media (max-width: 600px) {
            body { padding: 12px; }
            .summary { grid-template-columns: repeat(2, 1fr); }
            .positions-grid { grid-template-columns: 1fr; }
            .header { flex-direction: column; align-items: flex-start; gap: 8px; }
        }
    </style>
</head>
<body>
<div class="container">

    <div class="header">
        <div>
            <div class="header-title">ManuHeadFund <span>Trading Dashboard</span></div>
        </div>
        <div class="header-time">
            <span class="live-dot"></span>Live via GitHub Actions<br>
            $timestamp
        </div>
    </div>

    <div class="summary">
        <div class="summary-card">
            <div class="summary-label">Posicoes Abertas</div>
            <div class="summary-value">$($posData.Count)</div>
            <div class="summary-sub">FUTURES</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">PNL Total</div>
            <div class="summary-value $pnlSummaryClass">${pnlSign}$totalPnl</div>
            <div class="summary-sub $pnlSummaryClass">${pnlSign}$totalPnlPct%</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">Margem Total</div>
            <div class="summary-value">`$$totalMargin</div>
            <div class="summary-sub">USDT em uso</div>
        </div>
        <div class="summary-card">
            <div class="summary-label">Capital Futures</div>
            <div class="summary-value">`$$futuresCap</div>
            <div class="summary-sub">Spot: `$$spotCap</div>
        </div>
    </div>

    <div class="section-title">Posicoes</div>
    <div class="positions-grid">
        $positionsHtml
    </div>

    <div class="footer">
        <span>ManuHeadFund &copy; 2026</span>
        <span>Atualiza a cada 5min | GitHub Actions 24/7</span>
    </div>

</div>
</body>
</html>
"@

    $dashboardPath = Join-Path $cpEnv.DashboardDir "index.html"
    $html | Out-File -FilePath $dashboardPath -Encoding UTF8 -Force
    Write-CrossPlatformLog "Dashboard v2 gerado: $dashboardPath" -LogFile "dashboard.log"
    Write-CrossPlatformLog "=== DASHBOARD v2 END ===" -LogFile "dashboard.log"
    exit 0

} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "dashboard.log"
    exit 1
}
