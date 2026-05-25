# find_short_opportunities.ps1 - Busca oportunidades de SHORT com bom Risk/Reward
# Analisa principais moedas e retorna candidatos com R:R >= 1:2

. (Join-Path $PSScriptRoot "..\agents\config.ps1")
. (Join-Path $PSScriptRoot "..\agents\lib_coinex.ps1")

function Get-ShortSetup {
    param(
        [string]$Market,
        [double]$MinRR = 2.0
    )
    
    try {
        # Busca candles 1h (100 periodos = ~4 dias)
        $candles = CoinEx-GetFuturesCandles -market $Market -period "1hour" -limit 100
        if (-not $candles -or $candles.Count -lt 20) { return $null }
        
        $current = $candles[-1].close
        $high24h = ($candles[-24..-1] | Measure-Object -Property high -Maximum).Maximum
        $low24h  = ($candles[-24..-1] | Measure-Object -Property low -Minimum).Minimum
        
        # Calcula SMAs
        $sma5  = ($candles[-5..-1] | Measure-Object -Property close -Average).Average
        $sma10 = ($candles[-10..-1] | Measure-Object -Property close -Average).Average
        $sma20 = ($candles[-20..-1] | Measure-Object -Property close -Average).Average
        
        # Calcula ATR(14)
        $atrSum = 0
        for ($i = $candles.Count - 14; $i -lt $candles.Count; $i++) {
            $tr = [math]::Max($candles[$i].high - $candles[$i].low, 
                  [math]::Max([math]::Abs($candles[$i].high - $candles[$i-1].close),
                             [math]::Abs($candles[$i].low - $candles[$i-1].close)))
            $atrSum += $tr
        }
        $atr = $atrSum / 14
        
        # Sinais tÃ©cnicos para SHORT
        $belowSMA5  = $current -lt $sma5
        $belowSMA10 = $current -lt $sma10
        $downtrend  = $sma5 -lt $sma10
        $fromHigh   = (($high24h - $current) / $high24h) * 100
        
        # Score tÃ©cnico (0-4)
        $techScore = 0
        if ($belowSMA5)  { $techScore++ }
        if ($belowSMA10) { $techScore++ }
        if ($downtrend)  { $techScore++ }
        if ($fromHigh -gt 5) { $techScore++ }
        
        # Setup de SHORT
        $entry = $current
        $stop  = $entry + (2 * $atr)  # Stop 2 ATR acima
        $target1 = $entry - (2 * $atr)  # Target 2 ATR abaixo
        $target2 = $entry - (3 * $atr)  # Target 3 ATR abaixo
        $target3 = $low24h * 0.98       # Target prÃ³ximo da mÃ­nima 24h
        
        # Escolhe melhor target (mais prÃ³ximo mas >= 2 ATR)
        $target = $target1
        if ($target3 -gt $target1 -and $target3 -lt $entry) {
            $target = $target3
        }
        
        # Calcula Risk/Reward
        $risk   = (($stop - $entry) / $entry) * 100
        $reward = (($entry - $target) / $entry) * 100
        $rr     = if ($risk -gt 0) { $reward / $risk } else { 0 }
        
        # Valida setup
        if ($rr -lt $MinRR) { return $null }
        if ($techScore -lt 3) { return $null }
        
        # Busca volume e funding
        $ticker = CoinEx-GetTicker -market $Market
        $volume24h = [double]$ticker.vol_24h
        $funding = CoinEx-GetFundingRate -market $Market
        
        return [PSCustomObject]@{
            market      = $Market
            entry       = [math]::Round($entry, 4)
            stop        = [math]::Round($stop, 4)
            target      = [math]::Round($target, 4)
            risk_pct    = [math]::Round($risk, 2)
            reward_pct  = [math]::Round($reward, 2)
            rr_ratio    = [math]::Round($rr, 2)
            tech_score  = $techScore
            atr         = [math]::Round($atr, 4)
            from_high   = [math]::Round($fromHigh, 2)
            volume_24h  = [math]::Round($volume24h, 0)
            funding_8h  = if ($funding) { [math]::Round($funding * 100, 4) } else { 0 }
            sma5        = [math]::Round($sma5, 4)
            sma10       = [math]::Round($sma10, 4)
        }
    } catch {
        Write-Host "Erro ao analisar $Market : $_" -ForegroundColor Yellow
        return $null
    }
}

