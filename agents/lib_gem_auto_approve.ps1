# lib_gem_auto_approve.ps1 -- Auto-approve GEMs strict (2026-05-20 PM4)
#
# Background:
#   GEM detection envia TG com botao manual approve (Wait-TgCallbackApproval 5min).
#   Se user dorme/desconectado, gem rejeita por timeout. Audit 24h: 6 gems perdidos.
#
# Solucao: auto-approve OPCIONAL pra GEMs que atendem criterios STRICT.
#
# Criterios SIMULTANEOS (TODOS necessarios):
#   1. journal/GEM_AUTO_APPROVE.flag presente (opt-in explicito)
#   2. score >= 90 (top tier do scoring)
#   3. FQS category in (BLUE_CHIP, QUALITY) -- NOT SPECULATIVE/AVOID
#   4. market tem entry no coin_registry.json (nao N/A_no_registry)
#   5. sizing <= 1% (defensive cap dentro do golden rule)
#   6. daily auto-approve count < $DailyCap (default 3/dia)
#
# Audit trail: cada auto-approve loga em journal/gem_auto_approve_log.jsonl.
# Telegram alert sempre dispara pos auto-approve (user sabe).

# P3 lazy enrich (2026-05-23): synchronous CoinGecko on-demand quando market missing
# Opt-in via env FQS_LAZY_ENRICH_ENABLED=1
if (-not (Get-Command Invoke-FqsLazyEnrich -ErrorAction SilentlyContinue)) {
    $_lazyLib = Join-Path $PSScriptRoot "lib_fqs_lazy_enrich.ps1"
    if (Test-Path $_lazyLib) { . $_lazyLib }
}


function Test-GemAutoApprove {
    <#
    .SYNOPSIS
        Retorna $true se gem atende TODOS criterios strict de auto-approve.
        Retorna PSCustomObject {approved, reasons[], blocked_by}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Gem,           # @{market;score;mode;...}
        [string] $JournalDir = "",
        [double] $MinScore = 90,
        [double] $MaxSizingPct = 1.0,
        [int] $DailyCap = 3,
        [string[]] $AllowedFqsCategories = @("BLUE_CHIP","QUALITY")
    )

    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }

    $reasons = @()
    $blockedBy = @()

    # 1. Flag opt-in
    $flagFile = Join-Path $JournalDir "GEM_AUTO_APPROVE.flag"
    if (-not (Test-Path $flagFile)) {
        $blockedBy += "no_opt_in_flag"
        return [PSCustomObject]@{ approved = $false; reasons = @(); blocked_by = $blockedBy }
    }
    $reasons += "opt_in_flag_present"

    # 2. Score
    $score = if ($Gem.PSObject.Properties['score']) { [double]$Gem.score } else { 0 }
    if ($score -lt $MinScore) {
        $blockedBy += "score_below_min($score<$MinScore)"
    } else {
        $reasons += "score_ok($score)"
    }

    # 3. FQS category
    $fqsCategory = "AVOID"
    try {
        if (Get-Command Get-FundamentalScore -ErrorAction SilentlyContinue) {
            $fqs = Get-FundamentalScore -Market $Gem.market
            if ($fqs) { $fqsCategory = [string]$fqs.category }
        }
    } catch {}

    # P3 (2026-05-23): lazy on-demand enrichment quando market missing no registry.
    # Substitui veto cego "N/A_no_registry" por tentativa synchronous CoinGecko (~1-3s).
    # Opt-in via env FQS_LAZY_ENRICH_ENABLED=1. Default off pra rollback fast.
    if ($fqsCategory -eq "N/A_no_registry" -and $env:FQS_LAZY_ENRICH_ENABLED -eq "1") {
        if (Get-Command Invoke-FqsLazyEnrich -ErrorAction SilentlyContinue) {
            try {
                $lazyResult = Invoke-FqsLazyEnrich -Market $Gem.market -TimeoutSec 20
                if ($lazyResult.success -and $lazyResult.new_fqs_category) {
                    $fqsCategory = $lazyResult.new_fqs_category
                    $reasons += "fqs_lazy_enriched_to_$fqsCategory"
                } else {
                    $reasons += "fqs_lazy_attempt_failed_$($lazyResult.reason)"
                }
            } catch {}
        }
    }

    if ($fqsCategory -notin $AllowedFqsCategories) {
        $blockedBy += "fqs_category_too_low($fqsCategory)"
    } else {
        $reasons += "fqs_$fqsCategory"
    }

    # 4. Market in registry (no N/A)
    if ($fqsCategory -eq "N/A_no_registry") {
        $blockedBy += "market_not_in_registry"
    }

    # 5. Sizing cap
    $sizingPct = if ($Gem.PSObject.Properties['sizing_pct']) { [double]$Gem.sizing_pct } else { 0.5 }
    if ($sizingPct -gt $MaxSizingPct) {
        $blockedBy += "sizing_exceeds_cap($sizingPct>$MaxSizingPct)"
    } else {
        $reasons += "sizing_ok($sizingPct%)"
    }

    # 6. Daily cap
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $logFile = Join-Path $JournalDir "gem_auto_approve_log.jsonl"
    $todayCount = 0
    if (Test-Path $logFile) {
        $todayCount = @(Get-Content $logFile -ErrorAction SilentlyContinue | ForEach-Object {
            try { $o = $_ | ConvertFrom-Json; if ($o.date -eq $today) { $o } } catch {}
        }).Count
    }
    if ($todayCount -ge $DailyCap) {
        $blockedBy += "daily_cap_reached($todayCount>=$DailyCap)"
    } else {
        $reasons += "daily_cap_ok($todayCount/$DailyCap)"
    }

    $approved = ($blockedBy.Count -eq 0)
    # C6 fix 2026-05-20 PM6+580min: force [string[]]@() wrap pra PS 5.1 array contract
    # (callers podem assign property -> PS unwrap single-element. JSON write seria scalar).
    return [PSCustomObject]@{
        approved   = $approved
        reasons    = [string[]]@($reasons)
        blocked_by = [string[]]@($blockedBy)
        market     = $Gem.market
        score      = $score
        fqs        = $fqsCategory
        daily_used = $todayCount
        daily_cap  = $DailyCap
    }
}


function Add-GemAutoApproveLog {
    <#
    .SYNOPSIS
        Loga auto-approve em jsonl pra audit trail + daily cap counter.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Gem,
        [Parameter(Mandatory)] [PSCustomObject] $ApprovalResult,
        [string] $OrderId = "",
        [string] $JournalDir = ""
    )
    if (-not $JournalDir) {
        $JournalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path (Split-Path $PSScriptRoot -Parent) "journal" }
    }
    $logFile = Join-Path $JournalDir "gem_auto_approve_log.jsonl"
    $entry = [PSCustomObject]@{
        timestamp = (Get-Date).ToString('o')
        date      = (Get-Date).ToString("yyyy-MM-dd")
        market    = [string]$Gem.market
        score     = if ($Gem.PSObject.Properties['score']) { [double]$Gem.score } else { 0 }
        fqs       = [string]$ApprovalResult.fqs
        order_id  = [string]$OrderId
        reasons   = [string[]]@($ApprovalResult.reasons)
    }
    ($entry | ConvertTo-Json -Compress) | Add-Content -Path $logFile -Encoding utf8 -ErrorAction SilentlyContinue
}
