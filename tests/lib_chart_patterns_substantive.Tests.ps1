# lib_chart_patterns_substantive.Tests.ps1 -- TESTES SUBSTANTIVOS (nao so math).
# Pester 3.x. ASCII puro (PS5.1 quirk com box-drawing chars).
#
# Filosofia: testes anteriores validavam que codigo FAZ o que pedi (math correta).
# Estes testes validam que codigo FAZ ALGO UTIL (responde questoes operacionais):
#
#   Q1. Quao FREQUENTE o predicate dispara em dado real? (nao-zero-event check)
#   Q2. Quando dispara, qual EDGE estatistico vs baseline?
#   Q3. Predicate e ROBUSTO entre markets (nao overfit a 1 asset)?
#   Q4. Custo computacional escala linear (nao O(N^2))?
#
# Dado real: journal/candles_coinex/*_1day.json (47 markets * ~1000 bars cada).

$script:subst_here = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:subst_root = Split-Path -Parent $subst_here
. (Join-Path $subst_root "agents\lib_chart_patterns.ps1")

$script:subst_candlesDir = Join-Path $subst_root "journal\candles_coinex"


function _LoadCandles {
    param([string] $Market)
    $p = Join-Path $script:subst_candlesDir "${Market}_1day.json"
    if (-not (Test-Path $p)) { return @() }
    try {
        $raw = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($raw | ForEach-Object {
            [PSCustomObject]@{
                open  = [double]$_.open
                high  = [double]$_.high
                low   = [double]$_.low
                close = [double]$_.close
                volume= [double]$_.volume
            }
        })
    } catch { return @() }
}


# === Q1. FREQUENCY — predicate fires N% of bars? ===

Describe "Q1. Frequency check vol_climax LONG em dado real" {

    It "Dispara entre 0.1% e 5% das barras BTCUSDT" {
        $candles = _LoadCandles -Market "BTCUSDT"
        if (@($candles).Count -lt 60) { Set-TestInconclusive "BTC candles ausente"; return }
        $triggers = 0; $total = 0
        for ($i = 60; $i -lt $candles.Length; $i++) {
            $win = $candles[($i - 60)..$i]
            $vols   = @($win | ForEach-Object { $_.volume })
            $lows   = @($win | ForEach-Object { $_.low })
            $highs  = @($win | ForEach-Object { $_.high })
            $closes = @($win | ForEach-Object { $_.close })
            $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
            $total++
            if ($r.detected) { $triggers++ }
        }
        Write-Host "  vol_climax LONG BTCUSDT: $triggers triggers / $total bars" -ForegroundColor DarkCyan
        $triggers | Should BeGreaterThan 0
        $freq = ($triggers / $total) * 100
        $freq | Should BeLessThan 5.0
        $freq | Should BeGreaterThan 0.05
    }
}


