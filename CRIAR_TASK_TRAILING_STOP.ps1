$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Write-Host "=== CRIANDO TASK TRAILING STOP ===" -ForegroundColor Cyan
$existingTask = Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -ErrorAction SilentlyContinue
if ($existingTask) { Unregister-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -Confirm:$false }
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Users\thiag\Coinex_AI_USER_API\scripts\trailing_stop_monitor.ps1`"" -WorkingDirectory "C:\Users\thiag\Coinex_AI_USER_API"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -Hidden
Register-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Trailing stop monitor" | Out-Null
Write-Host "SUCESSO! Task criada!" -ForegroundColor Green
Start-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
Start-Sleep -Seconds 3