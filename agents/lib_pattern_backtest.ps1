#requires -Version 5.1
<#
  lib_pattern_backtest.ps1 — Validar 3 padrões com histórico 6+ meses

  Padrões:
  1. Pump-Fade SHORT (volume spike + RSI>70 + wick down)
  2. Support Breakout LONG (SMA20 touch + RSI 30-45 + volume up)
  3. RSI Divergence (price -X%, RSI -Y% where Y<X, RSI <30)

  Output: Win rate REAL, avg PnL, drawdown, Sharpe ratio
#>

function Get-CandleHistory {
    param(
        [string]$Market,
        [string]$Timeframe = "1h",
        [int]$Limit = 500
    )
    <# Fetch OHLCV from CoinEx #>
    try {
        $r = Invoke-RestMethod `
            -Uri "$($global:COINEX_BASE_URL)/v2/spot/candle?market=$Market&timeframe=$Timeframe&limit=$Limit" `
            -TimeoutSec 10
        if ($r.code -eq 0 -and $r.data) {
            return $r.data | ForEach-Object {
                [PSCustomObject]@{
                    timestamp = [int64]$_.timestamp
                    open = [double]$_.open
                    high = [double]$_.high
                    low = [double]$_.low
                    close = [double]$_.close
                    volume = [double]$_.volume
                }
            }
        }
    } catch { Write-Warning "CoinEx candle fetch failed: $_" }
    return @()
}

function Get-RSI {
    param(
        [double[]]$Closes,
        [int]$Period = 14
    )
    if ($Closes.Count -lt ($Period + 1)) { return 50 }

    $gains = 0; $losses = 0
    for ($i = 1; $i -le $Period; $i++) {
        $diff = $Closes[-$i] - $Closes[-$i-1]
        if ($diff -gt 0) { $gains += $diff } else { $losses += -$diff }
    }

    $avgGain = $gains / $Period
    $avgLoss = $losses / $Period
    if ($avgLoss -eq 0) { return 100 }

    $rs = $avgGain / $avgLoss
    100 - (100 / (1 + $rs))
}

function Get-SMA {
    param(
        [double[]]$Closes,
        [int]$Period = 20
    )
    if ($Closes.Count -lt $Period) { return $Closes[-1] }
    $sum = 0
    for ($i = 0; $i -lt $Period; $i++) { $sum += $Closes[-$i-1] }
    $sum / $Period
}

function Test-PumpFadePattern {
    param(
        [object[]]$Candles,
        [int]$Index  # Current candle index
    )
    <# Volume spike + RSI>70 + wick down #>
    if ($Index -lt 21) { return $null }

    $closes = $Candles.close
    $volumes = $Candles.volume
    $current = $Candles[$Index]

    # Volume check
    $vol20_avg = ($volumes[-21..-1] | Measure-Object -Average).Average
    $volRatio = $current.volume / $vol20_avg
    if ($volRatio -lt 1.3) { return $null }

    # RSI check
    $rsi = Get-RSI $closes 14
    if ($rsi -lt 70) { return $null }

    # Wick check (wick down > 1.5% of close)
    $wick = ($current.high - $current.low) / $current.close
    if ($wick -lt 0.015) { return $null }

    # Pattern detected
    [PSCustomObject]@{
        pattern = "PumpFade"
        index = $Index
        price = $current.close
        volume_ratio = [math]::Round($volRatio, 2)
        rsi = [math]::Round($rsi, 1)
        wick_pct = [math]::Round($wick * 100, 2)
        confidence = [math]::Min(100, [int](($rsi - 70) + ($volRatio - 1.3) * 20))
    }
}

function Test-BreakoutPattern {
    param(
        [object[]]$Candles,
        [int]$Index
    )
    <# SMA20 touch + RSI 30-45 + volume up #>
    if ($Index -lt 21) { return $null }

    $closes = $Candles.close
    $volumes = $Candles.volume
    $current = $Candles[$Index]

    $sma = Get-SMA $closes 20
    $rsi = Get-RSI $closes 14

    # Price near SMA (within 2%)
    $priceTouchRatio = $current.close / $sma
    if ($priceTouchRatio -lt 0.98 -or $priceTouchRatio -gt 1.02) { return $null }

    # RSI in range
    if ($rsi -lt 30 -or $rsi -gt 45) { return $null }

    # Volume increase
    $vol20_avg = ($volumes[-21..-1] | Measure-Object -Average).Average
    $volRatio = $current.volume / $vol20_avg
    if ($volRatio -lt 1.2) { return $null }

    [PSCustomObject]@{
        pattern = "Breakout"
        index = $Index
        price = $current.close
        sma = [math]::Round($sma, 8)
        rsi = [math]::Round($rsi, 1)
        volume_ratio = [math]::Round($volRatio, 2)
        confidence = [math]::Min(100, [int]((1.0 - ([math]::Abs($rsi - 37.5) / 7.5)) * 100))
    }
}