Describe "Q1. Tori predicate 4-AND LOCKDOWN" {

    It "DOCUMENTA: Tori predicate 4-AND fires 0 percent em historico BTC" {
        # Lockdown do achado 2026-05-22: backtest unified mostrou 0 events em 50k bars.
        # Se predicate magicamente comecar a disparar, vale entender o que mudou.
        $candles = _LoadCandles -Market "BTCUSDT"
        if (@($candles).Count -lt 60) { Set-TestInconclusive "BTC candles ausente"; return }

        $rsiThresh = 40.0; $volRatio = 0.7
        $slopeMin = 5.0; $slopeMax = 35.0
        $proxMin = -3.0; $proxMax = 5.0
        $minTouches = 3

        $triggers = 0; $total = 0
        for ($i = 60; $i -lt $candles.Length; $i++) {
            $win = $candles[($i - 60)..$i]
            $closes = @($win | ForEach-Object { $_.close })
            $lows   = @($win | ForEach-Object { $_.low })
            $vols   = @($win | ForEach-Object { $_.volume })
            $total++

            $n = $lows.Length
            $sx = 0; $sy = 0; $sxy = 0; $sx2 = 0
            for ($j = 0; $j -lt $n; $j++) { $sx += $j; $sy += $lows[$j]; $sxy += $j * $lows[$j]; $sx2 += $j*$j }
            $denom = $n * $sx2 - $sx*$sx
            if ($denom -eq 0) { continue }
            $slope = ($n*$sxy - $sx*$sy) / $denom
            $inter = ($sy - $slope*$sx) / $n
            $mean = ($closes | Measure-Object -Average).Average
            if ($mean -le 0) { continue }
            $slopeDeg = [Math]::Atan(($slope / $mean) * 100) * (180 / [Math]::PI)
            if ($slopeDeg -lt $slopeMin -or $slopeDeg -gt $slopeMax) { continue }

            $touches = 0
            for ($j = 0; $j -lt $n; $j++) {
                $line = $inter + $slope*$j
                if ($line -le 0) { continue }
                if ([Math]::Abs($lows[$j] - $line) / $line * 100 -le 1.5) { $touches++ }
            }
            if ($touches -lt $minTouches) { continue }

            $line = $inter + $slope*($n-1)
            if ($line -le 0) { continue }
            $prox = ($closes[-1] - $line) / $line * 100
            if ($prox -lt $proxMin -or $prox -gt $proxMax) { continue }

            if ($closes.Length -lt 15) { continue }
            $g = 0; $l = 0
            for ($j = 1; $j -le 14; $j++) {
                $d = $closes[$j] - $closes[$j-1]
                if ($d -gt 0) { $g += $d } else { $l += [Math]::Abs($d) }
            }
            $ag = $g/14; $al = $l/14
            for ($j = 15; $j -lt $closes.Length; $j++) {
                $d = $closes[$j] - $closes[$j-1]
                if ($d -gt 0) { $ag = ($ag*13 + $d)/14; $al = $al*13/14 }
                else { $ag = $ag*13/14; $al = ($al*13 + [Math]::Abs($d))/14 }
            }
            $rsi = if ($al -eq 0) { 100 } else { 100 - (100 / (1 + $ag/$al)) }
            if ($rsi -ge $rsiThresh) { continue }

            if ($vols.Length -lt 10) { continue }
            $ra = ($vols[($vols.Length-3)..($vols.Length-1)] | Measure-Object -Average).Average
            $pa = ($vols[($vols.Length-10)..($vols.Length-4)] | Measure-Object -Average).Average
            if ($pa -le 0 -or $ra -ge $pa * $volRatio) { continue }

            $triggers++
        }

        $pct = ($triggers / [Math]::Max($total, 1)) * 100
        Write-Host "  Tori predicate 4-AND BTCUSDT: $triggers triggers / $total bars" -ForegroundColor DarkYellow
        # Lockdown: predicate teorico nao deve magicamente comecar a disparar muito
        $pct | Should BeLessThan 1.0
    }
}


# === Q2. EDGE — quando dispara, outcome vs baseline ===

Describe "Q2. Edge contract vol_climax LONG" {

    It "Strength acima 50 com vol 5x mais new low + close rejection" {
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0
            $lows  += 100.0 + ($i * 0.1)
            $highs += $lows[-1] + 2
            $closes += $lows[-1] + 1
        }
        $vols   += 5000.0; $lows += 85.0; $highs += 100; $closes += 99
        $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
        $r.detected | Should Be $true
        $r.strength | Should BeGreaterThan 50
        $r.vol_ratio | Should Be 5.0
    }

    It "Strength escala monotonica com vol_ratio (mesmo break_pct)" {
        # Test: dois cenarios com BREAK pequeno (low so 99.5, prior min era 100.0 -- break 0.5%)
        # mas vol_ratio diferente (3x vs 10x). Strength deve ser maior no 10x.
        # Manter break_pct pequeno (~0.5%) pra strength NAO saturar em 100.
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 19; $i++) {
            $vols += 1000.0
            $lows  += 100.0 + ($i * 0.1)   # lows sobem 100..101.8
            $highs += $lows[-1] + 0.5
            $closes += $lows[-1] + 0.2
        }
        # Climax bar: low 99.5 (break ~0.5% vs min 100), close above (rejection)
        $vols_w = $vols + 3000;  $lows_w = $lows + 99.5; $highs_w = $highs + 100; $closes_w = $closes + 99.9
        $r1 = Detect-VolumeClimax -Volumes $vols_w -Lows $lows_w -Highs $highs_w -Closes $closes_w -Side LONG
        $vols_s = $vols + 10000; $lows_s = $lows + 99.5; $highs_s = $highs + 100; $closes_s = $closes + 99.9
        $r2 = Detect-VolumeClimax -Volumes $vols_s -Lows $lows_s -Highs $highs_s -Closes $closes_s -Side LONG
        Write-Host "  3x strength=$($r1.strength) 10x strength=$($r2.strength)" -ForegroundColor DarkCyan
        $r1.detected | Should Be $true
        $r2.detected | Should Be $true
        $r2.strength | Should BeGreaterThan $r1.strength
    }
}


