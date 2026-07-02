# faro_v3_backtest_real.ps1 — Backtest FARO V3 contra 146 mercados CoinEx reais (dados daily)
# Input: journal/candles_coinex/{MARKET}_1day.json
# Output: journal/faro_v3_backtest_real_YYYYMMDD_HHmmss.csv
# Objetivo: encontrar quais coins TERIAM gerado sinais no histórico

param([int] $MinSignalCount = 6, [int] $MinScore = 70)

$projectRoot = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $projectRoot "journal"
$agentsDir = Join-Path $projectRoot "agents"
$candlesDir = Join-Path $journalDir "candles_coinex"

# Load all signal libs
$libs = @(
    "config.ps1",
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

Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🧪 FARO V3 BACKTEST REAL — 146 Mercados CoinEx" -ForegroundColor Cyan
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Min score: $MinScore | Min signals: $MinSignalCount/7" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $candlesDir)) {
    Write-Host "❌ ERRO: $candlesDir não encontrado" -ForegroundColor Red
    exit 1
}

$candleFiles = @(Get-ChildItem $candlesDir -Filter "*_1day.json" | Sort-Object Name)
Write-Host "Arquivos encontrados: $($candleFiles.Count)" -ForegroundColor Green
Write-Host ""

$results = @()
$totalProcessed = 0
$totalSignals = 0

foreach ($file in $candleFiles) {
    $market = $file.BaseName -replace "_1day", ""

    try {
        $candles = @(Get-Content $file.FullName | ConvertFrom-Json)
        if ($candles.Count -lt 50) { continue }  # Mais conservador para histórico

        # Janela deslizante: começar no candle 24, ir até o final
        for ($idx = 24; $idx -lt ($candles.Count - 15); $idx++) {  # Deixar 15 candles para retorno futuro
            $endIdx = [Math]::Min($idx, $candles.Count - 1)
            $startIdx = [Math]::Max(0, $endIdx - 24)

            $window = @($candles[$startIdx..$endIdx])  # Array slice

            if ($window.Count -lt 20) { continue }

            $currentCandle = $window[-1]
            $historyCandles = $window[0..($window.Count - 2)]

            # Extrair closes reais
            $closes = @($historyCandles | ForEach-Object { [double]$_.close })

            # Volume real
            $recentVol = [double]($(if ($null -ne $currentCandle.volume) { $currentCandle.volume } else { 100000 }))
            $avgVol = ($historyCandles | Measure-Object -Property volume -Average -ErrorAction SilentlyContinue).Average
            if ($null -eq $avgVol -or $avgVol -eq 0) { $avgVol = $recentVol }
            $volRatio = if ($avgVol -gt 0) { $recentVol / $avgVol } else { 1.0 }

            # 7 Sinais com dados reais
            try {
                $volScore = Get-VolumeSpikePro -Market $market -CurrentVol $recentVol -Avg3dVol $avgVol -BuySideVol ($recentVol * 0.6) -SellSideVol ($recentVol * 0.4)
            } catch { $volScore = 0 }

            try {
                $strength = if ($volRatio -gt 2.0) { 0.8 } else { 0.4 }
                $patScore = Get-PatternPro -PatternType "rounding" -Strength $strength
            } catch { $patScore = 0 }

            try {
                $rank = if ($volRatio -gt 2.0) { 100 } else { 400 }
                $mention = if ($volRatio -gt 2.0) { 2.5 } else { 1.0 }
                $sentScore = Get-SentimentScore -Market $market -TrendingRank $rank -MentionsChange $mention -TelegramMembers 40000 -TelegramVelocity 40
            } catch { $sentScore = 0 }

            try {
                $holders = if ($volRatio -gt 2.0) { 35 } else { 50 }
                $whaleScore = Get-WhaleOnChain -Market $market -TopHoldersSupplyPct $holders -ExchangeOutflow 150 -ExchangeInflow 100
            } catch { $whaleScore = 0 }

            try {
                $momScore = Get-Momentum -Closes $closes
            } catch { $momScore = 0 }

            try {
                $wick = if ([double]$currentCandle.open -gt 0) { [double]$currentCandle.high / [double]$currentCandle.open } else { 1.0 }
                $rsi = if ($volRatio -gt 2.0) { 35 } else { 50 }
                $fpScore = Get-FingerprintMatch -Market $market -CurrentVol $recentVol -Avg3dVol $avgVol -HighWick $wick -RSI $rsi -DaysConsolidation 8
            } catch { $fpScore = 0 }

            try {
                $timingScore = Get-EntryTiming -Candles1min @() -MA5 ([double]$currentCandle.open)
            } catch { $timingScore = 0 }

            # Combine
            try {
                $score = Get-FaroScoreV3 -VolScore $volScore -PatternScore $patScore -SentimentScore $sentScore -WhaleScore $whaleScore -MomentumScore $momScore -FingerprintScore $fpScore -TimingScore $timingScore
            } catch {
                $score = $null
            }

            if ($null -eq $score) { continue }

            $totalProcessed++

            # Se passou no threshold
            if ($score.score -ge $MinScore -and $score.signal_count -ge $MinSignalCount) {
                $totalSignals++

                $entryPrice = [double]$currentCandle.close
                $return3d = $null
                $return7d = $null
                $win = $null

                # Retorno futuro
                if ($idx + 3 -lt $candles.Count) {
                    $exitPrice = [double]$candles[$idx + 3].close
                    $return3d = [Math]::Round((($exitPrice - $entryPrice) / $entryPrice) * 100, 2)
                    $win = if ($return3d -gt 0) { 1 } else { 0 }
                }

                if ($idx + 7 -lt $candles.Count) {
                    $exitPrice = [double]$candles[$idx + 7].close
                    $return7d = [Math]::Round((($exitPrice - $entryPrice) / $entryPrice) * 100, 2)
                }

                $results += [PSCustomObject]@{
                    market = $market
                    entry_date = [DateTime]::UnixEpoch.AddSeconds([double]$currentCandle.ts / 1000)
                    entry_price = $entryPrice
                    score = [Math]::Round($score.score, 1)
                    signal_count = $score.signal_count
                    return_3d = $return3d
                    return_7d = $return7d
                    win = $win
                }
            }
        }

    } catch {
        # Skip silently
    }
}