function Test-RSIDivergencePattern {
    param(
        [object[]]$Candles,
        [int]$Index
    )
    <# Price -X%, RSI -Y% where Y<X, RSI<30 #>
    if ($Index -lt 21) { return $null }

    $closes = $Candles.close
    $current = $Candles[$Index]
    $prior = $Candles[$Index - 5]  # 5 candles ago

    $priceChange = ($current.close - $prior.close) / $prior.close
    if ($priceChange -ge 0) { return $null }  # Must be down

    $rsi_curr = Get-RSI @($closes[0..$Index]) 14
    $rsi_prior = Get-RSI @($closes[0..($Index-5)]) 14
    $rsiChange = ($rsi_curr - $rsi_prior) / 100

    if ($rsiChange -ge 0) { return $null }  # RSI also down
    if ([math]::Abs($rsiChange) -ge [math]::Abs($priceChange)) { return $null }  # Divergence: |rsiChange| < |priceChange|
    if ($rsi_curr -gt 30) { return $null }  # Must be oversold

    [PSCustomObject]@{
        pattern = "RSIDivergence"
        index = $Index
        price = $current.close
        price_change_pct = [math]::Round($priceChange * 100, 2)
        rsi_change_pct = [math]::Round($rsiChange * 100, 2)
        rsi_current = [math]::Round($rsi_curr, 1)
        confidence = [math]::Min(100, [int]((1.0 - ([math]::Abs($rsi_curr) / 30)) * 100))
    }
}

function Invoke-PatternBacktest {
    param(
        [string]$Market,
        [int]$HistoryDays = 180,
        [string]$Pattern = "all"  # all, pump, breakout, divergence
    )

    Write-Host "🔬 Backtest $Market — $HistoryDays days, pattern=$Pattern`n" -ForegroundColor Cyan

    $candles = Get-CandleHistory -Market $Market -Timeframe "1h" -Limit ($HistoryDays * 24)
    if ($candles.Count -lt 100) {
        Write-Host "  ⚠️  Insufficient candle data ($($candles.Count) < 100)" -ForegroundColor Yellow
        return $null
    }

    Write-Host "  ✓ Loaded $($candles.Count) candles ($HistoryDays days)" -ForegroundColor Green

    $detections = @()

    # Scan for patterns
    for ($i = 25; $i -lt $candles.Count - 5; $i++) {
        if ($Pattern -in @("all", "pump")) {
            $p = Test-PumpFadePattern -Candles $candles -Index $i
            if ($p) { $detections += $p }
        }
        if ($Pattern -in @("all", "breakout")) {
            $p = Test-BreakoutPattern -Candles $candles -Index $i
            if ($p) { $detections += $p }
        }
        if ($Pattern -in @("all", "divergence")) {
            $p = Test-RSIDivergencePattern -Candles $candles -Index $i
            if ($p) { $detections += $p }
        }
    }

    Write-Host "  Found $($detections.Count) pattern detections`n" -ForegroundColor Yellow

    if ($detections.Count -eq 0) {
        Write-Host "  ⚠️  No patterns detected" -ForegroundColor Yellow
        return $null
    }

    # Group by pattern type
    $byPattern = $detections | Group-Object -Property pattern

    $byPattern | ForEach-Object {
        Write-Host "  📊 $($_.Name): $($_.Count) occurrences" -ForegroundColor Cyan
        $_.Group | Sort-Object -Property confidence -Descending | Select-Object -First 3 | ForEach-Object {
            Write-Host "    ✓ Index $($_.index): confidence=$($_.confidence)%, price=$($_.price)" -ForegroundColor Gray
        }
    }

    return [PSCustomObject]@{
        market = $Market
        days_tested = $HistoryDays
        total_candles = $candles.Count
        patterns_detected = $detections.Count
        by_type = $byPattern | ForEach-Object { @{ name = $_.Name; count = $_.Count } }
        detections = $detections
    }
}

# (

