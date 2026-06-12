# VERSÃO SIMPLIFICADA — backtest real com cálculo manual dos sinais
# Sem dependência das libs de scoring completas

param([int] $MinScore = 30, [int] $MinSignalCount = 2, [int] $SampleSize = 146)

$projectRoot = Split-Path $PSScriptRoot -Parent
$journalDir = Join-Path $projectRoot "journal"
$candlesDir = Join-Path $journalDir "candles_coinex"

Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "🧪 FARO V3 BACKTEST REAL V2 — Simplificado" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "MinScore: $MinScore | MinSignals: $MinSignalCount" -ForegroundColor Yellow
Write-Host ""

if (-not (Test-Path $candlesDir)) {
    Write-Host "❌ Erro: $candlesDir não encontrado" -ForegroundColor Red
    exit 1
}

$candleFiles = @(Get-ChildItem $candlesDir -Filter "*_1day.json" | Sort-Object Name | Select-Object -First $SampleSize)
Write-Host "Processando: $($candleFiles.Count) mercados" -ForegroundColor Green
Write-Host ""

$results = [System.Collections.Generic.List[PSObject]]::new()
$totalCandles = 0
$totalSignalsFound = 0

foreach ($file in $candleFiles) {
    $market = $file.BaseName -replace "_1day", ""

    try {
        $candles = @(Get-Content $file.FullName | ConvertFrom-Json -ErrorAction Stop)
        if ($candles.Count -lt 50) { continue }

        # Varrer candle-a-candle
        for ($idx = 24; $idx -lt ($candles.Count - 7); $idx++) {
            $window = @($candles[($idx - 24)..$idx])
            if ($window.Count -lt 24) { continue }

            $curr = $window[-1]
            $hist = $window[0..23]

            $totalCandles++

            # Cálculo MANUAL de sinais (sem libs complexas)
            $signalCount = 0
            $score = 0

            # Signal 1: Volume spike (> 2x média)
            $currVol = [double]($curr.volume ?? 0)
            $avgVol = ($hist | ForEach-Object { [double]$_.volume } | Measure-Object -Average).Average
            if ($currVol -gt ($avgVol * 2.0)) { $signalCount++; $score += 20 }

            # Signal 2: High/low extremes (wick rejection)
            $curr_close = [double]$curr.close
            $curr_open = [double]$curr.open
            if ($curr_close -lt $curr_open -and [double]$curr.high -gt ($curr_close * 1.02)) { $signalCount++; $score += 15 }

            # Signal 3: Momentum (close > open and above previous)
            $prevClose = [double]$hist[-1].close
            if ($curr_close -gt $curr_open -and $curr_close -gt $prevClose) { $signalCount++; $score += 20 }

            # Signal 4: Volume concentration (vol > 2x AND trend exists)
            $closes = @($hist | ForEach-Object { [double]$_.close })
            $ma10 = ($closes[-10..-1] | Measure-Object -Average).Average
            if ($currVol -gt ($avgVol * 1.5) -and $curr_close -gt $ma10) { $signalCount++; $score += 18 }

            # Signal 5: Extended move (>2% move in a day)
            $pctChange = [Math]::Abs(($curr_close - $curr_open) / $curr_open)
            if ($pctChange -gt 0.02) { $signalCount++; $score += 15 }

            # Signal 6: Gap up from previous
            if ($curr_open -gt [double]$hist[-1].high) { $signalCount++; $score += 12 }

            # Signal 7: Strong close (>75% of range)
            $range = [double]$curr.high - [double]$curr.low
            if ($range -gt 0 -and ($curr_close - [double]$curr.low) / $range -gt 0.75) { $signalCount++; $score += 10 }

            # Normalizar score a 0-100
            $score = [Math]::Min($score, 100)

            # Registrar se passou no threshold
            if ($score -ge $MinScore -and $signalCount -ge $MinSignalCount) {
                $totalSignalsFound++

                # Calcular retorno futuro
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

Write-Host "Processamento completo:" -ForegroundColor Green
Write-Host "  Candles: $totalCandles" -ForegroundColor Yellow
Write-Host "  Sinais: $totalSignalsFound" -ForegroundColor Yellow
Write-Host "  Results array: $($results.Count)" -ForegroundColor Cyan
Write-Host ""

# Export
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $journalDir "faro_v3_backtest_real_v2_$timestamp.csv"

if ($results.Count -gt 0) {
    $results | Export-Csv -Path $outputFile -NoTypeInformation -ErrorAction SilentlyContinue

    Write-Host "✅ CSV SALVO: $(Split-Path $outputFile -Leaf)" -ForegroundColor Green
    Write-Host ""

    $wins = @($results | Where-Object { $_.win -eq 1 }).Count
    $winRate = [Math]::Round(($wins / $results.Count) * 100, 1)
    $avgRet3d = ($results | ForEach-Object { [double]$_.return_3d } | Measure-Object -Average).Average

    Write-Host "📊 STATS:" -ForegroundColor Cyan
    Write-Host "  Total: $($results.Count)" -ForegroundColor Yellow
    Write-Host "  Win rate (3d): $winRate%" -ForegroundColor Yellow
    Write-Host "  Avg return 3d: $([Math]::Round($avgRet3d, 2))%" -ForegroundColor Yellow

    $top = $results | Group-Object -Property market | Sort-Object -Property Count -Descending | Select-Object -First 3
    Write-Host ""
    Write-Host "Top markets:" -ForegroundColor Green
    foreach ($m in $top) {
        Write-Host "  $($m.Name): $($m.Count)" -ForegroundColor Cyan
    }

} else {
    Write-Host "⚠️  Nenhum sinal gerado" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
