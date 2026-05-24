# CORRIGIR_TASK_DASHBOARD.ps1
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Write-Host "=== CORRIGINDO TASK DASHBOARD ===" -ForegroundColor Cyan
Unregister-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML" -Confirm:$false
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\Users\thiag\Coinex_AI_USER_API\UPDATE_DASHBOARD_COMPLETO.ps1`"" -WorkingDirectory "C:\Users\thiag\Coinex_AI_USER_API"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -MultipleInstances IgnoreNew -Hidden
Register-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Dashboard completo" | Out-Null
Write-Host "SUCESSO! Task corrigida!" -ForegroundColor Green
& "C:\Users\thiag\Coinex_AI_USER_API\UPDATE_DASHBOARD_COMPLETO.ps1"
Start-Sleep -Seconds 3