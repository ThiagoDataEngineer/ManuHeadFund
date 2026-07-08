# Backtesting Tori com Confluências — Validação 60 dias
# Uso: .\backtest_tori_confluence_validation.ps1

$COINEX_BASE_URL = "https://api.coinex.com"

function Get-RSI {
    param($closes, $period = 14)
    if ($closes.Count -lt $period + 1) { return 50 }

    $gains = 0
    $losses = 0

    for ($i = 1; $i -le $period; $i++) {
        $change = $closes[-$i] - $closes[-$i-1]
        if ($change -gt 0) { $gains += $change } else { $losses += [math]::Abs($change) }
    }

    $avgGain = $gains / $period
    $avgLoss = $losses / $period

    if ($avgLoss -eq 0) { return 100 }
    $rs = $avgGain / $avgLoss
    $rsi = 100 - (100 / (1 + $rs))
    return $rsi
}

function Get-VolumeClimax {
    param($volumes)
    if ($volumes.Count -lt 20) { return $false }
    $avg = ($volumes | Measure-Object -Average).Average
    $current = $volumes[-1]
    return ($current -gt ($avg * 1.8))
}

function Get-Fractal {
    param($lows, $highs, $setupType)
    if ($lows.Count -lt 5) { return $false }

    $mid = $lows[-3]
    if ($setupType -eq "LONG") {
        # Bullish fractal: lower lows on both sides
        return ($lows[-5] -gt $mid -and $lows[-4] -gt $mid -and $lows[-2] -gt $mid -and $lows[-1] -gt $mid)
    } else {
        # Bearish fractal: higher highs on both sides
        return ($highs[-5] -lt $highs[-3] -and $highs[-4] -lt $highs[-3] -and $highs[-2] -lt $highs[-3] -and $highs[-1] -lt $highs[-3])
    }
}

function Get-ConfluenceScore {
    param($closes, $volumes, $lows, $highs, $setupType)

    $score = 50  # Base

    # RSI Extreme
    $rsi = Get-RSI -closes $closes
    if ($setupType -eq "SHORT" -and $rsi -gt 65) { $score += 20 }
    if ($setupType -eq "LONG" -and $rsi -lt 35) { $score += 20 }

    # Volume Climax
    if (Get-VolumeClimax -volumes $volumes) { $score += 15 }

    # Fractal
    if (Get-Fractal -lows $lows -highs $highs -setupType $setupType) { $score += 15 }

    return [math]::Min($score, 100)
}

Write-Host "🔄 BACKTESTING TORI COM CONFLUÊNCIAS — 60 DIAS" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

