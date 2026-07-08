# Start-ToriDaemon.ps1 - Launch Tori Daemon in background with watchdog
#
# Responsibilities:
# 1. Verify prerequisites (config, libs, directories)
# 2. Launch daemon as background job
# 3. Start watchdog monitor
# 4. Validate startup
# 5. Log initialization
#
# Usage:
#   .\Start-ToriDaemon.ps1
#   .\Start-ToriDaemon.ps1 -Verbose
#
# PS 5.1 compatible, UTF-8 BOM

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,

    [Parameter(Mandatory=$false)]
    [switch]$SkipWatchdog
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$CONFIG_FILE = Join-Path $PSScriptRoot "config.local.ps1"
$DAEMON_SCRIPT = Join-Path $PSScriptRoot "tori_daemon_24h.ps1"
$WATCHDOG_SCRIPT = Join-Path $PSScriptRoot "tori_daemon_watchdog.ps1"
$LOG_DIR = Join-Path $PSScriptRoot "..\journal"
$DAEMON_LOG = Join-Path $LOG_DIR "tori_daemon.log"
$STARTUP_LOG = Join-Path $LOG_DIR "tori_daemon_startup.log"
$LOCK_FILE = Join-Path $LOG_DIR "tori_daemon.lock"

# ============================================================================
# LOGGING
# ============================================================================