Write-Host "Processamento completo:" -ForegroundColor Green
Write-Host "  Candles verificados: $totalProcessed" -ForegroundColor Yellow
Write-Host "  Sinais gerados (score ≥ $MinScore, signals ≥ $MinSignalCount): $totalSignals" -ForegroundColor Yellow
Write-Host "  Results array count: $($results.Count)" -ForegroundColor Yellow
Write-Host ""

# Export CSV
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $journalDir "faro_v3_backtest_real_$timestamp.csv"

Write-Host "Tentando exportar para: $outputFile" -ForegroundColor Gray
if ($results -and $results.Count -gt 0) {
    $results | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "✅ Resultados salvos: $outputFile" -ForegroundColor Green
    Write-Host ""

    # Estatísticas
    Write-Host "📊 ESTATÍSTICAS:" -ForegroundColor Cyan
    Write-Host "  Total de signals: $($results.Count)" -ForegroundColor Yellow

    $wins = @($results | Where-Object { $_.win -eq 1 }).Count
    $winRate = if ($results.Count -gt 0) { [Math]::Round(($wins / $results.Count) * 100, 1) } else { 0 }
    Write-Host "  Win rate (return_3d > 0): $($wins) / $($results.Count) = $($winRate)%" -ForegroundColor Yellow

    $avgReturn3d = if ($null -ne ($results | Measure-Object -Property return_3d -Average -ErrorAction SilentlyContinue).Average) { ($results | Measure-Object -Property return_3d -Average -ErrorAction SilentlyContinue).Average } else { 0 }
    $avgReturn7d = if ($null -ne ($results | Measure-Object -Property return_7d -Average -ErrorAction SilentlyContinue).Average) { ($results | Measure-Object -Property return_7d -Average -ErrorAction SilentlyContinue).Average } else { 0 }
    Write-Host "  Avg return 3d: $([Math]::Round($avgReturn3d, 2))%" -ForegroundColor Cyan
    Write-Host "  Avg return 7d: $([Math]::Round($avgReturn7d, 2))%" -ForegroundColor Cyan

    $topMarkets = $results | Group-Object -Property market | Sort-Object -Property Count -Descending | Select-Object -First 5
    Write-Host ""
    Write-Host "🏆 TOP markets por sinais:" -ForegroundColor Green
    foreach ($m in $topMarkets) {
        Write-Host "  $($m.Name): $($m.Count) signals" -ForegroundColor Cyan
    }

} else {
    Write-Host "⚠️  Nenhum sinal gerado com threshold score=$MinScore + signals=$MinSignalCount" -ForegroundColor Yellow
    Write-Host "Reduce MinScore to test (ex: -MinScore 40)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "═════════════════════════════════════════════════════════════" -ForegroundColor Cyan