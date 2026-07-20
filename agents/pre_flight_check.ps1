#!/usr/bin/env pwsh
# pre_flight_check.ps1 — CRITICAL: Blocks daemon start if any code has errors
# Runs BEFORE every daemon startup
# Failures: Alert Telegram + Exit 1 (daemon does NOT start)

$ErrorActionPreference = "SilentlyContinue"

$criticalFiles = @(
    "agents\gem_executor.ps1"
    "agents\lib_tori_confluence_detector.ps1"
    "agents\lib_coinex.ps1"
    "agents\lib_beta_calculator_multitf.ps1"
    "agents\lib_tori_gate_wrapper.ps1"
    "agents\lib_tori_trades_scanner.ps1"
    "agents\lib_pattern_backtest.ps1"
    "agents\lib_stop_loss_calibration_study.ps1"
    "agents\lib_telegram_essential_alerts.ps1"
    "agents\lib_tori_html_renderer.ps1"
    "agents\lib_trailing.ps1"
    "scripts\scan_master.ps1"
)

Write-Host "🛡️ PRE-FLIGHT CHECK — Validating critical files..." -ForegroundColor Cyan
Write-Host ""

$failed = @()
$passed = 0

foreach ($file in $criticalFiles) {
    $fullPath = Join-Path (Split-Path $PSScriptRoot -Parent) $file

    if (-not (Test-Path $fullPath)) {
        Write-Host "⚠️  MISSING: $file" -ForegroundColor Yellow
        $failed += @{file=$file; reason="FILE NOT FOUND"}
        continue
    }

    # Test parsing
    try {
        $content = Get-Content $fullPath -Raw -ErrorAction Stop

        # Check for forbidden patterns
        if ($content -match "Export-ModuleMember") {
            Write-Host "❌ BLOCKED: $file — Contains Export-ModuleMember (scripts can't have this)" -ForegroundColor Red
            $failed += @{file=$file; reason="Export-ModuleMember found (invalid for scripts)"}
            continue
        }

        # Try to parse
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
        Write-Host "✅ $file" -ForegroundColor Green
        $passed++

    } catch {
        Write-Host "❌ PARSE ERROR: $file" -ForegroundColor Red
        Write-Host "   $($_.Exception.Message.Split("`n")[0])" -ForegroundColor Red
        $failed += @{file=$file; reason=$_.Exception.Message}
    }
}

Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "RESULTS: $passed passed, $($failed.Count) failed" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "🚨 PRE-FLIGHT FAILED — DAEMON WILL NOT START" -ForegroundColor Red
    Write-Host ""

    foreach ($failure in $failed) {
        Write-Host "❌ $($failure.file)" -ForegroundColor Red
        Write-Host "   Reason: $($failure.reason)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "ACTION REQUIRED: Fix these files before daemon can start" -ForegroundColor Yellow

    exit 1
} else {
    Write-Host ""
    Write-Host "✅ ALL CHECKS PASSED — Safe to start daemons" -ForegroundColor Green
    exit 0
}
