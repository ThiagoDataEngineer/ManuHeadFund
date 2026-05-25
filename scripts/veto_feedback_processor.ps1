# scripts\veto_feedback_processor.ps1
# Processa fila de vetos e executa acoes corretivas
# Executar a cada 30min via Task Scheduler
# 2026-05-24

$scriptRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path (Join-Path $scriptRoot "agents") "lib_veto_feedback.ps1")

# Log file
$logFile = (Join-Path (Join-Path $scriptRoot "logs") "veto_feedback_processor.log")
$logDir = Split-Path -Parent $logFile

if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

Write-Log "=== VETO FEEDBACK PROCESSOR START ==="

try {
    # Processar fila
    $result = Process-VetoFeedbackQueue -DryRun:$false
    
    Write-Log "Processed: $($result.processed)"
    Write-Log "Success: $($result.success)"
    Write-Log "Failed: $($result.failed)"
    Write-Log "Skipped: $($result.skipped)"
    
    Write-Log "=== VETO FEEDBACK PROCESSOR END ==="
}
catch {
    Write-Log "CRITICAL ERROR: $_"
    Write-Log $_.ScriptStackTrace
    exit 1
}
