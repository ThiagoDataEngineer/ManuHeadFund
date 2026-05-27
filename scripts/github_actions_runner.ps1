# github_actions_runner.ps1
# Script wrapper para rodar no GitHub Actions (Ubuntu)
# Compatível com Linux e Windows

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("trailing-stop", "position-risk", "dashboard")]
    [string]$Job
)

$ErrorActionPreference = "Stop"

# Detectar OS
$isLinux = $PSVersionTable.Platform -eq "Unix" -or $PSVersionTable.OS -like "*Linux*"
$pathSep = if ($isLinux) { "/" } else { "\" }

# Root do projeto
$projectRoot = $PSScriptRoot | Split-Path -Parent

Write-Host "=== GitHub Actions Runner ===" -ForegroundColor Cyan
Write-Host "Job: $Job" -ForegroundColor White
Write-Host "OS: $(if ($isLinux) { 'Linux' } else { 'Windows' })" -ForegroundColor Gray
Write-Host "Root: $projectRoot" -ForegroundColor Gray
Write-Host ""

# Criar diretórios necessários
$dirs = @("agents", "journal", "logs", "dashboard")
foreach ($dir in $dirs) {
    $path = Join-Path $projectRoot $dir
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# Verificar credenciais
if (-not $env:COINEX_ACCESS_ID -or -not $env:COINEX_SECRET_KEY) {
    Write-Host "ERROR: Credenciais não configuradas" -ForegroundColor Red
    Write-Host "COINEX_ACCESS_ID: $($env:COINEX_ACCESS_ID -ne $null)" -ForegroundColor Gray
    Write-Host "COINEX_SECRET_KEY: $($env:COINEX_SECRET_KEY -ne $null)" -ForegroundColor Gray
    exit 1
}

# Executar job específico
try {
    switch ($Job) {
        "trailing-stop" {
            Write-Host "=== TRAILING STOP MONITOR ===" -ForegroundColor Yellow
            
            # Carregar libs necessárias (ordem importa!)
            . (Join-Path $projectRoot "agents" "config.ps1")
            . (Join-Path $projectRoot "agents" "lib_coinex.ps1")
            . (Join-Path $projectRoot "agents" "lib_trailing.ps1")
            . (Join-Path $projectRoot "agents" "lib_trailing_orphan_detection.ps1")
            
            # Buscar posições
            Write-Host "Buscando posições na exchange..." -ForegroundColor Gray
            $positions = @(CoinEx-GetPendingPositions)
            Write-Host "Posições encontradas: $($positions.Count)" -ForegroundColor White
            
            # Detectar órfãs
            Write-Host "Detectando órfãs..." -ForegroundColor Gray
            $orphanSync = Sync-OrphanPositions
            
            if ($orphanSync.success) {
                Write-Host "Exchange positions: $($orphanSync.total_exchange)" -ForegroundColor White
                Write-Host "Orphans detected: $($orphanSync.orphans_detected)" -ForegroundColor White
                Write-Host "Registered: $($orphanSync.registered)" -ForegroundColor Green
                
                if ($orphanSync.orphans_detected -gt 0) {
                    foreach ($detail in $orphanSync.details) {
                        if ($detail.registered) {
                            Write-Host "  ✓ $($detail.market) registered" -ForegroundColor Green
                        }
                    }
                }
            } else {
                Write-Host "Orphan detection error: $($orphanSync.error)" -ForegroundColor Red
            }

            # Phantom reconciliation: posicoes locais active mas nao na exchange
            # (oposto de orphan - fecha posicoes ghost que ficam stuck no trailing)
            if (Get-Command Reconcile-PhantomPositions -ErrorAction SilentlyContinue) {
                Write-Host "Reconciling phantoms..." -ForegroundColor Gray
                $phantomSync = Reconcile-PhantomPositions
                if ($phantomSync.phantoms_detected -gt 0) {
                    Write-Host "Phantoms detected: $($phantomSync.phantoms_detected) closed: $($phantomSync.closed)" -ForegroundColor Yellow
                    foreach ($d in $phantomSync.details) {
                        $sym = if ($d.closed) { "OK" } else { "FAIL" }
                        Write-Host "  $sym $($d.market) exit=$($d.exitPrice)" -ForegroundColor $(if ($d.closed) { "Green" } else { "Red" })
                    }
                }
            }

            # Verificar trailing positions
            $localPositions = @(Get-TrailingPositions | Where-Object { $_.active })
            Write-Host "Local active positions: $($localPositions.Count)" -ForegroundColor White
            
            Write-Host "✓ Trailing Stop Monitor OK" -ForegroundColor Green
        }
        
        "position-risk" {
            Write-Host "=== POSITION RISK MANAGER ===" -ForegroundColor Yellow
            
            # Verificar se deve rodar (a cada 15min)
            $minute = (Get-Date).Minute
            if ($minute % 15 -ne 0) {
                Write-Host "Skipped (runs every 15min, current: ${minute}min)" -ForegroundColor Yellow
                exit 0
            }
            
            # Carregar libs
            . (Join-Path $projectRoot "agents" "config.ps1")
            . (Join-Path $projectRoot "agents" "lib_coinex.ps1")
            
            # Buscar posições
            Write-Host "Checking positions..." -ForegroundColor Gray
            $positions = @(CoinEx-GetPendingPositions)
            Write-Host "Positions: $($positions.Count)" -ForegroundColor White
            
            foreach ($pos in $positions) {
                $pnl = [math]::Round([double]$pos.unrealized_pnl, 2)
                $pnlColor = if ($pnl -ge 0) { "Green" } else { "Red" }
                Write-Host "  $($pos.market): PNL `$$pnl" -ForegroundColor $pnlColor
            }
            
            Write-Host "✓ Position Risk Manager OK" -ForegroundColor Green
        }
        
        "dashboard" {
            Write-Host "=== DASHBOARD GENERATOR ===" -ForegroundColor Yellow
            
            # Carregar libs
            . (Join-Path $projectRoot "agents" "config.ps1")
            . (Join-Path $projectRoot "agents" "lib_coinex.ps1")
            
            # Coletar dados
            Write-Host "Collecting data..." -ForegroundColor Gray
            $positions = @(CoinEx-GetPendingPositions)
            
            # Criar dashboard simples
            $dashboardPath = Join-Path $projectRoot "dashboard" "index.html"
            $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Trading Dashboard</title>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="300">
    <style>
        body { font-family: Arial; background: #1a1a1a; color: #fff; padding: 20px; }
        .header { font-size: 24px; margin-bottom: 20px; }
        .position { background: #2a2a2a; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .profit { color: #4caf50; }
        .loss { color: #f44336; }
        .timestamp { color: #888; font-size: 12px; }
    </style>
</head>
<body>
    <div class="header">📊 Trading Dashboard</div>
    <div class="timestamp">Updated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC")</div>
    <div class="timestamp">Positions: $($positions.Count)</div>
    
    $(foreach ($pos in $positions) {
        $pnl = [math]::Round([double]$pos.unrealized_pnl, 2)
        $pnlClass = if ($pnl -ge 0) { "profit" } else { "loss" }
        $side = $pos.side.ToUpper()
        @"
    <div class="position">
        <strong>$($pos.market)</strong> - $side<br>
        Entry: `$$($pos.avg_entry_price)<br>
        PNL: <span class="$pnlClass">`$$pnl</span>
    </div>
"@
    })
</body>
</html>
"@
            
            $html | Out-File -FilePath $dashboardPath -Encoding UTF8 -Force
            Write-Host "Dashboard created: $dashboardPath" -ForegroundColor White
            Write-Host "✓ Dashboard Generator OK" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    Write-Host "Job completed successfully" -ForegroundColor Green
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
    exit 1
}