$pairs = @("BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "AVAXUSDT")
$allTrades = @()

foreach ($pair in $pairs) {
    Write-Host "📊 Processando $pair..." -ForegroundColor Yellow

    try {
        # Puxar 1440 candles (60 dias × 1H)
        $r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/kline?market=$pair&period=1hour&limit=1440" -Method GET -TimeoutSec 10 -ErrorAction Stop

        if ($r.code -eq 0 -and $r.data -and $r.data.Count -gt 100) {
            $candles = $r.data
            $closes = @($candles | ForEach-Object { [double]$_.close })
            $volumes = @($candles | ForEach-Object { [double]$_.volume })
            $lows = @($candles | ForEach-Object { [double]$_.low })
            $highs = @($candles | ForEach-Object { [double]$_.high })

            # Simular trades a cada 100 candles (análise walking-forward)
            for ($i = 50; $i -lt $candles.Count - 50; $i += 100) {
                $closesWindow = $closes[0..$i]
                $volumesWindow = $volumes[0..$i]
                $lowsWindow = $lows[0..$i]
                $highsWindow = $highs[0..$i]

                # Determinar setup (simulado com SMA)
                $sma20 = ($closesWindow | Select-Object -Last 20 | Measure-Object -Average).Average
                $currentPrice = $closes[$i]

                $setupType = if ($currentPrice -lt $sma20) { "SHORT" } else { "LONG" }

                # Calcular confluence
                $confluence = Get-ConfluenceScore -closes $closesWindow -volumes $volumesWindow -lows $lowsWindow -highs $highsWindow -setupType $setupType

                # Se confluência >= 75, entrar
                if ($confluence -ge 75) {
                    $entryPrice = $currentPrice
                    $entryCandle = $i

                    # Simular exit nos próximos 50 candles
                    $exitCandle = -1
                    $exitPrice = 0
                    $result = "LOSS"

                    for ($j = $i + 1; $j -lt [math]::Min($i + 50, $candles.Count); $j++) {
                        $checkPrice = [double]$candles[$j].close

                        if ($setupType -eq "SHORT") {
                            $targetPrice = $entryPrice * 0.98  # 2% ganho
                            $stopPrice = $entryPrice * 1.01   # 1% loss

                            if ($checkPrice -le $targetPrice) {
                                $exitPrice = $checkPrice
                                $exitCandle = $j
                                $result = "WIN"
                                break
                            } elseif ($checkPrice -ge $stopPrice) {
                                $exitPrice = $checkPrice
                                $exitCandle = $j
                                $result = "LOSS"
                                break
                            }
                        } else {
                            $targetPrice = $entryPrice * 1.02
                            $stopPrice = $entryPrice * 0.99

                            if ($checkPrice -ge $targetPrice) {
                                $exitPrice = $checkPrice
                                $exitCandle = $j
                                $result = "WIN"
                                break
                            } elseif ($checkPrice -le $stopPrice) {
                                $exitPrice = $checkPrice
                                $exitCandle = $j
                                $result = "LOSS"
                                break
                            }
                        }
                    }

                    # Se não saiu, usar último candle
                    if ($exitCandle -eq -1) {
                        $exitPrice = [double]$candles[$i + 49].close
                        $exitCandle = $i + 49
                    }

                    $pnl = if ($setupType -eq "SHORT") {
                        (($entryPrice - $exitPrice) / $entryPrice) * 100
                    } else {
                        (($exitPrice - $entryPrice) / $entryPrice) * 100
                    }

                    $allTrades += [PSCustomObject]@{
                        pair = $pair
                        setup_type = $setupType
                        entry_price = $entryPrice
                        exit_price = $exitPrice
                        pnl_pct = $pnl
                        hold_candles = $exitCandle - $entryCandle
                        confluence_score = $confluence
                        result = $result
                    }
                }
            }
        }
    } catch {
        Write-Host "  ⚠️ Erro: $_" -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 100
}

# Estatísticas
$wins = @($allTrades | Where-Object { $_.result -eq "WIN" })
$losses = @($allTrades | Where-Object { $_.result -eq "LOSS" })

$winRate = if ($allTrades.Count -gt 0) { ($wins.Count / $allTrades.Count) * 100 } else { 0 }
$avgWin = if ($wins.Count -gt 0) { ($wins | Measure-Object -Property pnl_pct -Average).Average } else { 0 }
$avgLoss = if ($losses.Count -gt 0) { ($losses | Measure-Object -Property pnl_pct -Average).Average } else { 0 }
$totalPnL = ($allTrades | Measure-Object -Property pnl_pct -Sum).Sum
$profitFactor = if ($losses.Count -gt 0 -and $avgLoss -ne 0) { ($wins | Measure-Object -Property pnl_pct -Sum).Sum / [math]::Abs(($losses | Measure-Object -Property pnl_pct -Sum).Sum) } else { 0 }

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 RESULTADOS DO BACKTESTING (60 dias):" -ForegroundColor Green
Write-Host ""
Write-Host "  Total de Trades: $($allTrades.Count)" -ForegroundColor Gray
Write-Host "  Wins: $($wins.Count) | Losses: $($losses.Count)" -ForegroundColor $(if ($wins.Count -gt $losses.Count) { "Green" } else { "Red" })
Write-Host "  Win Rate: $([math]::Round($winRate, 1))%" -ForegroundColor $(if ($winRate -gt 50) { "Green" } else { "Red" })
Write-Host "  Avg Win: $([math]::Round($avgWin, 3))% | Avg Loss: $([math]::Round($avgLoss, 3))%" -ForegroundColor Gray
Write-Host "  Ganho Total: $([math]::Round($totalPnL, 2))%" -ForegroundColor $(if ($totalPnL -gt 0) { "Green" } else { "Red" })
Write-Host "  Profit Factor: $([math]::Round($profitFactor, 2))" -ForegroundColor $(if ($profitFactor -gt 1) { "Green" } else { "Red" })
Write-Host ""

if ($allTrades.Count -gt 0) {
    Write-Host "  Top 5 Melhores Trades:" -ForegroundColor Cyan
    $allTrades | Sort-Object -Property pnl_pct -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host "    $($_.pair) | $($_.setup_type) | Entry: $($_.entry_price.ToString('F4')) | Exit: $($_.exit_price.ToString('F4')) | P&L: $($_.pnl_pct.ToString('F3'))% | $($_.result) | Conf: $($_.confluence_score)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Bottom 5 Piores Trades:" -ForegroundColor Red
    $allTrades | Sort-Object -Property pnl_pct | Select-Object -First 5 | ForEach-Object {
        Write-Host "    $($_.pair) | $($_.setup_type) | Entry: $($_.entry_price.ToString('F4')) | Exit: $($_.exit_price.ToString('F4')) | P&L: $($_.pnl_pct.ToString('F3'))% | $($_.result) | Conf: $($_.confluence_score)" -ForegroundColor Gray
    }
}

# Exportar
$allTrades | ConvertTo-Json -Depth 10 | Out-File "c:\Users\thiag\Coinex_AI_USER_API\backtest_tori_60d_results.json" -Encoding UTF8

Write-Host ""
Write-Host "✅ Resultados exportados para backtest_tori_60d_results.json" -ForegroundColor Green

Write-Host ""
Write-Host "🎯 CONCLUSÃO:" -ForegroundColor Yellow
if ($winRate -ge 55 -and $totalPnL -gt 0) {
    Write-Host "   ✅ METODOLOGIA TORI COM CONFLUÊNCIAS = RENTÁVEL" -ForegroundColor Green
    Write-Host "   Base para produção validada!" -ForegroundColor Green
} else {
    Write-Host "   ⚠️ Resultados mistos — precisa ajustes nos thresholds" -ForegroundColor Yellow
}
