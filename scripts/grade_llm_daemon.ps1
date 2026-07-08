# grade_llm_daemon.ps1 — Runs grade_llm_decisions.ps1 every 1 hour
param([switch]$Daemon)

$root = Split-Path $PSScriptRoot -Parent
$gradeScript = Join-Path $root "scripts\grade_llm_decisions.ps1"
$logFile = Join-Path $root "journal\grade_llm_daemon.log"

function Write-Log { param([string]$msg); "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg" | Add-Content $logFile -Encoding UTF8 }

Write-Log "DAEMON: Started (PID: $PID)"

$interval = 3600  # 1 hour in seconds

while ($true) {
    try {
        Write-Log "Running grade_llm_decisions.ps1..."
        & $gradeScript -MinAgeHours 0 -MaxGrade 300
        Write-Log "✅ Grade run completed"
    } catch {
        Write-Log "❌ Error: $_"
    }
    
    Write-Log "Sleeping 1h until next run..."
    Start-Sleep -Seconds $interval
}
