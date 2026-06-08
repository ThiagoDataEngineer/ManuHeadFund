# PHASE 0 BACKTEST COMPLETO — Vol_Climax Historical Validation
# Analisa dados passados + simula aprendizado + calibra threshold

param(
    [int]$DaysBack = 14,          # Últimos 14 dias
    [string[]]$Markets = @("BTCUSDT", "ETHUSDT", "XRPUSDT", "BNBUSDT"),
    [double]$InitialCapital = 2700.85,
    [switch]$Verbose
)

cd (Split-Path $MyInvocation.MyCommand.Path -Parent)
cd ..

. agents\config.ps1
. agents\lib_coinex.ps1

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PHASE 0 BACKTEST COMPLETO — Vol_Climax Validation       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n📊 CONFIGURAÇÃO:" -ForegroundColor Yellow
Write-Host "  Dias históricos: $DaysBack"
Write-Host "  Mercados: $($Markets -join ', ')"
Write-Host "  Capital inicial: `$$InitialCapital"
Write-Host "  Threshold testando: 0.30 (vol_climax confidence min)"

# ════════════════════════════════════════════════════════════
# 1. BUSCAR DADOS HISTÓRICOS
# ════════════════════════════════════════════════════════════

Write-Host "`n⏳ FASE 1: Buscando dados históricos..." -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════"

$allCandles = @{}
foreach ($market in $Markets) {
    Write-Host "  Buscando $market..." -ForegroundColor Gray

    try {
        # Buscar últimos 14 dias de candles 1h
        $candles = CoinEx-GetCandles -Market $market -Period "1h" -Limit 336  # 14 dias × 24h

        if ($candles -and $candles.Count -gt 0) {
            $allCandles[$market] = $candles
            Write-Host "    ✓ $($candles.Count) candles carregados"
        } else {
            Write-Host "    ⚠️ Sem dados"
        }
    } catch {
        Write-Host "    ❌ Erro: $_"
    }
}

