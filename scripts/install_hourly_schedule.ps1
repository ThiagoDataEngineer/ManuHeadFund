# install_hourly_schedule.ps1
# Instala task scheduler pra rodar daily_autocalibration a cada hora
# Run as Administrator: Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process; .\scripts\install_hourly_schedule.ps1

param(
    [string]$ScriptPath = "$(Split-Path -Parent $PSScriptRoot)\scripts\daily_autocalibration.ps1",
    [string]$TaskName = "ManuHeadFund-Hourly-AutoCalibration",
    [string]$Author = "ManuHeadFund"
)

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  INSTALLING HOURLY AUTO-CALIBRATION TASK                 ║" -ForegroundColor Cyan
Write-Host "║  Runs every hour at :00                                   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "[ERROR] Must run as Administrator" -ForegroundColor Red
    Write-Host "  Solution: Open PowerShell as Admin and retry" -ForegroundColor Yellow
    exit 1
}

# Verify script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "[ERROR] Script not found: $ScriptPath" -ForegroundColor Red
    exit 1
}

Write-Host "[1] Script path: $ScriptPath" -ForegroundColor Green
Write-Host "[2] Task name: $TaskName" -ForegroundColor Green
Write-Host ""

# Create task action
$action = New-ScheduledTaskAction `
    -Execute "pwsh" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory (Split-Path $ScriptPath -Parent)

Write-Host "[3] Action created (pwsh -File daily_autocalibration.ps1)" -ForegroundColor Green

# Create trigger: every hour at :00
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([timespan]::MaxValue)

Write-Host "[4] Trigger created (every hour)" -ForegroundColor Green

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

Write-Host "[5] Settings created" -ForegroundColor Green
Write-Host ""

# Create or update task
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "[WARN] Task already exists. Updating..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$task = Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "ManuHeadFund: Auto-calibrate gates every hour based on winners/losers analysis" `
    -Author $Author `
    -RunLevel Highest

Write-Host "[6] Task registered: $TaskName" -ForegroundColor Green
Write-Host ""

# Verify
$verify = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($verify) {
    Write-Host "✓ SUCCESS: Task installed" -ForegroundColor Green
    Write-Host ""
    Write-Host "Task Details:" -ForegroundColor Cyan
    Write-Host "  Name: $($verify.TaskName)" -ForegroundColor Gray
    Write-Host "  State: $($verify.State)" -ForegroundColor Gray
    Write-Host "  Path: $($verify.TaskPath)" -ForegroundColor Gray
    Write-Host "  Last Run: $($verify.LastRunTime)" -ForegroundColor Gray
    Write-Host "  Next Run: $($verify.NextRunTime)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To test manually:" -ForegroundColor Yellow
    Write-Host "  Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To view logs:" -ForegroundColor Yellow
    Write-Host "  Get-Content journal/daily_calibration.jsonl -Tail 5" -ForegroundColor Gray
    Write-Host ""
    exit 0
} else {
    Write-Host "✗ FAILED: Task installation failed" -ForegroundColor Red
    exit 1
}
