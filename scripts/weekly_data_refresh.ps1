# weekly_data_refresh.ps1 -- Cron semanal: funding history + correlation matrix.
#
# Roda 1x/semana (Domingo 02:00 BRT, antes do promotion_weekly_cron).
# Refresh incremental dos coletores que alimentam Test-FundingRateGate e Test-CrossAssetCorrelation.
#
# 1. binance_funding_collector.py --since 2020-01-01 (full re-collect; idempotente, sobrescreve)
#    -> journal/funding_history/<SYM>.jsonl
# 2. correlation_matrix.py (le candles cache atualizado)
#    -> journal/correlation_matrix.json
#
# Exit code 0 = sucesso; 1 = falha critica; 2 = warning (1 collector falhou).

$ErrorActionPreference = "Continue"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$logDir      = Join-Path $projectRoot "logs"
$journalDir  = Join-Path $projectRoot "journal"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$logFile = Join-Path $logDir ("weekly_data_refresh_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "===== Weekly Data Refresh START ====="

# Tier A LIVE symbols dinamicos da whitelist mais recente
$wlFile = Get-ChildItem -Path $journalDir -Filter "per_asset_whitelist_*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
$symbols = @()
if ($wlFile) {
    try {
        $wl = Get-Content $wlFile.FullName -Raw | ConvertFrom-Json
        # Pega Tier A + Tier B; exclui BITSTAMP (referencia, sem Binance equivalent direto)
        $allMarkets = @()
        $allMarkets += @($wl.TIER_A_LIVE | ForEach-Object { $_.market })
        $allMarkets += @($wl.TIER_B_PAPER | ForEach-Object { $_.market })
        $symbols = @($allMarkets | Where-Object { $_ -and -not ($_ -match "BITSTAMP") } | Select-Object -Unique)
    } catch { Log "WARN: parse whitelist falhou: $_" }
}
if ($symbols.Count -eq 0) {
    $symbols = @("BTCUSDT","ETHUSDT","INJUSDT","SOLUSDT","RENDERUSDT","CFGUSDT","ZECUSDT","PENDLEUSDT")
    Log "INFO: usando fallback hardcoded ($($symbols.Count) symbols)"
} else {
    Log "INFO: $($symbols.Count) symbols da whitelist: $($symbols -join ',')"
}

# 1. Funding collector
$exitCollector = 1
try {
    $symArg = $symbols -join ","
    Log "RUN binance_funding_collector.py --symbols $symArg"
    $py = Join-Path $projectRoot "backtest\binance_funding_collector.py"
    Push-Location $projectRoot
    $env:PYTHONIOENCODING = "utf-8"
    & python $py --symbols $symArg --since "2020-01-01" 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitCollector = $LASTEXITCODE
    Pop-Location
    Log "Funding collector exit=$exitCollector"
} catch {
    Log "ERROR funding collector: $_"
}

# 2. Correlation matrix
$exitMatrix = 1
try {
    $py = Join-Path $projectRoot "backtest\correlation_matrix.py"
    Log "RUN correlation_matrix.py"
    Push-Location $projectRoot
    & python $py 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitMatrix = $LASTEXITCODE
    Pop-Location
    Log "Correlation matrix exit=$exitMatrix"
} catch {
    Log "ERROR correlation matrix: $_"
}

# 3. Trend persistence cache (2026-05-19 PM added)
$exitTrend = 1
try {
    $py = Join-Path $projectRoot "backtest\trend_persistence.py"
    Log "RUN trend_persistence.py --build-cache"
    Push-Location $projectRoot
    & python $py --build-cache 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitTrend = $LASTEXITCODE
    Pop-Location
    Log "Trend persistence exit=$exitTrend"
} catch {
    Log "ERROR trend persistence: $_"
}

# 4. Beta cache rebuild
$exitBeta = 1
try {
    $py = Join-Path $projectRoot "backtest\build_beta_cache.py"
    Log "RUN build_beta_cache.py"
    Push-Location $projectRoot
    & python $py 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitBeta = $LASTEXITCODE
    Pop-Location
    Log "Beta cache exit=$exitBeta"
} catch {
    Log "ERROR beta cache: $_"
}

# 5a. CoinGecko BATCH (2026-05-19 PM v2) -- 300x mais rapido que per-coin.
# /coins/markets retorna 30 markets em 1 call: supply + ATH + price.
$exitCG = 1
try {
    $py = Join-Path $projectRoot "backtest\coingecko_batch.py"
    Log "RUN coingecko_batch.py (supply + ATH + price em ~3s)"
    Push-Location $projectRoot
    $env:PYTHONIOENCODING = "utf-8"
    & python $py 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitCG = $LASTEXITCODE
    Pop-Location
    Log "CoinGecko batch exit=$exitCG"
} catch {
    Log "ERROR coingecko batch: $_"
}

# 5b. CoinGecko --new-only (per-coin com genesis para markets novos sem age_years)
# Tipicamente 0 markets/semana se nao ha additions; ate ~3 markets = ~10s.
$exitCGNew = 1
try {
    $py = Join-Path $projectRoot "backtest\coingecko_enrichment.py"
    Log "RUN coingecko_enrichment.py --new-only (auto-detect novos sem age)"
    Push-Location $projectRoot
    & python $py --new-only --sleep 3 2>&1 | Tee-Object -FilePath $logFile -Append
    $exitCGNew = $LASTEXITCODE
    Pop-Location
    Log "CoinGecko --new-only exit=$exitCGNew"
} catch {
    Log "ERROR coingecko new-only: $_"
}

# 5c. FQS Queue processor (2026-05-20 PM2): markets que Mentor pediu mas nao existem
# no registry sao enfileirados em journal/fqs_enrichment_queue.jsonl. Processa aqui
# (per-coin via coingecko_enrichment) pra populacao automatica.
$exitFqsQueue = 1
try {
    $queueScript = Join-Path $projectRoot "scripts\process_fqs_queue.ps1"
    if (Test-Path $queueScript) {
        Log "RUN process_fqs_queue.ps1 (auto-enrich markets faltantes)"
        & powershell -NoProfile -ExecutionPolicy Bypass -File $queueScript 2>&1 | Tee-Object -FilePath $logFile -Append
        $exitFqsQueue = $LASTEXITCODE
        Log "FQS queue processor exit=$exitFqsQueue"
    } else {
        Log "process_fqs_queue.ps1 nao existe (skip)"
        $exitFqsQueue = 0
    }
} catch {
    Log "ERROR fqs queue: $_"
}

Log "===== Weekly Data Refresh END ====="

$exits = @{
    collector       = $exitCollector
    matrix          = $exitMatrix
    trend           = $exitTrend
    beta            = $exitBeta
    coingecko_batch = $exitCG
    coingecko_new   = $exitCGNew
    fqs_queue       = $exitFqsQueue
}
$failed = @($exits.Keys | Where-Object { $exits[$_] -ne 0 })
if ($failed.Count -eq 0) {
    Log "ALL OK ($($exits.Count)/$($exits.Count))"
    exit 0
} elseif ($failed.Count -eq $exits.Count) {
    Log "ALL FAILED"
    exit 1
} else {
    Log "PARTIAL: failed=[$($failed -join ',')] OK=[$(($exits.Keys | Where-Object { $exits[$_] -eq 0 }) -join ',')]"
    exit 2
}
