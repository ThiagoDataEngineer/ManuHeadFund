# tori_daemon_reporter.ps1 - HTML Dashboard & JSON reports for Tori Daemon
#
# Generates:
# 1. Interactive HTML dashboard with charts
# 2. JSON export for external analysis
# 3. CSV export for spreadsheet analysis
# 4. Performance statistics
#
# PS 5.1 compatible, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:STATE_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_state.json"
$script:OUTPUT_DIR = Join-Path $PSScriptRoot "..\journal\reports"
$script:REPORT_HTML = Join-Path $script:OUTPUT_DIR "tori_dashboard.html"
$script:REPORT_JSON = Join-Path $script:OUTPUT_DIR "tori_report.json"
$script:REPORT_CSV = Join-Path $script:OUTPUT_DIR "tori_trades.csv"

# ============================================================================
# HELPER: Load daemon state
# ============================================================================

function Load-DaemonState {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:STATE_FILE)) {
        return $null
    }

    try {
        $content = Get-Content -Path $script:STATE_FILE -Raw -Encoding UTF8 -ErrorAction Stop
        return $content | ConvertFrom-Json
    } catch {
        Write-Host "Failed to load state: $_"
        return $null
    }
}

# ============================================================================
# HELPER: Create output directory
# ============================================================================

function Ensure-OutputDirectory {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:OUTPUT_DIR)) {
        New-Item -ItemType Directory -Path $script:OUTPUT_DIR -Force | Out-Null
    }
}

# ============================================================================
# REPORT GENERATOR: HTML Dashboard
# ============================================================================

function Export-HtmlDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$State
    )

    Ensure-OutputDirectory

    $activeSetups = $State.active_setups
    $closedTrades = $State.closed_trades
    $performance = $State.performance

    # Calculate statistics
    $totalActive = $activeSetups.Count
    $longActive = ($activeSetups | Where-Object { $_.trend_type -eq "LONG" }).Count
    $shortActive = ($activeSetups | Where-Object { $_.trend_type -eq "SHORT" }).Count

    $totalClosed = $closedTrades.Count
    $wins = ($closedTrades | Where-Object { $_.unrealized_pnl -gt 0 }).Count
    $losses = ($closedTrades | Where-Object { $_.unrealized_pnl -lt 0 }).Count
    $totalPnL = ($closedTrades | Measure-Object -Property unrealized_pnl -Sum).Sum
    $winRate = if ($totalClosed -gt 0) { ($wins / $totalClosed * 100) } else { 0 }

    # Build active setups table
    $activeTableRows = $activeSetups | ForEach-Object {
        $unregPct = if ($_.entry_price -ne 0) { (($_.unrealized_pnl / $_.entry_price) * 100) } else { 0 }
        $pnlClass = if ($_.unrealized_pnl -ge 0) { "positive" } else { "negative" }

        @"
        <tr>
            <td class="pair">$($_.pair)</td>
            <td class="timeframe">$($_.timeframe)</td>
            <td class="type">$($_.trend_type)</td>
            <td class="score">$($_.confidence_score)</td>
            <td class="price">$('{0:F8}' -f $_.entry_price)</td>
            <td class="price">$('{0:F8}' -f $_.current_price)</td>
            <td class="pnl $pnlClass">$('{0:F2}' -f $_.unrealized_pnl) ($unregPct%)</td>
            <td class="status">$($_.status)</td>
        </tr>
"@
    }

    if ($activeTableRows.Count -eq 0) {
        $activeTableRows = "<tr><td colspan='8' style='text-align:center;'>No active setups</td></tr>"
    } else {
        $activeTableRows = $activeTableRows -join "`n"
    }

    # Build closed trades table
    $closedTableRows = $closedTrades | Select-Object -Last 50 | ForEach-Object {
        $closedPct = if ($_.entry_price -ne 0) { (($_.unrealized_pnl / $_.entry_price) * 100) } else { 0 }
        $pnlClass = if ($_.unrealized_pnl -ge 0) { "positive" } else { "negative" }

        @"
        <tr>
            <td class="pair">$($_.pair)</td>
            <td class="timeframe">$($_.timeframe)</td>
            <td class="type">$($_.trend_type)</td>
            <td class="score">$($_.confidence_score)</td>
            <td class="price">$('{0:F8}' -f $_.entry_price)</td>
            <td class="price">$('{0:F8}' -f $_.target_price)</td>
            <td class="pnl $pnlClass">$('{0:F2}' -f $_.unrealized_pnl) ($closedPct%)</td>
            <td class="status">$($_.status)</td>
        </tr>
"@
    }

    if ($closedTableRows.Count -eq 0) {
        $closedTableRows = "<tr><td colspan='8' style='text-align:center;'>No closed trades</td></tr>"
    } else {
        $closedTableRows = $closedTableRows -join "`n"
    }

    # Build signal breakdown
    $signalBreakdown = @"
        <div class="stat-card">
            <h4>Signal Performance</h4>
            <ul>
                <li><strong>Volume Climax:</strong> <span class="badge">High Precision</span></li>
                <li><strong>RSI Extreme:</strong> <span class="badge">Reversal Confirmation</span></li>
                <li><strong>Fractal Pattern:</strong> <span class="badge">Structural Support</span></li>
                <li><strong>CHoCH:</strong> <span class="badge">Breakout Signal</span></li>
                <li><strong>Volume Profile:</strong> <span class="badge">Cluster Analysis</span></li>
            </ul>
        </div>
