# Generate-BacktestReport.ps1 - Create HTML backtest report dashboard
#
# Generates interactive HTML report with:
# - Equity curve (cumulative P&L over time)
# - Win rate by confluence signal
# - Trade-by-trade details table
# - Drawdown analysis
# - Summary statistics
#
# PS 5.1, UTF-8 BOM

param(
    [Parameter(Mandatory=$true)]
    [string]$BacktestJsonPath,

    [string]$OutputPath = "c:\Users\thiag\Coinex_AI_USER_API\backtest\tori_backtest_report.html"
)

# ============================================================================
# LOAD BACKTEST RESULTS
# ============================================================================

if (-not (Test-Path $BacktestJsonPath)) {
    throw "Backtest JSON not found: $BacktestJsonPath"
}

Write-Host "Loading backtest results from $BacktestJsonPath..." -ForegroundColor Cyan

$jsonContent = Get-Content -Path $BacktestJsonPath -Encoding UTF8 -Raw
$backtest = $jsonContent | ConvertFrom-Json

$metadata = $backtest.metadata
$metrics = $backtest.metrics
$trades = @($backtest.trades)

Write-Host "Loaded $($trades.Count) trades" -ForegroundColor Green

# ============================================================================
# CALCULATE ADDITIONAL METRICS
# ============================================================================

# Equity curve
$cumulativePnL = 0
$equityCurve = @()
$drawdowns = @()

foreach ($i in 0..($trades.Count - 1)) {
    $trade = $trades[$i]
    $cumulativePnL += $trade.pnl_usdt

    $equityCurve += @{
        trade_num = $i + 1
        cumulative_pnl = $cumulativePnL
        pnl = $trade.pnl_usdt
    }
}

# Calculate max drawdown
$runningMax = 0
$maxDD = 0
$maxDDTrade = 0
foreach ($equity in $equityCurve) {
    if ($equity.cumulative_pnl -gt $runningMax) {
        $runningMax = $equity.cumulative_pnl
    }
    $dd = $runningMax - $equity.cumulative_pnl
    if ($dd -gt $maxDD) {
        $maxDD = $dd
        $maxDDTrade = $equity.trade_num
    }
}

# Signal analysis
$signalStats = @{}
foreach ($trade in $trades) {
    $signals = @($trade.confluence_signals_at_entry -split ", " | ForEach-Object { $_.Trim() })
    foreach ($signal in $signals) {
        if ($signal -ne "") {
            if (-not $signalStats.ContainsKey($signal)) {
                $signalStats[$signal] = @{ wins = 0; losses = 0; total = 0 }
            }
            $signalStats[$signal].total += 1
            if ($trade.result -eq "WIN") {
                $signalStats[$signal].wins += 1
            } elseif ($trade.result -eq "LOSS") {
                $signalStats[$signal].losses += 1
            }
        }
    }
}

# ============================================================================
# HTML GENERATION
# ============================================================================

