# register_whale_watcher.ps1 -- Registra cron 10min pra Whale Watcher MVP.
#
# Strategy: 10min cycle. Mempool BTC TXs ficam pendentes 10-30min antes confirmation,
# entao 10min interval captura whales novos sem sobreposicao excessiva.
#
# Custos: mempool.space free, sem signup. ~144 calls/dia. Bem dentro de rate limits.
#
# Uso:
#   pwsh -File scripts\register_whale_watcher.ps1            # registra
#   pwsh -File scripts\register_whale_watcher.ps1 -Unregister # remove

param(
    [switch] $Unregister,
    [double] $MinBtc = 100.0,
    [int]    $IntervalMinutes = 10
)

$taskName   = "CoinExWhaleWatcher"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$cronScript = Join-Path $scriptRoot "whale_watcher_cron.ps1"

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

# Trigger every N min, starting em 2min
$startDate = (Get-Date).AddMinutes(2)
$trigger = New-ScheduledTaskTrigger -Once -At $startDate `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cronScript`" -MinBtc $MinBtc"

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action `
    -Settings $settings -Description "Whale Watcher MVP (mempool.space BTC pending TXs >=${MinBtc}BTC)" | Out-Null

$task = Get-ScheduledTask -TaskName $taskName
Write-Host "[OK] Task '$taskName' registrada. Proxima execucao: $startDate (intervalo ${IntervalMinutes}min)" -ForegroundColor Green
Write-Host "  Acao: $($task.Actions.Execute) $($task.Actions.Arguments)" -ForegroundColor DarkGray
Write-Host "  Threshold: >= $MinBtc BTC" -ForegroundColor DarkGray
