# daily_kelly_audit.ps1 -- Auto-activator pra Kelly sizing.
# Roda 02:35 BRT (5 min depois do parallel audit), checa trade_outcomes,
# se passa criterios cria journal/USE_KELLY_SIZING.flag.

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$journalDir = Join-Path $scriptDir "..\journal"
$logDir = Join-Path $scriptDir "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$logFile = Join-Path $logDir ("kelly_audit_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== Kelly Graduation Audit START ==="
$global:JOURNAL_DIR = $journalDir

try {
    . (Join-Path $agentsDir "lib_feedback_loop.ps1")
    . (Join-Path $agentsDir "lib_kelly_graduation.ps1")
} catch {
    Log "ERROR loading libs: $_"
    exit 1
}

try {
    $r = Invoke-KellyGraduationAudit
    Log "Action: $($r.action)"
    Log "n=$($r.check.n_trades) win_rate=$($r.check.win_rate) avg_r=$($r.check.avg_r)"
    if ($r.action -eq "enabled") {
        Log "FLAG ENABLED: $($r.enable.flag_path)"
    } else {
        Log "Reason: $($r.check.reason)"
    }
    exit 0
} catch {
    Log "ERROR audit: $_"
    exit 1
}
