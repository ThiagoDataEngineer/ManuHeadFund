# Stop-ToriDaemon.ps1 - Graceful shutdown of Tori Daemon
#
# Responsibilities:
# 1. Find running daemon and watchdog
# 2. Request graceful shutdown
# 3. Wait for state save
# 4. Kill if necessary (after timeout)
# 5. Clean up lock files
# 6. Generate final session report
#
# Usage:
#   .\Stop-ToriDaemon.ps1
#   .\Stop-ToriDaemon.ps1 -Force
#   .\Stop-ToriDaemon.ps1 -GenerateReport
#
# PS 5.1 compatible, UTF-8 BOM

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [switch]$GenerateReport
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "SilentlyContinue"
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$LOG_DIR = Join-Path $PSScriptRoot "..\journal"
$SHUTDOWN_LOG = Join-Path $LOG_DIR "tori_daemon_shutdown.log"
$HEARTBEAT_FILE = Join-Path $LOG_DIR "tori_daemon_heartbeat.txt"
$STATE_FILE = Join-Path $LOG_DIR "tori_daemon_state.json"
$LOCK_FILE = Join-Path $LOG_DIR "tori_daemon.lock"
$REPORTER_SCRIPT = Join-Path $PSScriptRoot "tori_daemon_reporter.ps1"

$GRACEFUL_TIMEOUT_SEC = 30
$FORCE_KILL_TIMEOUT_SEC = 10

# ============================================================================
# LOGGING
# ============================================================================

function Write-ShutdownLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"

    Write-Host $logEntry -ForegroundColor $(
        switch ($Level) {
            "SUCCESS" { "Green" }
            "ERROR" { "Red" }
            "WARN" { "Yellow" }
            default { "Cyan" }
        }
    )

    Add-Content -Path $SHUTDOWN_LOG -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# ============================================================================
# FIND RUNNING DAEMON
# ============================================================================

function Find-RunningDaemon {
    [CmdletBinding()]
    param()

    Write-ShutdownLog "Searching for running daemon..." -Level INFO

    $daemonJobs = Get-Job -Name "ToriDaemon*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }

    if ($daemonJobs) {
        if ($daemonJobs -is [array]) {
            Write-ShutdownLog "Found $($daemonJobs.Count) running daemon jobs" -Level WARN
            return $daemonJobs[0]  # Use first one
        } else {
            Write-ShutdownLog "Found 1 running daemon job: $($daemonJobs.Name)" -Level SUCCESS
            return $daemonJobs
        }
    }

    Write-ShutdownLog "No running daemon found" -Level WARN
    return $null
}

# ============================================================================
# FIND RUNNING WATCHDOG
# ============================================================================

function Find-RunningWatchdog {
    [CmdletBinding()]
    param()

    $watchdogJobs = Get-Job -Name "ToriWatchdog*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }

    if ($watchdogJobs) {
        if ($watchdogJobs -is [array]) {
            return $watchdogJobs[0]
        } else {
            return $watchdogJobs
        }
    }

    return $null
}

# ============================================================================
# GRACEFUL SHUTDOWN ATTEMPT
# ============================================================================

function Request-GracefulShutdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Job]$DaemonJob
    )

    Write-ShutdownLog "Requesting graceful shutdown (Job ID: $($DaemonJob.Id))..." -Level INFO

    # Get heartbeat for baseline
    $heartbeatBefore = if (Test-Path $HEARTBEAT_FILE) {
        $content = Get-Content -Path $HEARTBEAT_FILE -Raw -ErrorAction SilentlyContinue
        if ($content) {
            $content | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
    } else {
        $null
    }

    # Send stop signal to daemon (via shared variable in job context)
    # Since we can't directly communicate, we'll use a timeout approach
    Write-ShutdownLog "Waiting for graceful shutdown (${GRACEFUL_TIMEOUT_SEC}s timeout)..." -Level INFO

    $startTime = Get-Date
    $gracefulComplete = $false

    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($GRACEFUL_TIMEOUT_SEC)) {
        # Check if job is still running
        $job = Get-Job -Id $DaemonJob.Id -ErrorAction SilentlyContinue
        if ($job -and $job.State -eq "Completed") {
            Write-ShutdownLog "Daemon completed gracefully" -Level SUCCESS
            $gracefulComplete = $true
            break
        }

        # Check if heartbeat is updating (sign of life)
        $heartbeatNow = if (Test-Path $HEARTBEAT_FILE) {
            $content = Get-Content -Path $HEARTBEAT_FILE -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $content | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
        } else {
            $null
        }

        if ($heartbeatBefore -and $heartbeatNow -and $heartbeatNow.timestamp -ne $heartbeatBefore.timestamp) {
            Write-ShutdownLog "Daemon responsive (scans completed: $($heartbeatNow.scans_completed))" -Level INFO
            $heartbeatBefore = $heartbeatNow
        }

        Start-Sleep -Seconds 2
    }

    if ($gracefulComplete) {
        return $true
    } else {
        Write-ShutdownLog "Graceful shutdown timeout" -Level WARN
        return $false
    }
}

# ============================================================================
# FORCE KILL
# ============================================================================

