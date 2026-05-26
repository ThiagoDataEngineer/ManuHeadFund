# lib_capital_context.ps1 -- Snapshot atual de capital + drift detection vs baseline.
#
# Phase 0a (2026-05-23): foundation pra eliminar bias por capital antigo em todos
# backtests/calibrations downstream. Lib + cache JSON + drift detection.
#
# Funcoes:
#   - Get-CapitalContext: snapshot current (spot + futures + total) com cache fresh
#   - Set-CapitalBaseline: registra baseline (referencia pra drift calc)
#   - Get-CapitalDrift: drift_pct = (current - baseline) / baseline * 100
#   - Test-CapitalStale: true se drift > threshold OR cache older than max_age
#
# Storage: journal/capital_context.json (overwritten per refresh).
# Storage: journal/capital_baseline.json (set manualmente OR primeira call).
#
# Fail-soft: CoinEx fetch falha -> usa cached. Cache miss -> usa fallback config.
#
# PS 5.1. UTF-8 BOM.


$script:CAPITAL_CONTEXT_PATH = $null
$script:CAPITAL_BASELINE_PATH = $null


function _Init-CapitalPaths {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { "journal" }
    if (-not $script:CAPITAL_CONTEXT_PATH) {
        $script:CAPITAL_CONTEXT_PATH = Join-Path $journalDir "capital_context.json"
    }
    if (-not $script:CAPITAL_BASELINE_PATH) {
        $script:CAPITAL_BASELINE_PATH = Join-Path $journalDir "capital_baseline.json"
    }
}


function Get-CapitalContext {
    <#
    .SYNOPSIS
    Retorna snapshot current de capital. Refresh from CoinEx se cache stale.

    .PARAMETER MaxAgeMinutes
    Refresh threshold. Default 60min.

    .PARAMETER Force
    Force refresh ignorando cache.

    .PARAMETER ContextPath
    Override (testing).

    .OUTPUTS
    PSCustomObject @{ spot, futures, total, snapshot_ts, source }
    source = 'fresh' | 'cached' | 'fallback'
    #>
    [CmdletBinding()]
    param(
        [int] $MaxAgeMinutes = 60,
        [switch] $Force,
        [string] $ContextPath = ""
    )
    if ($ContextPath) { $script:CAPITAL_CONTEXT_PATH = $ContextPath }
    _Init-CapitalPaths
    $path = $script:CAPITAL_CONTEXT_PATH

    # Check cache freshness
    if (-not $Force -and (Test-Path $path)) {
        try {
            $cached = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $cachedTs = [System.DateTimeOffset]::Parse($cached.snapshot_ts).UtcDateTime
            $ageMin = ((Get-Date).ToUniversalTime() - $cachedTs).TotalMinutes
            if ($ageMin -le $MaxAgeMinutes) {
                return [PSCustomObject]@{
                    spot = [double]$cached.spot
                    futures = [double]$cached.futures
                    total = [double]$cached.total
                    snapshot_ts = $cached.snapshot_ts
                    source = "cached"
                }
            }
        } catch {}
    }

    # Fresh fetch via CoinEx (se libs disponiveis)
    # Bug fix 2026-05-25: CoinEx-GetTotalCapitalUSDT retorna escalar (soma), nao
    # objeto. Chamamos os 2 fetchers individuais que populam $global:CAPITAL_SPOT
    # e $global:CAPITAL_FUTURES como side effect.
    $spot = 0.0; $futures = 0.0
    $source = "fallback"

    $hasSpot = Get-Command CoinEx-GetSpotCapitalUSDT -ErrorAction SilentlyContinue
    $hasFut  = Get-Command CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue

    if ($hasSpot -or $hasFut) {
        $okSpot = $false; $okFut = $false
        if ($hasSpot) {
            try {
                $sVal = [double](CoinEx-GetSpotCapitalUSDT)
                if ($sVal -ge 0) { $spot = $sVal; $okSpot = $true }
            } catch {}
        }
        if ($hasFut) {
            try {
                $fVal = [double](CoinEx-GetFuturesCapitalUSDT)
                if ($fVal -ge 0) { $futures = $fVal; $okFut = $true }
            } catch {}
        }
        # source = fresh apenas se ao menos uma chamada deu certo E o resultado
        # nao e exclusivamente o fallback global (i.e., total real > 0)
        if (($okSpot -or $okFut) -and ($spot + $futures) -gt 0) {
            $source = "fresh"
        }
    }
    # Fallback global vars (set by orchestrator on successful fetches)
    if ($source -eq "fallback") {
        if ($null -ne $global:CAPITAL_SPOT) { $spot = [double]$global:CAPITAL_SPOT }
        if ($null -ne $global:CAPITAL_FUTURES) { $futures = [double]$global:CAPITAL_FUTURES }
        if ($spot -eq 0 -and $futures -eq 0 -and $null -ne $global:CAPITAL_TOTAL) {
            # Worst fallback: only total available
            $total = [double]$global:CAPITAL_TOTAL
            $spot = 0; $futures = $total
        }
    }

    $total = $spot + $futures
    $ctx = [PSCustomObject]@{
        spot = $spot
        futures = $futures
        total = $total
        snapshot_ts = (Get-Date).ToUniversalTime().ToString("o")
        source = $source
    }

    # Persist (atomic write)
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    try {
        $ctx | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8 -Force
    } catch {}

    return $ctx
}


