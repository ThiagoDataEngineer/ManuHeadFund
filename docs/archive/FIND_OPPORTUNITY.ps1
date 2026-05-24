# FIND_OPPORTUNITY.ps1
# Encontrar oportunidade para cobrir perdas
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"

Write-Host "=== BUSCANDO OPORTUNIDADE PARA COBRIR PERDAS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Perdas a cobrir: ~`$8 USDT"
Write-Host "Capital disponivel: `$1,588 USDT"
Write-Host ""

# Buscar tickers
Write-Host "Analisando mercado..." -ForegroundColor Yellow
$tickers = CoinEx-GetAllFuturesTickers

# Calcular change_24h e filtrar
$candidates = @()

foreach ($t in $tickers) {
    $market = $t.market
    $last = [double]$t.last
    $open = [double]$t.open
    $high = [double]$t.high
    $low = [double]$t.low
    $volume = [double]$t.volume
    $value = [double]$t.value
    
    # Calcular change
    if ($open -gt 0) {
        $change = (($last - $open) / $open) * 100
    } else {
        continue
    }
    
    # Filtros:
    # - Volume > 50k contratos
    # - Value > 100k USDT
    # - Preço entre $0.05 e $200
    # - Change absoluto > 1%
    if ($volume -gt 50000 -and $value -gt 100000 -and $last -gt 0.05 -and $last -lt 200 -and [Math]::Abs($change) -gt 1) {
        $range = (($high - $low) / $low) * 100
        
        $candidates += [PSCustomObject]@{
            market = $market
            last = $last
            open = $open
            high = $high
            low = $low
            change = $change
            volume = $volume
            value = $value
            range_pct = $range
        }
    }
}

# Ordenar por momentum
$candidates = $candidates | Sort-Object { [Math]::Abs($_.change) } -Descending

Write-Host ""
Write-Host "=== TOP 15 CANDIDATOS POR MOMENTUM ===" -ForegroundColor Green
Write-Host ""

$top15 = $candidates | Select-Object -First 15

foreach ($c in $top15) {
    $changeColor = if ($c.change -gt 0) { "Green" } else { "Red" }
    
    Write-Host "$($c.market.PadRight(12))" -NoNewline
    Write-Host " | `$$([Math]::Round($c.last, 4))".PadRight(15) -NoNewline
    Write-Host " | " -NoNewline
    Write-Host "$([Math]::Round($c.change, 2))%".PadRight(8) -ForegroundColor $changeColor -NoNewline
    Write-Host " | Range: $([Math]::Round($c.range_pct, 2))%".PadRight(15) -NoNewline
    Write-Host " | Vol: `$$([Math]::Round($c.value/1000000, 1))M"
}

Write-Host ""
Write-Host "=== ANALISE TECNICA TOP 5 ===" -ForegroundColor Cyan
Write-Host ""

$top5 = $top15 | Select-Object -First 5

foreach ($c in $top5) {
    Write-Host "--- $($c.market) ---" -ForegroundColor Yellow
    Write-Host "  Preco: `$$([Math]::Round($c.last, 4))"
    Write-Host "  Change 24h: $([Math]::Round($c.change, 2))%"
    Write-Host "  Range 24h: $([Math]::Round($c.range_pct, 2))%"
    
    # Buscar candles
    try {
        $candles = CoinEx-GetFuturesCandles -market $c.market -period "15min" -limit 50
        
        if ($candles.Count -ge 20) {
            # RSI simples
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
            
            # SMA20
            $sma20 = ($candles | Select-Object -Last 20 | Measure-Object -Property close -Average).Average
            $currentPrice = $candles[-1].close
            $distSma = (($currentPrice - $sma20) / $sma20) * 100
            
            # Suporte/Resistencia
            $support = ($candles | Select-Object -Last 20 | Measure-Object -Property low -Minimum).Minimum
            $resistance = ($candles | Select-Object -Last 20 | Measure-Object -Property high -Maximum).Maximum
            $distSupport = (($currentPrice - $support) / $support) * 100
            $distResistance = (($resistance - $currentPrice) / $currentPrice) * 100
            
            Write-Host "  RSI(14): $([Math]::Round($rsi, 2))"
            Write-Host "  SMA20: `$$([Math]::Round($sma20, 4)) (dist: $([Math]::Round($distSma, 2))%)"
            Write-Host "  Suporte: `$$([Math]::Round($support, 4)) (dist: $([Math]::Round($distSupport, 2))%)"
            Write-Host "  Resistencia: `$$([Math]::Round($resistance, 4)) (dist: $([Math]::Round($distResistance, 2))%)"
            
            # Avaliar setup
            if ($c.change -gt 0) {
                # Momentum positivo
                if ($rsi -lt 40 -and $distSma -lt 0) {
                    Write-Host "  Setup: LONG FORTE (sobrevenda + abaixo SMA)" -ForegroundColor Green
                } elseif ($rsi -lt 50 -and $distSupport -lt 3) {
                    Write-Host "  Setup: LONG (proximo de suporte)" -ForegroundColor Green
                } elseif ($rsi -gt 70) {
                    Write-Host "  Setup: CUIDADO (sobrecompra)" -ForegroundColor Yellow
                } else {
                    Write-Host "  Setup: LONG MODERADO (momentum positivo)" -ForegroundColor Cyan
                }
            } else {
                # Momentum negativo
                if ($rsi -lt 30 -and $distSupport -lt 2) {
                    Write-Host "  Setup: LONG REVERSAL (sobrevenda extrema)" -ForegroundColor Green
                } elseif ($rsi -gt 60) {
                    Write-Host "  Setup: SHORT (sobrecompra em queda)" -ForegroundColor Red
                } else {
                    Write-Host "  Setup: AGUARDAR (sem setup claro)" -ForegroundColor Gray
                }
            }
        }
    } catch {
        Write-Host "  Erro: $_" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "=== RECOMENDACAO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Analise os setups acima e escolha:"
Write-Host "1. LONG FORTE/MODERADO = Momentum positivo com confirmacao tecnica"
Write-Host "2. LONG REVERSAL = Sobrevenda extrema, potencial de recuperacao"
Write-Host "3. Evite: CUIDADO (sobrecompra) e AGUARDAR (sem setup)"
Write-Host ""
Write-Host "Para cobrir `$8 de perdas com 5x leverage:"
Write-Host "- Precisa de ~+0.5% de lucro em posicao de `$100"
Write-Host "- Ou ~+1% de lucro em posicao de `$50"
Write-Host ""