function Force-KillDaemon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.Job]$DaemonJob
    )

    Write-ShutdownLog "Force killing daemon (Job ID: $($DaemonJob.Id))..." -Level WARN

    try {
        Stop-Job -Job $DaemonJob -PassThru -ErrorAction Stop | Out-Null
        Write-ShutdownLog "Daemon job stopped" -Level SUCCESS
    } catch {
        Write-ShutdownLog "Error stopping daemon job: $_" -Level ERROR
    }

    # Wait for completion
    $startTime = Get-Date
    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($FORCE_KILL_TIMEOUT_SEC)) {
        $job = Get-Job -Id $DaemonJob.Id -ErrorAction SilentlyContinue
        if ($job -and $job.State -eq "Stopped") {
            Write-ShutdownLog "Daemon job stopped confirmed" -Level SUCCESS
            break
        }
        Start-Sleep -Seconds 1
    }

    # Remove job
    try {
        Remove-Job -Id $DaemonJob.Id -Force -ErrorAction Stop
        Write-ShutdownLog "Daemon job removed from queue" -Level SUCCESS
    } catch {
        Write-ShutdownLog "Error removing job: $_" -Level WARN
    }
}

# ============================================================================
# CLEANUP
# ============================================================================

function Clean-UpDaemon {
    [CmdletBinding()]
    param()

    Write-ShutdownLog "Cleaning up resources..." -Level INFO

    # Remove lock file
    if (Test-Path $LOCK_FILE) {
        Remove-Item -Path $LOCK_FILE -Force -ErrorAction SilentlyContinue
        Write-ShutdownLog "Lock file removed" -Level SUCCESS
    }

    # Archive logs
    $archiveDir = Join-Path $LOG_DIR "archives"
    if (-not (Test-Path $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }

    Write-ShutdownLog "Cleanup complete" -Level SUCCESS
}

# ============================================================================
# GENERATE FINAL SESSION REPORT
# ============================================================================

function Generate-SessionReport {
    [CmdletBinding()]
    param()

    Write-ShutdownLog "Generating session reports..." -Level INFO

    if (-not (Test-Path $REPORTER_SCRIPT)) {
        Write-ShutdownLog "Reporter script not found, skipping reports" -Level WARN
        return
    }

    try {
        & {
            . $REPORTER_SCRIPT
            Export-ToriReports -ReportType all
        }

        Write-ShutdownLog "Session reports generated" -Level SUCCESS
    } catch {
        Write-ShutdownLog "Failed to generate reports: $_" -Level WARN
    }
}

# ============================================================================
# RETRIEVE FINAL STATISTICS
# ============================================================================

function Show-FinalStatistics {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $STATE_FILE)) {
        return
    }

    try {
        $state = Get-Content -Path $STATE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json

        Write-Host ""
        Write-ShutdownLog "═══════════════════════════════════════════════════════════" -Level SUCCESS
        Write-ShutdownLog "                  Final Session Statistics" -Level SUCCESS
        Write-ShutdownLog "═══════════════════════════════════════════════════════════" -Level SUCCESS

        Write-Host "
📊 Performance Summary:
  Total Scans: $($state.performance.total_scans)
  Pairs Analyzed (Last): $($state.performance.pairs_analyzed)
  Setups Found: $($state.performance.setups_found)
  Avg Confluence: $($state.performance.avg_confluence_score)/100

🎯 Current Status:
  Active Setups: $($state.active_setups.Count)
  Closed Trades: $($state.closed_trades.Count)
  Total P&L: $([Math]::Round($state.performance.total_pnl, 2)) USDT
  Win Rate: $([Math]::Round($state.performance.win_rate * 100, 1))%

💾 State Saved:
  Last Update: $($state.timestamp)
"
    } catch {
        Write-ShutdownLog "Could not read final statistics: $_" -Level WARN
    }
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  Stopping Tori Daemon                                     ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# Find daemon
$daemon = Find-RunningDaemon
if (-not $daemon) {
    Write-ShutdownLog "No running daemon found" -Level WARN

    # Check if we should still clean up
    if (Test-Path $LOCK_FILE) {
        Write-ShutdownLog "Stale lock file found, cleaning up..." -Level INFO
        Remove-Item -Path $LOCK_FILE -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-ShutdownLog "Nothing to stop" -Level INFO
    exit 0
}

Write-ShutdownLog "Daemon found: $($daemon.Name)" -Level SUCCESS

# Request graceful shutdown
if (-not $Force) {
    $graceful = Request-GracefulShutdown -DaemonJob $daemon
} else {
    Write-ShutdownLog "Force mode enabled, skipping graceful shutdown" -Level WARN
    $graceful = $false
}

# If graceful failed or forced, kill it
if (-not $graceful) {
    Force-KillDaemon -DaemonJob $daemon
}

# Stop watchdog
$watchdog = Find-RunningWatchdog
if ($watchdog) {
    Write-ShutdownLog "Stopping watchdog ($($watchdog.Name))..." -Level INFO
    Stop-Job -Job $watchdog -PassThru -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Id $watchdog.Id -Force -ErrorAction SilentlyContinue
    Write-ShutdownLog "Watchdog stopped" -Level SUCCESS
}

# Cleanup
Clean-UpDaemon

# Generate reports if requested
if ($GenerateReport) {
    Generate-SessionReport
}

# Show final stats
Show-FinalStatistics

Write-Host ""
Write-ShutdownLog "╔════════════════════════════════════════════════════════════╗" -Level SUCCESS
Write-ShutdownLog "║  Tori Daemon Stopped                                      ║" -Level SUCCESS
Write-ShutdownLog "╚════════════════════════════════════════════════════════════╝" -Level SUCCESS
Write-Host ""

exit 0
