# lib_capital_context.ps1 -- Snapshot atual de capital + drift detection vs baseline.
#
# Phase 0a (2026-05-23): foundation pra eliminar bias por capital antigo em todos
# backtests/calibrations downstream. Lib + cache JSON + drift detection.
#
# Etapa 2.1 (2026-05-26): refatorado pra usar state_store quando disponivel.
# Backend: STATE_STORE_BACKEND=local (default, JSON) ou supabase (24/7).
# Tabela: 'capital_context' (single-row, id=1).
#
# Funcoes:
#   - Get-CapitalContext: snapshot current (spot + futures + total) com cache fresh
#   - Set-CapitalBaseline: registra baseline (referencia pra drift calc)
#   - Get-CapitalDrift: drift_pct = (current - baseline) / baseline * 100
#   - Test-CapitalStale: true se drift > threshold OR cache older than max_age
#
# Storage:
#   - Backend local: journal/capital_context.json (overwritten per refresh)
#   - Backend supabase: manuheadfund.capital_context (id=1)
# Storage baseline: journal/capital_baseline.json (set manualmente OR primeira call).
#
# Fail-soft: CoinEx fetch falha -> usa cached. Cache miss -> usa fallback config.
#
# PS 5.1. UTF-8 BOM.


$script:CAPITAL_CONTEXT_PATH = $null
$script:CAPITAL_BASELINE_PATH = $null

