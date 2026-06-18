# backtest_24h_movers.ps1 -- Quais LONGs/SHORTs o ensemble atual teria pego nas ult 24h.
# Avalia a conviccao COMO ESTAVA ~24h atras (trunca candles) -> honesto "pegariamos antes?".
# Read-only. Nao executa trade.

$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root "agents/config.ps1")
$cl = Join-Path $root "agents/config.local.ps1"; if (Test-Path $cl) { . $cl }
. (Join-Path $root "agents/lib_coinex.ps1")
. (Join-Path $root "agents/lib_candle_fetcher.ps1")
. (Join-Path $root "agents/lib_multiframe_analysis.ps1")
. (Join-Path $root "agents/lib_btc_relative_strength.ps1")
. (Join-Path $root "agents/lib_entry_conviction_ensemble.ps1")

$OVERRIDE = 75   # threshold que vence o veto do Tori
$READY    = 55   # threshold "ready" do ensemble

function Trunc($arr, $n) {
    if (-not $arr -or $arr.Count -le $n) { return @() }
    return $arr[0..($arr.Count - 1 - $n)]
}

# Conviccao com candles ja truncados (estado de ~24h atras)
function Get-ConvictionTrunc($c1H, $c4H, $c1D, $btc1H, $dir) {
    if ($c1H.Count -lt 20 -or $c4H.Count -lt 8) { return $null }
    $axes = @{}
    $t1D = Get-TrendDirection -Candles $c1D -Timeframe "1D"
    $t4H = Get-TrendDirection -Candles $c4H -Timeframe "4H"
    $t1H = Get-TrendDirection -Candles $c1H -Timeframe "1H"
    $axes.multitf = Get-MultiTimeframeConviction -Trend1D $t1D -Trend4H $t4H -Trend1H $t1H -Direction $dir
    $alt = @($c1H | ForEach-Object { [double]$_.close }); $btc = @($btc1H | ForEach-Object { [double]$_.close })
    $rs = Get-BtcRelativeStrength -AltCloses $alt -BtcCloses $btc -Beta 1.0
    if ($rs) { $axes.btc_rs = Get-RsConvictionScore -Rs $rs.rs -BtcReturn $rs.btc_return -Direction $dir }
    $axes.volume = Get-VolumeConvictionScore -Volumes @($c1H | ForEach-Object { [double]$_.volume })
    $h4=@($c4H|ForEach-Object{[double]$_.high}); $l4=@($c4H|ForEach-Object{[double]$_.low}); $cl4=@($c4H|ForEach-Object{[double]$_.close}); $v4=@($c4H|ForEach-Object{[double]$_.volume})
    $axes.structure  = Get-StructureFromCandles -Highs $h4 -Lows $l4 -Closes $cl4 -Direction $dir
    $axes.historical = Get-PrePumpFingerprintScore -Highs $h4 -Lows $l4 -Closes $cl4 -Volumes $v4 -Direction $dir
    return (Get-EntryConviction -Axes $axes -Direction $dir -Threshold $READY)
}

Write-Host "Baixando tickers..." -ForegroundColor DarkGray
$r = Invoke-RestMethod -Uri "$COINEX_BASE_URL/v2/futures/ticker" -Method GET
$rows = @()
foreach ($t in $r.data) {
    $open = [double]$t.open; $last = [double]$t.last; $val = [double]$t.value
    if ($open -le 0 -or $val -lt 1000000) { continue }   # liquidez minima $1M 24h
    $rows += [PSCustomObject]@{ market=$t.market; chg=[math]::Round(($last-$open)/$open*100,1); vol_usd=$val }
}
$gainers = @($rows | Sort-Object chg -Descending | Select-Object -First 8)
$losers  = @($rows | Sort-Object chg | Select-Object -First 8)

# BTC candles (truncado p/ btc_rs as-of-24h)
$btcFull = Get-CoinExCandles -Market "BTCUSDT" -Period "1hour" -Limit 140 -IsFutures $true
$btcTrunc = Trunc $btcFull 24

function Eval($list, $dir) {
    Write-Host ""
    Write-Host ("=== {0} (top movers 24h) ===" -f $dir) -ForegroundColor Cyan
    Write-Host ("{0,-14}{1,8}{2,10}{3,10}" -f "Market","24h%","ConvAntes","Pegaria?")
    foreach ($g in $list) {
        $m = $g.market
        $c1Hf = Get-CoinExCandles -Market $m -Period "1hour" -Limit 140 -IsFutures $true
        $c4Hf = Get-CoinExCandles -Market $m -Period "4hour" -Limit 70  -IsFutures $true
        $c1Df = Get-CoinExCandles -Market $m -Period "1day"  -Limit 60  -IsFutures $true
        if (-not $c1Hf -or $c1Hf.Count -lt 50) { continue }
        $c1H = Trunc $c1Hf 24; $c4H = Trunc $c4Hf 6; $c1D = Trunc $c1Df 1
        $conv = Get-ConvictionTrunc $c1H $c4H $c1D $btcTrunc $dir
        if (-not $conv) { Write-Host ("{0,-14}{1,8}    (sem dados)" -f $m,$g.chg); continue }
        $catch = if ($conv.conviction -ge $OVERRIDE) { "SIM (>=75)" } elseif ($conv.conviction -ge $READY) { "talvez" } else { "nao" }
        $col = if ($conv.conviction -ge $OVERRIDE) { "Green" } elseif ($conv.conviction -ge $READY) { "Yellow" } else { "DarkGray" }
        Write-Host ("{0,-14}{1,8}{2,10}{3,10}" -f $m,$g.chg,$conv.conviction,$catch) -ForegroundColor $col
    }
}

Eval $gainers "LONG"
Eval $losers  "SHORT"
Write-Host ""
Write-Host "Threshold override (vence Tori) = $OVERRIDE | ready = $READY" -ForegroundColor DarkGray