function Set-CapitalBaseline {
    <#
    .SYNOPSIS
    Salva baseline atual (referencia pra drift calc). Usar quando rodar backtest grande.

    .PARAMETER Spot
    .PARAMETER Futures
    .PARAMETER Tag
    Identificador (e.g., "wss_branch_a_v2").
    .PARAMETER BaselinePath
    Override (testing).
    #>
    [CmdletBinding()]
    param(
        [double] $Spot = 0,
        [double] $Futures = 0,
        [string] $Tag = "auto",
        [string] $BaselinePath = ""
    )
    if ($BaselinePath) { $script:CAPITAL_BASELINE_PATH = $BaselinePath }
    _Init-CapitalPaths
    $path = $script:CAPITAL_BASELINE_PATH

    $entry = [PSCustomObject]@{
        spot = $Spot
        futures = $Futures
        total = $Spot + $Futures
        tag = $Tag
        snapshot_ts = (Get-Date).ToUniversalTime().ToString("o")
    }
    $dir = Split-Path $path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $entry | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8 -Force
}


function Get-CapitalBaseline {
    [CmdletBinding()]
    param([string] $BaselinePath = "")
    if ($BaselinePath) { $script:CAPITAL_BASELINE_PATH = $BaselinePath }
    _Init-CapitalPaths
    $path = $script:CAPITAL_BASELINE_PATH
    if (-not (Test-Path $path)) { return $null }
    try {
        return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { return $null }
}


function Get-CapitalDrift {
    <#
    .SYNOPSIS
    Computa drift_pct entre current e baseline.

    .OUTPUTS
    PSCustomObject @{ drift_pct, current_total, baseline_total, baseline_tag, is_stale, reason }
    drift_pct = (current - baseline) / baseline * 100  (positivo = capital cresceu)
    is_stale = $true se abs(drift_pct) > Threshold (default 30%)
    #>
    [CmdletBinding()]
    param(
        [double] $Threshold = 30,
        [string] $ContextPath = "",
        [string] $BaselinePath = ""
    )

    if ($ContextPath) { $script:CAPITAL_CONTEXT_PATH = $ContextPath }
    if ($BaselinePath) { $script:CAPITAL_BASELINE_PATH = $BaselinePath }

    $ctx = Get-CapitalContext -ContextPath $script:CAPITAL_CONTEXT_PATH
    $baseline = Get-CapitalBaseline -BaselinePath $script:CAPITAL_BASELINE_PATH

    if (-not $baseline -or -not $baseline.total -or $baseline.total -le 0) {
        return [PSCustomObject]@{
            drift_pct = $null
            current_total = $ctx.total
            baseline_total = 0
            baseline_tag = "none"
            is_stale = $false
            reason = "no_baseline"
        }
    }

    $drift = ($ctx.total - [double]$baseline.total) / [double]$baseline.total * 100
    $isStale = [math]::Abs($drift) -gt $Threshold
    return [PSCustomObject]@{
        drift_pct = [math]::Round($drift, 1)
        current_total = $ctx.total
        baseline_total = [double]$baseline.total
        baseline_tag = "$($baseline.tag)"
        is_stale = $isStale
        reason = if ($isStale) { "drift_$([math]::Round($drift,0))pct_above_$Threshold" } else { "ok" }
    }
}


function Test-CapitalStale {
    <#
    .SYNOPSIS
    True/false rapido pra checar se capital drifted significativamente.
    #>
    [CmdletBinding()]
    param([double] $Threshold = 30)
    $d = Get-CapitalDrift -Threshold $Threshold
    return [bool]$d.is_stale
}
