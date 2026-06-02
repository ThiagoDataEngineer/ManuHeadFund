param([bool] $DryRun = $false)
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"
$libs = @("lib_faro_volume_plus.ps1","lib_faro_pattern_pro.ps1","lib_faro_sentiment.ps1","lib_faro_whale_onchain.ps1","lib_faro_momentum.ps1","lib_faro_fingerprint_dna.ps1","lib_faro_entry_timing.ps1","lib_faro_v3_scoring.ps1")
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}
$timestamp = Get-Date -Format "o"
Write-Host "🔵 FARO V3 Engine started" -ForegroundColor Green
$candidates = @()
foreach ($market in @("SOLUSDT","NEARUSDT","LINKUSDT","BNBUSDT","UNIUSDT")) {
    try {
        $volScore = Get-VolumeSpikePro -Market $market -CurrentVol 100000 -Avg3dVol 40000 -BuySideVol 65000 -SellSideVol 35000
        $patScore = Get-PatternPro -PatternType "consolidation" -Strength 0.8
        $sentScore = Get-SentimentScore -Market $market -TrendingRank 120 -MentionsChange 2.5 -TelegramMembers 50000 -TelegramVelocity 80
        $whaleScore = Get-WhaleOnChain -Market $market -TopHoldersSupplyPct 35 -ExchangeOutflow 150 -ExchangeInflow 50
        $momScore = Get-Momentum -Closes @(100..114)
        $fpScore = Get-FingerprintMatch -Market $market -CurrentVol 100000 -Avg3dVol 40000 -HighWick 1.025 -RSI 35 -DaysConsolidation 12
        $timingScore = Get-EntryTiming -Candles1min @(@{high=100.5;close=100.2}) -MA5 100
        $score = Get-FaroScoreV3 -VolScore $volScore -PatternScore $patScore -SentimentScore $sentScore -WhaleScore $whaleScore -MomentumScore $momScore -FingerprintScore $fpScore -TimingScore $timingScore
        $cand = [PSCustomObject]@{ts=$timestamp;market=$market;score=$score.score;decision=$score.decision;signal_count=$score.signal_count;confidence=$score.confidence;breakdown=$score.breakdown}
        $candidates += $cand
        if (-not $DryRun) {
            $candPath = Join-Path $journalDir "faro_v3_candidates.jsonl"
            Add-Content -Path $candPath -Value ($cand | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
        }
        if ($score.decision -in "ENTRA","URGENTE") {
            Write-Host "✅ $($score.decision): $market ($($score.signal_count)/7 signals)"
        }
    } catch {
        Write-Warning "Error: $market - $_"
    }
}
Write-Host "🟢 FARO V3 Engine completed"
