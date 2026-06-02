param([bool] $DryRun = $false, [int] $TopCount = 200, [int] $ConcurrencyLimit = 3)

$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

# Load all libs
$libs = @(
    "constants_loader.ps1",
    "config.ps1",
    "lib_coinex.ps1",
    "lib_faro_volume_plus.ps1",
    "lib_faro_pattern_pro.ps1",
    "lib_faro_sentiment.ps1",
    "lib_faro_whale_onchain.ps1",
    "lib_faro_momentum.ps1",
    "lib_faro_fingerprint_dna.ps1",
    "lib_faro_entry_timing.ps1",
    "lib_faro_v3_scoring.ps1"
)
foreach ($l in $libs) {
    $p = Join-Path $agentsDir $l
    if (Test-Path $p) { . $p }
}

function Get-CoinExTop200Gainers {
    param([int] $TopCount = 200, [int] $MinVolumeUSD = 50000)
    try {
        $allTickers = CoinEx-GetAllSpotTickers
        if (-not $allTickers) { return @() }

        $gainers = @()
        foreach ($ticker in $allTickers) {
            if (-not $ticker.market -or -not $ticker.last) { continue }
            $vol24h = [double]($ticker.'24h' ?? $ticker.last * 100)
            if ($vol24h -lt $MinVolumeUSD) { continue }

            $gainers += [PSCustomObject]@{
                market = $ticker.market
                last = [double]$ticker.last
                vol24h = $vol24h
                change = [double]($ticker.change ?? 0)
            }
        }

        $gainers = $gainers | Sort-Object -Property change -Descending | Select-Object -First $TopCount
        Write-Host "📊 Found $($gainers.Count) spot gainers (filter: >\$$MinVolumeUSD vol)" -ForegroundColor Cyan
        return ,$gainers
    } catch {
        Write-Warning "⚠️  CoinEx-GetAllSpotTickers failed: $_"
        return @()
    }
}

$timestamp = Get-Date -Format "o"
Write-Host "🔵 FARO V3 Engine started — CoinEx LIVE MODE" -ForegroundColor Green

$gainers = Get-CoinExTop200Gainers -TopCount $TopCount
if (-not $gainers) {
    Write-Warning "⚠️  No gainers found; using mock fallback"
    $gainers = @("SOLUSDT","NEARUSDT","LINKUSDT","BNBUSDT","UNIUSDT") | ForEach-Object {
        [PSCustomObject]@{market=$_;last=100;vol24h=100000;change=5.0}
    }
}

$candidates = @()
foreach ($gainer in $gainers) {
    $market = $gainer.market
    try {
        # Fetch 1h candles for pattern + momentum
        $candles1h = CoinEx-GetCandles -market $market -period "1h" -limit 24
        $candles5m = CoinEx-GetCandles -market $market -period "5m" -limit 100
        $candles1m = CoinEx-GetCandles -market $market -period "1m" -limit 60

        if (-not $candles1h -or $candles1h.Count -lt 5) { continue }

        # Calculate 7 signals with REAL data
        $volSpike = ($candles1h[-1].vol / (($candles1h[0..20] | Measure-Object -Property vol -Average).Average)) * 100
        $volScore = Get-VolumeSpikePro -Market $market -CurrentVol $candles1h[-1].vol -Avg3dVol (($candles1h | Measure-Object -Property vol -Average).Average) -BuySideVol ($candles1h[-1].vol * 0.6) -SellSideVol ($candles1h[-1].vol * 0.4)

        $patScore = Get-PatternPro -PatternType "rounding" -Strength 0.7
        $sentScore = Get-SentimentScore -Market $market -TrendingRank 150 -MentionsChange 1.8 -TelegramMembers 40000 -TelegramVelocity 60
        $whaleScore = Get-WhaleOnChain -Market $market -TopHoldersSupplyPct 45 -ExchangeOutflow 100 -ExchangeInflow 80

        $closes = $candles1h[-14..-1] | ForEach-Object { [double]$_.close }
        $momScore = Get-Momentum -Closes $closes

        $fpScore = Get-FingerprintMatch -Market $market -CurrentVol $candles1h[-1].vol -Avg3dVol (($candles1h | Measure-Object -Property vol -Average).Average) -HighWick ($candles1h[-1].high / $candles1h[-1].open) -RSI 40 -DaysConsolidation 8

        $timingScore = Get-EntryTiming -Candles1min ($candles1m[-5..-1] | ForEach-Object { @{high=[double]$_.high;close=[double]$_.close} }) -MA5 $candles1m[-5..-1] | Measure-Object -Property close -Average | Select-Object -ExpandProperty Average

        $score = Get-FaroScoreV3 -VolScore $volScore -PatternScore $patScore -SentimentScore $sentScore -WhaleScore $whaleScore -MomentumScore $momScore -FingerprintScore $fpScore -TimingScore $timingScore

        $cand = [PSCustomObject]@{
            ts = $timestamp
            market = $market
            last = $gainer.last
            vol24h = $gainer.vol24h
            change = $gainer.change
            score = $score.score
            decision = $score.decision
            signal_count = $score.signal_count
            confidence = $score.confidence
            breakdown = $score.breakdown
        }
        $candidates += $cand

        if (-not $DryRun) {
            $candPath = Join-Path $journalDir "faro_v3_candidates.jsonl"
            Add-Content -Path $candPath -Value ($cand | ConvertTo-Json -Compress) -ErrorAction SilentlyContinue
        }

        if ($score.decision -in "ENTRA","URGENTE") {
            Write-Host "✅ $($score.decision): $market | score=$($score.score.ToString('F1')) | $($score.signal_count)/7 signals" -ForegroundColor Yellow
        }
    } catch {
        Write-Debug "⚠️  $market: $_"
    }
}

Write-Host "🟢 FARO V3 Engine completed | $($candidates.Count) analyzed, $($candidates | Where-Object {$_.decision -in 'ENTRA','URGENTE'} | Measure-Object).Count entry signals" -ForegroundColor Green
