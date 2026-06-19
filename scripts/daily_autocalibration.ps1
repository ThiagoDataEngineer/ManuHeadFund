#!/usr/bin/env pwsh
# daily_autocalibration.ps1
# 2026-06-18: Daily self-learning calibration
# Runs at 00:00 UTC: analyzes yesterday, updates gates for today

param(
    [string]$JournalDir = "journal",
    [string]$ConfigDir = "config"
)

# Load insight tool
Write-Host "[AUTOCALIBRATION] Starting daily calibration cycle" -ForegroundColor Cyan
Write-Host "[AUTOCALIBRATION] Time: $(Get-Date -Format 'o')" -ForegroundColor Cyan
Write-Host ""

# Step 1: Run insight tool
Write-Host "[STEP 1] Running insight analysis..." -ForegroundColor Yellow
$insight_output = & python3 backtest/insight_realtime_winners_24h.py 2>&1 | Out-String

# Parse output
$gap_line = $insight_output | Select-String "NET:" | ForEach-Object { $_.Line }
$action_line = $insight_output | Select-String "Action:" | ForEach-Object { $_.Line }

Write-Host $gap_line
Write-Host $action_line
Write-Host ""

# Step 2: Load current gates
Write-Host "[STEP 2] Loading current gates..." -ForegroundColor Yellow
$gates_file = "$ConfigDir/gates_drift.json"
$gates = Get-Content $gates_file | ConvertFrom-Json

Write-Host "  Current conviction: $($gates.gates.conviction_threshold)"
Write-Host "  Current mesa_strong: $($gates.gates.mesa_score_strong)"
Write-Host ""

# Step 3: Decide calibration
Write-Host "[STEP 3] Deciding calibration..." -ForegroundColor Yellow

$new_conviction = $gates.gates.conviction_threshold
$new_mesa = $gates.gates.mesa_score_strong
$action = "MAINTAIN"
$reason = "Stable"

if ($gap_line -match "left.*(\d+)") {
    $gap = [int]$matches[1]

    if ($gap -gt 600) {
        $new_conviction = [math]::Max(45, $new_conviction - 2)
        $new_mesa = [math]::Max(50, $new_mesa - 5)
        $action = "OPEN"
        $reason = "Missed $gap in gains — loosen gates"
    }
    elseif ($gap -lt -200) {
        $new_conviction = [math]::Min(55, $new_conviction + 2)
        $new_mesa = [math]::Min(75, $new_mesa + 5)
        $action = "TIGHTEN"
        $reason = "Avoided large losses — tighten gates"
    }
}

Write-Host "  Action: $action"
Write-Host "  Reason: $reason"
Write-Host "  New conviction: $new_conviction (was $($gates.gates.conviction_threshold))"
Write-Host "  New mesa_strong: $new_mesa (was $($gates.gates.mesa_score_strong))"
Write-Host ""

# Step 4: Update gates
Write-Host "[STEP 4] Updating gates configuration..." -ForegroundColor Yellow

$gates.gates.conviction_threshold = $new_conviction
$gates.gates.mesa_score_strong = $new_mesa

# Add metadata
$gates | Add-Member -NotePropertyName "last_calibration_date" -NotePropertyValue (Get-Date -Format 'o') -Force
$gates | Add-Member -NotePropertyName "last_calibration_action" -NotePropertyValue $action -Force
$gates | Add-Member -NotePropertyName "last_calibration_reason" -NotePropertyValue $reason -Force

$gates_json = $gates | ConvertTo-Json -Depth 10
$gates_json | Set-Content $gates_file

Write-Host "  gates_drift.json updated"
Write-Host ""

# Step 5: Log calibration
Write-Host "[STEP 5] Logging calibration event..." -ForegroundColor Yellow

$log_entry = @{
    timestamp = (Get-Date -Format 'o')
    action = $action
    reason = $reason
    conviction_before = $gates.gates.conviction_threshold
    conviction_after = $new_conviction
    mesa_before = $gates.gates.mesa_score_strong
    mesa_after = $new_mesa
} | ConvertTo-Json

$log_entry | Add-Content "$JournalDir/daily_calibration.jsonl"

Write-Host "  Logged to journal/daily_calibration.jsonl"
Write-Host ""

Write-Host "[AUTOCALIBRATION] ✓ Calibration cycle complete" -ForegroundColor Green
Write-Host ""
