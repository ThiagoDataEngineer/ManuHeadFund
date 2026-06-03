# lib_news_entry_boost.ps1 -- Calcula boost de score baseado em sinais externos.
#
# Fontes:
#   1. journal/idea_triggers.jsonl -- user-priced ideas que ja triggered (fired)
#   2. journal/news_signals.jsonl  -- news tracker (CoinEx feed, twitter, etc)
#   3. journal/trend_persistence_cache.json -- ker+hurst pre-computado
#
# Boost composite (0-30 pontos add ao Mentor score):
#   - Idea TRIGGERED nas ultimas 24h:    +10
#   - News bullish recente (<3 dias):    +5
#   - Trend persistence MODERATE/STRONG: +5
#   - Trend persistence STRONG (>0.5):   +10
#   - Funding z favoravel direcao:       +5 (z<-1 pra LONG, z>+1 pra SHORT)
#
# Threshold: boost so adiciona se Mentor ja >= 50 (nao salva score baixo).
# Apply: orchestrator_v6 chama Get-NewsEntryBoost -Market -Direction antes do
# decisao final; soma ao score; se boost > 10 inclui no payload de log.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}


function Test-IdeaTriggeredRecently {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $WithinHours = 24,
        [string] $IdeaPath = (Join-Path $global:JOURNAL_DIR "idea_triggers.jsonl")
    )
    if (-not (Test-Path $IdeaPath)) { return $false }
    $cutoff = (Get-Date).ToUniversalTime().AddHours(-$WithinHours)
    foreach ($line in Get-Content $IdeaPath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if (-not $line) { continue }
        try {
            $o = $line | ConvertFrom-Json
            if ($o.market -ne $Market) { continue }
            if ($o.status -ne "triggered") { continue }
            if ($o.fired_at) {
                $firedTs = [DateTime]::Parse([string]$o.fired_at).ToUniversalTime()
                if ($firedTs -ge $cutoff) { return $true }
            }
        } catch {}
    }
    return $false
}


function Get-NewsSignalRecent {
    # Retorna sentiment score (-1 a +1) mais recente do market nos ultimos N dias.
    # 0 = sem news / neutro. >0.3 = bullish. <-0.3 = bearish.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [int] $WithinDays = 3,
        [string] $NewsPath = (Join-Path $global:JOURNAL_DIR "news_signals.jsonl")
    )
    if (-not (Test-Path $NewsPath)) { return 0.0 }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$WithinDays)
    $latest = $null
    foreach ($line in Get-Content $NewsPath -Encoding UTF8 -ErrorAction SilentlyContinue) {
        if (-not $line) { continue }
        try {
            $o = $line | ConvertFrom-Json
            if ($o.market -ne $Market -and $o.symbol -ne $Market) { continue }
            $ts = if ($o.ts) { [DateTime]::Parse([string]$o.ts).ToUniversalTime() } else { continue }
            if ($ts -lt $cutoff) { continue }
            if ($null -eq $latest -or $ts -gt $latest.ts) {
                $latest = @{ ts = $ts; sentiment = [double]$o.sentiment }
            }
        } catch {}
    }
    if ($null -eq $latest) { return 0.0 }
    return [double]$latest.sentiment
}


function Get-TrendPersistenceLabel {
    # Le cache pre-computado (trend_persistence.py output).
    # Sem cache: returna "UNKNOWN".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [string] $CachePath = (Join-Path $global:JOURNAL_DIR "trend_persistence_cache.json")
    )
    if (-not (Test-Path $CachePath)) { return @{ label = "UNKNOWN"; score = 0 } }
    try {
        $cache = Get-Content $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cache.PSObject.Properties[$Market]) {
            $entry = $cache.$Market
            return @{ label = [string]$entry.label; score = [double]$entry.score }
        }
    } catch {}
    return @{ label = "UNKNOWN"; score = 0 }
}


function Get-FundingZScoreCached {
    # Le cache funding existente (ou consulta via lib_promotion_gates se disponivel)
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market
    )
    if (Get-Command Get-FundingZScore -ErrorAction SilentlyContinue) {
        $r = Get-FundingZScore -Market $Market
        if ($null -ne $r.z) { return [double]$r.z }
    }
    return $null
}


function Get-NewsEntryBoost {
    # Calcula boost total (0-30) baseado nas 4 fontes.
    # Retorna PSCustomObject com breakdown + total.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Direction   # "LONG" | "SHORT"
    )
    $boost = 0
    $reasons = @()

    # 1. Idea triggered recente
    if (Test-IdeaTriggeredRecently -Market $Market) {
        $boost += 10
        $reasons += "idea_triggered_24h:+10"
    }

    # 2. News sentiment
    $sentiment = Get-NewsSignalRecent -Market $Market
    if (($Direction -eq "LONG" -and $sentiment -gt 0.3) -or
        ($Direction -eq "SHORT" -and $sentiment -lt -0.3)) {
        $boost += 5
        $reasons += "news_aligned_${Direction}:+5"
    }

    # 3. Trend persistence
    $trend = Get-TrendPersistenceLabel -Market $Market
    if ($trend.label -eq "STRONG_TREND") {
        $boost += 10
        $reasons += "trend_strong:+10"
    } elseif ($trend.label -eq "MODERATE_TREND") {
        $boost += 5
        $reasons += "trend_moderate:+5"
    }

    # 4. Funding z-score favoravel
    $z = Get-FundingZScoreCached -Market $Market
    if ($null -ne $z) {
        if ($Direction -eq "LONG" -and $z -lt -1.0) {
            $boost += 5
            $reasons += "funding_favorable_long:+5"
        } elseif ($Direction -eq "SHORT" -and $z -gt 1.0) {
            $boost += 5
            $reasons += "funding_favorable_short:+5"
        }
    }

    return [PSCustomObject]@{
        market     = $Market
        direction  = $Direction
        boost      = $boost
        reasons    = $reasons
        components = @{
            idea_triggered  = (Test-IdeaTriggeredRecently -Market $Market)
            news_sentiment  = $sentiment
            trend_label     = $trend.label
            trend_score     = $trend.score
            funding_z       = $z
        }
    }
}
