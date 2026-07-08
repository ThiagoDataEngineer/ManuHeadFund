# tori_daemon_watchdog.ps1 - Watchdog monitor for Tori Daemon
#
# Responsibilities:
# 1. Monitor daemon process health
# 2. Detect stale heartbeat (dead daemon)
# 3. Auto-restart crashed daemon
# 4. Log restart events
# 5. Track uptime and restart count
#
# Integration: Started by Start-ToriDaemon.ps1
# Runs as background job alongside daemon
#
# PS 5.1 compatible, UTF-8 BOM

# ============================================================================
# CONFIGURATION
# ============================================================================

$script:HEARTBEAT_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon_heartbeat.txt"
$script:WATCHDOG_LOG = Join-Path $PSScriptRoot "..\journal\tori_daemon_watchdog.log"
$script:LOCK_FILE = Join-Path $PSScriptRoot "..\journal\tori_daemon.lock"
$script:RESTART_HISTORY = Join-Path $PSScriptRoot "..\journal\tori_daemon_restarts.json"

# Heartbeat monitoring
$script:HEARTBEAT_TIMEOUT_SEC = 600        # 10 minutes = dead
$script:CHECK_INTERVAL_SEC = 30            # Check every 30 seconds
$script:MAX_RESTART_ATTEMPTS = 3           # Max restarts per session

# ============================================================================
# LOGGING
# ============================================================================

function Write-WatchdogLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR", "RESTART")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "[$timestamp] [$Level] $Message"

    Write-Host $logEntry

    if (Test-Path $script:WATCHDOG_LOG) {
        Add-Content -Path $script:WATCHDOG_LOG -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } else {
        Set-Content -Path $script:WATCHDOG_LOG -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# HEARTBEAT MONITORING
# ============================================================================

function Test-DaemonHeartbeat {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:HEARTBEAT_FILE)) {
        return @{
            is_alive = $false
            age_seconds = -1
            reason = "Heartbeat file not found"
        }
    }

    try {
        $fileInfo = Get-Item -Path $script:HEARTBEAT_FILE -ErrorAction Stop
        $age = (Get-Date) - $fileInfo.LastWriteTime
        $ageSeconds = $age.TotalSeconds

        $content = Get-Content -Path $script:HEARTBEAT_FILE -Raw -ErrorAction SilentlyContinue
        $heartbeat = if ($content) { $content | ConvertFrom-Json -ErrorAction SilentlyContinue } else { $null }

        if ($ageSeconds -gt $script:HEARTBEAT_TIMEOUT_SEC) {
            return @{
                is_alive = $false
                age_seconds = $ageSeconds
                reason = "Heartbeat stale (${ageSeconds}s old, threshold ${script:HEARTBEAT_TIMEOUT_SEC}s)"
                heartbeat = $heartbeat
            }
        }

        return @{
            is_alive = $true
            age_seconds = $ageSeconds
            reason = "Healthy"
            heartbeat = $heartbeat
        }
    } catch {
        return @{
            is_alive = $false
            age_seconds = -1
            reason = "Failed to read heartbeat: $_"
        }
    }
}

# ============================================================================
# DAEMON PROCESS VERIFICATION
# ============================================================================

function Test-DaemonProcess {
    [CmdletBinding()]
    param()

    $daemonJobs = Get-Job -Name "ToriDaemon*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }

    if ($daemonJobs) {
        if ($daemonJobs -is [array]) {
            return @{
                is_running = $true
                job_count = $daemonJobs.Count
                job = $daemonJobs[0]
            }
        } else {
            return @{
                is_running = $true
                job_count = 1
                job = $daemonJobs
            }
        }
    }

    return @{
        is_running = $false
        job_count = 0
        job = $null
    }
}

# ============================================================================
# RESTART TRACKING
# ============================================================================

function Get-RestartHistory {
    [CmdletBinding()]
    param()

    if (Test-Path $script:RESTART_HISTORY) {
        try {
            $content = Get-Content -Path $script:RESTART_HISTORY -Raw -ErrorAction SilentlyContinue
            return $content | ConvertFrom-Json -ErrorAction SilentlyContinue
        } catch {
            return @{
                total_restarts = 0
                restarts = @()
                session_start = Get-Date -Format "o"
            }
        }
    }

    return @{
        total_restarts = 0
        restarts = @()
        session_start = Get-Date -Format "o"
    }
}

function Save-RestartHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSObject]$History
    )

    $json = $History | ConvertTo-Json -Depth 3
    Set-Content -Path $script:RESTART_HISTORY -Value $json -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Log-Restart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Reason
    )

    $history = Get-RestartHistory

    $restart = @{
        timestamp = Get-Date -Format "o"
        reason = $Reason
        attempt = $history.total_restarts + 1
    }

    $history.total_restarts += 1
    $history.restarts += @($restart)

    Save-RestartHistory -History $history

    Write-WatchdogLog "Restart logged (attempt $($restart.attempt)): $Reason" -Level RESTART
}

