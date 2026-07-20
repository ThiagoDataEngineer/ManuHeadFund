# watchdog_autonomous_recovery.ps1 — Auto-recovery se daemon cair
# Roda a cada 5min via Scheduler, traz tudo de volta sozinho

param([switch]$DryRun, [switch]$Verbose)

$ErrorActionPreference = "Continue"

$projectRoot = Split-Path -Parent $PSScriptRoot
$journalDir = Join-Path $projectRoot "journal"
$scriptsDir = $PSScriptRoot

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log($msg) {
    $line = "[$timestamp] $msg"
    Add-Content "$journalDir/watchdog_auto_recovery.log" -Value $line -Encoding UTF8
    if ($Verbose) { Write-Host $line }
}

Log "=== AUTO-RECOVERY WATCHDOG ==="

# ═══════════════════════════════════════════════════════════════════════════
# 1. Verificar daemons esperados
# ═══════════════════════════════════════════════════════════════════════════

$expectedDaemons = @(
    @{ name = "scan_master"; script = "scripts/scan_master.ps1"; essential = $true }
    @{ name = "collect_1h"; script = "scripts/collect_1h_klines.ps1"; essential = $true }
)

$downDaemons = @()

foreach ($daemon in $expectedDaemons) {
    $lockFile = Join-Path $journalDir "daemon_locks" "$($daemon.name).json"

    if (Test-Path $lockFile) {
        try {
            $lock = Get-Content $lockFile -Encoding UTF8 | ConvertFrom-Json
            $lockAge = [int]((Get-Date) - [DateTime]::Parse($lock.ts)).TotalMinutes

            if ($lockAge -gt 10) {
                Log "WARN: $($daemon.name) lock OLD ($lockAge min)"
                $downDaemons += $daemon
            } else {
                Log "OK: $($daemon.name) lock recent ($lockAge min)"
            }
        } catch {
            Log "ERROR: $($daemon.name) lock corrupted"
            $downDaemons += $daemon
        }
    } else {
        if ($daemon.essential) {
            Log "ERROR: $($daemon.name) NO LOCK FILE"
            $downDaemons += $daemon
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 2. Rearrancar daemons caidos
# ═══════════════════════════════════════════════════════════════════════════

if ($downDaemons.Count -eq 0) {
    Log "OK: All daemons alive"
} else {
    Log "ACTION: Restarting $($downDaemons.Count) daemon(s)"

    foreach ($daemon in $downDaemons) {
        $scriptPath = Join-Path $projectRoot $daemon.script

        if (Test-Path $scriptPath) {
            if (-not $DryRun) {
                try {
                    $lockFile = Join-Path $journalDir "daemon_locks" "$($daemon.name).json"
                    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue

                    Start-Process -FilePath "powershell" -ArgumentList @(
                        "-NoProfile",
                        "-WindowStyle", "Hidden",
                        "-File", $scriptPath
                    ) -ErrorAction Stop

                    Log "RESTART OK: $($daemon.name)"
                } catch {
                    Log "RESTART FAILED: $($daemon.name) — $_"
                }
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# 3. Limpeza automatica
# ═══════════════════════════════════════════════════════════════════════════

Log "ACTION: Auto-cleanup"

$old = @(Get-ChildItem $journalDir -Filter "*.log" -ErrorAction SilentlyContinue | Where-Object {
    (Get-Date) - $_.LastWriteTime -gt (New-TimeSpan -Days 7)
})

if ($old.Count -gt 0) {
    $old | ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    Log "CLEANUP: Removed $($old.Count) old logs"
}

Log "Done"
