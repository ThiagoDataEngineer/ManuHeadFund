# lib_fqs_lazy_enrich.ps1 -- P3 (2026-05-23): synchronous on-demand FQS enrichment.
#
# Trigger: GEM detected, market NAO esta em coin_registry.json (FQS missing).
# Action: chamar coingecko_enrichment.py --markets X SINCRONO (1-3s latency).
# Resultado: market enriched -> FQS lookup imediato -> auto_approve gates re-check.
#
# Substitui o blocking veto "fqs_category_too_low(N/A_no_registry)" por:
#   1. Tenta lazy enrich (~1s)
#   2. Se sucesso + FQS QUALITY+: GEM passa
#   3. Se falha: fallback ao comportamento atual (veto + enqueue)
#
# Rate-limit aware: CoinGecko free tier = 10 calls/min. Cache per-market 24h.
# Cap: max 1 lazy enrich call per cycle (avoid burst).
#
# Funcoes:
#   - Test-FqsLazyEnrichEligible: pre-check (market mapped em MARKET_TO_CG)
#   - Invoke-FqsLazyEnrich: synchronous CoinGecko call + registry update
#   - Get-FqsLazyCacheStatus: rate-limit + recent attempts
#
# PS 5.1. UTF-8 BOM.


$script:LAZY_ENRICH_CACHE_PATH = $null
$script:LAZY_ENRICH_MIN_INTERVAL_SEC = 6  # respect 10/min CoinGecko free tier
$script:LAZY_ENRICH_PER_MARKET_TTL_HOURS = 24


function _Init-LazyEnrichPath {
    if (-not $script:LAZY_ENRICH_CACHE_PATH) {
        $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
        $script:LAZY_ENRICH_CACHE_PATH = Join-Path $journalDir "fqs_lazy_enrich_attempts.jsonl"
    }
}


function Test-FqsLazyEnrichEligible {
    <#
    .SYNOPSIS
    Pre-check: market mapped em MARKET_TO_CG (CoinGecko ID known)?
    Sem mapping, lazy enrich vai falhar — skip cedo.

    .PARAMETER Market
    Symbol like "NEARUSDT", "BTCUSDT".

    .OUTPUTS
    PSCustomObject @{ eligible, cg_id, reason }
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Market)

    # Strip USDT suffix for CG lookup
    $base = $Market -replace "USDT$", "" -replace "USD$", ""

    # Read MARKET_TO_CG mapping from python source (parse simples)
    $cgEnrichPy = Join-Path (Split-Path $PSScriptRoot -Parent) "backtest\coingecko_enrichment.py"
    if (-not (Test-Path $cgEnrichPy)) {
        return [PSCustomObject]@{ eligible = $false; cg_id = $null; reason = "coingecko_enrichment_py_missing" }
    }

    # Quick grep MARKET_TO_CG entry
    try {
        $content = Get-Content $cgEnrichPy -Raw -Encoding UTF8
        # Pattern: "MARKETUSDT": "coingecko-id" OR "MARKET": "coingecko-id"
        if ($content -match "['""]$Market['""]\s*:\s*['""]([^'""]+)['""]") {
            return [PSCustomObject]@{ eligible = $true; cg_id = $matches[1]; reason = "mapped" }
        }
        if ($content -match "['""]$base['""]\s*:\s*['""]([^'""]+)['""]") {
            return [PSCustomObject]@{ eligible = $true; cg_id = $matches[1]; reason = "mapped_base" }
        }
        return [PSCustomObject]@{ eligible = $false; cg_id = $null; reason = "not_in_MARKET_TO_CG" }
    } catch {
        return [PSCustomObject]@{ eligible = $false; cg_id = $null; reason = "parse_error" }
    }
}


function Get-FqsLazyCacheStatus {
    <#
    .SYNOPSIS
    Retorna last_attempt_ts global + per-market last_attempt pra rate-limit + dedup.

    .PARAMETER Market
    Optional: query per-market last attempt.

    .OUTPUTS
    PSCustomObject @{ last_global_ts, last_market_ts, can_attempt_global, can_attempt_market }
    #>
    [CmdletBinding()]
    param(
        [string] $Market = "",
        [string] $CachePath = ""
    )
    if ($CachePath) { $script:LAZY_ENRICH_CACHE_PATH = $CachePath } else { _Init-LazyEnrichPath }
    $path = $script:LAZY_ENRICH_CACHE_PATH

    $lastGlobal = $null
    $lastMarket = $null
    if (Test-Path $path) {
        try {
            $lines = @(Get-Content $path -Encoding UTF8 -ErrorAction Stop)
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $obj = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($obj.ts) {
                        $ts = [System.DateTimeOffset]::Parse($obj.ts).UtcDateTime
                        if (-not $lastGlobal -or $ts -gt $lastGlobal) { $lastGlobal = $ts }
                        if ($Market -and $obj.market -eq $Market) {
                            if (-not $lastMarket -or $ts -gt $lastMarket) { $lastMarket = $ts }
                        }
                    }
                } catch {}
            }
        } catch {}
    }
    $now = (Get-Date).ToUniversalTime()
    $canGlobal = if ($lastGlobal) { (($now - $lastGlobal).TotalSeconds -ge $script:LAZY_ENRICH_MIN_INTERVAL_SEC) } else { $true }
    $canMarket = if ($lastMarket) { (($now - $lastMarket).TotalHours -ge $script:LAZY_ENRICH_PER_MARKET_TTL_HOURS) } else { $true }
    return [PSCustomObject]@{
        last_global_ts = $lastGlobal
        last_market_ts = $lastMarket
        can_attempt_global = $canGlobal
        can_attempt_market = $canMarket
    }
}


