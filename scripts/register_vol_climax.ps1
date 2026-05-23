# register_vol_climax.ps1 -- Registra cron hourly pra vol_climax_scanner.
#
# Strategy: HOURLY. Daily candles atualizam 1x/dia UTC mas CoinEx extended bar pode
# mover durante o dia -- hourly captura sem desperdicio. Dedup interno (1 alert/market/dia).
#
# Edge validado: backtest unified 2026-05-22 mostrou +8.6pp hit-rate vs baseline
# (n=278 events em 47 markets x 3 anos, avg_hit_outcome +14.4% em 5d).
#
# Custo: 24 cycles/dia x ~11 markets x 1 API call = ~264 CoinEx calls/dia (gentle).
# Zero LLM. ~$0/dia.
#
# Uso:
#   pwsh -File scripts\register_vol_climax.ps1            # registra
#   pwsh -File scripts\register_vol_climax.ps1 -Unregister # remove

param([switch] $Unregister)

$taskName   = "CoinExVolClimax"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript = Join-Path $scriptRoot "vol_climax_scanner.ps1"

if (-not (Test-Path $cronScript)) {
    Write-Host "[ERROR] $cronScript nao existe" -ForegroundColor Red
    exit 1
}

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
}
if ($Unregister) {
    Write-Host "Task '$taskName' desregistrada." -ForegroundColor Green; exit 0
}

# Trigger hourly, starting em 3min
$startDate = (Get-Date).AddMinutes(3)
$trigger = New-ScheduledTaskTrigger -Once -At $startDate `
    -RepetitionInterval (New-TimeSpan -Hours 1)

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`""

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Vol Climax Scanner (LONG side selling climax, edge +8.6pp validado backtest unified 2026-05-22)" | Out-Null

$task = Get-ScheduledTask -TaskName $taskName
Write-Host "[OK] Task '$taskName' registrada. Proxima execucao: $startDate (interval HOURLY)" -ForegroundColor Green
Write-Host "  Edge: +8.6pp hit-rate vs baseline (n=278 backtest 3 anos)" -ForegroundColor DarkGray
Write-Host "  Custo: ~264 CoinEx calls/dia (gentle)" -ForegroundColor DarkGray
