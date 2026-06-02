# V3 — Sinais realistas para dados DAILY (não synthetic)
# Threshold reduzido, critérios ajustados

param([int] $MinScore = 40, [int] $MinSignalCount = 3)

$projectRoot = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $projectRoot "journal"
$candlesDir = Join-Path $journalDir "candles_coinex"

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🧪 FARO V3 BACKTEST V3 — Sinais Realistas (Daily)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "MinScore: $MinScore | MinSignals: $MinSignalCount" -ForegroundColor Yellow
Write-Host ""

$results = [System.Collections.Generic.List[PSObject]]::new()
$totalProcessed = 0
$totalSignalsFound = 0

$candleFiles = @(Get-ChildItem $candlesDir -Filter "*_1day.json" | Sort-Object Name)
Write-Host "Processando: $($candleFiles.Count) mercados" -ForegroundColor Green

foreach ($file in $candleFiles) {
    $market = $file.BaseName -replace "_1day", ""

    try {
        $candles = @(Get-Content $file.FullName | ConvertFrom-Json -ErrorAction Stop)
        if ($candles.Count -lt 50) { continue }

        # Janela deslizante
        for ($idx = 20; $idx -lt ($candles.Count - 7); $idx++) {
            $window = @($candles[($idx - 20)..$idx])
            if ($window.Count -lt 20) { continue }

            $curr = $window[-1]
            $hist = $window[0..19]
            $totalProcessed++

            # Dados básicos
            $currVol = [double]($curr.volume ?? 0)
            $avgVol = ($hist | ForEach-Object { [double]($_.volume ?? 0) } | Measure-Object -Average).Average
            $curr_close = [double]$curr.close
            $curr_open = [double]$curr.open
            $prev_close = [double]$hist[-1].close

            $signalCount = 0
            $score = 0

            # Signal 1: Volume increasing (>1.3x average)
            if ($currVol -gt ($avgVol * 1.3)) { $signalCount++; $score += 15 }

            # Signal 2: Price moving up (>1.5% daily move)
            $pctChange = [Math]::Abs(($curr_close - $curr_open) / $curr_open)
            if ($pctChange -gt 0.015) { $signalCount++; $score += 15 }

            # Signal 3: Positive close (close > open = bullish body)
            if ($curr_close -gt $curr_open) { $signalCount++; $score += 12 }

            # Signal 4: Breaking previous high
            $prevHigh = ($hist | ForEach-Object { [double]$_.high } | Measure-Object -Maximum).Maximum
            if ([double]$curr.high -gt $prevHigh) { $signalCount++; $score += 18 }

            # Signal 5: Momentum building (close > 20-day MA)
            $closes = @($hist | ForEach-Object { [double]$_.close })
            $ma20 = ($closes | Measure-Object -Average).Average
            if ($curr_close -gt $ma20) { $signalCount++; $score += 12 }

            # Signal 6: Volume & price together
            if ($currVol -gt ($avgVol * 1.2) -and $curr_close -gt $prev_close) { $signalCount++; $score += 10 }

            # Signal 7: Range expansion (wider body)
            $range = [double]$curr.high - [double]$curr.low
            $prevRange = ($hist | ForEach-Object { [double]$_.high - [double]$_.low } | Measure-Object -Average).Average
            if ($range -gt ($prevRange * 1.2)) { $signalCount++; $score += 8 }

            # Normalizar
            $score = [Math]::Min([Math]::Max($score, 0), 100)

            # Registrar
            if ($score -ge $MinScore -and $signalCount -ge $MinSignalCount) {
                $totalSignalsFound++

                $return3d = $null
                $return7d = $null
                $win = 0

                if ($idx + 3 -lt $candles.Count) {
                    $exit3d = [double]$candles[$idx + 3].close
                    $return3d = [Math]::Round((($exit3d - $curr_close) / $curr_close) * 100, 2)
                    $win = if ($return3d -gt 0) { 1 } else { 0 }
                }

                if ($idx + 7 -lt $candles.Count) {
                    $exit7d = [double]$candles[$idx + 7].close
                    $return7d = [Math]::Round((($exit7d - $curr_close) / $curr_close) * 100, 2)
                }

                $results.Add([PSCustomObject]@{
                    market = $market
                    entry_date = if ($curr.ts) { [DateTime]::UnixEpoch.AddSeconds([double]$curr.ts / 1000) } else { Get-Date }
                    entry_price = $curr_close
                    score = $score
                    signal_count = $signalCount
                    return_3d = $return3d
                    return_7d = $return7d
                    win = $win
                }) | Out-Null
            }
        }

    } catch {
        # Skip
    }
}

Write-Host ""
Write-Host "✅ Processamento completo:" -ForegroundColor Green
Write-Host "  Candles: $totalProcessed" -ForegroundColor Yellow
Write-Host "  Sinais (score≥$MinScore, signals≥$MinSignalCount): $($results.Count)" -ForegroundColor Cyan
Write-Host ""

# Export
if ($results.Count -gt 0) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputFile = Join-Path $journalDir "faro_v3_backtest_real_$timestamp.csv"

    $results | Export-Csv -Path $outputFile -NoTypeInformation

    Write-Host "✅ CSV: $(Split-Path $outputFile -Leaf)" -ForegroundColor Green
    Write-Host ""

    $wins = @($results | Where-Object { $_.win -eq 1 }).Count
    $winRate = [Math]::Round(($wins / $results.Count) * 100, 1)
    $avgRet3d = ($results | ForEach-Object { [double]$_.return_3d } | Measure-Object -Average).Average

    Write-Host "📊 RESULTADOS:" -ForegroundColor Cyan
    Write-Host "  Total sinais: $($results.Count)" -ForegroundColor Yellow
    Write-Host "  Win rate (3d): $winRate%" -ForegroundColor $(if ($winRate -ge 55) { "Green" } else { "Yellow" })
    Write-Host "  Avg return 3d: $([Math]::Round($avgRet3d, 2))%" -ForegroundColor Yellow

    $top = $results | Group-Object -Property market | Sort-Object -Property Count -Descending | Select-Object -First 5
    Write-Host ""
    Write-Host "Top markets:" -ForegroundColor Green
    foreach ($m in $top) {
        Write-Host "  $($m.Name): $($m.Count) signals" -ForegroundColor Cyan
    }
} else {
    Write-Host "⚠️  Nenhum sinal gerado" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
