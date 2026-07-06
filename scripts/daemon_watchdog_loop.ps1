# daemon_watchdog_loop.ps1 — Watchdog infinito que monitora + reinicia daemons
# Roda 24/7, polição a cada 60sec
# Se algum daemon cair → reinicia automático em <5min
#
# Uso:
#   pwsh -File scripts\daemon_watchdog_loop.ps1           # 60sec interval default
#   pwsh -File scripts\daemon_watchdog_loop.ps1 -Interval 30  # 30sec interval
#
# Idempotente: singleton próprio (watchdog.lock)
# PS 5.1, UTF-8 BOM.

param(
    [int]$Interval = 60,  # polling interval em segundos
    [switch]$Force
)

$ErrorActionPreference = "Continue"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$journalDir = Join-Path $projectRoot "journal"
$agentsDir = Join-Path $projectRoot "agents"
$lockDir = Join-Path $journalDir "daemon_locks"
$watchdogLog = Join-Path $journalDir "watchdog_loop.log"

# Idempotent check
$myPid = $PID
$__watchdogLock = Join-Path $lockDir "watchdog_loop.lock"

if (Test-Path $__watchdogLock) {
    try {
        $existing = Get-Content $__watchdogLock | ConvertFrom-Json
        $existingPid = $existing.pid
        $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "[SKIP] Watchdog já roda (PID=$existingPid). Use -Force para override."
            exit 0
        }
    } catch {}
}

# Create lock
@{pid=$myPid; ts=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')} | ConvertTo-Json | Set-Content $__watchdogLock -Encoding UTF8

# Load lib
if (Test-Path (Join-Path $agentsDir "lib_daemon_watchdog_v2.ps1")) {
    . (Join-Path $agentsDir "lib_daemon_watchdog_v2.ps1")
} else {
    Write-Host "[ERROR] lib_daemon_watchdog_v2.ps1 not found"
    exit 1
}

# Start loop
Write-Host "[START] Watchdog loop iniciado (interval=${Interval}s, log=$watchdogLog)"
Watch-DaemonsLoopInfinite -IntervalSeconds $Interval -ProjectRoot $projectRoot -LogFile $watchdogLog
