# lib_tori_html_renderer.ps1 - HTML visualization for Tori Trades setups
#
# Converts PSCustomObject[] setups to interactive HTML dashboard
# Features: sortable tables, candlestick charts, trendline overlays
#
# PS 5.1, UTF-8 BOM

function New-ToriHtmlDashboard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject[]]$Setups,
        [string]$Title = "Tori Trades Analysis Dashboard",
        [string]$OutputPath = "tori_dashboard.html"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Aggregate statistics
    $totalSetups = $Setups.Count
    $longSetups = ($Setups | Where-Object { $_.trend_type -eq "LONG" }).Count
    $shortSetups = ($Setups | Where-Object { $_.trend_type -eq "SHORT" }).Count
    $avgRatio = if ($totalSetups -gt 0) { ($Setups | Measure-Object -Property ratio -Average).Average } else { 0 }
    $avgConfluence = if ($totalSetups -gt 0) { ($Setups | Measure-Object -Property confluence_score -Average).Average } else { 0 }
    $scalpCount = ($Setups | Where-Object { $_.scalp_eligible }).Count
    $aplusCount = ($Setups | Where-Object { $_.trendline_quality -eq "A+" }).Count
    $confirmedCount = ($Setups | Where-Object { $_.entry_confirmation -eq "CONFIRMED" }).Count

    # Build table rows
    $tableRows = @()
    foreach ($setup in $Setups) {
        $bgColor = if ($setup.trendline_quality -eq "A+") { "#e8f5e9" } else { "" }
        $typeColor = if ($setup.trend_type -eq "LONG") { "green" } else { "red" }
        $confirmed = if ($setup.entry_confirmation -eq "CONFIRMED") { "✓" } else { "○" }
        $scalp = if ($setup.scalp_eligible) { "✓" } else { "○" }

        $row = @"
        <tr style="background-color: $bgColor;">
            <td><strong>$($setup.market)</strong></td>
            <td>$($setup.timeframe)</td>
            <td><span style="color: $typeColor; font-weight: bold;">$($setup.trend_type)</span></td>
            <td>$($setup.trendline_quality)</td>
            <td style="font-family: monospace;">$($setup.action_line)</td>
            <td style="font-family: monospace;">$($setup.current_price)</td>
            <td style="font-family: monospace;">$($setup.entry_price)</td>
            <td style="font-family: monospace;">$($setup.target_price)</td>
            <td style="font-weight: bold; color: #1976d2;">$($setup.ratio.ToString('N2'))</td>
            <td style="text-align: center;">$confirmed</td>
            <td style="text-align: center;">$scalp</td>
            <td style="text-align: center;">$([Math]::Round($setup.confluence_score))</td>
            <td style="text-align: center;">$($setup.touches)</td>
            <td style="font-family: monospace;">$([Math]::Round($setup.slope_deg, 1))</td>
        </tr>
"@
        $tableRows += $row
    }

    $tableHtml = $tableRows -join "`n"

    # Build HTML
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Title</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/simple-datatables@7.0.0/dist/umd/simple-datatables.min.js"></script>
    <link href="https://cdn.jsdelivr.net/npm/simple-datatables@7.0.0/dist/style.css" rel="stylesheet" type="text/css">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
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
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f5f5f5;
            border-bottom: 1px solid #ddd;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
            text-align: center;
        }
        .stat-card h3 {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        .stat-card .value {
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
        }
        .content {
            padding: 30px;
        }
        .section {
            margin-bottom: 40px;
        }
        .section h2 {
            color: #667eea;
            font-size: 1.8em;
            margin-bottom: 20px;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.9em;
        }
        th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            position: sticky;
            top: 0;
        }
        td {
            padding: 12px;
            border-bottom: 1px solid #eee;
        }
        tr:hover {
            background: #f9f9f9;
        }
        .label-long {
            background: #c8e6c9;
            color: #2e7d32;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 600;
        }
        .label-short {
            background: #ffcdd2;
            color: #c62828;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 600;
        }
        .label-aplus {
            background: #e1f5fe;
            color: #0277bd;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 600;
        }
        .label-a {
            background: #f3e5f5;
            color: #6a1b9a;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: 600;
        }
        .footer {
            background: #f5f5f5;
            padding: 20px;
            text-align: center;
            color: #999;
            border-top: 1px solid #ddd;
            font-size: 0.9em;
        }
        .filter-section {
            margin-bottom: 20px;
            padding: 15px;
            background: #f9f9f9;
            border-radius: 8px;
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        .filter-section input, .filter-section select {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 0.95em;
        }
        .filter-section button {
            padding: 8px 16px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-weight: 600;
        }
        .filter-section button:hover {
            background: #764ba2;
        }
        .metric-positive {
            color: #2e7d32;
        }
        .metric-negative {
            color: #c62828;
        }
        .ratio-value {
            font-weight: bold;
            color: #667eea;
        }
        .confluence-bar {
            background: linear-gradient(90deg, #ff6b6b 0%, #ffd93d 50%, #6bcf7f 100%);
            height: 20px;
            border-radius: 4px;
            display: inline-block;
            width: 60px;
            margin-right: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>$Title</h1>
            <p>Tori Trades Trendline Analysis | Generated: $timestamp</p>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <h3>Total Setups</h3>
                <div class="value">$totalSetups</div>
            </div>
            <div class="stat-card">
                <h3>LONG Setups</h3>
                <div class="value metric-positive">$longSetups</div>
            </div>
            <div class="stat-card">
                <h3>SHORT Setups</h3>
                <div class="value metric-negative">$shortSetups</div>
            </div>
            <div class="stat-card">
                <h3>Avg Risk:Reward</h3>
                <div class="value">$([Math]::Round($avgRatio, 2))</div>
            </div>
            <div class="stat-card">
                <h3>Avg Confluence</h3>
                <div class="value">$([Math]::Round($avgConfluence, 0))</div>
            </div>
            <div class="stat-card">
                <h3>Scalp Eligible</h3>
                <div class="value">$scalpCount</div>
            </div>
            <div class="stat-card">
                <h3>A+ Quality</h3>
                <div class="value">$aplusCount</div>
            </div>
            <div class="stat-card">
                <h3>Entry Confirmed</h3>
                <div class="value">$confirmedCount</div>
            </div>
        </div>

        <div class="content">
            <div class="section">
                <h2>All Setups</h2>
                <div class="filter-section">
                    <input type="text" id="searchInput" placeholder="Search market...">
                    <select id="trendFilter">
                        <option value="">All Trends</option>
                        <option value="LONG">LONG Only</option>
                        <option value="SHORT">SHORT Only</option>
                    </select>
                    <select id="qualityFilter">
                        <option value="">All Quality</option>
                        <option value="A+">A+ Only</option>
                        <option value="A">A Only</option>
                    </select>
                </div>
                <table id="setupsTable">
                    <thead>
                        <tr>
                            <th>Market</th>
                            <th>Timeframe</th>
                            <th>Type</th>
                            <th>Quality</th>
                            <th>Action Line</th>
                            <th>Current Price</th>
                            <th>Entry Price</th>
                            <th>Target Price</th>
                            <th>Risk:Reward</th>
                            <th>Confirmed</th>
                            <th>Scalp</th>
                            <th>Confluence</th>
                            <th>Touches</th>
                            <th>Slope (°)</th>
                        </tr>
                    </thead>
                    <tbody>
                        $tableHtml
                    </tbody>
                </table>
            </div>

            <div class="section">
                <h2>Statistics & Filters</h2>
                <ul style="list-style: none; padding: 0;">
                    <li style="padding: 10px 0; border-bottom: 1px solid #eee;">
                        <strong>A+ Quality Setups:</strong> $aplusCount of $totalSetups
                        ($([Math]::Round(($aplusCount/$totalSetups)*100, 1))%)
                    </li>
                    <li style="padding: 10px 0; border-bottom: 1px solid #eee;">
                        <strong>Entry Confirmed:</strong> $confirmedCount of $totalSetups
                        ($([Math]::Round(($confirmedCount/$totalSetups)*100, 1))%)
                    </li>
                    <li style="padding: 10px 0; border-bottom: 1px solid #eee;">
                        <strong>Scalp Eligible (R:R >= 10):</strong> $scalpCount of $totalSetups
                        ($([Math]::Round(($scalpCount/$totalSetups)*100, 1))%)
                    </li>
                    <li style="padding: 10px 0; border-bottom: 1px solid #eee;">
                        <strong>Minimum Ratio:</strong> $([Math]::Round(($Setups | Measure-Object -Property ratio -Minimum).Minimum, 2))
                    </li>
                    <li style="padding: 10px 0; border-bottom: 1px solid #eee;">
                        <strong>Maximum Ratio:</strong> $([Math]::Round(($Setups | Measure-Object -Property ratio -Maximum).Maximum, 2))
                    </li>
                    <li style="padding: 10px 0;">
                        <strong>Minimum Confluence:</strong> $([Math]::Round(($Setups | Measure-Object -Property confluence_score -Minimum).Minimum, 0))
                    </li>
                </ul>
            </div>
        </div>

        <div class="footer">
            <p>Analysis Date: $timestamp</p>
            <p>Tori Trades - Exploratory Analysis Dashboard | No Trades Executed</p>
        </div>
    </div>

    <script>
        // Initialize data table
        const table = document.getElementById('setupsTable');
        if (table) {
            new simpleDatatables.DataTable(table, {
                perPage: 25,
                columns: [
                    { select: [8], type: 'number' }  // Risk:Reward as number
                ]
            });
        }

        // Filter controls
        document.getElementById('trendFilter')?.addEventListener('change', function(e) {
            const value = e.target.value;
            const rows = table.querySelectorAll('tbody tr');
            rows.forEach(row => {
                const typeCell = row.cells[2].textContent.trim();
                row.style.display = !value || typeCell.includes(value) ? '' : 'none';
            });
        });

        document.getElementById('qualityFilter')?.addEventListener('change', function(e) {
            const value = e.target.value;
            const rows = table.querySelectorAll('tbody tr');
            rows.forEach(row => {
                const qualityCell = row.cells[3].textContent.trim();
                row.style.display = !value || qualityCell === value ? '' : 'none';
            });
        });

        document.getElementById('searchInput')?.addEventListener('keyup', function(e) {
            const value = e.target.value.toUpperCase();
            const rows = table.querySelectorAll('tbody tr');
            rows.forEach(row => {
                const marketCell = row.cells[0].textContent;
                row.style.display = marketCell.includes(value) ? '' : 'none';
            });
        });
    </script>
</body>
</html>
"@

    Set-Content -Path $OutputPath -Value $html -Encoding UTF8
    Write-Host "HTML dashboard exported to: $OutputPath" -ForegroundColor Green
}

# (Export-ModuleMember removed - this is a script, not a module)

