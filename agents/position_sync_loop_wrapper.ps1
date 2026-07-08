# position_sync_loop_wrapper.ps1
# DAEMON WRAPPER: Chama SYNC_POSITIONS_FROM_EXCHANGE.ps1 a cada 45s
# 2026-07-08 — Integração final

#Requires -Version 5.1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$baseDir = Split-Path -Parent $scriptDir
$syncScript = Join-Path $baseDir "scripts\maintenance\SYNC_POSITIONS_FROM_EXCHANGE.ps1"
$journalDir = Join-Path $baseDir "journal"
$logFile = Join-Path $journalDir "position_sync_daemon_wrapper.log"

function Write-Log {
    param([string]$Message)
    $ts = [datetime]::Now.ToString("HH:mm:ss")
    $msg = "[$ts] $Message"
    Add-Content -Path $logFile -Value $msg -ErrorAction SilentlyContinue
    Write-Host $msg -ForegroundColor Gray
}

Write-Log "=== Wrapper daemon started ==="
Write-Log "Script: $syncScript"

if (-not (Test-Path $syncScript)) {
    Write-Log "ERROR: $syncScript not found!"
    exit 1
}

$syncCount = 0
$lastSync = [datetime]::MinValue
$syncInterval = 45

while ($true) {
    try {
        $now = [datetime]::Now
        if (($now - $lastSync).TotalSeconds -ge $syncInterval) {
            $syncCount++
            Write-Log "Running sync #$syncCount..."

            try {
                & $syncScript 2>&1 | ForEach-Object { Write-Log "  $_" }
                Write-Log "Sync completed"
            } catch {
                Write-Log "ERROR: $_"
            }

            $lastSync = $now
        }

        Start-Sleep -Seconds 5

    } catch {
        Write-Log "Loop error: $_"
        Start-Sleep -Seconds 10
    }
}
