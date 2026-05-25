# scripts\position_risk_cron.ps1
# Position Risk Manager - CROSS-PLATFORM (Windows/Linux)
# Gestão automática de risco
# 2026-05-24

$ErrorActionPreference = "Stop"

# Setup Cross-Platform
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) { . $configLocal }

# Inicializar ambiente
$env = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== POSITION RISK MANAGER START ===" -LogFile "position_risk.log"
Write-CrossPlatformLog "OS: $(if ($env.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "position_risk.log"

# Validar credenciais
if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "position_risk.log"
    exit 1
}

# Carregar bibliotecas
try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "position_risk.log"
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    Write-CrossPlatformLog "Libraries loaded" -LogFile "position_risk.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "position_risk.log"
    exit 1
}

# Executar
try {
    Write-CrossPlatformLog "--- SCANNING POSITIONS ---" -LogFile "position_risk.log"
    
    $positions = @(CoinEx-GetPendingPositions)
    Write-CrossPlatformLog "Positions found: $($positions.Count)" -LogFile "position_risk.log"
    
    foreach ($pos in $positions) {
        $pnl = [math]::Round([double]$pos.unrealized_pnl, 2)
        $pnlPct = if ($pos.margin -gt 0) { [math]::Round(($pnl / $pos.margin) * 100, 2) } else { 0 }
        $leverage = [math]::Round([double]$pos.leverage, 1)
        
        $pnlColor = if ($pnl -ge 0) { "INFO" } else { "WARN" }
        Write-CrossPlatformLog "  $($pos.market): Leverage ${leverage}x | PNL `$$pnl ($pnlPct%)" -Level $pnlColor -LogFile "position_risk.log"
        
        # Alertas
        if ($leverage -gt 20) {
            Write-CrossPlatformLog "  WARNING: High leverage ${leverage}x on $($pos.market)" -Level WARN -LogFile "position_risk.log"
        }
        
        if ($pnlPct -lt -10) {
            Write-CrossPlatformLog "  WARNING: Large loss $pnlPct% on $($pos.market)" -Level WARN -LogFile "position_risk.log"
        }
    }
    
    Write-CrossPlatformLog "=== POSITION RISK MANAGER END ===" -LogFile "position_risk.log"
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "position_risk.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "position_risk.log"
    exit 1
}