function Invoke-FqsLazyEnrich {
    <#
    .SYNOPSIS
    Synchronous CoinGecko enrichment for one market. Updates coin_registry.json.

    .DESCRIPTION
    Flow:
      1. Pre-check eligibility (MARKET_TO_CG)
      2. Rate-limit check (last_global >= 6s ago + market not attempted in 24h)
      3. Spawn python coingecko_enrichment.py --markets X (synchronous)
      4. Log attempt (success/fail) to jsonl
      5. Return result with new_fqs_category (if success)

    .PARAMETER Market
    Symbol.

    .PARAMETER TimeoutSec
    Default 20s (CoinGecko response + Python startup + multiple HTTP calls).

    .OUTPUTS
    PSCustomObject @{ success, market, cg_id, new_fqs_category, duration_sec, reason }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $TimeoutSec = 20,
        [string] $CachePath = ""
    )

    if ($CachePath) { $script:LAZY_ENRICH_CACHE_PATH = $CachePath } else { _Init-LazyEnrichPath }
    $path = $script:LAZY_ENRICH_CACHE_PATH
    $tsStart = (Get-Date).ToUniversalTime()

    # 1. Eligibility
    $elig = Test-FqsLazyEnrichEligible -Market $Market
    if (-not $elig.eligible) {
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $null
            new_fqs_category = $null; duration_sec = 0
            reason = "not_eligible: $($elig.reason)"
        }
    }

    # 2. Rate limit
    $cache = Get-FqsLazyCacheStatus -Market $Market -CachePath $path
    if (-not $cache.can_attempt_global) {
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $elig.cg_id
            new_fqs_category = $null; duration_sec = 0
            reason = "rate_limit_global (last attempt < ${script:LAZY_ENRICH_MIN_INTERVAL_SEC}s ago)"
        }
    }
    if (-not $cache.can_attempt_market) {
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $elig.cg_id
            new_fqs_category = $null; duration_sec = 0
            reason = "market_attempted_recently (TTL ${script:LAZY_ENRICH_PER_MARKET_TTL_HOURS}h)"
        }
    }

    # 3. Spawn python
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $pyScript = Join-Path $projectRoot "backtest\coingecko_enrichment.py"
    if (-not (Test-Path $pyScript)) {
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $elig.cg_id
            new_fqs_category = $null; duration_sec = 0
            reason = "coingecko_enrichment_py_missing"
        }
    }

    # Direct exec via cmd: mais confiavel que Start-Process pra short-lived process
    $exitCode = 0
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        Push-Location $projectRoot
        # 2>&1 captura stderr; & operator chama python diretamente
        $stdout = & python $pyScript --markets $Market 2>$stderrFile
        $exitCode = $LASTEXITCODE
        $durationSec = [math]::Round(((Get-Date).ToUniversalTime() - $tsStart).TotalSeconds, 1)
    } catch {
        $errMsg = $_.Exception.Message.Substring(0, [Math]::Min(100, $_.Exception.Message.Length))
        Pop-Location
        if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force }
        _Log-LazyAttempt -Market $Market -CgId $elig.cg_id -Success $false -Reason "spawn_error: $errMsg" -CachePath $path
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $elig.cg_id
            new_fqs_category = $null; duration_sec = 0
            reason = "spawn_error: $errMsg"
        }
    } finally {
        Pop-Location
    }
    if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force }

    if ($exitCode -ne 0) {
        _Log-LazyAttempt -Market $Market -CgId $elig.cg_id -Success $false -Reason "python_exit_$exitCode" -CachePath $path
        return [PSCustomObject]@{
            success = $false; market = $Market; cg_id = $elig.cg_id
            new_fqs_category = $null; duration_sec = $durationSec
            reason = "python_exit_$exitCode"
        }
    }

    # 4. Re-read registry, check if enriched (auto-load fundamental_quality se ausente)
    if (-not (Get-Command Get-FundamentalScore -ErrorAction SilentlyContinue)) {
        $_fqLib = Join-Path $PSScriptRoot "lib_fundamental_quality.ps1"
        if (Test-Path $_fqLib) { . $_fqLib }
    }
    $newCategory = $null
    if (Get-Command Get-FundamentalScore -ErrorAction SilentlyContinue) {
        try {
            $fqs = Get-FundamentalScore -Market $Market
            if ($fqs -and $fqs.category) { $newCategory = [string]$fqs.category }
        } catch {}
    }

    _Log-LazyAttempt -Market $Market -CgId $elig.cg_id -Success $true -Reason "category_$newCategory" -CachePath $path

    return [PSCustomObject]@{
        success = $true
        market = $Market
        cg_id = $elig.cg_id
        new_fqs_category = $newCategory
        duration_sec = $durationSec
        reason = "enriched_$newCategory"
    }
}


function _Log-LazyAttempt {
    param(
        [string] $Market,
        [string] $CgId,
        [bool] $Success,
        [string] $Reason,
        [string] $CachePath = ""
    )
    if ($CachePath) { $path = $CachePath } else { _Init-LazyEnrichPath; $path = $script:LAZY_ENRICH_CACHE_PATH }
    $entry = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString("o")
        market = $Market
        cg_id = $CgId
        success = $Success
        reason = $Reason
    }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $path -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
}
