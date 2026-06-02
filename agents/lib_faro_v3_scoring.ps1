# lib_faro_v3_scoring.ps1 — 7-signal scoring (5/7 threshold)
function Get-FaroScoreV3 {
    param([decimal] $VolScore = 0, [decimal] $PatternScore = 0, [decimal] $SentimentScore = 0, [decimal] $WhaleScore = 0, [decimal] $MomentumScore = 0, [decimal] $FingerprintScore = 0, [decimal] $TimingScore = 0)
    $vol = [decimal]($VolScore ?? 0)
    $pat = [decimal]($PatternScore ?? 0)
    $sent = [decimal]($SentimentScore ?? 0)
    $whale = [decimal]($WhaleScore ?? 0)
    $mom = [decimal]($MomentumScore ?? 0)
    $fp = [decimal]($FingerprintScore ?? 0)
    $timing = [decimal]($TimingScore ?? 0)
    $signalCount = 0
    if ($vol -gt 0) { $signalCount++ }
    if ($pat -gt 0) { $signalCount++ }
    if ($sent -gt 0) { $signalCount++ }
    if ($whale -gt 0) { $signalCount++ }
    if ($mom -gt 0) { $signalCount++ }
    if ($fp -gt 0) { $signalCount++ }
    if ($timing -gt 0) { $signalCount++ }
    $totalRaw = $vol + $pat + $sent + $whale + $mom + $fp + $timing
    $totalNormalized = if ($totalRaw -gt 0) { [int](($totalRaw / 175) * 100) } else { 0 }
    $totalNormalized = [Math]::Min($totalNormalized, 100)
    $decision = switch {
        ($signalCount -ge 6) { "URGENTE" }
        ($signalCount -eq 5) { "ENTRA" }
        ($signalCount -eq 4) { "WATCH" }
        default { "SKIP" }
    }
    $confidence = [decimal]($signalCount) / 7.0
    return [PSCustomObject]@{
        score = $totalNormalized
        decision = $decision
        signal_count = $signalCount
        signals_needed = 5
        confidence = [decimal]::Round($confidence, 2)
        breakdown = @{
            volume = [int]$vol
            pattern = [int]$pat
            sentiment = [int]$sent
            whale = [int]$whale
            momentum = [int]$mom
            fingerprint = [int]$fp
            timing = [int]$timing
        }
    }
}
Export-ModuleMember -Function "Get-FaroScoreV3"
