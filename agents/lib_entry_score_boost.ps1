# lib_entry_score_boost.ps1 -- Entry score boost direto baseado em trend_persistence cache.
#
# Diferente de lib_news_entry_boost (composite multi-source):
# Aqui foco em trend_persistence_cache.json APENAS, retornando score ajustado.
# Wire em orchestrator: apos Mentor APROVAR, aplica boost no score final.
#
# Lookup:
#   STRONG_TREND   = +10  (Hurst > 0.55 + KER > 0.3 = trend persistente)
#   MODERATE_TREND = +5
#   WEAK_TREND     = 0
#   NOISE          = -5   (penalty: edge nao persiste = nao trade-follow)
#   MEAN_REVERTING = -5
#   UNKNOWN        = 0    (sem cache = neutro)

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Get-EntryScoreBoost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [double] $BaseScore,
        [string] $CachePath = (Join-Path $global:JOURNAL_DIR "trend_persistence_cache.json")
    )
    $label = "UNKNOWN"
    $trendScore = $null

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

    $boost = switch ($label) {
        "STRONG_TREND"   { 10 }
        "MODERATE_TREND" { 5 }
        "WEAK_TREND"     { 0 }
        "NOISE"          { -5 }
        "MEAN_REVERTING" { -5 }
        default          { 0 }
    }

    $adjusted = $BaseScore + $boost
    if ($adjusted -lt 0) { $adjusted = 0 }
    if ($adjusted -gt 100) { $adjusted = 100 }

    return [PSCustomObject]@{
        market         = $Market
        base_score     = $BaseScore
        trend_label    = $label
        trend_score    = $trendScore
        boost          = $boost
        adjusted_score = $adjusted
    }
}
