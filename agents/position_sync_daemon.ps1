# position_sync_daemon.ps1
# Sincroniza posições CoinEx → tracking.jsonl a cada 30-60 segundos
# Evita divergência entre app e sistema

#Requires -Version 5.1
$ErrorActionPreference = "Continue"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent $scriptDir
$journalDir = Join-Path $baseDir "journal"

# Load libs
. "$scriptDir\lib_coinex.ps1" -ErrorAction SilentlyContinue
. "$scriptDir\lib_position_sync_live.ps1" -ErrorAction SilentlyContinue

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

$syncInterval = 30  # segundos
$maxRetries = 3
$logFile = Join-Path $journalDir "position_sync_daemon.log"

function Write-SyncLog {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")] $Level = "INFO")
    $ts = [datetime]::UtcNow.ToString("HH:mm:ss")
    $msg = "[$ts] [$Level] $Message"
    Add-Content -Path $logFile -Value $msg -ErrorAction SilentlyContinue

    $color = @{ INFO = "Gray"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }[$Level]
    Write-Host $msg -ForegroundColor $color
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────────────────────────────────────

Write-SyncLog "Position sync daemon started" "INFO"

$lastSync = [datetime]::MinValue
$syncCount = 0

while ($true) {
    try {
        $now = [datetime]::UtcNow

        # Sync a cada $syncInterval segundos
        if (($now - $lastSync).TotalSeconds -ge $syncInterval) {

            Write-SyncLog "Fetching positions from CoinEx..." "INFO"

            # Tentar buscar posições abertas
            try {
                if (Test-Command -Name "Get-CoinExOpenPositions" -ErrorAction SilentlyContinue) {
                    $positions = @(Get-CoinExOpenPositions -ErrorAction SilentlyContinue)
                    Write-SyncLog "Fetched $($positions.Count) positions from exchange" "SUCCESS"

                    # Atualizar tracking.jsonl
                    if ($positions.Count -gt 0) {
                        $tracking = @{
                            timestamp = $now.ToString("O")
                            positions = @($positions)
                        }

                        $trackingFile = Join-Path $journalDir "open_positions_tracking.jsonl"
                        $tracking | ConvertTo-Json -Depth 10 | Set-Content -Path $trackingFile -ErrorAction SilentlyContinue

                        Write-SyncLog "Updated tracking file: $($positions.Count) positions" "SUCCESS"
                        $syncCount++
                    }
                } else {
                    Write-SyncLog "Get-CoinExOpenPositions not available, skipping" "WARN"
                }
            } catch {
                Write-SyncLog "ERROR fetching positions: $_" "ERROR"
            }

            $lastSync = $now
        }

        # Sleep
        Start-Sleep -Seconds 5

    } catch {
        Write-SyncLog "Daemon error: $_" "ERROR"
        Start-Sleep -Seconds 10
    }
}

