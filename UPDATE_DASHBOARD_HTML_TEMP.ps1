# UPDATE_DASHBOARD_COMPLETO.ps1
# Dashboard HTML COMPLETO com todas as informações
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

Write-Host "=== ATUALIZANDO DASHBOARD COMPLETO ===" -ForegroundColor Cyan
Write-Host ""

try {
    # 1. POSIÇÕES
    Write-Host "Buscando posicoes..." -ForegroundColor Yellow
    $positions = CoinEx-GetPendingPositions
    
    # Buscar preços atuais
    $prices = @{}
    if ($positions -and $positions.Count -gt 0) {
        foreach ($pos in $positions) {
            try {
                $ticker = CoinEx-GetFuturesTicker -market $pos.market
                $prices[$pos.market] = [double]$ticker.last
            }
            catch {
                $prices[$pos.market] = 0
            }
        }
    }
    
    # 2. CAPITAL
    Write-Host "Buscando capital..." -ForegroundColor Yellow
    $capital = CoinEx-GetFuturesCapitalUSDT
    
    # 3. TASKS
    Write-Host "Buscando tasks..." -ForegroundColor Yellow
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
    
    # 4. LOGS
    Write-Host "Lendo logs..." -ForegroundColor Yellow
    $logFile = "$PSScriptRoot\logs\trailing_stop_monitor.log"
    $logs = @()
    if (Test-Path $logFile) {
        $logs = Get-Content $logFile -Tail 50 -ErrorAction SilentlyContinue
    }
    
    # 5. VALIDAÇÃO DE STOPS
    Write-Host "Validando stops..." -ForegroundColor Yellow
    $positionsWithoutStop = 0
    $positionsWithTrailing = 0
    
    # Calcular métricas
    $totalPnl = 0
    $positionsHtml = ""
    
    if ($positions -and $positions.Count -gt 0) {
        foreach ($pos in $positions) {
            $market = $pos.market
            $side = $pos.side
            $entry = [double]$pos.avg_entry_price
            $current = if ($prices.ContainsKey($market)) { $prices[$market] } else { 0 }
            $pnl = [double]$pos.unrealized_pnl
            $pnlRate = [double]$pos.unrealized_pnl_rate
            $leverage = $pos.leverage
            $stopLoss = [double]$pos.stop_loss_price
            $takeProfit = [double]$pos.take_profit_price
            $margin = [double]$pos.ath_margin_size
            
            $totalPnl += $pnl
            
            if ($stopLoss -le 0) { $positionsWithoutStop++ }
            if ($pnlRate -ge 3) { $positionsWithTrailing++ }
            
            $sideClass = if ($side -eq "long") { "long" } else { "short" }
            $pnlClass = if ($pnl -gt 0) { "status-positive" } elseif ($pnl -lt 0) { "status-negative" } else { "status-neutral" }
            
            $trailingStatus = if ($pnlRate -ge 3) {
                "<span class='trailing-active'><i class='fas fa-chart-line'></i> TRAILING ATIVO</span>"
            } elseif ($stopLoss -le 0) {
                "<span class='status-negative'><i class='fas fa-exclamation-triangle'></i> SEM STOP LOSS</span>"
            } else {
                "<span class='trailing-waiting'>Aguardando +3%</span>"
            }
            
            $stopDisplay = if ($stopLoss -gt 0) { "`$$([Math]::Round($stopLoss, 2))" } else { "<span class='status-negative'>NÃO CONFIGURADO</span>" }
            $tpDisplay = if ($takeProfit -gt 0) { "`$$([Math]::Round($takeProfit, 2))" } else { "<span class='status-neutral'>-</span>" }
            
            $positionsHtml += @"
                        <tr>
                            <td><strong>$market</strong></td>
                            <td><span class='badge $sideClass'>$($side.ToUpper())</span></td>
                            <td>`$$([Math]::Round($entry, 4))</td>
                            <td>`$$([Math]::Round($current, 4))</td>
                            <td class='$pnlClass'>$([Math]::Round($pnlRate, 2))%</td>
                            <td class='$pnlClass'>`$$([Math]::Round($pnl, 2))</td>
                            <td>${leverage}x</td>
                            <td>`$$([Math]::Round($margin, 2))</td>
                            <td>$stopDisplay</td>
                            <td>$tpDisplay</td>
                            <td>$trailingStatus</td>
                        </tr>
"@
        }
    } else {
        $positionsHtml = @"
                        <tr>
                            <td colspan='11' style='text-align: center; padding: 40px; color: #5c6bc0;'>
                                <i class='fas fa-inbox' style='font-size: 2em; display: block; margin-bottom: 10px; opacity: 0.4;'></i>
                                Nenhuma posição aberta
                            </td>
                        </tr>
"@
    }
    
    # TASKS HTML
    $tasksHtml = ""
    $tasksRunning = 0
    $tasksReady = 0
    $tasksDisabled = 0
    
    foreach ($task in $tasks) {
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
        $status = $task.State
        $lastRun = $info.LastRunTime
        $nextRun = $info.NextRunTime
        $lastResult = $info.LastTaskResult
        
        switch ($status) {
            "Running" { $tasksRunning++; $statusClass = "status-info"; $statusIcon = "fa-spinner fa-spin" }
            "Ready" { $tasksReady++; $statusClass = "status-positive"; $statusIcon = "fa-check-circle" }
            "Disabled" { $tasksDisabled++; $statusClass = "status-neutral"; $statusIcon = "fa-ban" }
            default { $statusClass = "status-negative"; $statusIcon = "fa-exclamation-circle" }
        }
        
        $resultClass = if ($lastResult -eq 0) { "status-positive" } else { "status-negative" }
        $resultText = if ($lastResult -eq 0) { "OK" } else { "ERRO" }
        
        $tasksHtml += @"
                        <tr>
                            <td><strong>$($task.TaskName)</strong></td>
                            <td><span class='$statusClass'><i class='fas $statusIcon'></i> $status</span></td>
                            <td>$($lastRun.ToString('dd/MM HH:mm'))</td>
                            <td>$($nextRun.ToString('dd/MM HH:mm'))</td>
                            <td><span class='$resultClass'>$resultText</span></td>
                        </tr>
"@
    }
    
    # LOGS HTML
    $logsHtml = ""
    if ($logs -and $logs.Count -gt 0) {
        foreach ($line in $logs) {
            $lineClass = "log-normal"
            $icon = "fa-circle"
            
            if ($line -match "ERROR|CRITICAL|ALERT") {
                $lineClass = "log-error"
                $icon = "fa-exclamation-circle"
            }
            elseif ($line -match "WARNING|WARN") {
                $lineClass = "log-warning"
                $icon = "fa-exclamation-triangle"
            }
            elseif ($line -match "SUCCESS|UPDATED|OK") {
                $lineClass = "log-success"
                $icon = "fa-check-circle"
            }
            
            $logsHtml += "<div class='log-line $lineClass'><i class='fas $icon'></i> $([System.Web.HttpUtility]::HtmlEncode($line))</div>`n"
        }
    } else {
        $logsHtml = "<div class='log-line log-normal'><i class='fas fa-info-circle'></i> Nenhum log disponível</div>"
    }
    
    $posCount = if ($positions) { $positions.Count } else { 0 }
    $totalPnlClass = if ($totalPnl -gt 0) { "positive" } elseif ($totalPnl -lt 0) { "negative" } else { "" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Gerar HTML COMPLETO
    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
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
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
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
        .container { max-width: 1900px; margin: 0 auto; padding: 30px; }
        
        /* Metrics Grid */
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(6, 1fr);
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
        
        /* Panel */
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
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .panel-body { padding: 24px; }
        
        /* Table */
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.85em;
        }
        th {
            background: rgba(100, 181, 246, 0.08);
            color: #7986cb;
            padding: 12px 14px;
            text-align: left;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            font-size: 0.7em;
            border-bottom: 1px solid rgba(100, 181, 246, 0.15);
        }
        td {
            padding: 14px;
            border-bottom: 1px solid rgba(100, 181, 246, 0.06);
            color: #c5cae9;
        }
        tr:hover { background: rgba(100, 181, 246, 0.04); }
        
        /* Badge */
        .badge {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.7em;
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
        
        /* Status */
        .status-positive { color: #66bb6a; font-weight: 600; }
        .status-negative { color: #ef5350; font-weight: 600; }
        .status-neutral { color: #9fa8da; font-weight: 600; }
        .status-info { color: #42a5f5; font-weight: 600; }
        
        /* Trailing */
        .trailing-active {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 5px 12px;
            background: rgba(102, 187, 106, 0.15);
            color: #66bb6a;
            border: 1px solid rgba(102, 187, 106, 0.3);
            border-radius: 4px;
            font-size: 0.7em;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .trailing-active i { animation: pulse 2s ease-in-out infinite; }
        .trailing-waiting {
            color: #5c6bc0;
            font-size: 0.7em;
            text-transform: uppercase;
            font-weight: 500;
        }
        
        /* Logs */
        .logs-container {
            background: #0d1117;
            border-radius: 6px;
            padding: 16px;
            max-height: 400px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 0.8em;
        }
        .log-line {
            padding: 6px 10px;
            margin-bottom: 4px;
            border-left: 3px solid transparent;
            border-radius: 3px;
        }
        .log-normal { color: #9fa8da; border-left-color: #5c6bc0; }
        .log-success { color: #66bb6a; border-left-color: #66bb6a; background: rgba(102, 187, 106, 0.05); }
        .log-warning { color: #ffa726; border-left-color: #ffa726; background: rgba(255, 167, 38, 0.05); }
        .log-error { color: #ef5350; border-left-color: #ef5350; background: rgba(239, 83, 80, 0.05); }
        .log-line i { margin-right: 8px; opacity: 0.7; }
        
        /* Grid Layout */
        .grid-2 {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 24px;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        @media (max-width: 1400px) {
            .metrics-grid { grid-template-columns: repeat(3, 1fr); }
            .grid-2 { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="logo"><i class="fas fa-chart-line"></i> CoinEx Trading Dashboard</div>
        <div class="timestamp"><i class="far fa-clock"></i> $timestamp UTC | Auto-refresh: 5 min</div>
    </div>
    
    <div class="container">
        <!-- Metrics Grid -->
        <div class="metrics-grid">
            <div class="metric-card info">
                <div class="label"><i class="fas fa-layer-group"></i> Posições Abertas</div>
                <div class="value">$posCount</div>
            </div>
            <div class="metric-card $totalPnlClass">
                <div class="label"><i class="fas fa-dollar-sign"></i> PNL Total</div>
                <div class="value">`$$([Math]::Round($totalPnl, 2))</div>
            </div>
            <div class="metric-card">
                <div class="label"><i class="fas fa-wallet"></i> Capital Disponível</div>
                <div class="value">`$$([Math]::Round($capital, 2))</div>
            </div>
            <div class="metric-card $(if ($positionsWithoutStop -gt 0) { 'warning' } else { 'positive' })">
                <div class="label"><i class="fas fa-shield-alt"></i> Sem Stop Loss</div>
                <div class="value">$positionsWithoutStop</div>
            </div>
            <div class="metric-card $(if ($positionsWithTrailing -gt 0) { 'positive' } else { 'info' })">
                <div class="label"><i class="fas fa-chart-line"></i> Trailing Ativo</div>
                <div class="value">$positionsWithTrailing</div>
            </div>
            <div class="metric-card positive">
                <div class="label"><i class="fas fa-tasks"></i> Tasks Ativas</div>
                <div class="value">$tasksReady</div>
            </div>
        </div>
        
        <!-- Positions -->
        <div class="panel">
            <div class="panel-header">
                <span><i class="fas fa-chart-bar"></i> Posições Abertas</span>
                <span style="font-size: 0.9em; color: #9fa8da;">$posCount posição(ões)</span>
            </div>
            <div class="panel-body">
                <table>
                    <thead>
                        <tr>
                            <th>Market</th>
                            <th>Side</th>
                            <th>Entry</th>
                            <th>Current</th>
                            <th>PNL %</th>
                            <th>PNL USD</th>
                            <th>Leverage</th>
                            <th>Margin</th>
                            <th>Stop Loss</th>
                            <th>Take Profit</th>
                            <th>Trailing</th>
                        </tr>
                    </thead>
                    <tbody>
$positionsHtml
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="grid-2">
            <!-- Tasks -->
            <div class="panel">
                <div class="panel-header">
                    <span><i class="fas fa-cogs"></i> Tasks Agendadas</span>
                    <span style="font-size: 0.9em; color: #9fa8da;">$($tasks.Count) task(s) | $tasksReady ativas</span>
                </div>
                <div class="panel-body">
                    <table>
                        <thead>
                            <tr>
                                <th>Task</th>
                                <th>Status</th>
                                <th>Última Exec</th>
                                <th>Próxima Exec</th>
                                <th>Resultado</th>
                            </tr>
                        </thead>
                        <tbody>
$tasksHtml
                        </tbody>
                    </table>
                </div>
            </div>
            
            <!-- Logs -->
            <div class="panel">
                <div class="panel-header">
                    <span><i class="fas fa-file-alt"></i> Logs do Sistema</span>
                    <span style="font-size: 0.9em; color: #9fa8da;">Últimas 50 linhas</span>
                </div>
                <div class="panel-body">
                    <div class="logs-container">
$logsHtml
                    </div>
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"@
    
    # Salvar HTML com encoding correto
    $htmlPath = "$PSScriptRoot\dashboard\index.html"
    [System.IO.File]::WriteAllText($htmlPath, $html, [System.Text.Encoding]::UTF8)
    
    Write-Host ""
    Write-Host "=== DASHBOARD COMPLETO ATUALIZADO ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Arquivo: $htmlPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "METRICAS:" -ForegroundColor Yellow
    Write-Host "  Posicoes: $posCount" -ForegroundColor White
    Write-Host "  PNL Total: `$$([Math]::Round($totalPnl, 2))" -ForegroundColor $(if ($totalPnl -gt 0) { "Green" } else { "Red" })
    Write-Host "  Capital: `$$([Math]::Round($capital, 2))" -ForegroundColor White
    Write-Host "  Sem Stop Loss: $positionsWithoutStop" -ForegroundColor $(if ($positionsWithoutStop -gt 0) { "Red" } else { "Green" })
    Write-Host "  Trailing Ativo: $positionsWithTrailing" -ForegroundColor $(if ($positionsWithTrailing -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Tasks Ativas: $tasksReady / $($tasks.Count)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "=== ERRO ===" -ForegroundColor Red
    Write-Host "$_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}
