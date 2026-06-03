# Clean restart do telegram_listener
# Mata todos os processos anteriores e inicia uma nova instância limpa

param([switch]$NoStart)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$journalDir = Join-Path $projectRoot "journal"
$scriptDir = Join-Path $projectRoot "scripts"

Write-Host "[RESTART] Iniciando limpeza..."

# Kill ALL PowerShell processes with telegram/listener
Get-Process pwsh, powershell -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cmd = (Get-WmiObject Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        if ($cmd -and ($cmd.Contains("telegram_listener") -or $cmd.Contains("telegram_listener_wrapper"))) {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Host "[RESTART] Killed PID=$($_.Id)"
        }
    } catch {}
}

Start-Sleep -Seconds 2

# Clean state files
@(Join-Path $journalDir "tg_listener.log", "tg_listener_state.json") | ForEach-Object {
    if (Test-Path $_) {
        if ($_ -like "*.log") { Clear-Content $_ } else { Remove-Item $_ -Force }
    }
}

# Set initial state
$state = @{
    last_update_id = 0
    updated_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    restart_reason = "clean_restart_$(Get-Date -Format yyyyMMdd_HHmmss)"
}
$state | ConvertTo-Json | Out-File (Join-Path $journalDir "tg_listener_state.json") -Encoding utf8

Write-Host "[RESTART] State resetado"

if (-not $NoStart) {
    # Start new instance
    $env:TELEGRAM_BOT_TOKEN = "8763265579:AAFPaVZjeS_rQSzs4xpzb9stMG5veP_Qo54"
    $env:TELEGRAM_CHAT_ID = "5592104053"

    Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $scriptDir 'telegram_listener.ps1')`"" -WindowStyle Hidden
    Write-Host "[RESTART] Nova instância iniciada"

    Start-Sleep -Seconds 5
    $log = Get-Content (Join-Path $journalDir "tg_listener.log") -Tail 3 -ErrorAction SilentlyContinue
    Write-Host "`n[LOG]:"
    $log | ForEach-Object { Write-Host "  $_" }
}