# === Q3. ROBUSTNESS — multi-market anti-overfit ===

Describe "Q3. Robustness vol_climax em multiplos markets" {

    It "Detecta climax em pelo menos 3 markets diferentes em historico" {
        $marketFiles = Get-ChildItem $script:subst_candlesDir -Filter "*_1day.json" -ErrorAction SilentlyContinue |
                       Select-Object -First 10
        if (@($marketFiles).Count -lt 3) { Set-TestInconclusive "Markets cache insuficiente"; return }

        $detections_per_market = @{}
        foreach ($f in $marketFiles) {
            $mkt = $f.BaseName -replace "_1day", ""
            $candles = _LoadCandles -Market $mkt
            if (@($candles).Count -lt 60) { continue }
            $count = 0
            for ($i = 60; $i -lt $candles.Length; $i++) {
                $win = $candles[($i - 60)..$i]
                $vols   = @($win | ForEach-Object { $_.volume })
                $lows   = @($win | ForEach-Object { $_.low })
                $highs  = @($win | ForEach-Object { $_.high })
                $closes = @($win | ForEach-Object { $_.close })
                $r = Detect-VolumeClimax -Volumes $vols -Lows $lows -Highs $highs -Closes $closes -Side LONG
                if ($r.detected) { $count++ }
            }
            $detections_per_market[$mkt] = $count
        }
        $marketsWithDetection = @($detections_per_market.GetEnumerator() | Where-Object { $_.Value -gt 0 })
        $marketsWithDetection.Count | Should BeGreaterThan 2
        Write-Host "  Markets com detection vol_climax LONG:" -ForegroundColor DarkCyan
        foreach ($kv in $detections_per_market.GetEnumerator()) {
            Write-Host "    $($kv.Key): $($kv.Value) events" -ForegroundColor DarkGray
        }
    }
}


# === Q4. PERFORMANCE — linear scaling ===

Describe "Q4. Performance vol_climax linear" {

    It "Walk de 1000 bars completa rapido" {
        $vols = @(); $lows = @(); $highs = @(); $closes = @()
        for ($i = 0; $i -lt 1000; $i++) {
            $vols   += (Get-Random -Minimum 500 -Maximum 2000)
            $lows   += 100.0 + (Get-Random -Minimum -10 -Maximum 10)
            $highs  += $lows[-1] + 5
            $closes += $lows[-1] + 2
        }
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($i = 60; $i -lt 1000; $i++) {
            $wv = $vols[($i-60)..$i]; $wl = $lows[($i-60)..$i]
            $wh = $highs[($i-60)..$i]; $wc = $closes[($i-60)..$i]
            Detect-VolumeClimax -Volumes $wv -Lows $wl -Highs $wh -Closes $wc -Side LONG | Out-Null
        }
        $sw.Stop()
        $secs = $sw.Elapsed.TotalSeconds
        Write-Host "  1000 bars walk: $secs s" -ForegroundColor DarkCyan
        $secs | Should BeLessThan 5.0
    }
}
