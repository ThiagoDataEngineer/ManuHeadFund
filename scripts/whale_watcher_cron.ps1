# whale_watcher_cron.ps1 -- Cron entry point pra whale watcher.
#
# Roda 1 cycle de Invoke-WhaleWatcherCycle, persiste log.
# Idempotent: lib_whale_watcher dedupa via journal/whale_alerts_seen.jsonl.
#
# Cadencia recomendada: 10min (mempool muda rapido, mas TXs grandes ficam 1-3 blocks
# pendentes ~10-30min antes confirmation).

param(
    [double] $MinBtc = 100.0,    # Threshold default ~$7.7M @ $77k/BTC
    [int]    $DedupeHours = 24,
    [switch] $DryRun
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "config.local.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_telegram.ps1")
. (Join-Path (Join-Path $projectRoot "agents") "lib_whale_watcher.ps1")

$logFile = Join-Path $projectRoot ("logs\whale_cron_" + (Get-Date -Format "yyyyMMdd") + ".log")
$logDir = Split-Path $logFile -Parent
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

try {
    $r = Invoke-WhaleWatcherCycle -MinBtc $MinBtc -DedupeHours $DedupeHours -DryRun:$DryRun
    Log ("Cycle done: fetched=$($r.fetched) new_alerts=$($r.new_alerts) total_btc_alerted=$($r.total_btc_alerted) min_btc=$MinBtc")
    exit 0
} catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}
