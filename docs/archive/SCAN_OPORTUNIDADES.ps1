# SCAN_OPORTUNIDADES.ps1
# Scanner de oportunidades para cobrir perdas
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"

Write-Host "=== SCANNER DE OPORTUNIDADES ===" -ForegroundColor Cyan
Write-Host ""

# Buscar todos os tickers
Write-Host "Buscando tickers..." -ForegroundColor Yellow
$tickers = CoinEx-GetAllFuturesTickers
Write-Host "Total tickers: $($tickers.Count)"
Write-Host ""

# Filtrar por volume e volatilidade
Write-Host "Filtrando por volume e momentum..." -ForegroundColor Yellow

$candidates = @()

foreach ($t in $tickers) {
    $market = $t.market
    $last = [double]$t.last
    $high = [double]$t.high_24h
    $low = [double]$t.low_24h
    $change = [double]$t.change_24h
    $vol = [double]$t.vol
    
    # Filtros:
    # - Volume > 1M USDT
    # - Preço entre $0.1 e $100 (evitar muito barato ou muito caro)
    # - Change > 2% (momentum)
    if ($vol -gt 1000000 -and $last -gt 0.1 -and $last -lt 100 -and [Math]::Abs($change) -gt 2) {
        $range = (($high - $low) / $low) * 100
        
        $candidates += [PSCustomObject]@{
            market = $market
            last = $last
            high_24h = $high
            low_24h = $low
            change_24h = $change
            vol = $vol
            range_pct = $range
        }
    }
}

# Ordenar por momentum (change absoluto)
$candidates = $candidates | Sort-Object { [Math]::Abs($_.change_24h) } -Descending

Write-Host ""
Write-Host "=== TOP 20 CANDIDATOS POR MOMENTUM ===" -ForegroundColor Green
Write-Host ""

$top20 = $candidates | Select-Object -First 20

foreach ($c in $top20) {
    $changeColor = if ($c.change_24h -gt 0) { "Green" } else { "Red" }
    
    Write-Host "$($c.market.PadRight(15))" -NoNewline
    Write-Host " | Price: `$$([Math]::Round($c.last, 4))".PadRight(20) -NoNewline
    Write-Host " | Change: " -NoNewline
    Write-Host "$([Math]::Round($c.change_24h, 2))%".PadRight(10) -ForegroundColor $changeColor -NoNewline
    Write-Host " | Range: $([Math]::Round($c.range_pct, 2))%".PadRight(15) -NoNewline
    Write-Host " | Vol: `$$([Math]::Round($c.vol/1000000, 1))M"
}

Write-Host ""
Write-Host "=== ANALISE TECNICA DOS TOP 5 ===" -ForegroundColor Cyan
Write-Host ""

$top5 = $top20 | Select-Object -First 5

foreach ($c in $top5) {
    Write-Host "--- $($c.market) ---" -ForegroundColor Yellow
    
    # Buscar candles 15min
    try {
        $candles = CoinEx-GetFuturesCandles -market $c.market -period "15min" -limit 50
        
        if ($candles.Count -ge 20) {
            # Calcular RSI simples (14 periodos)
            $closes = $candles | Select-Object -Last 14 | ForEach-Object { $_.close }
            $gains = @()
            $losses = @()
            
            for ($i = 1; $i -lt $closes.Count; $i++) {
                $diff = $closes[$i] - $closes[$i-1]
                if ($diff -gt 0) {
                    $gains += $diff
                    $losses += 0
                } else {
                    $gains += 0
                    $losses += [Math]::Abs($diff)
                }
            }
            
            $avgGain = ($gains | Measure-Object -Average).Average
            $avgLoss = ($losses | Measure-Object -Average).Average
            
            if ($avgLoss -gt 0) {
                $rs = $avgGain / $avgLoss
                $rsi = 100 - (100 / (1 + $rs))
            } else {
                $rsi = 100
            }
            
            # Preco atual vs SMA20
            $sma20 = ($candles | Select-Object -Last 20 | Measure-Object -Property close -Average).Average
            $currentPrice = $candles[-1].close
            $distSma = (($currentPrice - $sma20) / $sma20) * 100
            
            Write-Host "  RSI(14): $([Math]::Round($rsi, 2))"
            Write-Host "  SMA20: `$$([Math]::Round($sma20, 4))"
            Write-Host "  Dist SMA20: $([Math]::Round($distSma, 2))%"
            
            # Avaliar setup
            $setup = ""
            if ($rsi -lt 35 -and $distSma -lt -2) {
                $setup = "LONG (sobrevenda + abaixo SMA20)"
                Write-Host "  Setup: $setup" -ForegroundColor Green
            } elseif ($rsi -gt 65 -and $distSma -gt 2) {
                $setup = "SHORT (sobrecompra + acima SMA20)"
                Write-Host "  Setup: $setup" -ForegroundColor Red
            } elseif ($rsi -gt 45 -and $rsi -lt 55 -and [Math]::Abs($distSma) -lt 1) {
                $setup = "NEUTRO (sem setup claro)"
                Write-Host "  Setup: $setup" -ForegroundColor Gray
            } else {
                $setup = "AVALIAR (momentum mas sem confirmacao)"
                Write-Host "  Setup: $setup" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "  Erro ao buscar candles: $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "=== SCAN COMPLETO ===" -ForegroundColor Green
