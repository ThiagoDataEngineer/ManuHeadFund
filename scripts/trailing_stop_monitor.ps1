# scripts\trailing_stop_monitor.ps1
# Monitor de Trailing Stop - CROSS-PLATFORM (Windows/Linux)
# Funciona tanto localmente quanto no GitHub Actions
# 2026-05-24

$ErrorActionPreference = "Stop"

# ============================================================================
# Setup Cross-Platform
# ============================================================================

# Detectar raiz do projeto
$projectRoot = Split-Path -Parent $PSScriptRoot

# Carregar lib cross-platform primeiro
$agentsDir = Join-Path $projectRoot "agents"
$crossPlatformLib = Join-Path $agentsDir "lib_cross_platform.ps1"
. $crossPlatformLib

# Carregar config.local.ps1 se existir (para credenciais)
$configLocal = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocal) {
    . $configLocal
}

# Inicializar ambiente
$cpEnv = Initialize-CrossPlatformEnvironment

Write-CrossPlatformLog "=== TRAILING STOP MONITOR START ===" -LogFile "trailing_stop_monitor.log"
Write-CrossPlatformLog "OS: $(if ($cpEnv.IsLinux) { 'Linux' } else { 'Windows' })" -LogFile "trailing_stop_monitor.log"
Write-CrossPlatformLog "Project Root: $($cpEnv.ProjectRoot)" -LogFile "trailing_stop_monitor.log"

# ============================================================================
# Validar Credenciais
# ============================================================================

if (-not (Test-CrossPlatformCredentials)) {
    Write-CrossPlatformLog "ERROR: Credentials not configured" -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}

# ============================================================================
# Carregar Bibliotecas
# ============================================================================

try {
    Write-CrossPlatformLog "Loading libraries..." -LogFile "trailing_stop_monitor.log"
    
    # Carregar libs diretamente com Join-Path (cross-platform)
    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    . (Join-Path $agentsDir "lib_telegram.ps1")
    . (Join-Path $agentsDir "lib_trailing.ps1")
    . (Join-Path $agentsDir "lib_trailing_stop_intelligent.ps1")
    . (Join-Path $agentsDir "lib_trailing_orphan_detection.ps1")
    
    Write-CrossPlatformLog "Libraries loaded successfully" -LogFile "trailing_stop_monitor.log"
} catch {
    Write-CrossPlatformLog "ERROR loading libraries: $_" -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}

# ============================================================================
# Executar Monitor
# ============================================================================