# ============================================================================
# AUTO-RESTART LOGIC
# ============================================================================

function Restart-Daemon {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Reason
    )

    Write-WatchdogLog "Attempting daemon restart (reason: $Reason)..." -Level RESTART

    $history = Get-RestartHistory

    # Check restart limit
    if ($history.total_restarts -ge $script:MAX_RESTART_ATTEMPTS) {
        Write-WatchdogLog "Restart limit reached ($script:MAX_RESTART_ATTEMPTS), stopping watchdog" -Level ERROR
        return $false
    }

    try {
        $daemonScript = Join-Path $PSScriptRoot "Start-ToriDaemon.ps1"

        if (-not (Test-Path $daemonScript)) {
            Write-WatchdogLog "Start script not found: $daemonScript" -Level ERROR
            return $false
        }

        # Execute in same process to preserve context
        & $daemonScript -ErrorAction Stop

        Log-Restart -Reason $Reason
        Write-WatchdogLog "Daemon restart initiated" -Level RESTART
        return $true
    } catch {
        Write-WatchdogLog "Restart failed: $_" -Level ERROR
        return $false
    }
}

# ============================================================================
# LOCK FILE MANAGEMENT
# ============================================================================

function Update-LockFile {
    [CmdletBinding()]
    param()

    try {
        $lockData = @{
            timestamp = Get-Date -Format "o"
            watchdog_pid = $PID
            daemon_alive = (Test-DaemonHeartbeat).is_alive
        } | ConvertTo-Json

        Set-Content -Path $script:LOCK_FILE -Value $lockData -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        Write-WatchdogLog "Failed to update lock file: $_" -Level WARN
    }
}

# ============================================================================
# MAIN WATCHDOG LOOP
# ============================================================================

function Start-ToriWatchdog {
    [CmdletBinding()]
    param()

    Write-WatchdogLog "=== TORI WATCHDOG STARTED ===" -Level INFO
    Write-WatchdogLog "Heartbeat timeout: ${script:HEARTBEAT_TIMEOUT_SEC}s | Check interval: ${script:CHECK_INTERVAL_SEC}s" -Level INFO

    $lastHeartbeatAge = -1

    while ($true) {
        try {
            # Check daemon heartbeat
            $heartbeat = Test-DaemonHeartbeat
            $process = Test-DaemonProcess

            # Update lock file
            Update-LockFile

            # Log status periodically
            if ($heartbeat.age_seconds -ge 0) {
                if ($heartbeat.age_seconds -ne $lastHeartbeatAge) {
                    # Only log on change
                    if ($heartbeat.is_alive) {
                        Write-WatchdogLog "Daemon healthy (heartbeat age: $([Math]::Round($heartbeat.age_seconds))s, scans: $($heartbeat.heartbeat.scans_completed))" -Level INFO
                    } else {
                        Write-WatchdogLog "Daemon UNHEALTHY: $($heartbeat.reason)" -Level WARN
                    }
                    $lastHeartbeatAge = $heartbeat.age_seconds
                }
            }

            # Check for crash (no process but heartbeat was recent)
            if (-not $process.is_running -and $heartbeat.is_alive) {
                Write-WatchdogLog "PROCESS CRASH DETECTED: No running daemon, but heartbeat is fresh" -Level ERROR
                $restarted = Restart-Daemon -Reason "Process crash"
                if ($restarted) {
                    Start-Sleep -Seconds 10  # Wait before next check
                }
            }

            # Check for stale heartbeat (no update)
            if ($heartbeat.is_alive -eq $false) {
                Write-WatchdogLog "STALE HEARTBEAT: $($heartbeat.reason)" -Level ERROR
                $restarted = Restart-Daemon -Reason $heartbeat.reason
                if ($restarted) {
                    Start-Sleep -Seconds 10
                }
            }

        } catch {
            Write-WatchdogLog "Watchdog error: $_" -Level ERROR
        }

        # Sleep before next check
        Start-Sleep -Seconds $script:CHECK_INTERVAL_SEC
    }

    Write-WatchdogLog "=== TORI WATCHDOG STOPPED ===" -Level INFO
}

# ============================================================================
# EXPORT & ENTRY POINT
# ============================================================================

Export-ModuleMember -Function Start-ToriWatchdog, Test-DaemonHeartbeat, Test-DaemonProcess

# If run directly (not sourced)
if ($MyInvocation.InvocationName -ne ".") {
    Start-ToriWatchdog
}