"@

    # Create HTML
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tori Daemon Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #1e1e2e 0%, #2d2d44 100%);
            color: #e0e0e0;
            line-height: 1.6;
        }

        header {
            background: rgba(0,0,0,0.3);
            padding: 2rem;
            border-bottom: 2px solid #00d9ff;
            margin-bottom: 2rem;
        }

        header h1 {
            color: #00d9ff;
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
        }

        header p {
            color: #aaa;
            font-size: 0.95rem;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 0 1rem;
        }

        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1.5rem;
            margin-bottom: 2rem;
        }

        .stat-card {
            background: rgba(0, 217, 255, 0.05);
            border: 1px solid rgba(0, 217, 255, 0.2);
            border-radius: 8px;
            padding: 1.5rem;
            transition: all 0.3s ease;
        }

        .stat-card:hover {
            background: rgba(0, 217, 255, 0.1);
            border-color: rgba(0, 217, 255, 0.4);
            transform: translateY(-2px);
        }

        .stat-card h4 {
            color: #00d9ff;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 1rem;
        }

        .stat-card .value {
            font-size: 2rem;
            font-weight: bold;
            color: #fff;
            margin-bottom: 0.25rem;
        }

        .stat-card .label {
            color: #aaa;
            font-size: 0.85rem;
        }

        .stat-card ul {
            list-style: none;
            font-size: 0.9rem;
        }

        .stat-card li {
            padding: 0.5rem 0;
            border-bottom: 1px solid rgba(0, 217, 255, 0.1);
        }

        .stat-card li:last-child {
            border-bottom: none;
        }

        .badge {
            display: inline-block;
            background: rgba(0, 217, 255, 0.2);
            border: 1px solid rgba(0, 217, 255, 0.4);
            padding: 0.25rem 0.75rem;
            border-radius: 4px;
            font-size: 0.8rem;
            color: #00d9ff;
            margin-left: auto;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 2rem;
            font-size: 0.9rem;
        }

        table thead {
            background: rgba(0, 217, 255, 0.1);
            border-bottom: 2px solid rgba(0, 217, 255, 0.3);
        }

        table th {
            padding: 1rem;
            text-align: left;
            color: #00d9ff;
            font-weight: 600;
            text-transform: uppercase;
            font-size: 0.8rem;
        }

        table td {
            padding: 0.75rem 1rem;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
        }

        table tr:last-child td {
            border-bottom: none;
        }

        table tbody tr:hover {
            background: rgba(0, 217, 255, 0.05);
        }

        .pair {
            font-weight: bold;
            color: #fff;
        }

        .timeframe {
            font-size: 0.85rem;
            color: #00d9ff;
        }

        .type {
            padding: 0.25rem 0.75rem;
            border-radius: 4px;
            font-weight: 600;
        }

        .type:contains("LONG") {
            background: rgba(0, 255, 0, 0.1);
            color: #00ff00;
        }

        .type {
            background: rgba(255, 0, 0, 0.1);
            color: #ff0000;
        }

        .score {
            color: #fff;
            font-weight: 500;
        }

        .price {
            font-family: 'Courier New', monospace;
            color: #aaa;
            font-size: 0.85rem;
        }

        .pnl {
            font-weight: 600;
        }

        .pnl.positive {
            color: #00ff00;
        }

        .pnl.negative {
            color: #ff4444;
        }

        .status {
            font-size: 0.85rem;
            color: #aaa;
        }

        section {
            margin-bottom: 3rem;
        }

        section h2 {
            color: #00d9ff;
            font-size: 1.5rem;
            margin-bottom: 1.5rem;
            border-bottom: 2px solid rgba(0, 217, 255, 0.2);
            padding-bottom: 0.75rem;
        }

        footer {
            text-align: center;
            padding: 2rem;
            color: #666;
            border-top: 1px solid rgba(0, 217, 255, 0.1);
            margin-top: 3rem;
        }
    </style>