try {
    # 1. ORPHAN DETECTION
    Write-CrossPlatformLog "--- ORPHAN DETECTION ---" -LogFile "trailing_stop_monitor.log"
    
    $orphanSync = Sync-OrphanPositions
    
    if ($orphanSync.success) {
        Write-CrossPlatformLog "Exchange positions: $($orphanSync.total_exchange)" -LogFile "trailing_stop_monitor.log"
        Write-CrossPlatformLog "Orphans detected: $($orphanSync.orphans_detected)" -LogFile "trailing_stop_monitor.log"
        
        if ($orphanSync.orphans_detected -gt 0) {
            Write-CrossPlatformLog "  Registered: $($orphanSync.registered)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "  Skipped (duplicates): $($orphanSync.skipped)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "  Errors: $($orphanSync.errors)" -LogFile "trailing_stop_monitor.log"
            
            foreach ($detail in $orphanSync.details) {
                if ($detail.registered) {
                    $stopType = if ($detail.stop_calculated) { "calculated" } else { "from exchange" }
                    Write-CrossPlatformLog "  ORPHAN REGISTERED: $($detail.market) | Entry: $($detail.entry) | Stop: $($detail.stop) ($stopType)" -LogFile "trailing_stop_monitor.log"
                }
                elseif ($detail.error) {
                    Write-CrossPlatformLog "  ORPHAN ERROR: $($detail.error)" -Level WARN -LogFile "trailing_stop_monitor.log"
                }
            }
        }
        else {
            Write-CrossPlatformLog "No orphans detected - all positions registered locally" -LogFile "trailing_stop_monitor.log"
        }
    }

    # 1.5 PHANTOM RECONCILIATION (2026-05-26 A.0): fecha posicoes locais active=true
    # que nao existem na exchange (oposto de orphan - position fechada externamente).
    if (Get-Command Reconcile-PhantomPositions -ErrorAction SilentlyContinue) {
        Write-CrossPlatformLog "--- PHANTOM RECONCILIATION ---" -LogFile "trailing_stop_monitor.log"
        $phantomSync = Reconcile-PhantomPositions
        Write-CrossPlatformLog "Phantoms detected: $($phantomSync.phantoms_detected) closed: $($phantomSync.closed) errors: $($phantomSync.errors)" -LogFile "trailing_stop_monitor.log"
        foreach ($d in $phantomSync.details) {
            $level = if ($d.closed) { "INFO" } else { "WARN" }
            Write-CrossPlatformLog "  PHANTOM: $($d.market) closed=$($d.closed) exit=$($d.exitPrice)" -Level $level -LogFile "trailing_stop_monitor.log"
        }
    }
    else {
        Write-CrossPlatformLog "ORPHAN DETECTION ERROR: $($orphanSync.error)" -Level ERROR -LogFile "trailing_stop_monitor.log"
    }
    
    # 2. TRAILING STOP UPDATE (se lib disponível)
    Write-CrossPlatformLog "--- TRAILING STOP UPDATE ---" -LogFile "trailing_stop_monitor.log"
    
    if (Get-Command Update-AllTrailingStops -ErrorAction SilentlyContinue) {
        $result = Update-AllTrailingStops -DryRun $false
        
        if ($result.success) {
            Write-CrossPlatformLog "Total positions: $($result.total_positions)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "Updated: $($result.updated)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "No update needed: $($result.no_update)" -LogFile "trailing_stop_monitor.log"
            Write-CrossPlatformLog "Errors: $($result.errors)" -LogFile "trailing_stop_monitor.log"
            
            # Log detalhado
            foreach ($posResult in $result.results) {
                if ($posResult.success) {
                    if ($posResult.action -eq "updated") {
                        Write-CrossPlatformLog "  $($posResult.market): UPDATED stop from $($posResult.old_stop) to $($posResult.new_stop)" -LogFile "trailing_stop_monitor.log"
                    }
                    elseif ($posResult.action -eq "no_update") {
                        Write-CrossPlatformLog "  $($posResult.market): NO UPDATE - $($posResult.reason)" -LogFile "trailing_stop_monitor.log"
                    }
                }
                else {
                    Write-CrossPlatformLog "  $($posResult.market): ERROR - $($posResult.error)" -Level WARN -LogFile "trailing_stop_monitor.log"
                }
            }
        }
        else {
            Write-CrossPlatformLog "ERROR: $($result.error)" -Level ERROR -LogFile "trailing_stop_monitor.log"
        }
    }
    else {
        Write-CrossPlatformLog "Update-AllTrailingStops not available (simplified mode)" -Level WARN -LogFile "trailing_stop_monitor.log"
        
        # Modo simplificado: apenas listar posições
        $localPositions = @(Get-TrailingPositions | Where-Object { $_.active })
        Write-CrossPlatformLog "Local active positions: $($localPositions.Count)" -LogFile "trailing_stop_monitor.log"
        
        foreach ($pos in $localPositions) {
            Write-CrossPlatformLog "  $($pos.market): Entry $($pos.entry) | Stop $($pos.stopCurrent)" -LogFile "trailing_stop_monitor.log"
        }
    }
    
    # 3. VALIDATION
    Write-CrossPlatformLog "--- VALIDATION ---" -LogFile "trailing_stop_monitor.log"
    
    $allPositions = @(CoinEx-GetPendingPositions)
    $positionsWithoutStop = @()
    
    foreach ($pos in $allPositions) {
        if (-not $pos.stop_loss_price -or $pos.stop_loss_price -eq 0) {
            $positionsWithoutStop += $pos
            Write-CrossPlatformLog "  ALERT: $($pos.market) WITHOUT STOP LOSS!" -Level WARN -LogFile "trailing_stop_monitor.log"
        }
    }
    
    if ($positionsWithoutStop.Count -gt 0) {
        Write-CrossPlatformLog "CRITICAL: $($positionsWithoutStop.Count) position(s) WITHOUT STOP LOSS PROTECTION!" -Level ERROR -LogFile "trailing_stop_monitor.log"
    } else {
        Write-CrossPlatformLog "All positions have stop loss configured." -LogFile "trailing_stop_monitor.log"
    }
    
    Write-CrossPlatformLog "=== TRAILING STOP MONITOR END ===" -LogFile "trailing_stop_monitor.log"
    
    exit 0
    
} catch {
    Write-CrossPlatformLog "CRITICAL ERROR: $_" -Level ERROR -LogFile "trailing_stop_monitor.log"
    Write-CrossPlatformLog $_.ScriptStackTrace -Level ERROR -LogFile "trailing_stop_monitor.log"
    exit 1
}
