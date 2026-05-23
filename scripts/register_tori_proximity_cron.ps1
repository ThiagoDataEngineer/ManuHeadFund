# register_tori_proximity_cron.ps1 -- Registra/desregistra CoinExToriProximity 15min.
#
# Anticipatory Tori scanner: detecta proximidade da action_line ANTES do bounce
# maturar, alerta no TG pra observar o setup. Zero LLM, fail-silent.
#
# Uso:
#   pwsh -File scripts\register_tori_proximity_cron.ps1                # registra
#   pwsh -File scripts\register_tori_proximity_cron.ps1 -Unregister    # remove
#
# PS 5.1.

param([switch]$Unregister)

$taskName    = "CoinExToriProximity"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript  = Join-Path $scriptRoot "tori_proximity_scanner.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
if ($Unregister) {
    Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green
    exit 0
}

# Trigger 15min, starting em 2min (da tempo de validar antes da primeira execucao)
$startDate = (Get-Date).AddMinutes(2)
$trigger = New-ScheduledTaskTrigger -Once -At $startDate -RepetitionInterval (New-TimeSpan -Minutes 15)

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings `
    -Description "Tori proximity scanner (15min) -- alerta antecipatorio de bounce em trendline soft sobre PAPER whitelist. Zero LLM. Persiste journal/tori_proximity_state.json consumido por scan_master/gem_loop/Mentor." | Out-Null

$task = Get-ScheduledTask -TaskName $taskName
Write-Host "[OK] Task '$taskName' registrada. Proxima execucao: $startDate" -ForegroundColor Green
Write-Host "  Acao: $($task.Actions.Execute) $($task.Actions.Arguments)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Logs:    journal\tori_proximity_scanner.log" -ForegroundColor DarkGray
Write-Host "Dedup:   journal\tori_proximity_alerts.jsonl" -ForegroundColor DarkGray
Write-Host "Manual:  pwsh -File scripts\tori_proximity_scanner.ps1 -DryRun" -ForegroundColor DarkGray
