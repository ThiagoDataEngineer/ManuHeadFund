# faro_v3_schedule.ps1 — Setup Windows Task Scheduler for FARO V3 daemons
# Creates recurring tasks for engine (every 6h), entry (every 30m), manager (every 1h)

param([string] $Action = "install", [string] $ProjectRoot)

if (-not $ProjectRoot) {
    $ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$scriptsDir = Join-Path $ProjectRoot "scripts"

function Get-TaskName { param([string] $Script) ; return "ManuHeadFund_FARO_V3_$($Script -replace '\.ps1$', '')" }
function Invoke-TaskScheduler { param([string] $TaskName, [string] $ScriptPath, [string] $Trigger, [string] $Action) ; Write-Host "📋 $Action : $TaskName ($Trigger)" }

if ($Action -eq "install") {
    Write-Host "🔧 Installing FARO V3 Task Scheduler jobs..." -ForegroundColor Cyan

    # Validate PowerShell path
    $psPath = "$PSHOME\pwsh.exe"
    if (-not (Test-Path $psPath)) {
        $psPath = "$PSHOME\powershell.exe"
    }
    if (-not (Test-Path $psPath)) {
        Write-Error "❌ PowerShell executable not found"
        exit 1
    }

    # Task 1: Engine every 6 hours (00:00, 06:00, 12:00, 18:00)
    $enginePath = Join-Path $scriptsDir "faro_v3_engine.ps1"
    $engineTask = Get-TaskName "engine"
    $engineAction = New-ScheduledTaskAction -Execute $psPath -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$enginePath`""
    $engineTrigger = New-ScheduledTaskTrigger -Daily -At "00:00:00" -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration ([timespan]::MaxValue)
    $engineSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun -AllowStartIfOnBatteries
    try {
        Register-ScheduledTask -TaskName $engineTask -Action $engineAction -Trigger $engineTrigger -Settings $engineSettings -Force -ErrorAction Stop | Out-Null
        Write-Host "✅ $engineTask scheduled: every 6 hours" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Failed to schedule $engineTask : $_"
    }

    # Task 2: Entry every 30 minutes
    $entryPath = Join-Path $scriptsDir "faro_v3_entry.ps1"
    $entryTask = Get-TaskName "entry"
    $entryAction = New-ScheduledTaskAction -Execute $psPath -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$entryPath`""
    $entryTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([timespan]::MaxValue)
    $entrySettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun
    try {
        Register-ScheduledTask -TaskName $entryTask -Action $entryAction -Trigger $entryTrigger -Settings $entrySettings -Force -ErrorAction Stop | Out-Null
        Write-Host "✅ $entryTask scheduled: every 30 minutes" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Failed to schedule $entryTask : $_"
    }

    # Task 3: Manager every 1 hour
    $managerPath = Join-Path $scriptsDir "faro_v3_manager.ps1"
    $managerTask = Get-TaskName "manager"
    $managerAction = New-ScheduledTaskAction -Execute $psPath -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$managerPath`""
    $managerTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([timespan]::MaxValue)
    $managerSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun
    try {
        Register-ScheduledTask -TaskName $managerTask -Action $managerAction -Trigger $managerTrigger -Settings $managerSettings -Force -ErrorAction Stop | Out-Null
        Write-Host "✅ $managerTask scheduled: every 1 hour" -ForegroundColor Green
    } catch {
        Write-Warning "⚠️  Failed to schedule $managerTask : $_"
    }

    Write-Host "🟢 All FARO V3 tasks installed" -ForegroundColor Green
}

elseif ($Action -eq "uninstall") {
    Write-Host "🗑️  Removing FARO V3 Task Scheduler jobs..." -ForegroundColor Yellow
    $tasks = @("engine", "entry", "manager")
    foreach ($t in $tasks) {
        $taskName = Get-TaskName $t
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "✅ Removed: $taskName" -ForegroundColor Green
        } catch {
            Write-Warning "⚠️  Failed to remove $taskName : $_"
        }
    }
}

elseif ($Action -eq "status") {
    Write-Host "📊 FARO V3 Task Scheduler status:" -ForegroundColor Cyan
    $tasks = @("engine", "entry", "manager")
    foreach ($t in $tasks) {
        $taskName = Get-TaskName $t
        try {
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
            $lastRun = $task.LastRunTime ?? "Never"
            $nextRun = $task.NextRunTime ?? "Not scheduled"
            $state = $task.State
            Write-Host "  $taskName : $state | last=$lastRun | next=$nextRun" -ForegroundColor Cyan
        } catch {
            Write-Host "  $taskName : NOT FOUND" -ForegroundColor Gray
        }
    }
}

else {
    Write-Host "Usage: faro_v3_schedule.ps1 -Action [install|uninstall|status]" -ForegroundColor Yellow
}