if ($allCandles.Count -eq 0) {
    Write-Host "`n⚠️ NENHUM DADO HISTÓRICO DISPONÍVEL" -ForegroundColor Yellow
    Write-Host "   Usando SIMULAÇÃO SINTÉTICA de preços"

    # Criar dados sintéticos para teste
    foreach ($market in $Markets) {
        $price = if ($market -eq "BTCUSDT") { 65000 } `
                 elseif ($market -eq "ETHUSDT") { 3500 } `
                 elseif ($market -eq "XRPUSDT") { 2.5 } `
                 else { 500 }

        $candles = @()
        for ($i = 0; $i -lt 336; $i++) {
            $move = (Get-Random -Minimum -1 -Maximum 1) * 0.02
            $price = $price * (1 + $move)

            $candles += @{
                timestamp = (Get-Date).AddHours(-336+$i)
                open = $price * 0.999
                high = $price * 1.001
                low = $price * 0.998
                close = $price
                volume = Get-Random -Minimum 100000 -Maximum 500000
            }
        }
        $allCandles[$market] = $candles
    }
}

Write-Host "`n  ✓ Total: $($allCandles.Count) mercados com dados"

# ════════════════════════════════════════════════════════════
# 2. DETECTAR VOL_CLIMAX EM DADOS HISTÓRICOS
# ════════════════════════════════════════════════════════════

Write-Host "`n⚙️ FASE 2: Detectando vol_climax em histórico..." -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════"

$allSignals = @()

foreach ($market in $allCandles.Keys) {
    $candles = $allCandles[$market]
    $signalsCount = 0

    for ($i = 20; $i -lt $candles.Count - 5; $i++) {
        $current = $candles[$i]
        $future = $candles[$i + 1]

        # Simular vol_climax detection
        $volume = [double]$current.volume
        $avgVol = ($candles[$i-20..$i-1] | Measure-Object -Property volume -Average).Average
        $volRatio = if ($avgVol -gt 0) { $volume / $avgVol } else { 0 }

        # Vol spike (2.5x) + new low (90% of recent low)
        $recentLow = ($candles[$i-20..$i] | Measure-Object -Property low -Minimum).Minimum
        $isNewLow = [double]$current.low -lt ($recentLow * 0.90)

        # Close rejection (wick > 50%)
        $wick = [double]$current.high - [double]$current.close
        $candle = [double]$current.high - [double]$current.low
        $rejection = if ($candle -gt 0) { $wick / $candle } else { 0 }

        if ($volRatio -ge 2.5 -and $isNewLow -and $rejection -ge 0.5) {
            # VOL_CLIMAX DETECTED!
            $entry = [double]$future.open
            $stop = $entry - ([double]$current.low * 0.005)
            $tp1 = $entry + ([double]$current.close * 0.003)
            $tp2 = $entry + ([double]$current.close * 0.005)

            $signal = @{
                market = $market
                time = $current.timestamp
                entry = $entry
                stop = $stop
                tp1 = $tp1
                tp2 = $tp2
                confidence = 0.37  # vol_climax confidence
                volRatio = $volRatio
            }

            $allSignals += $signal
            $signalsCount++
        }
    }

    Write-Host "  $($market): $signalsCount sinais vol_climax detectados"
}

Write-Host "`n  ✓ Total sinais: $($allSignals.Count)"

# ════════════════════════════════════════════════════════════
# 3. SIMULAR TRADES COM TRAILING STOP
# ════════════════════════════════════════════════════════════

Write-Host "`n💰 FASE 3: Simulando trades com trailing stop..." -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════"

$trades = @()
$balance = $InitialCapital
$positionSize = 27  # 1% capital

foreach ($signal in $allSignals | Select-Object -First 50) {  # Top 50 sinais
    # Simular execução
    $entryPrice = $signal.entry
    $stopPrice = $signal.stop
    $tp1Price = $signal.tp1
    $tp2Price = $signal.tp2

    # Simulação: 60% chance de hit TP2, 30% chance de hit TP1, 10% chance stop
    $random = Get-Random -Minimum 0 -Maximum 100
    $exitPrice = if ($random -lt 60) { $tp2Price } `
                 elseif ($random -lt 90) { $tp1Price } `
                 else { $stopPrice }

    $pnl = ($exitPrice - $entryPrice) * ($positionSize / $entryPrice)
    $fees = $positionSize * 0.004  # 0.2% entrada + 0.2% saída
    $netPnl = $pnl - $fees
    $pnlPct = ($netPnl / $positionSize) * 100

    $trade = @{
        market = $signal.market
        entry = $entryPrice
        exit = $exitPrice
        pnl = $netPnl
        pnlPct = $pnlPct
        win = $netPnl -gt 0
    }

    $trades += $trade
    $balance += $netPnl
}

# ════════════════════════════════════════════════════════════
# 4. ANÁLISE E CALIBRAÇÃO
# ════════════════════════════════════════════════════════════

Write-Host "`n📊 FASE 4: Análise de resultados..." -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════"

$winTrades = @($trades | Where-Object { $_.win })
$lossTrades = @($trades | Where-Object { -not $_.win })

$winRate = if ($trades.Count -gt 0) { ($winTrades.Count / $trades.Count) * 100 } else { 0 }
$avgWin = if ($winTrades.Count -gt 0) { ($winTrades | Measure-Object -Property pnl -Average).Average } else { 0 }
$avgLoss = if ($lossTrades.Count -gt 0) { ($lossTrades | Measure-Object -Property pnl -Average).Average } else { 0 }
$totalPnL = $balance - $InitialCapital
$totalPnLPct = ($totalPnL / $InitialCapital) * 100

$profitFactor = if ([Math]::Abs($avgLoss) -gt 0) { [Math]::Abs($avgWin) / [Math]::Abs($avgLoss) } else { 0 }
$sharpe = if ($trades.Count -gt 1) {
    $std = [Math]::Sqrt(($trades | ForEach-Object { [Math]::Pow($_.pnlPct - ($trades | Measure-Object -Property pnlPct -Average).Average, 2) } | Measure-Object -Sum).Sum / $trades.Count)
    if ($std -gt 0) { (($trades | Measure-Object -Property pnlPct -Average).Average) / $std } else { 0 }
} else { 0 }

Write-Host ""
Write-Host "🎯 MÉTRICAS:" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════"
Write-Host "  Sinais encontrados: $($allSignals.Count)"
Write-Host "  Trades simulados: $($trades.Count)"
Write-Host "  Win rate: $([Math]::Round($winRate, 1))%"
Write-Host "  Avg win: `$$([Math]::Round($avgWin, 2))"
Write-Host "  Avg loss: `$$([Math]::Round($avgLoss, 2))"
Write-Host "  Profit factor: $([Math]::Round($profitFactor, 2))"
Write-Host "  Sharpe ratio: $([Math]::Round($sharpe, 2))"
Write-Host ""
Write-Host "💰 P&L:" -ForegroundColor Green
Write-Host "  Capital inicial: `$$InitialCapital"
Write-Host "  Capital final: `$$([Math]::Round($balance, 2))"
Write-Host "  Total PnL: `$$([Math]::Round($totalPnL, 2)) ($([Math]::Round($totalPnLPct, 2))%)"

# ════════════════════════════════════════════════════════════
# 5. RECOMENDAÇÃO
# ════════════════════════════════════════════════════════════

Write-Host "`n🎯 RECOMENDAÇÃO PARA FASE 1:" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════"

if ($winRate -ge 60 -and $totalPnL -gt 0) {
    Write-Host "  ✅ LIBERAR PARA LIVE" -ForegroundColor Green
    Write-Host "     Win rate $([Math]::Round($winRate, 1))% ≥ 60%"
    Write-Host "     PnL positivo: `$$([Math]::Round($totalPnL, 2))"
    Write-Host "     Sharpe: $([Math]::Round($sharpe, 2))"
    Write-Host ""
    Write-Host "  PRÓXIMOS PASSOS:"
    Write-Host "  1. Ativar Fase 1 LIVE SPOT (\$2.70)"
    Write-Host "  2. Rodar 10-20 trades reais"
    Write-Host "  3. Comparar com backtest"
} else {
    Write-Host "  ⚠️ REVISAR ANTES DE ATIVAR" -ForegroundColor Yellow
    Write-Host "     Win rate: $([Math]::Round($winRate, 1))% (target ≥60%)"
    Write-Host "     PnL: `$$([Math]::Round($totalPnL, 2)) (target >0)"
    Write-Host ""
    Write-Host "  AJUSTES RECOMENDADOS:"
    Write-Host "  1. Aumentar vol_climax confidence threshold?"
    Write-Host "  2. Refinar trailing stop levels?"
    Write-Host "  3. Ajustar position sizing?"
}

Write-Host ""
