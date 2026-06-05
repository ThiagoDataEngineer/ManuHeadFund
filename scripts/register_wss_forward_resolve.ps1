# register_wss_forward_resolve.ps1 -- Registra cron task CoinExWssForwardResolve
# Agenda cron_wss_forward_resolve.ps1 para rodar semanalmente (sabado 23h).
# Idempotente: re-registrar atualiza a task existente.
#
# Uso:
#   pwsh -File scripts\register_wss_forward_resolve.ps1            # registra/atualiza
#   pwsh -File scripts\register_wss_forward_resolve.ps1 -DryRun    # so mostra, nao cria
#
# PS 5.1. UTF-8 BOM.

param(
    [switch]$DryRun
)

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$cronScript  = Join-Path $scriptDir "cron_wss_forward_resolve.ps1"
$taskName    = "CoinExWssForwardResolve"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERRO] cron target nao encontrado: $cronScript" -ForegroundColor Red
    exit 1
}

# Calculo do proximo sabado 23h (0=dom..6=sab)
$now = Get-Date
$daysUntilSat = (6 - [int]$now.DayOfWeek + 7) % 7
if ($daysUntilSat -eq 0) {
    # hoje e sabado: agenda hoje se antes das 23h, senao proximo sabado
    if ($now.Hour -lt 23) { $daysUntilSat = 0 } else { $daysUntilSat = 7 }
}
$nextSat = $now.Date.AddDays($daysUntilSat).AddHours(23)

if ($DryRun) {
    Write-Host "[DRYRUN] Registraria task '$taskName'" -ForegroundColor Yellow
    Write-Host "[DRYRUN]   Target : $cronScript" -ForegroundColor Gray
    Write-Host "[DRYRUN]   Trigger: semanal, Sabado 23h (proximo: $($nextSat.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray
    Write-Host "[DRYRUN] Nenhuma task criada." -ForegroundColor Yellow
    exit 0
}

try {
    $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At "23:00"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

    # Idempotente: remove existente antes de re-registrar
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "[INFO] Task existente removida (re-registro idempotente)" -ForegroundColor DarkGray
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Settings $settings -Description "CoinEx WSS forward resolve semanal (sabado 23h)" | Out-Null
    Write-Host "[OK] Task '$taskName' registrada (Sabado 23h)" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao registrar task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
