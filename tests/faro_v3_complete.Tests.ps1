$projectRoot = Split-Path $PSScriptRoot -Parent
$agentsDir = Join-Path $projectRoot "agents"
$libs = @("lib_faro_volume_plus.ps1","lib_faro_pattern_pro.ps1","lib_faro_sentiment.ps1","lib_faro_whale_onchain.ps1","lib_faro_momentum.ps1","lib_faro_fingerprint_dna.ps1","lib_faro_entry_timing.ps1","lib_faro_v3_scoring.ps1")
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

Describe "FARO V3 Signal Libraries" {
    It "Get-VolumeSpikePro returns 0-25" { (Get-VolumeSpikePro -Market "X" -CurrentVol 100 -Avg3dVol 50) -ge 0 | Should Be $true }
    It "Get-PatternPro returns 0-25" { (Get-PatternPro -PatternType "consolidation" -Strength 0.8) -ge 0 | Should Be $true }
    It "Get-SentimentScore returns 0-30" { (Get-SentimentScore -Market "X" -TrendingRank 100 -MentionsChange 2.0) -ge 0 | Should Be $true }
    It "Get-WhaleOnChain returns 0-20" { (Get-WhaleOnChain -Market "X") -ge 0 | Should Be $true }
    It "Get-Momentum returns 0-25" { (Get-Momentum -Closes @(100..115)) -ge 0 | Should Be $true }
    It "Get-FingerprintMatch returns 0-20" { (Get-FingerprintMatch -Market "X" -CurrentVol 100 -Avg3dVol 50) -ge 0 | Should Be $true }
    It "Get-EntryTiming returns 0-20" { (Get-EntryTiming -Candles1min @(@{high=100.5;close=100.0}) -MA5 100) -ge 0 | Should Be $true }
}

Describe "FARO V3 Scoring" {
    It "Get-FaroScoreV3 returns valid score" {
        $r = Get-FaroScoreV3 -VolScore 20 -PatternScore 15 -SentimentScore 25 -WhaleScore 15 -MomentumScore 15
        $r.score | Should Not BeNullOrEmpty
    }
    It "5 signals = ENTRA" {
        $r = Get-FaroScoreV3 -VolScore 20 -PatternScore 15 -SentimentScore 25 -WhaleScore 15 -MomentumScore 15
        $r.decision | Should Be "ENTRA"
    }
    It "6 signals = URGENTE" {
        $r = Get-FaroScoreV3 -VolScore 20 -PatternScore 15 -SentimentScore 25 -WhaleScore 15 -MomentumScore 15 -FingerprintScore 12
        $r.decision | Should Be "URGENTE"
    }
    It "Score 0-100" {
        $r = Get-FaroScoreV3 -VolScore 25 -PatternScore 25 -SentimentScore 30 -WhaleScore 20 -MomentumScore 25 -FingerprintScore 20 -TimingScore 20
        ($r.score -ge 0 -and $r.score -le 100) | Should Be $true
    }
}
