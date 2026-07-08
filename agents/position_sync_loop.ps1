# position_sync_loop.ps1
# DAEMON: Sincroniza posições CoinEx → tracking.jsonl a cada 45 segundos
# Baseado em: scripts/maintenance/SYNC_POSITIONS_FROM_EXCHANGE.ps1
# 2026-07-08

#Requires -Version 5.1
$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent $scriptDir
$journalDir = Join-Path $baseDir "journal"

# ─────────────────────────────────────────────────────────────────────────────
# LOAD CONFIG + LIBS (SAME PATTERN AS OFFICIAL SYNC SCRIPT)
# ─────────────────────────────────────────────────────────────────────────────

try {
    . "$scriptDir\config.ps1" -ErrorAction Stop
    . "$scriptDir\lib_coinex.ps1" -ErrorAction Stop
    . "$scriptDir\lib_position_sync_realtime.ps1" -ErrorAction Stop
    . "$scriptDir\lib_trailing.ps1" -ErrorAction SilentlyContinue
} catch {
    Write-Host "❌ Load error: $_" -ForegroundColor Red
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

$syncInterval = 45  # segundos
$logFile = Join-Path $journalDir "position_sync_loop.log"

function Write-SyncLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")] $Level = "INFO"
    )
    $ts = [datetime]::UtcNow.ToString("HH:mm:ss")
    $msg = "[$ts] [$Level] $Message"

    try { Add-Content -Path $logFile -Value $msg -ErrorAction SilentlyContinue } catch { }

    $color = @{ INFO = "Gray"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }[$Level]
    Write-Host $msg -ForegroundColor $color
}

Write-SyncLog "Position sync daemon started" "INFO"
Write-SyncLog "Sync interval: $syncInterval segundos" "INFO"

# ─────────────────────────────────────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────────────────────────────────────

$syncCount = 0
$lastSync = [datetime]::MinValue

while ($true) {
    try {
        $now = [datetime]::UtcNow
        $timeSinceSync = ($now - $lastSync).TotalSeconds

        if ($timeSinceSync -ge $syncInterval) {

            try {
                Write-SyncLog "Sync #$($syncCount + 1) starting..." "INFO"

                # USAR EXATAMENTE COMO OFFICIAL SCRIPT
                if (Get-Command CoinEx-GetPendingPositions -ErrorAction SilentlyContinue) {
                    $positions = @(CoinEx-GetPendingPositions -ErrorAction Stop)

                    if ($positions -and $positions.Count -gt 0) {
                        Write-SyncLog "Fetched $($positions.Count) positions from exchange" "SUCCESS"

                        # Update tracking.jsonl
                        $tracking = @{
                            timestamp = $now.ToString("O")
                            positions = $positions
                        }

                        $trackingFile = Join-Path $journalDir "open_positions_tracking.jsonl"
                        $tracking | ConvertTo-Json -Depth 10 | Set-Content -Path $trackingFile -ErrorAction SilentlyContinue

                        Write-SyncLog "Updated tracking.jsonl: $($positions.Count) positions" "SUCCESS"
                        $syncCount++
                    } else {
                        Write-SyncLog "No positions found" "INFO"
                    }
                } else {
                    Write-SyncLog "CoinEx-GetPendingPositions not available" "ERROR"
                }

            } catch {
                Write-SyncLog "Sync error: $_" "ERROR"
            }

            $lastSync = $now
        }

        Start-Sleep -Seconds 5

    } catch {
        Write-SyncLog "Loop error: $_" "ERROR"
        Start-Sleep -Seconds 10
    }
}
