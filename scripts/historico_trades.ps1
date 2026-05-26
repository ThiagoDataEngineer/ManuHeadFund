# historico_trades.ps1 - Analise da jornada de cada trade desde abertura
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path (Join-Path $root "agents") "config.local.ps1")

$trail = Get-Content (Join-Path (Join-Path $root "journal") "trailing_positions.json") -Raw | ConvertFrom-Json
$active = @($trail | Where-Object { $_.active })

Write-Host "`n=== HISTORICO DETALHADO DOS 4 TRADES ===" -ForegroundColor Cyan
Write-Host "Periodo: desde $($active[0].openedAt) (~24h atras)`n"

foreach ($p in $active) {
    $mkt = $p.market
    $entry = [double]$p.entry
    $stop = [double]$p.stopCurrent
    $target = [double]$p.target
    
    # 30 candles 1h
    $kr = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/kline?market=$mkt&period=1hour&limit=30"
    $candles = @()
    foreach ($c in $kr.data) {
        $tsMs = [long]$c.created_at
        $ts = [DateTimeOffset]::FromUnixTimeMilliseconds($tsMs).LocalDateTime
        $candles += [PSCustomObject]@{
            ts = $ts
            high = [double]$c.high
            low = [double]$c.low
            close = [double]$c.close
            open = [double]$c.open
        }
    }
    
    $current = [double]$candles[-1].close
    $highSince = ($candles | Measure-Object -Property high -Maximum).Maximum
    $lowSince = ($candles | Measure-Object -Property low -Minimum).Minimum
    
    $maxGainPct = [math]::Round((($highSince - $entry) / $entry) * 100, 2)
    $maxDrawdownPct = [math]::Round((($lowSince - $entry) / $entry) * 100, 2)
    $currentPct = [math]::Round((($current - $entry) / $entry) * 100, 2)
    $closestToStopPct = [math]::Round((($lowSince - $stop) / $stop) * 100, 2)
    $hitStop = $lowSince -le $stop
    
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "$mkt - LONG" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "  Entry        : `$$entry"
    Write-Host "  Stop atual   : `$$stop"
    Write-Host "  Target       : `$$target"
    Write-Host ""
    Write-Host "  PEAK desde abertura: `$$([math]::Round($highSince, 4)) (+$maxGainPct%)" -ForegroundColor Green
    Write-Host "  LOW  desde abertura: `$$([math]::Round($lowSince, 4)) ($maxDrawdownPct%)" -ForegroundColor Red
    Write-Host "  ATUAL              : `$$current ($currentPct%)" -ForegroundColor Cyan
    Write-Host ""
    
    if ($hitStop) {
        Write-Host "  ALERTA: Low ($lowSince) ATINGIU stop ($stop)!" -ForegroundColor Red
    } else {
        Write-Host "  Distancia minima do stop: $([math]::Round($closestToStopPct, 2))%"
        if ($closestToStopPct -lt 1.5) {
            Write-Host "  >> Esteve PERIGOSAMENTE proximo!" -ForegroundColor Red
        } elseif ($closestToStopPct -lt 3) {
            Write-Host "  >> Foi resiliente (aguentou ate 3% do stop)" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "  EVOLUCAO horaria (selecionada):" -ForegroundColor Gray
    
    $samples = @(0, 5, 10, 15, 20, 25, ($candles.Count - 1)) | Where-Object { $_ -lt $candles.Count -and $_ -ge 0 } | Select-Object -Unique
    foreach ($i in $samples) {
        $c = $candles[$i]
        $pct = [math]::Round((($c.close - $entry) / $entry) * 100, 2)
        $color = if ($pct -gt 1) { "Green" } elseif ($pct -lt -1.5) { "Red" } else { "Gray" }
        Write-Host ("    {0:HH:mm dd/MM} close=`${1,9} ({2,5}%)" -f $c.ts, $c.close, $pct) -ForegroundColor $color
    }
    Write-Host ""
}
