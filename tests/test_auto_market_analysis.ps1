# tests\test_auto_market_analysis.ps1
# TDD: analise de mercado automatica (nossa "AI Analysis" interna).
#   - Get-BollingerBands / Get-MacdValue (helpers puros)
#   - Get-AutoTimeframeAnalysis (1 timeframe a partir de candles)
#   - Get-AutoMarketAnalysis (multi-timeframe consolidado, candles injetados)
#   - Format-TgAutoAnalysis (mensagem Telegram)
# Runner PowerShell puro (PASS/FAIL). Determinístico, offline.
# 2026-05-29

$ErrorActionPreference = 'Stop'
$agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"
. (Join-Path $agents "lib_auto_market_analysis.ps1")

$script:pass = 0; $script:fail = 0
function Check($name, $cond) {
    if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fail++ }
}

# Gerador de candles em tendencia (Step>0 alta, Step<0 baixa)
function New-TrendCandles {
    param([double]$Start, [double]$Step, [int]$Count, [double]$Range = 2.0)
    $c = @(); $p = $Start
    for ($i = 0; $i -lt $Count; $i++) {
        $open = $p; $close = $p + $Step
        $high = [math]::Max($open, $close) + $Range
        $low  = [math]::Min($open, $close) - $Range
        $c += [PSCustomObject]@{ ts=$i; open=$open; high=$high; low=$low; close=$close; volume=(1000 + $i*10) }
        $p = $close
    }
    return $c
}

# Gerador ondulado (gera swings -> suportes/resistencias)
function New-WavyCandles {
    param([int]$Count = 60, [double]$Base = 100.0, [double]$Amp = 5.0)
    $c = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $mid = $Base + $Amp * [math]::Sin($i / 3.0)
        $open = $mid - 0.5; $close = $mid + 0.5
        $high = $mid + 2; $low = $mid - 2
        $c += [PSCustomObject]@{ ts=$i; open=$open; high=$high; low=$low; close=$close; volume=(1000 + ($i % 5)*200) }
    }
    return $c
}

Write-Host "=== 1. Get-BollingerBands ==="
$closesUp = (New-TrendCandles -Start 100 -Step 0.5 -Count 60 | ForEach-Object { [double]$_.close })
$bb = Get-BollingerBands -Closes $closesUp -Period 20 -StdDevMult 2.0
Check "upper > mid > lower" ($bb.upper -gt $bb.mid -and $bb.mid -gt $bb.lower)
Check "pct_b calculado (0..1+ em alta)" ($bb.pct_b -gt 0.5)
Check "bandwidth >= 0" ($bb.bandwidth -ge 0)

Write-Host ""
Write-Host "=== 2. Get-MacdValue ==="
$macdUp = Get-MacdValue -Closes $closesUp
$closesDown = (New-TrendCandles -Start 130 -Step -0.5 -Count 60 | ForEach-Object { [double]$_.close })
$macdDown = Get-MacdValue -Closes $closesDown
Check "Alta -> histograma positivo" ($macdUp.histogram -gt 0)
Check "Alta -> trend BULLISH" ($macdUp.trend -eq "BULLISH")
Check "Baixa -> histograma negativo" ($macdDown.histogram -lt 0)
Check "Baixa -> trend BEARISH" ($macdDown.trend -eq "BEARISH")

Write-Host ""
Write-Host "=== 3. Get-AutoTimeframeAnalysis ==="
$tfUp = Get-AutoTimeframeAnalysis -Candles (New-TrendCandles -Start 100 -Step 0.5 -Count 60) -Timeframe "1h"
Check "RSI entre 0 e 100" ($tfUp.rsi -ge 0 -and $tfUp.rsi -le 100)
Check "Alta -> bias BULLISH" ($tfUp.bias -eq "BULLISH")
Check "Score entre 0 e 100" ($tfUp.score -ge 0 -and $tfUp.score -le 100)
Check "close preenchido" ($tfUp.close -gt 0)
Check "macd presente" ($null -ne $tfUp.macd)
Check "bollinger presente" ($null -ne $tfUp.bollinger)

