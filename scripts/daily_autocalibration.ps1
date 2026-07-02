#!/usr/bin/env pwsh
# daily_autocalibration.ps1
# 2026-06-18: Hourly self-learning calibration (CLOUD-ONLY)
# Runs via GitHub Actions every hour
# Uses: Supabase for state persistence (no local files)

param(
    [string]$JournalDir = "journal",
    [string]$SupabaseUrl = $env:SUPABASE_URL,
    [string]$SupabaseKey = $env:SUPABASE_SERVICE_KEY
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

# Step 2: Load current gates (from Supabase or local fallback)
Write-Host "[STEP 2] Loading current gates..." -ForegroundColor Yellow

$gates = $null

# Try Supabase first
if ($SupabaseUrl -and $SupabaseKey) {
    try {
        $headers = @{
            "Authorization" = "Bearer $SupabaseKey"
            "Content-Type" = "application/json"
            "Prefer" = "return=representation"
        }
        $response = Invoke-RestMethod -Uri "$SupabaseUrl/rest/v1/regime_state?select=*" -Headers $headers -ErrorAction Stop
        if ($response -and $response.Count -gt 0) {
            $gates = @{
                gates = @{
                    conviction_threshold = $(if ($null -ne $response[0].conviction_threshold) { $response[0].conviction_threshold } else { 50 })
                    mesa_score_strong = $(if ($null -ne $response[0].mesa_score_strong) { $response[0].mesa_score_strong } else { 60 })
                }
            }
            Write-Host "  [SUPABASE] Loaded gates from cloud" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Supabase load failed: $_ (using fallback)" -ForegroundColor Yellow
    }
}

# Fallback: load from local JSON
if (-not $gates) {
    $gates_file = "config/gates_drift.json"
    if (Test-Path $gates_file) {
        $gates = Get-Content $gates_file | ConvertFrom-Json
        Write-Host "  [LOCAL] Loaded gates from JSON (Supabase unavailable)" -ForegroundColor Yellow
    } else {
        # Hardcoded defaults
        $gates = @{
            gates = @{
                conviction_threshold = 50
                mesa_score_strong = 60
            }
        }
        Write-Host "  [DEFAULT] Using hardcoded defaults" -ForegroundColor Yellow
    }
}

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

# Step 4: Update gates (to Supabase or local)
Write-Host "[STEP 4] Updating gates configuration..." -ForegroundColor Yellow

$gates.gates.conviction_threshold = $new_conviction
$gates.gates.mesa_score_strong = $new_mesa
$calibration_ts = (Get-Date -Format 'o')

# Try Supabase update first
$updated_supabase = $false
if ($SupabaseUrl -and $SupabaseKey) {
    try {
        $headers = @{
            "Authorization" = "Bearer $SupabaseKey"
            "Content-Type" = "application/json"
            "Prefer" = "return=representation"
        }
        $body = @{
            conviction_threshold = $new_conviction
            mesa_score_strong = $new_mesa
            last_calibration = $calibration_ts
            last_calibration_action = $action
            last_calibration_reason = $reason
        } | ConvertTo-Json

        $response = Invoke-RestMethod `
            -Uri "$SupabaseUrl/rest/v1/regime_state?id=eq.1" `
            -Method PATCH `
            -Headers $headers `
            -Body $body `
            -ErrorAction Stop

        Write-Host "  [SUPABASE] Gates updated in cloud" -ForegroundColor Green
        $updated_supabase = $true
    } catch {
        Write-Host "  [WARN] Supabase update failed: $_ (falling back to local)" -ForegroundColor Yellow
    }
}

# Also update local JSON for redundancy
if (Test-Path "$ConfigDir/gates_drift.json") {
    try {
        $gates | Add-Member -NotePropertyName "last_calibration_date" -NotePropertyValue $calibration_ts -Force
        $gates | Add-Member -NotePropertyName "last_calibration_action" -NotePropertyValue $action -Force
        $gates | Add-Member -NotePropertyName "last_calibration_reason" -NotePropertyValue $reason -Force
        $gates_json = $gates | ConvertTo-Json -Depth 10
        $gates_json | Set-Content "$ConfigDir/gates_drift.json"
        Write-Host "  [LOCAL] JSON backup updated"
    } catch {}
}

if (-not $updated_supabase) {
    Write-Host "  [WARN] Update not persisted to Supabase" -ForegroundColor Yellow
}

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
