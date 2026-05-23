# cron_staleness_audit.ps1 -- Weekly Mon 02:00 BRT: capital drift + items stale.
#
# Phase 0b (2026-05-23): identifica automaticamente o que precisa rodar.
# Output: journal/staleness_audit.json + TG alert se HIGH priority items.

param([switch] $DryRun, [switch] $SendTg)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path $projectRoot "agents\config.local.ps1") -ErrorAction SilentlyContinue
. (Join-Path $projectRoot "agents\lib_capital_context.ps1")
. (Join-Path $projectRoot "agents\lib_staleness_engine.ps1")
. (Join-Path $projectRoot "agents\lib_telegram.ps1") -ErrorAction SilentlyContinue

$logFile = Join-Path $projectRoot ("logs\staleness_audit_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== Staleness Audit START ==="

# 1. Get current capital + drift
$ctx = Get-CapitalContext -Force
Log "  Capital current: spot=$($ctx.spot) futures=$($ctx.futures) total=$($ctx.total) source=$($ctx.source)"
$drift = Get-CapitalDrift -Threshold 30
if ($null -ne $drift.drift_pct) {
    Log "  Drift: $($drift.drift_pct)% (baseline=$($drift.baseline_total) tag=$($drift.baseline_tag)) stale=$($drift.is_stale)"
} else {
    Log "  Drift: no baseline registered (run Set-CapitalBaseline first)"
}

# 2. Audit staleness
$capitalSnap = @{ spot=$ctx.spot; futures=$ctx.futures; total=$ctx.total }
$driftPct = if ($null -ne $drift.drift_pct) { $drift.drift_pct } else { 0 }
$audit = Write-StalenessAudit -ProjectRoot $projectRoot -DriftPct $driftPct -CapitalSnapshot $capitalSnap
Log "  Items stale: $($audit.n_stale) | HIGH: $($audit.n_high) | auto_safe: $($audit.n_auto_safe)"
foreach ($item in $audit.items_stale) {
    Log "    [$($item.priority)] $($item.name): $(($item.reasons -join ', '))  cmd=$($item.rerun_cmd)"
}

# 3. TG alert se HIGH priority items
if ($SendTg -and $audit.n_high -gt 0 -and (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue)) {
    $highItems = $audit.items_stale | Where-Object { $_.priority -eq "HIGH" } | Select-Object -First 5
    $itemSummary = ($highItems | ForEach-Object { "$($_.name): $(($_.reasons -join ','))" }) -join "`n  "
    $msg = "[STALENESS AUDIT] HIGH priority`nCapital: total=$($ctx.total) drift=$([math]::Round($driftPct,1))%`n$($audit.n_high) HIGH items:`n  $itemSummary"
    if (-not $DryRun) {
        try { Send-TelegramAlert -Message $msg | Out-Null; Log "  TG alert enviado" } catch { Log "  TG fail: $_" }
    } else { Log "  [DRYRUN] would send TG alert" }
}

Log "=== Done ==="
exit 0
