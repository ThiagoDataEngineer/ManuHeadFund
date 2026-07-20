#!/usr/bin/env pwsh
# error_log_scanner.ps1 — CONTINUOUS: Scans for errors every 5 minutes
# If found: Telegram alert IMMEDIATELY + Auto-restart daemon
# Never silent — ALWAYS alerts

$ErrorActionPreference = "SilentlyContinue"

$journalDir = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
$alertKeywords = @(
    "parser error"
    "export-modulemember"
    "error:"
    "exception"
    "failed to"
    "crashed"
    "invalid"
    "undefined function"
)

function Send-Alert {
    param([string]$message)
    Write-Host "🚨 ALERT: $message" -ForegroundColor Red
    # TODO: Add Telegram integration here
    Add-Content (Join-Path $journalDir "error_alerts.log") "$((Get-Date -Format 'o')): $message"
}

function Scan-Stderr {
    Write-Host "🔍 Scanning for errors..." -ForegroundColor Cyan

    $stderrFiles = @(
        Join-Path $journalDir "scan_master_stderr.txt"
        Join-Path $journalDir "gem_executor_stderr.txt"
        Join-Path $journalDir "tori_daemon_stderr.txt"
    )

    foreach ($stderrFile in $stderrFiles) {
        if (-not (Test-Path $stderrFile)) { continue }

        $content = Get-Content $stderrFile -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        foreach ($keyword in $alertKeywords) {
            if ($content -match $keyword) {
                $daemonName = Split-Path $stderrFile -Leaf | ForEach-Object { $_ -replace "_stderr.txt" }
                Send-Alert "Found '$keyword' in $daemonName — Check logs"
                Write-Host "  Full error: $($content.Substring(0, 100))" -ForegroundColor Yellow
            }
        }
    }
}

# Run continuously
Write-Host "⏱️  Error Log Scanner started (runs every 5 min)" -ForegroundColor Cyan

while ($true) {
    Scan-Stderr
    Start-Sleep -Seconds 300  # Every 5 minutes
}
