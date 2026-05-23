# register_promotion_cron.ps1 -- Agenda promotion_weekly_cron.ps1 no Task Scheduler
#
# Cria task "CoinExPromotionCron" rodando Domingo 03:00 local (BRT no host).
# Idempotent: delete existing first, recreate fresh.
#
# Uso:
#   pwsh -File scripts\register_promotion_cron.ps1            # registra
#   pwsh -File scripts\register_promotion_cron.ps1 -Unregister # remove
#
# Requer Windows + PowerShell elevado (admin) para criar/deletar tasks.

param(
    [switch]$Unregister
)

$taskName    = "CoinExPromotionCron"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$cronScript  = Join-Path $scriptRoot "promotion_weekly_cron.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

# Delete existing (idempotent)
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removendo task existente '$taskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}

if ($Unregister) {
    Write-Host "Task '$taskName' desregistrada (se existia)." -ForegroundColor Green
    exit 0
}

# Criar task: Domingo 03:00 local time
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`" -Once" `
    -WorkingDirectory $projectRoot

$trigger = New-ScheduledTaskTrigger -Daily -At "02:00"

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Promotion ladder weekly cron -- evaluates pipeline candidates e propoe via Telegram" `
        -ErrorAction Stop | Out-Null
    Write-Host "[OK] Task '$taskName' registrada." -ForegroundColor Green
    Write-Host "  Trigger: DAILY 02:00 BRT (todo dia)"
    Write-Host "  Action:  $cronScript -Once"
    Write-Host ""
    Write-Host "Para testar agora:  Start-ScheduledTask -TaskName $taskName"
    Write-Host "Para remover:       pwsh -File register_promotion_cron.ps1 -Unregister"
} catch {
    Write-Host "[ERROR] Falha ao registrar task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Possivelmente precisa rodar PowerShell como Administrator." -ForegroundColor Yellow
    exit 1
}