$tfDown = Get-AutoTimeframeAnalysis -Candles (New-TrendCandles -Start 130 -Step -0.5 -Count 60) -Timeframe "1h"
Check "Baixa -> bias BEARISH" ($tfDown.bias -eq "BEARISH")

$tfWavy = Get-AutoTimeframeAnalysis -Candles (New-WavyCandles -Count 60) -Timeframe "4h"
Check "Suportes retornados como array" ($tfWavy.support_levels -is [array])
Check "Resistencias retornadas como array" ($tfWavy.resistance_levels -is [array])
Check "Suportes (se houver) abaixo do preco" (($tfWavy.support_levels | Where-Object { $_ -ge $tfWavy.close }).Count -eq 0)
Check "Resistencias (se houver) acima do preco" (($tfWavy.resistance_levels | Where-Object { $_ -le $tfWavy.close }).Count -eq 0)

Write-Host ""
Write-Host "=== 4. Get-AutoMarketAnalysis (multi-timeframe, candles injetados) ==="
$injected = @{
    "1h" = (New-TrendCandles -Start 100 -Step 0.4 -Count 60)
    "4h" = (New-TrendCandles -Start 90  -Step 0.5 -Count 60)
    "1d" = (New-TrendCandles -Start 60  -Step 0.6 -Count 60)
}
$a = Get-AutoMarketAnalysis -Market "INJUSDT" -CandlesByTimeframe $injected
Check "Symbol correto" ($a.symbol -eq "INJUSDT")
Check "generated_at preenchido" (-not [string]::IsNullOrEmpty($a.generated_at))
Check "overall_bias preenchido" (@("BULLISH","BEARISH","NEUTRAL") -contains $a.overall_bias)
Check "Alta consistente -> overall BULLISH" ($a.overall_bias -eq "BULLISH")
Check "Tem ao menos 1 takeaway" ($a.key_takeaways.Count -ge 1)
Check "Tem timeframes analisados" ($a.timeframes.Count -ge 3)
Check "short_term_view preenchido" (-not [string]::IsNullOrEmpty($a.short_term_view))
Check "long_term_view preenchido" (-not [string]::IsNullOrEmpty($a.long_term_view))
Check "recommendation preenchida" (-not [string]::IsNullOrEmpty($a.recommendation))
Check "confidence 0..100" ($a.confidence -ge 0 -and $a.confidence -le 100)

Write-Host ""
Write-Host "=== 5. Get-AutoMarketAnalysis usa CoinEx-GetFuturesCandles quando nao injetado ==="
$script:fetchCalls = 0
function CoinEx-GetFuturesCandles($market, $period, $limit=100) {
    $script:fetchCalls++
    return New-TrendCandles -Start 100 -Step 0.3 -Count 60
}
$a2 = Get-AutoMarketAnalysis -Market "BTCUSDT"
Check "Buscou candles via API (3 timeframes)" ($script:fetchCalls -eq 3)
Check "Analise gerada com fetch real" ($a2.symbol -eq "BTCUSDT" -and $a2.timeframes.Count -eq 3)

Write-Host ""
Write-Host "=== 6. Format-TgAutoAnalysis ==="
$msg = Format-TgAutoAnalysis -Analysis $a
Check "Contem o simbolo" ($msg -match "INJUSDT")
Check "Contem rotulo de analise" ($msg -match "(?i)ANALISE|ANALYSIS")
Check "Contem vies/bias" ($msg -match "(?i)BULLISH|BEARISH|NEUTRAL|ALTA|BAIXA")
Check "Sem tag HTML nao fechada no fim" ($msg -notmatch "<[^>]*$")

Write-Host ""
Write-Host "=== RESULTADO: $script:pass passou, $script:fail falhou ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
