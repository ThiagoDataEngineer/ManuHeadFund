param([switch]$Verbose)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$journalDir = Join-Path $projectRoot "journal"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Log($msg) {
    $line = "[$timestamp] $msg"
    Add-Content "$journalDir/auto_recovery.log" -Value $line -Encoding UTF8
    if ($Verbose) { Write-Host $line }
}

Log "Start"

$lockDir = Join-Path $journalDir "daemon_locks"
if (-not (Test-Path $lockDir)) { New-Item -ItemType Directory -Path $lockDir -Force | Out-Null }

$expected = @("scan_master", "collect_1h")
$down = @()

foreach ($name in $expected) {
    $lockFile = Join-Path $lockDir "$name.json"
    if (Test-Path $lockFile) {
        try {
            $lock = Get-Content $lockFile -Encoding UTF8 | ConvertFrom-Json
            $age = [int]((Get-Date) - [DateTime]::Parse($lock.ts)).TotalMinutes
            if ($age -gt 10) {
                Log "STALE: $name ($age min old)"
                $down += $name
            } else {
                Log "LIVE: $name"
            }
        } catch {
            Log "BAD LOCK: $name"
            $down += $name
        }
    } else {
        Log "MISSING: $name"
        $down += $name
    }
}

if ($down.Count -gt 0) {
    Log "RESTARTING: $($down -join ',')"

    foreach ($name in $down) {
        $lockFile = Join-Path $lockDir "$name.json"
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue

        $scriptMap = @{
            "scan_master" = "scripts/scan_master.ps1"
            "collect_1h" = "scripts/collect_1h_klines.ps1"
        }

        $scriptPath = Join-Path $projectRoot $scriptMap[$name]
        if (Test-Path $scriptPath) {
            Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-File", $scriptPath -ErrorAction SilentlyContinue
            Log "STARTED: $name"
        }
    }
} else {
    Log "OK"
}

Log "Done"