# Lazy load state_store (sibling lib). Skip se nao disponivel (caller direto sem stack).
$_ccStateStorePath = Join-Path $PSScriptRoot "lib_state_store.ps1"
if (Test-Path $_ccStateStorePath) {
    . $_ccStateStorePath
}


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

    # Determina se usa state_store (preferido) ou path legacy direto.
    # Se ContextPath foi passado explicitamente, mantemos legacy path (back-compat
    # com tests + callers que setam path custom).
    $useStateStore = $false
    if (-not $ContextPath) {
        $useStateStore = (Get-Command Get-StateRecords -ErrorAction SilentlyContinue) -ne $null
    }

    # Check cache freshness (2026-07-09 FIX: tentar LOCAL PRIMEIRO se Supabase falhar)
    if (-not $Force) {
        $cached = $null
        # Prioridade: arquivo local > Supabase (Supabase pode estar sem auth em local)
        if (Test-Path $path) {
            try {
                $cached = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch { $cached = $null }
        }
        # Se arquivo não tem, tenta Supabase
        if (-not $cached -and $useStateStore) {
            try {
                $rows = @(Get-StateRecords -Table "capital_context")
                if ($rows.Count -gt 0) { $cached = $rows[0] }
            } catch { $cached = $null }
        }

        if ($cached -and $cached.snapshot_ts) {
            try {
                $cachedTs = [System.DateTimeOffset]::Parse($cached.snapshot_ts).UtcDateTime
                $nowUtc = (Get-Date).ToUniversalTime()
                $ageMin = ($nowUtc - $cachedTs).TotalMinutes

                # Debug: log cache freshness check (only in tests)
                if ($global:DEBUG_CAPITAL_CONTEXT -eq $true) {
                    Write-Host "[capital_context] Cache check: ageMin=$([Math]::Round($ageMin, 2)) MaxAge=$MaxAgeMinutes Pass=$(if ($ageMin -le $MaxAgeMinutes) { 'YES' } else { 'NO' })"
                }

                if ($ageMin -le $MaxAgeMinutes) {
                    return [PSCustomObject]@{
                        spot = [double]$cached.spot
                        futures = [double]$cached.futures
                        total = [double]$cached.total
                        snapshot_ts = $cached.snapshot_ts
                        source = "cached"
                    }
                }
            } catch {
                if ($global:DEBUG_CAPITAL_CONTEXT -eq $true) {
                    Write-Host "[capital_context] Error parsing timestamp: $_"
                }
            }
        }
    }

    # Fresh fetch via CoinEx (se libs disponiveis)
    # Bug fix 2026-05-25: CoinEx-GetTotalCapitalUSDT retorna escalar (soma), nao
    # objeto. Chamamos os 2 fetchers individuais que populam $global:CAPITAL_SPOT
    # e $global:CAPITAL_FUTURES como side effect.
    # Bug fix 2026-06-08: Se cache stale, tenta usar globals (fallback) ao invés de falhar
    $spot = 0.0; $futures = 0.0
    $source = "fallback"

    $hasSpot = Get-Command CoinEx-GetSpotCapitalUSDT -ErrorAction SilentlyContinue
    $hasFut  = Get-Command CoinEx-GetFuturesCapitalUSDT -ErrorAction SilentlyContinue

    if ($hasSpot -or $hasFut) {
        # 2026-07-09 FIX (causa raiz da poluicao Supabase): CoinEx-Get*CapitalUSDT
        # retorna o bootstrap global SEM erro quando credenciais ausentes/API falha.
        # O unico sinal confiavel de fetch REAL e $global:CAPITAL_*_LAST_REFRESH,
        # que a lib_coinex so atualiza em resposta autenticada bem-sucedida.
        $preSpotRefresh = $global:CAPITAL_SPOT_LAST_REFRESH
        $preFutRefresh  = $global:CAPITAL_FUTURES_LAST_REFRESH
        $okSpot = $false; $okFut = $false
        if ($hasSpot) {
            try {
                $sVal = [double](CoinEx-GetSpotCapitalUSDT)
                if ($sVal -ge 0 -and $null -ne $global:CAPITAL_SPOT_LAST_REFRESH -and $global:CAPITAL_SPOT_LAST_REFRESH -ne $preSpotRefresh) {
                    $spot = $sVal; $okSpot = $true
                }
            } catch {}
        }
        if ($hasFut) {
            try {
                $fVal = [double](CoinEx-GetFuturesCapitalUSDT)
                if ($fVal -ge 0 -and $null -ne $global:CAPITAL_FUTURES_LAST_REFRESH -and $global:CAPITAL_FUTURES_LAST_REFRESH -ne $preFutRefresh) {
                    $futures = $fVal; $okFut = $true
                }
            } catch {}
        }
        # source = fresh apenas com fetch REAL confirmado (LAST_REFRESH avancou)
        if (($okSpot -or $okFut) -and ($spot + $futures) -gt 0) {
            $source = "fresh"
        }
    }
    # 2026-07-09 FIX: antes do fallback bootstrap, preferir cache REAL mesmo stale.
    # Local sem credenciais nao consegue fetch fresh, mas a NUVEM (autenticada)
    # mantem capital_context real no Supabase/journal. Dado real de horas atras
    # e sempre melhor que bootstrap 100+100 pra gates de exposure.
    if ($source -eq "fallback") {
        $staleCache = $null
        if ($useStateStore) {
            try {
                $rows = @(Get-StateRecords -Table "capital_context")
                if ($rows.Count -gt 0) { $staleCache = $rows[0] }
            } catch { $staleCache = $null }
        } elseif (Test-Path $path) {
            try { $staleCache = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $staleCache = $null }
        }
        if ($staleCache -and $staleCache.source -and "$($staleCache.source)" -notmatch "fallback" -and ([double]$staleCache.total) -gt 0) {
            Write-Warning "[capital_context] fetch fresh falhou; usando cache REAL stale (ts=$($staleCache.snapshot_ts) total=$($staleCache.total))"
            return [PSCustomObject]@{
                spot = [double]$staleCache.spot
                futures = [double]$staleCache.futures
                total = [double]$staleCache.total
                snapshot_ts = $staleCache.snapshot_ts
                source = "cached_stale"
            }
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
        Write-Warning "[capital_context] BOOTSTRAP fallback em uso (spot=$spot fut=$futures) -- gates de exposure operam com capital NAO-REAL"
    }

    $total = $spot + $futures
    $ctx = [PSCustomObject]@{
        spot = $spot
        futures = $futures
        total = $total
        snapshot_ts = (Get-Date).ToUniversalTime().ToString("o")
        source = $source
    }

    # 2026-07-09 FIX: NUNCA persistir fallback bootstrap. Persistir 100+100 aqui
    # sobrescreve o capital REAL que a nuvem autenticada gravou no Supabase --
    # foi exatamente isso que travou cap_exposure (12 gems bloqueados com capital falso).
    if ($source -eq "fallback") {
        return $ctx
    }

    # Persist via state_store (preferido) ou path legacy direto
    if ($useStateStore) {
        try {
            $record = [PSCustomObject]@{
                id          = 1
                spot        = $spot
                futures     = $futures
                total       = $total
                snapshot_ts = $ctx.snapshot_ts
                source      = $source
            }
            Save-StateRecords -Table "capital_context" -Records @($record) -PrimaryKey "id"
        } catch {
            Write-Warning "[capital_context] state_store save failed: $_"
        }
    } else {
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        try {
            $ctx | ConvertTo-Json | Out-File -FilePath $path -Encoding utf8 -Force
        } catch {}
    }

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


function Get-ExecutableCapitalUSDT {
    <#
    .SYNOPSIS
    Capital executavel considerando margin mode (2026-07-09).

    Cross margin: colateral = conta inteira -> spot + futures.
    Isolated:     colateral = so a margem alocada -> futures wallet only.
    Spot trade:   spot wallet only.

    .OUTPUTS
    PSCustomObject @{ capital, wallet_cap, margin_mode, source, snapshot_ts }
    capital    = base pro sizing/exposure gates
    wallet_cap = teto da carteira de execucao (evita margin call)
    #>
    [CmdletBinding()]
    param(
        [ValidateSet("FUTURES","SPOT")] [string] $MarketType = "FUTURES",
        [ValidateSet("cross","isolated")] [string] $MarginMode = "cross",
        [int] $MaxAgeMinutes = 30
    )

    $ctx = Get-CapitalContext -MaxAgeMinutes $MaxAgeMinutes

    if ($MarketType -eq "SPOT") {
        $capital = $ctx.spot
        $walletCap = $ctx.spot
    } elseif ($MarginMode -eq "isolated") {
        # Isolated: so a margem futures responde pela posicao
        $capital = $ctx.futures
        $walletCap = $ctx.futures
    } else {
        # Cross: conta inteira e colateral
        $capital = $ctx.total
        $walletCap = $ctx.futures   # execucao ainda exige saldo na carteira futures
    }

    return [PSCustomObject]@{
        capital     = [double]$capital
        wallet_cap  = [double]$walletCap
        margin_mode = $MarginMode
        source      = $ctx.source
        snapshot_ts = $ctx.snapshot_ts
    }
}
