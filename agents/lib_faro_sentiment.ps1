# lib_faro_sentiment.ps1 — Trending + Social sentiment
function Get-SentimentScore {
    param([string] $Market, [int] $TrendingRank, [decimal] $MentionsChange, [int] $TelegramMembers = 0, [int] $TelegramVelocity = 0)
    if (-not $TrendingRank -or -not $MentionsChange -or $TrendingRank -lt 1 -or $TrendingRank -gt 1000) { return 0 }
    $rankScore = switch ($TrendingRank) {
        {$_ -lt 50} { 30; break }
        {$_ -lt 100} { 25; break }
        {$_ -lt 200} { 18; break }
        {$_ -lt 500} { 10; break }
        default { 0 }
    }
    $score = $rankScore
    $mentionMultiplier = switch ($MentionsChange) {
        {$_ -ge 3.0} { 1.0; break }
        {$_ -ge 2.0} { 0.85; break }
        {$_ -ge 1.5} { 0.70; break }
        default { 0.5 }
    }
    $score = [int]($score * $mentionMultiplier)
    if ($TelegramVelocity -gt 0) {
        if ($TelegramVelocity -ge 100) { $score += 5 }
        elseif ($TelegramVelocity -ge 50) { $score += 3 }
        elseif ($TelegramVelocity -ge 20) { $score += 1 }
    }
    return [Math]::Min($score, 30)
}
