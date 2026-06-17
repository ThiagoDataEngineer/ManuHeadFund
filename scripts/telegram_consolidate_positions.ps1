#!/usr/bin/env pwsh
# telegram_consolidate_positions.ps1 -- Enviar resumo consolidado de posições via TG (1x/10min)
# Roda a cada 5 min (schedule ou cron), mas só envia se houver mudanças críticas

param(
    [int]$CheckIntervalSec = 300  # 5 min entre checks
)

$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$logFile = Join-Path $projectRoot "journal" "tg_consolidator.log"

function Write-Log {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content $logFile -Value "[$ts] $Message" -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host "[$ts] $Message"
}

# Load libs
try {
    . (Join-Path $agentsDir "lib_telegram_consolidator.ps1") -ErrorAction Stop
    . (Join-Path $agentsDir "lib_telegram.ps1") -ErrorAction SilentlyContinue
} catch {
    Write-Log "ERROR: Falha ao carregar libs: $($_.Exception.Message)"
    exit 1
}

Write-Log "TG Consolidator iniciado. Intervalo=$CheckIntervalSec sec"

$posFile = Join-Path $projectRoot "journal" "trailing_positions.json"

while ($true) {
    try {
        $result = Send-ConsolidatedTgAlert -PositionFile $posFile

        if ($result.sent) {
            Write-Log "✓ Alerta enviado: crítico=$($result.critico) aviso=$($result.aviso)"
        } elseif ($result.skipped) {
            Write-Log "  Pulado: $($result.reason)"
        } elseif ($result.error) {
            Write-Log "✗ Erro: $($result.error)"
        }
    } catch {
        Write-Log "ERROR em ciclo: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $CheckIntervalSec
}
