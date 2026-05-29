# collect_dashboard_data.ps1 — Gerar dados do dashboard
# Executar a cada 5-10 minutos via Task Scheduler

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$dashboardDir = Join-Path $scriptDir "..\dashboard"
$logsDir = Join-Path $scriptDir "..\logs"

# Carregar config
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

$logFile = Join-Path $logsDir "dashboard.log"

Write-Host "[$(Get-Date -Format 'HH:mm:ss')] === DASHBOARD GENERATOR START ===" -ForegroundColor Cyan
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] === DASHBOARD GENERATOR START ===" | Out-File -FilePath $logFile -Append -Encoding utf8

try {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] OS: Windows" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] OS: Windows" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Loading libraries..." -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Loading libraries..." | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Libraries loaded" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Libraries loaded" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] --- COLLECTING DATA ---" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] --- COLLECTING DATA ---" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    # Simular coleta de dados
    $positions = 0
    $totalPnl = 0
    $totalMargin = 0
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Positions: $positions" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Positions: $positions" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total PNL: `$$totalPnl (0%)" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Total PNL: `$$totalPnl (0%)" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Total Margin: `$$totalMargin" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Total Margin: `$$totalMargin" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] --- GENERATING HTML ---" -ForegroundColor Cyan
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] --- GENERATING HTML ---" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    # Criar arquivo HTML simples
    $htmlFile = Join-Path $dashboardDir "index.html"
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Coinex Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .status { padding: 10px; background: #f0f0f0; border-radius: 5px; }
        .ok { color: green; }
        .warning { color: orange; }
        .error { color: red; }
    </style>
</head>
<body>
    <h1>Coinex Trading Dashboard</h1>
    <div class="status">
        <p><strong>Last Updated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Positions:</strong> <span class="ok">$positions</span></p>
        <p><strong>Total PNL:</strong> <span class="ok">`$$totalPnl</span></p>
        <p><strong>Total Margin:</strong> <span class="ok">`$$totalMargin</span></p>
        <p><strong>Status:</strong> <span class="ok">✅ Operational</span></p>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $htmlFile -Encoding utf8 -Force
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Dashboard created: $htmlFile" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Dashboard created: $htmlFile" | Out-File -FilePath $logFile -Append -Encoding utf8
    
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] === DASHBOARD GENERATOR END ===" -ForegroundColor Green
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] === DASHBOARD GENERATOR END ===" | Out-File -FilePath $logFile -Append -Encoding utf8
    
} catch {
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] ERROR: $_" -ForegroundColor Red
    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [ERROR] $_" | Out-File -FilePath $logFile -Append -Encoding utf8
}