function Write-StartupLog {
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

    if (Test-Path $STARTUP_LOG) {
        Add-Content -Path $STARTUP_LOG -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    } else {
        Set-Content -Path $STARTUP_LOG -Value $logEntry -Encoding UTF8 -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================

function Test-Prerequisites {
    [CmdletBinding()]
    param()

    Write-StartupLog "Verifying prerequisites..." -Level INFO

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-StartupLog "PowerShell 5.1+ required (running $($PSVersionTable.PSVersion))" -Level ERROR
        return $false
    }
    Write-StartupLog "PowerShell version OK: $($PSVersionTable.PSVersion)" -Level SUCCESS

    # Check config file
    if (-not (Test-Path $CONFIG_FILE)) {
        Write-StartupLog "Config not found: $CONFIG_FILE" -Level WARN
        Write-StartupLog "Create agents/config.local.ps1 with COINEX_ACCESS_ID and COINEX_SECRET_KEY" -Level INFO
    } else {
        Write-StartupLog "Config file found" -Level SUCCESS
    }

    # Check daemon script
    if (-not (Test-Path $DAEMON_SCRIPT)) {
        Write-StartupLog "Daemon script not found: $DAEMON_SCRIPT" -Level ERROR
        return $false
    }
    Write-StartupLog "Daemon script found" -Level SUCCESS

    # Check libs
    $libs = @(
        "lib_tori_confluence_detector.ps1",
        "lib_tori_trades_scanner.ps1",
        "lib_coinex.ps1"
    )

    foreach ($lib in $libs) {
        $libPath = Join-Path $PSScriptRoot $lib
        if (Test-Path $libPath) {
            Write-StartupLog "  ✓ $lib" -Level SUCCESS
        } else {
            Write-StartupLog "  ✗ $lib (missing)" -Level WARN
        }
    }

    # Check/create journal directory
    if (-not (Test-Path $LOG_DIR)) {
        New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
        Write-StartupLog "Created journal directory" -Level SUCCESS
    } else {
        Write-StartupLog "Journal directory ready" -Level SUCCESS
    }

    return $true
}

# ============================================================================
# CHECK FOR EXISTING DAEMON
# ============================================================================

function Test-DaemonRunning {
    [CmdletBinding()]
    param()

    # Check if lock file exists and is recent
    if (Test-Path $LOCK_FILE) {
        $lockAge = (Get-Date) - (Get-Item $LOCK_FILE).LastWriteTime
        if ($lockAge.TotalSeconds -lt 120) {
            # Lock is fresh (< 2 min old)
            Write-StartupLog "Daemon appears to be running (lock file age: $([Math]::Round($lockAge.TotalSeconds))s)" -Level WARN
            return $true
        } else {
            Write-StartupLog "Stale lock file found (age: $([Math]::Round($lockAge.TotalSeconds))s), removing..." -Level WARN
            Remove-Item -Path $LOCK_FILE -Force -ErrorAction SilentlyContinue
        }
    }

    # Check if any Tori daemon jobs are running
    $jobs = Get-Job -Name "ToriDaemon*" -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
    if ($jobs) {
        Write-StartupLog "Found $($jobs.Count) running daemon job(s)" -Level WARN
        return $true
    }

    return $false
}

# ============================================================================
# LAUNCH DAEMON
# ============================================================================

function Start-DaemonProcess {
    [CmdletBinding()]
    param()

    Write-StartupLog "Starting daemon process..." -Level INFO

    try {
        # Create job script block
        $jobScript = {
            param($DaemonScript, $LogDir, $ConfigFile)

            # Load config if exists
            if (Test-Path $ConfigFile) {
                . $ConfigFile
            }

            # Run daemon
            . $DaemonScript
            Start-ToriDaemon
        }

        # Start as background job
        $job = Start-Job -Name "ToriDaemon_$(Get-Date -Format 'yyyyMMdd_HHmmss')" `
                         -ScriptBlock $jobScript `
                         -ArgumentList $DAEMON_SCRIPT, $LOG_DIR, $CONFIG_FILE `
                         -ErrorAction Stop

        Write-StartupLog "Daemon launched as job: $($job.Name) (ID: $($job.Id))" -Level SUCCESS

        # Wait for startup (5 seconds)
        Start-Sleep -Seconds 5

        # Verify job is running
        $job = Get-Job -Id $job.Id -ErrorAction SilentlyContinue
        if ($job -and $job.State -eq "Running") {
            Write-StartupLog "Daemon process confirmed running" -Level SUCCESS
            return $job.Id
        } else {
            Write-StartupLog "Daemon process failed to start" -Level ERROR
            Write-StartupLog "Job state: $($job.State)" -Level ERROR

            # Show any errors
            if ($job.Error.Count -gt 0) {
                Write-StartupLog "Errors: $($job.Error -join '; ')" -Level ERROR
            }
            return $null
        }
    } catch {
        Write-StartupLog "Failed to launch daemon: $_" -Level ERROR
        return $null
    }
}

# ============================================================================
# START WATCHDOG
# ============================================================================

function Start-WatchdogProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$DaemonJobId
    )

    if ($SkipWatchdog) {
        Write-StartupLog "Watchdog startup skipped (use without -SkipWatchdog to enable)" -Level WARN
        return
    }

    if (-not (Test-Path $WATCHDOG_SCRIPT)) {
        Write-StartupLog "Watchdog script not found, skipping..." -Level WARN
        return
    }

    Write-StartupLog "Starting watchdog monitor..." -Level INFO

    try {
        $watchdogJob = Start-Job -Name "ToriWatchdog_$(Get-Date -Format 'yyyyMMdd_HHmmss')" `
                                 -ScriptBlock {
            param($WatchdogScript)
            . $WatchdogScript
            Start-ToriWatchdog
        } -ArgumentList $WATCHDOG_SCRIPT -ErrorAction Stop

        Write-StartupLog "Watchdog started (ID: $($watchdogJob.Id))" -Level SUCCESS
    } catch {
        Write-StartupLog "Failed to start watchdog: $_" -Level WARN
    }
}

# ============================================================================
# VALIDATE STARTUP
# ============================================================================

function Wait-DaemonStartup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$JobId,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30
    )

    Write-StartupLog "Waiting for daemon initialization (timeout: ${TimeoutSeconds}s)..." -Level INFO

    $startTime = Get-Date
    $initialized = $false

    while ((Get-Date) - $startTime -lt [TimeSpan]::FromSeconds($TimeoutSeconds)) {
        # Check if heartbeat file exists
        $heartbeat = Join-Path $LOG_DIR "tori_daemon_heartbeat.txt"
        if (Test-Path $heartbeat) {
            $content = Get-Content -Path $heartbeat -Raw -ErrorAction SilentlyContinue
            if ($content | ConvertFrom-Json -ErrorAction SilentlyContinue) {
                $initialized = $true
                break
            }
        }

        # Check if job crashed
        $job = Get-Job -Id $JobId -ErrorAction SilentlyContinue
        if ($job -and $job.State -ne "Running") {
            Write-StartupLog "Daemon job not running (state: $($job.State))" -Level ERROR
            return $false
        }

        Start-Sleep -Seconds 1
    }

    if ($initialized) {
        Write-StartupLog "Daemon initialized successfully" -Level SUCCESS
        return $true
    } else {
        Write-StartupLog "Daemon initialization timed out" -Level WARN
        Write-StartupLog "Check log for details: $DAEMON_LOG" -Level INFO
        return $false
    }
}