</head>
<body>
    <header>
        <h1>🎯 Tori Daemon Dashboard</h1>
        <p>24/7 Trendline Confluence Scanner for CoinEx Futures</p>
        <p>Updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC") | Scans Completed: $($performance.total_scans)</p>
    </header>

    <div class="container">
        <section>
            <h2>📊 Performance Overview</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <h4>Active Setups</h4>
                    <div class="value">$totalActive</div>
                    <div class="label">
                        🟢 LONG: $longActive | 🔴 SHORT: $shortActive
                    </div>
                </div>

                <div class="stat-card">
                    <h4>Closed Trades</h4>
                    <div class="value">$totalClosed</div>
                    <div class="label">
                        ✅ Win Rate: $([Math]::Round($winRate, 1))% ($wins Wins, $losses Losses)
                    </div>
                </div>

                <div class="stat-card">
                    <h4>Total P&L</h4>
                    <div class="value" style="color: $(if ($totalPnL -ge 0) { '#00ff00' } else { '#ff4444' });">
                        $('{0:F2}' -f $totalPnL) USDT
                    </div>
                    <div class="label">
                        Average per trade: $('{0:F2}' -f $(if ($totalClosed -gt 0) { $totalPnL / $totalClosed } else { 0 })) USDT
                    </div>
                </div>

                <div class="stat-card">
                    <h4>Avg Confidence</h4>
                    <div class="value">
                        $([Math]::Round($performance.avg_confluence_score, 0))/100
                    </div>
                    <div class="label">
                        Confluence threshold: 80
                    </div>
                </div>

                $signalBreakdown
            </div>
        </section>

        <section>
            <h2>🟢 Active Setups (Currently Open)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Pair</th>
                        <th>TF</th>
                        <th>Type</th>
                        <th>Score</th>
                        <th>Entry</th>
                        <th>Current</th>
                        <th>Unrealized P&L</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    $activeTableRows
                </tbody>
            </table>
        </section>

        <section>
            <h2>📈 Recent Closed Trades (Last 50)</h2>
            <table>
                <thead>
                    <tr>
                        <th>Pair</th>
                        <th>TF</th>
                        <th>Type</th>
                        <th>Score</th>
                        <th>Entry</th>
                        <th>Exit</th>
                        <th>P&L</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
                    $closedTableRows
                </tbody>
            </table>
        </section>
    </div>

    <footer>
        <p>Tori Daemon v1.0 | Production 24/7 Scanner | No investment advice</p>
    </footer>
</body>
</html>
"@

    Set-Content -Path $script:REPORT_HTML -Value $html -Encoding UTF8
    Write-Host "HTML dashboard exported to: $script:REPORT_HTML"
}

# ============================================================================
# REPORT GENERATOR: JSON Export
# ============================================================================

function Export-JsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$State
    )

    Ensure-OutputDirectory

    $report = @{
        generated_at = Get-Date -Format "o"
        timestamp = $State.timestamp
        summary = @{
            total_scans = $State.performance.total_scans
            pairs_analyzed_last_scan = $State.performance.pairs_analyzed
            setups_found_last_scan = $State.performance.setups_found
            avg_confluence_score = $State.performance.avg_confluence_score
            win_rate = $State.performance.win_rate
            total_pnl = $State.performance.total_pnl
        }
        active_setups = @($State.active_setups)
        closed_trades = @($State.closed_trades)
    } | ConvertTo-Json -Depth 5

    Set-Content -Path $script:REPORT_JSON -Value $report -Encoding UTF8
    Write-Host "JSON report exported to: $script:REPORT_JSON"
}

# ============================================================================
# REPORT GENERATOR: CSV Export
# ============================================================================

function Export-CsvReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject[]]$Trades
    )

    Ensure-OutputDirectory

    $csvData = $Trades | ForEach-Object {
        [PSCustomObject]@{
            timestamp = $_.timestamp
            pair = $_.pair
            timeframe = $_.timeframe
            trend_type = $_.trend_type
            confidence_score = $_.confidence_score
            entry_price = $_.entry_price
            target_price = $_.target_price
            stop_loss = $_.stop_loss
            unrealized_pnl = $_.unrealized_pnl
            rr_ratio = $_.rr_ratio
            status = $_.status
        }
    }

    $csvData | Export-Csv -Path $script:REPORT_CSV -NoTypeInformation -Encoding UTF8
    Write-Host "CSV report exported to: $script:REPORT_CSV"
}

# ============================================================================
# PUBLIC INTERFACE: Generate all reports
# ============================================================================

function Export-ToriReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$StateFile = $script:STATE_FILE,

        [Parameter(Mandatory=$false)]
        [ValidateSet("all", "html", "json", "csv")]
        [string]$ReportType = "all"
    )

    Write-Host "Loading daemon state from: $StateFile"
    $state = Load-DaemonState

    if (-not $state) {
        Write-Host "No state available to report on"
        return
    }

    if ($ReportType -eq "html" -or $ReportType -eq "all") {
        Export-HtmlDashboard -State $state
    }

    if ($ReportType -eq "json" -or $ReportType -eq "all") {
        Export-JsonReport -State $state
    }

    if ($ReportType -eq "csv" -or $ReportType -eq "all") {
        $allTrades = @($state.active_setups) + @($state.closed_trades)
        Export-CsvReport -Trades $allTrades
    }

    Write-Host "`nAll reports generated in: $(Resolve-Path $script:OUTPUT_DIR)"
}

# ============================================================================
# EXPORT
# ============================================================================

Export-ModuleMember -Function Export-ToriReports, Export-HtmlDashboard, Export-JsonReport, Export-CsvReport

# If run directly
if ($MyInvocation.InvocationName -ne ".") {
    Export-ToriReports
}
