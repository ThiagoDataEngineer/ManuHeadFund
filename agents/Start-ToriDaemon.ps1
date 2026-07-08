#!/usr/bin/env pwsh
# Start-ToriDaemon.ps1 - Launch Tori Daemon (CLEAN VERSION)
# Date: 2026-07-08

param(
    [switch]$SkipWatchdog
)

$ErrorActionPreference = "Stop"
$PSScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$CONFIG_FILE = Join-Path $PSScriptRoot "config.local.ps1"
$DAEMON_SCRIPT = Join-Path $PSScriptRoot "tori_daemon_simple.ps1"
$LOG_DIR = Join-Path $PSScriptRoot "..\journal"
$STARTUP_LOG = Join-Path $LOG_DIR "tori_startup.log"

function Write-Log {
    param([string]$msg, [string]$level = "INFO", [string]$color = "Cyan")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$level] $msg"
    Write-Host $entry -ForegroundColor $color
    Add-Content -Path $STARTUP_LOG -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
}

# Prerequisites
if (-not (Test-Path $DAEMON_SCRIPT)) {
    Write-Log "ERROR: $DAEMON_SCRIPT not found" "ERROR" "Red"
    exit 1
}

if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

# Startup
Write-Log "Starting Tori Daemon..." "INFO" "Green"

$job = Start-Job -Name "ToriDaemon" -FilePath $DAEMON_SCRIPT -ErrorAction Stop

if ($job) {
    Write-Log "Job started: ID=$($job.Id) Name=$($job.Name)" "SUCCESS" "Green"
    Write-Log "Log file: $LOG_DIR\tori_daemon.log" "INFO" "Cyan"
    Write-Log "View live: Get-Content $LOG_DIR\tori_daemon.log -Tail 50 -Wait" "INFO" "Cyan"
} else {
    Write-Log "Failed to start daemon" "ERROR" "Red"
    exit 1
}