# ============================================================================
# FINAL STATUS REPORT
# ============================================================================

function Show-StatusReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$JobId
    )

    Write-Host ""
    Write-StartupLog "╔════════════════════════════════════════════════════════════╗" -Level SUCCESS
    Write-StartupLog "║         Tori Daemon Startup Complete                      ║" -Level SUCCESS
    Write-StartupLog "╚════════════════════════════════════════════════════════════╝" -Level SUCCESS

    $job = Get-Job -Id $JobId -ErrorAction SilentlyContinue

    Write-Host "
📊 Daemon Information:
  Job Name: $($job.Name)
  Job ID: $($job.Id)
  Status: $($job.State)
  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

📍 Locations:
  Daemon Log: $DAEMON_LOG
  Startup Log: $STARTUP_LOG
  State File: $(Join-Path $LOG_DIR 'tori_daemon_state.json')
  Dashboard: $(Join-Path $LOG_DIR 'reports\tori_dashboard.html')

⚙️ Configuration:
  Scan Interval: 240 minutes (4 hours)
  Heartbeat: Every 300 seconds (5 minutes)
  Confluence Threshold: 80/100
  Max Pairs Per Scan: 150

🎯 Quick Commands:
  Check daemon: Get-Job -Name 'ToriDaemon*'
  View log: Get-Content $DAEMON_LOG -Tail 50
  View state: Get-Content $(Join-Path $LOG_DIR 'tori_daemon_state.json') | ConvertFrom-Json
  Generate reports: . $(Join-Path $PSScriptRoot 'tori_daemon_reporter.ps1'); Export-ToriReports
  Stop daemon: .\Stop-ToriDaemon.ps1

📡 Telegram:
  Alerts enabled: Check TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in config.local.ps1
"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Starting Tori Daemon - 24/7 Trendline Scanner           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Verify prerequisites
if (-not (Test-Prerequisites)) {
    Write-StartupLog "Startup failed: Prerequisites not met" -Level ERROR
    exit 1
}

# Check for existing daemon
if (Test-DaemonRunning) {
    Write-StartupLog "Use .\Stop-ToriDaemon.ps1 to stop existing daemon, then try again" -Level INFO
    exit 1
}

# Launch daemon
$jobId = Start-DaemonProcess
if (-not $jobId) {
    Write-StartupLog "Startup failed: Could not launch daemon process" -Level ERROR
    exit 1
}

# Wait for initialization
if (-not (Wait-DaemonStartup -JobId $jobId)) {
    Write-StartupLog "Warning: Daemon may not have initialized properly" -Level WARN
}

# Start watchdog
Start-WatchdogProcess -DaemonJobId $jobId

# Show status report
Show-StatusReport -JobId $jobId

Write-Host ""
Write-StartupLog "✅ Startup Complete" -Level SUCCESS
