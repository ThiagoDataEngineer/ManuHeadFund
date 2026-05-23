# scan_2h.ps1 -- Wrapper do GemScan para agendamento (Task Scheduler / cron)
# Executa GemScan, loga resultado, envia alertas Telegram para top gems.
# Chamado pelo cron ebdbe13c a cada 2h.

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$logDir    = Join-Path $scriptDir "..\logs"

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$logFile = Join-Path $logDir "scan_$(Get-Date -Format 'yyyyMMdd').log"
$stamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $line = "[$stamp] [$Level] $Msg"
    Add-Content -Path $logFile -Value $line -Encoding utf8
    Write-Host $line
}

try {
    Write-Log "GemScan iniciado"

    . (Join-Path $agentsDir "config.ps1")
    . (Join-Path $agentsDir "lib_coinex.ps1")
    . (Join-Path $agentsDir "lib_journal.ps1")
    . (Join-Path $agentsDir "lib_telegram.ps1")
    . (Join-Path $agentsDir "gem_agent.ps1")

    $results = Invoke-GemScan -TopN 5

    if ($results -and $results.Count -gt 0) {
        Write-Log "Scan concluido: $($results.Count) gem(s) encontrado(s)"
        foreach ($r in $results) {
            Write-Log "  GEM: $($r.market) score=$($r.score) mode=$($r.mode)"
        }
    } else {
        Write-Log "Scan concluido: nenhum gem encontrado"
    }

} catch {
    Write-Log "ERRO no scan: $_" "ERROR"
    Send-TelegramAlert -Message "[ERROR] GemScan falhou: $_" | Out-Null
    exit 1
}
