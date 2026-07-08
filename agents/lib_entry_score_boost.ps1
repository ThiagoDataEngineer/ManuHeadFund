# lib_entry_score_boost.ps1 -- Entry score boost via trend_persistence cache + Tori confluence
#
# Multi-source boost strategy:
#   1. trend_persistence_cache.json (Hurst + KER + label)
#   2. Tori confluence score (if available via gate wrapper)
#   3. Composite boost = base + trend_boost + tori_boost
#
# Lookup:
#   STRONG_TREND   = +10  (Hurst > 0.55 + KER > 0.3 = trend persistente)
#   MODERATE_TREND = +5
#   WEAK_TREND     = 0
#   NOISE          = -5   (penalty: edge nao persiste = nao trade-follow)
#   MEAN_REVERTING = -5
#   UNKNOWN        = 0    (sem cache = neutro)
#
# Tori confluence boost (2026-07-08):
#   Score 90-100 = +15   (exceptional confluence)
#   Score 85-89  = +12   (strong confluence)
#   Score 80-84  = +8    (pass gate minimum)
#   Score <80    = block (fail-closed in gem_executor gate)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Get-EntryScoreBoost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $BaseScore,
        [string] $CachePath = (Join-Path $global:JOURNAL_DIR "trend_persistence_cache.json"),
        [int] $ToriConfluenceScore = -1   # -1 = not available; 0-100 = actual score
    )
    $label = "UNKNOWN"
    $trendScore = $null
    $trendBoost = 0
    $toriBoost = 0

    # ── Trend persistence boost (existing logic) ──
    if (Test-Path $CachePath) {
        try {
            $cache = Get-Content $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cache.PSObject.Properties[$Market]) {
                $entry = $cache.$Market
                $label = [string]$entry.label
                if ($entry.PSObject.Properties['score']) { $trendScore = [double]$entry.score }
            }
        } catch {}
    }

    $trendBoost = switch ($label) {
        "STRONG_TREND"   { 10 }
        "MODERATE_TREND" { 5 }
        "WEAK_TREND"     { 0 }
        "NOISE"          { -5 }
        "MEAN_REVERTING" { -5 }
        default          { 0 }
    }

    # ── Tori confluence boost (NEW 2026-07-08) ──
    # Confluence score passed via parameter (gate wrapper computes it)
    if ($ToriConfluenceScore -ge 0) {
        if ($ToriConfluenceScore -ge 90) {
            $toriBoost = 15   # exceptional
        } elseif ($ToriConfluenceScore -ge 85) {
            $toriBoost = 12   # strong
        } elseif ($ToriConfluenceScore -ge 80) {
            $toriBoost = 8    # minimum pass
        } else {
            $toriBoost = 0    # score < 80 blocked in gate; this branch unlikely
        }
    }

    $totalBoost = $trendBoost + $toriBoost
    $adjusted = $BaseScore + $totalBoost
    if ($adjusted -lt 0) { $adjusted = 0 }
    if ($adjusted -gt 100) { $adjusted = 100 }

    return [PSCustomObject]@{
        market              = $Market
        base_score          = $BaseScore
        trend_label         = $label
        trend_score         = $trendScore
        trend_boost         = $trendBoost
        tori_confluence     = $ToriConfluenceScore
        tori_boost          = $toriBoost
        total_boost         = $totalBoost
        adjusted_score      = $adjusted
    }
}
