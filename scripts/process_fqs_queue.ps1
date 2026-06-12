# process_fqs_queue.ps1 -- Auto-enrich markets sem entry no coin_registry.json
#
# Background:
#   Build-MentorFullContext (mentor_agent.ps1) detecta markets faltantes e
#   enfileira em journal/fqs_enrichment_queue.jsonl. Este script:
#   1. Le queue (jsonl, append-only, sem schema rigido)
#   2. Dedupe markets unicos
#   3. Chama coingecko_enrichment.py --markets X,Y,Z pra cada
#   4. Limpa queue ao final (move pra .processed)

param([switch]$DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$journalDir = Join-Path $projectRoot "journal"
$queueFile = Join-Path $journalDir "fqs_enrichment_queue.jsonl"
$logDir = Join-Path $projectRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("fqs_enrich_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== FQS Enrichment Queue Processor ==="

if (-not (Test-Path $queueFile)) {
    Log "Queue vazia (arquivo nao existe). Exit."
    exit 0
}

# Le + dedupe
$markets = New-Object System.Collections.Generic.HashSet[string]
Get-Content $queueFile -Encoding UTF8 | ForEach-Object {
    try {
        $obj = $_ | ConvertFrom-Json
        if ($obj.market) { [void]$markets.Add([string]$obj.market) }
    } catch {}
}
Log "Markets unicos na queue: $($markets.Count) [$([string]::Join(',', $markets))]"

if ($markets.Count -eq 0) {
    Log "Queue vazia apos dedupe. Cleanup."
    Remove-Item $queueFile -Force -ErrorAction SilentlyContinue
    exit 0
}

if ($DryRun) {
    Log "DRY_RUN -- would enrich $($markets.Count) markets"
    exit 0
}

# Chama coingecko enrichment per-coin (full data: genesis, ath, max_supply etc)
$csvMarkets = [string]::Join(',', $markets)
$pyScript = Join-Path $projectRoot "backtest\coingecko_enrichment.py"
if (-not (Test-Path $pyScript)) {
    Log "ERROR: $pyScript nao existe"
    exit 1
}

Log "Executing: python $pyScript --markets $csvMarkets"
try {
    & python $pyScript --markets $csvMarkets 2>&1 | ForEach-Object { Log "  [py] $_" }
    if ($LASTEXITCODE -ne 0) {
        Log "ERROR: python exit code $LASTEXITCODE"
        exit 1
    }
    Log "Enrichment OK"
} catch {
    Log "ERROR: $($_.Exception.Message)"
    exit 1
}

# Move queue pra .processed (audit trail) em vez de delete
$processedFile = Join-Path $journalDir ("fqs_enrichment_queue_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".processed.jsonl")
Move-Item $queueFile $processedFile -Force -ErrorAction SilentlyContinue
Log "Queue movida -> $processedFile"