# Lista de moedas para analisar (top 30 por volume)
$markets = @(
    "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT",
    "ADAUSDT", "DOGEUSDT", "AVAXUSDT", "DOTUSDT", "MATICUSDT",
    "LINKUSDT", "UNIUSDT", "ATOMUSDT", "LTCUSDT", "ETCUSDT",
    "NEARUSDT", "APTUSDT", "ARBUSDT", "OPUSDT", "SUIUSDT",
    "TONUSDT", "INJUSDT", "TAOUSDT", "FILUSDT", "ICPUSDT",
    "HYPEUSDT", "PEPEUSDT", "SHIBUSDT", "WIFUSDT", "BONKUSDT"
)

Write-Host "`n=== BUSCANDO OPORTUNIDADES DE SHORT ===" -ForegroundColor Cyan
Write-Host "Criterios: R:R >= 1:2, Score Tecnico >= 3/4`n" -ForegroundColor Gray

$opportunities = @()
$count = 0

foreach ($market in $markets) {
    $count++
    Write-Host "[$count/$($markets.Count)] Analisando $market..." -NoNewline
    
    $setup = Get-ShortSetup -Market $market -MinRR 2.0
    
    if ($setup) {
        Write-Host " ENCONTRADO!" -ForegroundColor Green
        $opportunities += $setup
    } else {
        Write-Host " -" -ForegroundColor DarkGray
    }
    
    Start-Sleep -Milliseconds 200  # Rate limit
}

Write-Host "`n=== RESULTADOS ===" -ForegroundColor Cyan
Write-Host "Oportunidades encontradas: $($opportunities.Count)`n" -ForegroundColor Yellow

if ($opportunities.Count -eq 0) {
    Write-Host "Nenhuma oportunidade de SHORT com bom R:R encontrada." -ForegroundColor Red
    Write-Host "Mercado pode estar em tendencia de alta ou sem setups claros.`n" -ForegroundColor Gray
    exit 0
}

# Ordena por melhor R:R
$opportunities = $opportunities | Sort-Object -Property rr_ratio -Descending

Write-Host "TOP 5 MELHORES SETUPS:`n" -ForegroundColor Green

$top5 = $opportunities | Select-Object -First 5

foreach ($opp in $top5) {
    Write-Host "=== $($opp.market) ===" -ForegroundColor Cyan
    Write-Host "Entry:       `$$($opp.entry)"
    Write-Host "Stop Loss:   `$$($opp.stop) (+$($opp.risk_pct)%)" -ForegroundColor Red
    Write-Host "Target:      `$$($opp.target) (-$($opp.reward_pct)%)" -ForegroundColor Green
    Write-Host "Risk/Reward: 1:$($opp.rr_ratio)" -ForegroundColor Yellow
    Write-Host "Score:       $($opp.tech_score)/4"
    Write-Host "ATR:         `$$($opp.atr)"
    Write-Host "From High:   -$($opp.from_high)%"
    Write-Host "Volume 24h:  `$$($opp.volume_24h)"
    Write-Host "Funding 8h:  $($opp.funding_8h)%"
    Write-Host ""
}

# Salva resultado completo
$reportPath = (Join-Path $PSScriptRoot (Join-Path ".." "SHORT_OPPORTUNITIES_$(Get-Date -Format 'yyyy_MM_dd_HHmm').md"))
$report = @"
# SHORT OPPORTUNITIES - $(Get-Date -Format 'yyyy-MM-dd HH:mm')

## CRITERIOS
- Risk/Reward minimo: 1:2
- Score tecnico minimo: 3/4
- Moedas analisadas: $($markets.Count)
- Oportunidades encontradas: $($opportunities.Count)

## TOP SETUPS

"@

foreach ($opp in $opportunities) {
    $report += @"

### $($opp.market)
- **Entry**: `$$($opp.entry)
- **Stop Loss**: `$$($opp.stop) (+$($opp.risk_pct)%)
- **Target**: `$$($opp.target) (-$($opp.reward_pct)%)
- **Risk/Reward**: 1:$($opp.rr_ratio)
- **Score Tecnico**: $($opp.tech_score)/4
- **ATR**: `$$($opp.atr)
- **Distancia da Maxima 24h**: -$($opp.from_high)%
- **Volume 24h**: `$$($opp.volume_24h)
- **Funding Rate 8h**: $($opp.funding_8h)%
- **SMA5**: `$$($opp.sma5)
- **SMA10**: `$$($opp.sma10)

"@
}

$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Relatorio salvo em: $reportPath`n" -ForegroundColor Green