function Generate-HTML {
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tori Trades Backtest Report</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            min-height: 100vh;
        }

        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            overflow: hidden;
        }

        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }

        .header p {
            font-size: 1.1em;
            opacity: 0.9;
        }

        .content {
            padding: 40px;
        }

        .section {
            margin-bottom: 50px;
        }

        .section h2 {
            color: #667eea;
            font-size: 1.8em;
            margin-bottom: 20px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .metric-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            text-align: center;
        }

        .metric-label {
            font-size: 0.9em;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .metric-value {
            font-size: 2.2em;
            font-weight: bold;
            margin-top: 10px;
        }

        .metric-card.positive {
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
        }

        .metric-card.negative {
            background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%);
        }

        .chart-container {
            position: relative;
            height: 400px;
            margin-bottom: 30px;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
        }

        .signal-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 15px;
        }

        .signal-card {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }

        .signal-name {
            font-weight: bold;
            color: #667eea;
            margin-bottom: 10px;
        }

        .signal-stat {
            font-size: 0.9em;
            display: flex;
            justify-content: space-between;
            margin: 5px 0;
        }

        .win-rate {
            font-weight: bold;
            color: #11998e;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            border: 1px solid #ddd;
            border-radius: 8px;
            overflow: hidden;
        }

        th {
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }

        td {
            padding: 12px;
            border-bottom: 1px solid #eee;
        }

        tr:hover {
            background: #f8f9fa;
        }

        .result-win {
            color: #11998e;
            font-weight: bold;
        }

        .result-loss {
            color: #eb3349;
            font-weight: bold;
        }

        .result-breakeven {
            color: #f59e0b;
            font-weight: bold;
        }

        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
            border-top: 1px solid #ddd;
        }

        @media (max-width: 768px) {
            .header h1 {
                font-size: 1.8em;
            }

            .metrics-grid {
                grid-template-columns: repeat(2, 1fr);
            }

            table {
                font-size: 0.9em;
            }

            td, th {
                padding: 8px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Tori Trades Backtest Report</h1>
            <p>Walk-forward historical simulation with enhanced confluence detection</p>
            <p style="font-size: 0.9em; margin-top: 10px;">Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        </div>

        <div class="content">
            <!-- SUMMARY SECTION -->
            <div class="section">
                <h2>Summary Statistics</h2>
                <div class="metrics-grid">
                    <div class="metric-card">
                        <div class="metric-label">Total Trades</div>
                        <div class="metric-value">$($metrics.total_trades)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Win Rate</div>
                        <div class="metric-value">$($metrics.win_rate_pct)%</div>
                    </div>
                    <div class="metric-card $(if ($metrics.total_pnl -gt 0) { 'positive' } else { 'negative' })">
                        <div class="metric-label">Total P&L</div>
                        <div class="metric-value">`$$($metrics.total_pnl)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Profit Factor</div>
                        <div class="metric-value">$($metrics.profit_factor)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Avg Hold Time</div>
                        <div class="metric-value">$($metrics.avg_hold_min)min</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Expectancy</div>
                        <div class="metric-value">`$$($metrics.expectancy)</div>
                    </div>
                </div>

                <div class="metrics-grid">
                    <div class="metric-card">
                        <div class="metric-label">Wins</div>
                        <div class="metric-value">$($metrics.wins)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Losses</div>
                        <div class="metric-value">$($metrics.losses)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Breakeven</div>
                        <div class="metric-value">$($metrics.breakeven)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Max Consecutive Losses</div>
                        <div class="metric-value">$($metrics.max_consecutive_losses)</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Max Drawdown</div>
                        <div class="metric-value">`$$([Math]::Round($maxDD, 2))</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-label">Avg Win / Loss</div>
                        <div class="metric-value">`$$($metrics.avg_win_usdt) / `$$($metrics.avg_loss_usdt)</div>
                    </div>
                </div>
            </div>

            <!-- EQUITY CURVE -->
            <div class="section">
                <h2>Equity Curve</h2>
                <div class="chart-container">
                    <canvas id="equityChart"></canvas>
                </div>
            </div>

            <!-- CONFLUENCE SIGNALS ANALYSIS -->
            <div class="section">
                <h2>Confluence Signal Performance</h2>
                <div class="signal-grid">
"@

    foreach ($signal in ($signalStats.Keys | Sort-Object)) {
        $stat = $signalStats[$signal]
        $winRate = if ($stat.total -gt 0) { ($stat.wins / $stat.total) * 100 } else { 0 }

        $html += @"
                    <div class="signal-card">
                        <div class="signal-name">$signal</div>
                        <div class="signal-stat">
                            <span>Total Signals:</span>
                            <span>$($stat.total)</span>
                        </div>
                        <div class="signal-stat">
                            <span>Wins:</span>
                            <span style="color: #11998e;">$($stat.wins)</span>
                        </div>
                        <div class="signal-stat">
                            <span>Losses:</span>
                            <span style="color: #eb3349;">$($stat.losses)</span>
                        </div>
                        <div class="signal-stat">
                            <span class="win-rate">Win Rate: $([Math]::Round($winRate, 1))%</span>
                        </div>
                    </div>
"@
    }

    $html += @"
                </div>
            </div>

            <!-- TRADE DETAILS -->
            <div class="section">
                <h2>Trade-by-Trade Details (Latest 50)</h2>
                <table>
                    <thead>
                        <tr>
                            <th>Pair</th>
                            <th>Type</th>
                            <th>Entry</th>
                            <th>Exit</th>
                            <th>P&L %</th>
                            <th>P&L USD</th>
                            <th>Result</th>
                            <th>Hold</th>
                            <th>Confidence</th>
                        </tr>
                    </thead>
                    <tbody>
"@

    # Show latest 50 trades
    $tradesToShow = @($trades | Select-Object -Last 50)
    foreach ($trade in $tradesToShow) {
        $resultClass = switch ($trade.result) {
            "WIN" { "result-win" }
            "LOSS" { "result-loss" }
            "BREAKEVEN" { "result-breakeven" }
            default { "" }
        }

        $html += @"
                        <tr>
                            <td>$($trade.pair)</td>
                            <td>$($trade.setup_type)</td>
                            <td>`$$([Math]::Round($trade.entry_price, 8))</td>
                            <td>`$$([Math]::Round($trade.exit_price, 8))</td>
                            <td>$($trade.pnl_pct)%</td>
                            <td>`$$($trade.pnl_usdt)</td>
                            <td class="$resultClass">$($trade.result)</td>
                            <td>$($trade.hold_time_min)min</td>
                            <td>$([Math]::Round($trade.confluence_score, 0))</td>
                        </tr>
"@
    }

    $html += @"
                    </tbody>
                </table>
            </div>

            <!-- BACKTEST PARAMETERS -->
            <div class="section">
                <h2>Backtest Parameters</h2>
                <table>
                    <tr>
                        <td><strong>Number of Pairs</strong></td>
                        <td>$($metadata.num_pairs)</td>
                    </tr>
                    <tr>
                        <td><strong>Number of Candles per Pair</strong></td>
                        <td>$($metadata.num_candles) (~$([Math]::Round($metadata.num_candles / 24, 0)) days)</td>
                    </tr>
                    <tr>
                        <td><strong>Minimum Confluence Score</strong></td>
                        <td>$($metadata.min_confluence_score)</td>
                    </tr>
                    <tr>
                        <td><strong>Minimum Risk:Reward</strong></td>
                        <td>1:$($metadata.risk_reward)</td>
                    </tr>
                    <tr>
                        <td><strong>Backtest Date</strong></td>
                        <td>$($metadata.backtest_date)</td>
                    </tr>
                </table>
            </div>
        </div>

        <div class="footer">
            <p>Tori Trades Confluence Backtest Engine | PS 5.1</p>
            <p style="font-size: 0.9em; margin-top: 10px;">Disclaimer: Backtesting results do not guarantee future performance. Past performance is not indicative of future results.</p>
        </div>
    </div>

    <script>
        // Equity Curve Data
        const equityData = [
"@

    foreach ($equity in $equityCurve) {
        $html += "            { trade: $($equity.trade_num), pnl: $($equity.cumulative_pnl) },`n"
    }

    $html += @"
        ];

        const equityCtx = document.getElementById('equityChart').getContext('2d');
        new Chart(equityCtx, {
            type: 'line',
            data: {
                labels: equityData.map((d, i) => 'Trade ' + d.trade),
                datasets: [{
                    label: 'Cumulative P&L (USD)',
                    data: equityData.map(d => d.pnl),
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    borderWidth: 2,
                    tension: 0.4,
                    fill: true,
                    pointBackgroundColor: '#667eea',
                    pointBorderColor: '#fff',
                    pointBorderWidth: 2,
                    pointRadius: 3,
                    pointHoverRadius: 5
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: true,
                        labels: {
                            font: { size: 12 }
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            callback: function(value) {
                                return '\$' + value.toFixed(2);
                            }
                        }
                    }
                }
            }
        });
    </script>
</body>
</html>
"@

    return $html
}

# ============================================================================
# GENERATE AND SAVE
# ============================================================================

Write-Host "Generating HTML report..." -ForegroundColor Cyan

$html = Generate-HTML

# Ensure output directory exists
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $html -Encoding UTF8

Write-Host "Report generated: $OutputPath" -ForegroundColor Green
Write-Host "Open in browser to view interactive dashboard" -ForegroundColor Green
