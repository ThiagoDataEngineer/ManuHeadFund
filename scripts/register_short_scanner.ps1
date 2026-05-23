# register_short_scanner.ps1 -- Cron hourly: SHORT signal observatory.

param([switch]$Unregister)

$taskName    = "CoinExShortScanner"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "short_scanner.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
if ($Unregister) {
    Write-Host "[OK] $taskName unregistered" -ForegroundColor Green
    exit 0
}

$argStr = '-NoProfile -ExecutionPolicy Bypass -File "' + $cronScript + '"'
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argStr -WorkingDirectory $projectRoot

# Hourly trigger
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 365)

$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$userId = "$($env:USERDOMAIN)\$($env:USERNAME)"
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Hourly SHORT signal scanner Tier 2 Block 1 observatory only no trade execution" | Out-Null
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$v = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($v) {
    Write-Host "[OK] $taskName registered: hourly observatory" -ForegroundColor Green
    Write-Host "  Next run: $($v.Triggers[0].StartBoundary)"
    exit 0
}
exit 1
