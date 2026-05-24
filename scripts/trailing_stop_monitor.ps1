# scripts\trailing_stop_monitor.ps1
# Monitor de Trailing Stop - Executa a cada 5 minutos via Task Scheduler
# 2026-05-24

# Carregar libs
$scriptRoot = Split-Path -Parent $PSScriptRoot
. "$scriptRoot\agents\config.ps1"
. "$scriptRoot\agents\lib_coinex.ps1"
. "$scriptRoot\agents\lib_coinex_position_management.ps1"
. "$scriptRoot\agents\lib_trailing_stop_intelligent.ps1"
. "$scriptRoot\agents\lib_trailing_stop_adaptive.ps1"
. "$scriptRoot\agents\lib_order_validation.ps1"

# Log file
$logFile = "$scriptRoot\logs\trailing_stop_monitor.log"
$logDir = Split-Path -Parent $logFile

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

Write-Log "=== TRAILING STOP MONITOR START ==="

try {
    # Verificar credenciais
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) {
        Write-Log "ERROR: Credenciais nao configuradas"
        exit 1
    }
    
    Write-Log "Buscando posicoes abertas..."
    
    # Atualizar trailing stops
    $result = Update-AllTrailingStops -DryRun $false
    
    if (-not $result.success) {
        Write-Log "ERROR: $($result.error)"
        exit 1
    }
    
    Write-Log "Total positions: $($result.total_positions)"
    Write-Log "Updated: $($result.updated)"
    Write-Log "No update needed: $($result.no_update)"
    Write-Log "Errors: $($result.errors)"
    
    # VALIDACAO: Verificar posicoes sem stop loss
    Write-Log ""
    Write-Log "=== VALIDACAO DE STOP LOSS ==="
    
    $positionsWithoutStop = @()
    $allPositions = CoinEx-GetPendingPositions
    
    foreach ($pos in $allPositions) {
        $validation = Test-PositionHasStopLoss -Market $pos.market
        
        if ($validation.success -and -not $validation.has_stop_loss) {
            $positionsWithoutStop += $pos
            Write-Log "  ALERT: $($pos.market) WITHOUT STOP LOSS! Entry: `$$($pos.avg_entry_price), PNL: `$$($pos.unrealized_pnl)"
        }
    }
    
    if ($positionsWithoutStop.Count -gt 0) {
        Write-Log ""
        Write-Log "CRITICAL: $($positionsWithoutStop.Count) position(s) WITHOUT STOP LOSS PROTECTION!"
        Write-Log "Run FIX_MISSING_STOPS.ps1 to protect these positions."
    } else {
        Write-Log "All positions have stop loss configured."
    }
    
    Write-Log ""
    Write-Log "=== TRAILING STOP RESULTS ==="
    
    # Log detalhado por posicao
    foreach ($posResult in $result.results) {
        if ($posResult.success) {
            if ($posResult.action -eq "updated") {
                Write-Log "  $($posResult.market): UPDATED stop from `$$($posResult.old_stop) to `$$($posResult.new_stop) (trailing $($posResult.trailing_pct)%, PNL $($posResult.pnl_pct)%)"
                Write-Log "    Reason: $($posResult.reason)"
            }
            elseif ($posResult.action -eq "no_update") {
                Write-Log "  $($posResult.market): NO UPDATE - $($posResult.reason) (PNL $($posResult.pnl_pct)%)"
            }
        }
        else {
            Write-Log "  $($posResult.market): ERROR - $($posResult.error)"
        }
    }
    
    Write-Log "=== TRAILING STOP MONITOR END ==="
}
catch {
    Write-Log "CRITICAL ERROR: $_"
    Write-Log $_.ScriptStackTrace
    exit 1
}
