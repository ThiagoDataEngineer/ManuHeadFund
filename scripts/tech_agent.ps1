
# TechAgent v3.0
# Referencias: Murphy, Bulkowski, Nison, Connors, Elder (Triple Screen), Carter, Crabel, Aronson
# v3.0 add: Stochastic(Lane), OBV(Granville), Ichimoku(Hosoda), SuperTrend, Keltner+BollingerSqueeze(Carter),
#           ParabolicSAR(Wilder), Power-of-3(ICT), CycleContext(Rekt Capital), KellyCriterion,
#           DarkCloudCover, PiercingLine, Dragonfly/GravestoneDoji, Marubozu, ElderScreen2+Stochastic
# Fonte: CoinEx API v2 (publico, sem autenticacao)

param(
    [string]$Market      = "TONUSDT",
    [int]$RefreshSecs    = 300,
    [switch]$Once,
    [switch]$Quiet          # suprime output detalhado, retorna apenas objeto resultado
)


# ── API ──────────────────────────────────────────────────────────────────────

function Get-Candles($market, $period, $limit) {
    # 2026-05-18 fix: tenta futures primeiro, fallback spot para pares spot-only
    # (como TRACUSDT, KAIAUSDT, micro-caps gems). Antes sempre futures = N/A em spot.
    $urls = @(
        "https://api.coinex.com/v2/futures/kline?market=$market&period=$period&limit=$limit",
        "https://api.coinex.com/v2/spot/kline?market=$market&period=$period&limit=$limit"
    )
    foreach ($u in $urls) {
        try {
            $r = Invoke-RestMethod -Uri $u -Method GET -TimeoutSec 10 -ErrorAction Stop
            if ($r.code -eq 0 -and $r.data -and @($r.data).Count -gt 0) {
                return $r.data | ForEach-Object {
                    [PSCustomObject]@{
                        ts=($_.created_at); open=[double]$_.open; high=[double]$_.high
                        low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume
                    }
                }
            }
        } catch {}
    }
    return @()
}

# ── Indicadores Base ─────────────────────────────────────────────────────────

function Calc-EMA($closes, $period) {
    $k = 2.0 / ($period + 1); $ema = $closes[0]
    foreach ($c in $closes[1..($closes.Count-1)]) { $ema = $c * $k + $ema * (1-$k) }
    return $ema
}

function Calc-RSI($closes, $period = 14) {
    $g = 0.0; $l = 0.0
    for ($i = 1; $i -le $period; $i++) {
        $d = $closes[$i] - $closes[$i-1]
        if ($d -gt 0) { $g += $d } else { $l += [math]::Abs($d) }
    }
    $ag = $g/$period; $al = $l/$period
    for ($i = $period+1; $i -lt $closes.Count; $i++) {
        $d = $closes[$i] - $closes[$i-1]
        if ($d -gt 0) { $ag=($ag*($period-1)+$d)/$period; $al=$al*($period-1)/$period }
        else           { $ag=$ag*($period-1)/$period; $al=($al*($period-1)+[math]::Abs($d))/$period }
    }
    if ($al -eq 0) { return 100.0 }
    return 100 - (100/(1+$ag/$al))
}

# RSI 2 periodos (Larry Connors) — extremos de oversold/overbought de curto prazo
function Calc-RSI2($closes) { return Calc-RSI $closes 2 }

function Calc-ATR($candles, $period = 14) {
    $tr = @()
    for ($i = 1; $i -lt $candles.Count; $i++) {
        $c=$candles[$i]; $p=$candles[$i-1]
        $tr += [math]::Max($c.high-$c.low, [math]::Max([math]::Abs($c.high-$p.close), [math]::Abs($c.low-$p.close)))
    }
    return ($tr | Select-Object -Last $period | Measure-Object -Average).Average
}

function Calc-ADX($candles, $period = 14) {
    $tr=@(); $pdm=@(); $ndm=@()
    for ($i=1; $i -lt $candles.Count; $i++) {
        $c=$candles[$i]; $p=$candles[$i-1]
        $t1=$c.high-$c.low; $t2=[math]::Abs($c.high-$p.close); $t3=[math]::Abs($c.low-$p.close)
        $tr  += [math]::Max($t1,[math]::Max($t2,$t3))
        $up=$c.high-$p.high; $dn=$p.low-$c.low
        $pdm += if ($up-gt$dn-and$up-gt0){$up}else{0}
        $ndm += if ($dn-gt$up-and$dn-gt0){$dn}else{0}
    }
    if ($tr.Count -lt $period) { return [PSCustomObject]@{adx=25.0;pdi=0;ndi=0} }
    $atr=($tr|Select-Object -Last $period|Measure-Object -Sum).Sum/$period
    $ap =($pdm|Select-Object -Last $period|Measure-Object -Sum).Sum/$period
    $an =($ndm|Select-Object -Last $period|Measure-Object -Sum).Sum/$period
    if ($atr -eq 0) { return [PSCustomObject]@{adx=0;pdi=0;ndi=0} }
    $pdi=100*$ap/$atr; $ndi=100*$an/$atr
    $dx=if(($pdi+$ndi)-eq0){0}else{100*[math]::Abs($pdi-$ndi)/($pdi+$ndi)}
    return [PSCustomObject]@{ adx=[math]::Round($dx,1); pdi=[math]::Round($pdi,1); ndi=[math]::Round($ndi,1) }
}

function Calc-BollingerBands($closes, $period = 20) {
    $s=$closes|Select-Object -Last $period
    $avg=($s|Measure-Object -Average).Average
    $sd=[math]::Sqrt((($s|ForEach-Object{($_-$avg)*($_-$avg)}|Measure-Object -Sum).Sum)/$period)
    return [PSCustomObject]@{ mid=[math]::Round($avg,4); upper=[math]::Round($avg+2*$sd,4); lower=[math]::Round($avg-2*$sd,4); sd=[math]::Round($sd,4) }
}

function Calc-MACD($closes) {
    $e12=Calc-EMA $closes 12; $e26=Calc-EMA $closes 26; $macd=$e12-$e26
    return [PSCustomObject]@{ macd=[math]::Round($macd,6); ema12=[math]::Round($e12,4); ema26=[math]::Round($e26,4) }
}

# Stochastic Oscillator (George Lane) — Slow (14,3,3)
# Ref: INDICATORS_REFERENCE.md — %K>%D em zona 20 = compra; %K<%D em zona 80 = venda
function Calc-Stochastic($candles, $kPeriod=14, $dPeriod=3) {
    $n=$candles.Count; if ($n-lt$kPeriod){return [PSCustomObject]@{k=50.0;d=50.0;signal="NONE"}}
    $kValues=@()
    for ($i=$kPeriod-1;$i-lt$n;$i++) {
        $slice=$candles[($i-$kPeriod+1)..$i]
        $hi=[double]($slice|Measure-Object -Property high -Maximum).Maximum
        $lo=[double]($slice|Measure-Object -Property low  -Minimum).Minimum
        $kValues+=if($hi-eq$lo){50.0}else{100*($candles[$i].close-$lo)/($hi-$lo)}
    }
    $kSmooth=@()
    for ($i=$dPeriod-1;$i-lt$kValues.Count;$i++){$kSmooth+=($kValues[($i-$dPeriod+1)..$i]|Measure-Object -Average).Average}
    $k=[math]::Round($kSmooth[-1],1)
    $d=if($kSmooth.Count-ge$dPeriod){[math]::Round(($kSmooth|Select-Object -Last $dPeriod|Measure-Object -Average).Average,1)}else{$k}
    $signal=if($k-lt20-and$k-gt$d){"OVERSOLD-CROSS-UP(compra)"}elseif($k-gt80-and$k-lt$d){"OVERBOUGHT-CROSS-DOWN(venda)"}elseif($k-lt20){"OVERSOLD"}elseif($k-gt80){"OVERBOUGHT"}else{"NEUTRO"}
    return [PSCustomObject]@{k=$k;d=$d;signal=$signal}
}

# OBV (On Balance Volume — Joe Granville)
# Ref: INDICATORS_REFERENCE.md — OBV sobe + preco sobe = confirmacao; divergencia = alerta
function Calc-OBV($candles) {
    $obv=0.0; $obvValues=@()
    for ($i=1;$i-lt$candles.Count;$i++) {
        if ($candles[$i].close-gt$candles[$i-1].close){$obv+=$candles[$i].volume}
        elseif($candles[$i].close-lt$candles[$i-1].close){$obv-=$candles[$i].volume}
        $obvValues+=$obv
    }
    if ($obvValues.Count-lt5){return [PSCustomObject]@{obv=0;trend="NONE"}}
    $obvNow=$obvValues[-1]; $obvPrev=($obvValues|Select-Object -Last 10|Select-Object -First 5|Measure-Object -Average).Average
    $pNow=$candles[-1].close; $pPrev=($candles|Select-Object -Last 10|Select-Object -First 5|ForEach-Object{$_.close}|Measure-Object -Average).Average
    $trend=if($obvNow-gt$obvPrev-and$pNow-gt$pPrev){"CONFIRMANDO-ALTA"}elseif($obvNow-lt$obvPrev-and$pNow-lt$pPrev){"CONFIRMANDO-BAIXA"}elseif($obvNow-gt$obvPrev-and$pNow-le$pPrev){"DIV-BULLISH(OBV-sobe,preco-lateral)"}elseif($obvNow-lt$obvPrev-and$pNow-ge$pPrev){"DIV-BEARISH(OBV-cai,preco-sobe)"}else{"NEUTRO"}
    return [PSCustomObject]@{obv=[math]::Round($obvNow,0);trend=$trend}
}

# Ichimoku Cloud (Hosoda) — filtro de tendencia multi-componente
# Ref: INDICATORS_REFERENCE.md — preco acima da nuvem = bullish; abaixo = bearish
function Calc-Ichimoku($candles) {
    $n=$candles.Count; if ($n-lt52){return [PSCustomObject]@{bias="INDEFINIDO";tenkan=0;kijun=0;spanA=0;spanB=0;cloud="NONE"}}
    function Mid($c,$p){$hi=[double]($c|Select-Object -Last $p|Measure-Object -Property high -Maximum).Maximum;$lo=[double]($c|Select-Object -Last $p|Measure-Object -Property low -Minimum).Minimum;return($hi+$lo)/2}
    $tenkan=Mid $candles 9
    $kijun =Mid $candles 26
    $spanA =($tenkan+$kijun)/2
    $spanB =Mid $candles 52
    $last  =$candles[-1].close
    $cloudTop=[math]::Max($spanA,$spanB)
    $cloudBot=[math]::Min($spanA,$spanB)
    $cloud=if($spanA-gt$spanB){"VERDE(suporte-fraco)"}else{"VERMELHA(suporte-forte)"}
    $bias=if($last-gt$cloudTop){"ACIMA-NUVEM(bullish)"}elseif($last-lt$cloudBot){"ABAIXO-NUVEM(bearish)"}else{"DENTRO-NUVEM(incerto)"}
    $tk=if($tenkan-gt$kijun){"TK-BULL"}else{"TK-BEAR"}
    return [PSCustomObject]@{bias=$bias;tenkan=[math]::Round($tenkan,4);kijun=[math]::Round($kijun,4);spanA=[math]::Round($spanA,4);spanB=[math]::Round($spanB,4);cloud=$cloud;tk=$tk}
}

# SuperTrend (ATR-based trend filter)
# Ref: INDICATORS_REFERENCE.md — comprar quando SuperTrend bullish; vender quando bearish
function Calc-SuperTrend($candles, $multiplier=3, $period=10) {
    $n=$candles.Count; if ($n-lt$period+1){return [PSCustomObject]@{value=0;trend="NONE"}}
    $atr=Calc-ATR-Wilder ($candles|Select-Object -Last ($period*3)) $period
    $last=$candles[-1]; $hl2=($last.high+$last.low)/2
    $upperBand=[math]::Round($hl2+$multiplier*$atr,4)
    $lowerBand=[math]::Round($hl2-$multiplier*$atr,4)
    $trend=if($last.close-gt$hl2){"BULLISH(preco>mid)"}else{"BEARISH(preco<mid)"}
    return [PSCustomObject]@{value=$hl2;upperBand=$upperBand;lowerBand=$lowerBand;trend=$trend;atr=[math]::Round($atr,5)}
}

# Keltner Channel (EMA20 +/- 2xATR)
# Ref: INDICATORS_REFERENCE.md — Bollinger dentro do Keltner = Squeeze de John Carter
function Calc-Keltner($closes, $candles, $period=20) {
    $ema=Calc-EMA $closes $period
    $atr=Calc-ATR-Wilder ($candles|Select-Object -Last ($period*2)) $period
    return [PSCustomObject]@{mid=[math]::Round($ema,4);upper=[math]::Round($ema+2*$atr,4);lower=[math]::Round($ema-2*$atr,4)}
}

# Bollinger Squeeze (John Carter) — Bollinger dentro do Keltner = compressao extrema
# Ref: INDICATORS_REFERENCE.md — squeeze ativo = breakout iminente
function Detect-BollingerSqueeze($bb, $keltner) {
    $squeeze=($bb.upper-lt$keltner.upper-and$bb.lower-gt$keltner.lower)
    if ($squeeze) { return "SQUEEZE-ATIVO(breakout-iminente)" }
    return "SQUEEZE-OFF"
}

# OBV-based Divergence simples (Granville)
# Parabolic SAR aproximado (Wilder) — trailing stop reference
function Calc-ParabolicSAR($candles, $step=0.02, $maxAF=0.2) {
    $n=$candles.Count; if ($n-lt5){return [PSCustomObject]@{sar=0;trend="NONE"}}
    $bull=$candles[-1].close-gt$candles[-2].close
    $ep=if($bull){($candles|Select-Object -Last 10|Measure-Object -Property high -Maximum).Maximum}else{($candles|Select-Object -Last 10|Measure-Object -Property low -Minimum).Minimum}
    $af=[math]::Min($step*5,$maxAF)
    $lastClose=$candles[-1].close
    $sar=if($bull){$ep-$af*($ep-$lastClose)}else{$ep+$af*($lastClose-$ep)}
    $trend=if($lastClose-gt$sar){"BULL(preco>SAR)"}else{"BEAR(preco<SAR)"}
    return [PSCustomObject]@{sar=[math]::Round($sar,4);trend=$trend}
}

# Power of 3 — ICT/SMC: detecta fase atual da sessao (acumulacao/manipulacao/distribuicao)
# Ref: WYCKOFF_SMC.md — Asia range, London manipulation, NY real move
function Get-PowerOf3() {
    $utcH=[DateTime]::UtcNow.Hour; $utcM=[DateTime]::UtcNow.Minute
    $utcDec=$utcH+$utcM/60.0
    if ($utcDec-ge0-and$utcDec-lt4) {return "PO3-FASE1-ASIA(definindo-range)"}
    if ($utcDec-ge7-and$utcDec-lt10){return "PO3-FASE2-LONDON(manipulacao-fakeout-esperado)"}
    if ($utcDec-ge12-and$utcDec-lt16){return "PO3-FASE3-NY(movimento-real)"}
    return "ENTRE-SESSOES"
}

# Contexto de Ciclo (pos-halving 2024 — Rekt Capital)
# Ref: MARKET_CYCLES.md — halving Apr2024, padrao historico: bull 6-18 meses depois
function Get-CycleContext() {
    $halvingDate=[DateTime]::new(2024,4,19)
    $monthsPostHalving=[math]::Round(([DateTime]::UtcNow-$halvingDate).TotalDays/30.4,1)
    $phase=if($monthsPostHalving-lt6){"CONSOLIDACAO-POS-HALVING(0-6m)"}elseif($monthsPostHalving-lt18){"BULL-EXPLOSIVO(6-18m)-HISTORICO-FAVORAVEL"}elseif($monthsPostHalving-lt24){"DISTRIBUICAO-POSSIVEL(18-24m)"}else{"BEAR-MARKET-POSSIVEL(>24m)"}
    $currentMonth=[DateTime]::UtcNow.Month
    $seasonal=switch($currentMonth){1{"JANEIRO:+30%-historico(otimismo)"};2{"FEVEREIRO:variavel"};3{"MARCO:variavel"};4{"ABRIL:variavel"};5{"MAIO:fraco-historicamente"};6{"JUNHO:-10%-historico"};7{"JULHO:recuperacao-frequente"};8{"AGOSTO:-3%-historico"};9{"SETEMBRO:-8%-Rektember"};10{"OUTUBRO:+22%-Uptober"};11{"NOVEMBRO:+46%-historico"};12{"DEZEMBRO:realizacao-lucros"};default{"?"}}
    return [PSCustomObject]@{monthsPostHalving=$monthsPostHalving;phase=$phase;seasonal=$seasonal}
}

# Kelly Criterion — sizing otimo
# Ref: RISK_MANAGEMENT.md — f*=(bp-q)/b; usar Quarter Kelly na pratica
function Calc-KellySize($winRate, $rr, $capital) {
    $p=$winRate; $q=1-$p; $b=$rr
    $fullKelly=if($b-gt0){[math]::Max(0,($b*$p-$q)/$b)}else{0}
    $quarterKelly=[math]::Round($fullKelly*0.25*100,2)
    $maxRisk1pct=[math]::Round($capital*0.01,2)
    return [PSCustomObject]@{fullKellyPct=[math]::Round($fullKelly*100,2);quarterKellyPct=$quarterKelly;rule1pctUSD=$maxRisk1pct}
}

# VWAP intraday — calcula a partir dos candles do dia corrente
function Calc-VWAP($candles) {
    $tpv=0.0; $vol=0.0
    foreach ($c in $candles) {
        $tp = ($c.high + $c.low + $c.close) / 3
        $tpv += $tp * $c.volume; $vol += $c.volume
    }
    if ($vol -eq 0) { return $null }
    $vwap = $tpv / $vol
    # Bandas de desvio padrao (VWAP +/- 1SD, 2SD)
    $variance = 0.0
    foreach ($c in $candles) {
        $tp = ($c.high + $c.low + $c.close) / 3
        $variance += $c.volume * [math]::Pow($tp - $vwap, 2)
    }
    $sd = [math]::Sqrt($variance / $vol)
    return [PSCustomObject]@{
        vwap  = [math]::Round($vwap, 4)
        upper1= [math]::Round($vwap + 1*$sd, 4)
        upper2= [math]::Round($vwap + 2*$sd, 4)
        lower1= [math]::Round($vwap - 1*$sd, 4)
        lower2= [math]::Round($vwap - 2*$sd, 4)
    }
}

# Fibonacci retracement e extensao
function Calc-Fibonacci($candles, $lookback = 20) {
    $s=$candles|Select-Object -Last $lookback
    $h=($s|Measure-Object -Property high -Maximum).Maximum
    $l=($s|Measure-Object -Property low  -Minimum).Minimum
    $r=$h-$l
    return [PSCustomObject]@{
        high=$h; low=$l; range=$r
        f236=[math]::Round($h-$r*0.236,4)
        f382=[math]::Round($h-$r*0.382,4)
        f500=[math]::Round($h-$r*0.500,4)
        f618=[math]::Round($h-$r*0.618,4)
        f786=[math]::Round($h-$r*0.786,4)
        # extensoes (alvos apos rompimento)
        ext127=[math]::Round($l-$r*0.272,4)
        ext161=[math]::Round($l-$r*0.618,4)
    }
}

# Volume Profile simplificado — POC (Point of Control)
function Calc-VolumeProfile($candles, $buckets = 20) {
    $h=($candles|Measure-Object -Property high -Maximum).Maximum
    $l=($candles|Measure-Object -Property low  -Minimum).Minimum
    $step=($h-$l)/$buckets
    if ($step -eq 0) { return [PSCustomObject]@{poc=$h;vah=$h;val=$l} }
    $volMap = @{}
    foreach ($c in $candles) {
        $bucket = [math]::Floor(($c.close - $l) / $step)
        if ($bucket -lt 0) { $bucket=0 } elseif ($bucket -ge $buckets) { $bucket=$buckets-1 }
        if (-not $volMap.ContainsKey($bucket)) { $volMap[$bucket]=0.0 }
        $volMap[$bucket] += $c.volume
    }
    $totalVol = ($volMap.Values|Measure-Object -Sum).Sum
    $pocBucket = ($volMap.GetEnumerator()|Sort-Object Value -Descending|Select-Object -First 1).Key
    $poc = [math]::Round($l + ($pocBucket + 0.5) * $step, 4)
    $sorted = $volMap.GetEnumerator()|Sort-Object Value -Descending
    $accumulated=0.0; $vaKeys=@()
    foreach ($kv in $sorted) {
        $accumulated+=$kv.Value; $vaKeys+=$kv.Key
        if ($accumulated -ge $totalVol*0.70) { break }
    }
    $vah=[math]::Round($l+(($vaKeys|Measure-Object -Maximum).Maximum+1)*$step,4)
    $val=[math]::Round($l+(($vaKeys|Measure-Object -Minimum).Minimum)*$step,4)
    return [PSCustomObject]@{ poc=$poc; vah=$vah; val=$val }
}

# ── Estrutura de Mercado (HH/HL/LH/LL — Murphy) ─────────────────────────────

function Get-MarketStructure($candles, $lookback=20) {
    $s=$candles|Select-Object -Last $lookback
    $h=$s|ForEach-Object{$_.high}; $l=$s|ForEach-Object{$_.low}; $n=$h.Count
    $hh=0;$hl=0;$lh=0;$ll=0
    for ($i=2;$i-lt$n;$i++) {
        if ($h[$i]-gt$h[$i-2]){$hh++}else{$lh++}
        if ($l[$i]-gt$l[$i-2]){$hl++}else{$ll++}
    }
    $bull=$hh+$hl; $bear=$lh+$ll
    if ($bull-gt$bear*1.3){return "UPTREND"} elseif ($bear-gt$bull*1.3){return "DOWNTREND"} else{return "SIDEWAYS"}
}

# ── Volume Signal ────────────────────────────────────────────────────────────

function Get-VolumeSignal($candles, $period=20) {
    $s=$candles|Select-Object -Last ($period+1)
    $avg=($s|Select-Object -First $period|Measure-Object -Property volume -Average).Average
    $last=($s|Select-Object -Last 1).volume
    $ratio=if($avg-gt0){[math]::Round($last/$avg,2)}else{1}
    $sig=if($ratio-ge3.0){"CLIMAX(3x+)"}elseif($ratio-ge2.0){"MUITO-FORTE(2x+)"}elseif($ratio-ge1.5){"FORTE(1.5x+)"}elseif($ratio-ge0.8){"NORMAL"}else{"FRACO(<0.8x)"}
    return [PSCustomObject]@{ ratio=$ratio; signal=$sig; avg=[math]::Round($avg,0) }
}

# ── Opening Range Breakout (Toby Crabel) ────────────────────────────────────
# Usa os primeiros N candles da sessao como referencia de range

function Get-ORB($candles, $barsInRange=4) {
    if ($candles.Count -le $barsInRange) { return $null }
    $orb    = $candles | Select-Object -First $barsInRange
    $orbHigh= ($orb|Measure-Object -Property high -Maximum).Maximum
    $orbLow = ($orb|Measure-Object -Property low  -Minimum).Minimum
    $last   = $candles[-1].close
    $signal = if ($last-gt$orbHigh){"BULLISH-BREAKOUT"}elseif($last-lt$orbLow){"BEARISH-BREAKOUT"}else{"DENTRO-DO-RANGE"}
    return [PSCustomObject]@{ high=[math]::Round($orbHigh,4); low=[math]::Round($orbLow,4); signal=$signal }
}

# ── RSI Divergencia ──────────────────────────────────────────────────────────

function Detect-RSIDivergence($candles, $period=14, $lookback=5) {
    $closes=$candles|ForEach-Object{$_.close}; $n=$closes.Count
    if ($n -lt $period+$lookback+2) { return "INDEFINIDO" }
    $rsiNow =Calc-RSI ($closes|Select-Object -Last ($period+5)) $period
    $rsiPrev=Calc-RSI ($closes|Select-Object -Last ($period+5+$lookback)|Select-Object -First ($period+5)) $period
    $pNow=$closes[$n-1]; $pPrev=$closes[$n-1-$lookback]
    if ($pNow-lt$pPrev-and$rsiNow-gt$rsiPrev){return "BULLISH-DIV"}
    if ($pNow-gt$pPrev-and$rsiNow-lt$rsiPrev){return "BEARISH-DIV"}
    return "NONE"
}

# ── Pullback em Tendencia (Carter/Murphy) ────────────────────────────────────

function Detect-Pullback($candles) {
    $closes=$candles|ForEach-Object{$_.close}
    $e9 =Calc-EMA $closes 9
    $e21=Calc-EMA $closes 21
    $last=$closes[-1]
    $struct=Get-MarketStructure $candles 20

    # Pullback em downtrend: preco volta para EMA9/21 de baixo antes de cair de novo
    if ($struct-eq"DOWNTREND"-and$e9-lt$e21) {
        $distE9=[math]::Abs($last-$e9)/$e9
        if ($distE9-lt0.005){return "PULLBACK-DOWNTREND-EM-EMA(vender)"}
        if ($last-gt$e9-and$last-lt$e21){return "PRECO-ENTRE-EMAs(zona-de-venda)"}
    }
    if ($struct-eq"UPTREND"-and$e9-gt$e21) {
        $distE9=[math]::Abs($last-$e9)/$e9
        if ($distE9-lt0.005){return "PULLBACK-UPTREND-EM-EMA(comprar)"}
        if ($last-lt$e9-and$last-gt$e21){return "PRECO-ENTRE-EMAs(zona-de-compra)"}
    }
    return "NONE"
}

# ── Padroes de Candle (Nison + Bulkowski) ────────────────────────────────────

function Detect-CandlePatterns($candles) {
    $n=$candles.Count; if ($n-lt5){return @("DADOS-INSUFICIENTES")}
    $c0=$candles[$n-1]; $c1=$candles[$n-2]; $c2=$candles[$n-3]; $c3=$candles[$n-4]
    $body0=[math]::Abs($c0.close-$c0.open); $range0=$c0.high-$c0.low
    $body1=[math]::Abs($c1.close-$c1.open); $range1=$c1.high-$c1.low
    $ls0=[math]::Min($c0.open,$c0.close)-$c0.low
    $us0=$c0.high-[math]::Max($c0.open,$c0.close)
    $patterns=@()

    # Doji
    if ($range0-gt0-and($body0/$range0)-lt0.05){$patterns+="DOJI(indecisao)"}

    # Hammer (bullish, apos queda)
    if ($body0-gt0-and$ls0-ge2*$body0-and$us0-le$body0*0.3-and$c1.close-lt$c1.open){$patterns+="HAMMER(bull-rev,60pct)"}

    # Shooting Star (bearish, apos alta)
    if ($body0-gt0-and$us0-ge2*$body0-and$ls0-le$body0*0.3-and$c1.close-gt$c1.open){$patterns+="SHOOTING-STAR(bear-rev,58pct)"}

    # Bullish Engulfing
    if ($c1.close-lt$c1.open-and$c0.close-gt$c0.open-and$c0.open-lt$c1.close-and$c0.close-gt$c1.open){$patterns+="BULLISH-ENGULFING(bull-rev,63pct)"}

    # Bearish Engulfing
    if ($c1.close-gt$c1.open-and$c0.close-lt$c0.open-and$c0.open-gt$c1.close-and$c0.close-lt$c1.open){$patterns+="BEARISH-ENGULFING(bear-rev,67pct)"}

    # Morning Star (bullish, 3 candles, 78pct)
    if ($c2.close-lt$c2.open){
        $midC2=($c2.open+$c2.close)/2
        $smallC1=($range1-gt0-and($body1/$range1)-lt0.35)
        if ($smallC1-and$c0.close-gt$c0.open-and$c0.close-gt$midC2){$patterns+="MORNING-STAR(bull-rev,78pct)"}
    }

    # Evening Star (bearish, 3 candles, 72pct)
    if ($c2.close-gt$c2.open){
        $midC2=($c2.open+$c2.close)/2
        $smallC1=($range1-gt0-and($body1/$range1)-lt0.35)
        if ($smallC1-and$c0.close-lt$c0.open-and$c0.close-lt$midC2){$patterns+="EVENING-STAR(bear-rev,72pct)"}
    }

    # Three Black Crows (bearish, 78pct) — 3 candles vermelhos consecutivos fechando perto das minimas
    $b0_bear=($c0.close-lt$c0.open)
    $b1_bear=($c1.close-lt$c1.open)
    $b2_bear=($c2.close-lt$c2.open)
    $nearLow0=($range0-gt0-and([math]::Min($c0.open,$c0.close)-$c0.low)/$range0-lt0.25)
    $nearLow1=($range1-gt0-and([math]::Min($c1.open,$c1.close)-$c1.low)/$range1-lt0.25)
    $nearLow2=($c2.high-$c2.low-gt0-and([math]::Min($c2.open,$c2.close)-$c2.low)/($c2.high-$c2.low)-lt0.25)
    if ($b0_bear-and$b1_bear-and$b2_bear-and$nearLow0-and$nearLow1-and$nearLow2){$patterns+="THREE-BLACK-CROWS(bear-cont,78pct)"}

    # Three White Soldiers (bullish) — inverso
    $b0_bull=($c0.close-gt$c0.open)
    $b1_bull=($c1.close-gt$c1.open)
    $b2_bull=($c2.close-gt$c2.open)
    $nearHigh0=($range0-gt0-and($c0.high-[math]::Max($c0.open,$c0.close))/$range0-lt0.25)
    $nearHigh1=($range1-gt0-and($c1.high-[math]::Max($c1.open,$c1.close))/$range1-lt0.25)
    $nearHigh2=($c2.high-$c2.low-gt0-and($c2.high-[math]::Max($c2.open,$c2.close))/($c2.high-$c2.low)-lt0.25)
    if ($b0_bull-and$b1_bull-and$b2_bull-and$nearHigh0-and$nearHigh1-and$nearHigh2){$patterns+="THREE-WHITE-SOLDIERS(bull-cont,82pct)"}

    # Flag — consolidacao apos movimento forte (Bulkowski: ~67% win rate)
    $priorMove=[math]::Abs($c3.close-$c3.open)
    $flagSlice=$candles[($n-3)..($n-1)]
    $flagHigh=([double]($flagSlice|Measure-Object -Property high -Maximum).Maximum)
    $flagLow =([double]($flagSlice|Measure-Object -Property low  -Minimum).Minimum)
    $consolidRange=[double]$flagHigh - [double]$flagLow
    if ($priorMove-gt0-and($consolidRange/$priorMove)-lt0.5) {
        if ($c3.close-lt$c3.open){$patterns+="BEAR-FLAG(bear-cont,67pct)"}
        elseif($c3.close-gt$c3.open){$patterns+="BULL-FLAG(bull-cont,67pct)"}
    }

    # Dark Cloud Cover (bearish reversal after uptrend — Nison, 66pct)
    if ($c1.close-gt$c1.open-and$c0.close-lt$c0.open-and$c0.open-gt$c1.high-and$c0.close-lt(($c1.open+$c1.close)/2)){$patterns+="DARK-CLOUD-COVER(bear-rev,66pct)"}

    # Piercing Line (bullish reversal after downtrend — Nison, 64pct)
    if ($c1.close-lt$c1.open-and$c0.close-gt$c0.open-and$c0.open-lt$c1.low-and$c0.close-gt(($c1.open+$c1.close)/2)){$patterns+="PIERCING-LINE(bull-rev,64pct)"}

    # Dragonfly Doji (long lower shadow = bulls rejected low — bullish)
    if ($range0-gt0-and($body0/$range0)-lt0.1-and$ls0-ge$range0*0.65){$patterns+="DRAGONFLY-DOJI(bull-rev)"}

    # Gravestone Doji (long upper shadow = bears rejected high — bearish)
    if ($range0-gt0-and($body0/$range0)-lt0.1-and$us0-ge$range0*0.65){$patterns+="GRAVESTONE-DOJI(bear-rev)"}

    # Marubozu (no wicks = strong conviction — Nison)
    if ($range0-gt0-and($body0/$range0)-gt0.95) {
        if ($c0.close-gt$c0.open){$patterns+="BULL-MARUBOZU(bull-cont,strong)"}
        else{$patterns+="BEAR-MARUBOZU(bear-cont,strong)"}
    }

    if ($patterns.Count-eq0){$patterns+="SEM-PADRAO"}
    return $patterns
}

# ── Elder Triple Screen ───────────────────────────────────────────────────────
# Screen1=1D(tendencia), Screen2=4H(oscilador contra tendencia), Screen3=1H(trigger)

function Calc-ElderTripleScreen($tf1d, $tf4h, $tf1h) {
    # Screen 1: Direcao da tendencia no TF maior (1D)
    $trend = if ($tf1d.ema9 -gt $tf1d.ema21) { "UP" } else { "DOWN" }

    # Screen 2: Elder usa Stochastic como oscilador de pullback (Elder original)
    # Downtrend: Stochastic 4H > 60 (rali terminou) OU RSI > 50 = vender
    # Uptrend:   Stochastic 4H < 40 (pullback terminou) OU RSI < 50 = comprar
    $stochOk  = ($trend -eq "DOWN" -and $tf4h.stoch.k -gt 60) -or ($trend -eq "UP" -and $tf4h.stoch.k -lt 40)
    $rsiOk    = ($trend -eq "DOWN" -and $tf4h.rsi -gt 50) -or ($trend -eq "UP" -and $tf4h.rsi -lt 50)
    $screen2ok = $stochOk -or $rsiOk

    # Screen 3: Entrada no TF menor
    $screen3signal = if ($trend -eq "DOWN" -and $tf1h.ema9 -lt $tf1h.ema21) { "VENDER" }
                     elseif ($trend -eq "UP" -and $tf1h.ema9 -gt $tf1h.ema21) { "COMPRAR" }
                     else { "AGUARDAR" }

    $active = $screen2ok -and ($screen3signal -ne "AGUARDAR")
    return [PSCustomObject]@{
        trend=$trend; screen2ok=$screen2ok; screen3=$screen3signal; active=$active
    }
}

# ── Stan Weinstein — 4 Fases ("Secrets for Profiting in Bull and Bear Markets") ──
# Fase1=acumulacao, Fase2=tendencia-alta, Fase3=distribuicao, Fase4=tendencia-baixa

function Get-WeinsteinPhase($candles) {
    $closes=$candles|ForEach-Object{$_.close}
    $n=$closes.Count
    if ($n -lt 30) { return "INDEFINIDO" }
    $ma30=Calc-EMA $closes 30
    $ma30prev=Calc-EMA ($closes|Select-Object -First ($n-5)) 30
    $last=$closes[-1]
    $maTrend=if($ma30-gt$ma30prev*1.002){"RISING"}elseif($ma30-lt$ma30prev*0.998){"FALLING"}else{"FLAT"}
    $aboveMA=($last-gt$ma30)

    # Volume tendencia
    $vol=$candles|ForEach-Object{$_.volume}
    $volNow=($vol|Select-Object -Last 5|Measure-Object -Average).Average
    $volPrev=($vol|Select-Object -Last 15|Select-Object -First 10|Measure-Object -Average).Average
    $volRising=($volNow-gt$volPrev)

    if ($aboveMA -and $maTrend-eq"RISING") { return "FASE2-UPTREND(comprar)" }
    if (-not$aboveMA -and $maTrend-eq"FALLING") { return "FASE4-DOWNTREND(vender)" }
    if ($aboveMA -and $maTrend-eq"FLAT" -and $volRising) { return "FASE3-DISTRIBUICAO(sair-longs)" }
    if (-not$aboveMA -and $maTrend-eq"FLAT" -and $volRising) { return "FASE1-ACUMULACAO(preparar)" }
    return "TRANSICAO"
}

# ── NR7 / Inside Bar (Toby Crabel) — compressao antes de expansao ────────────

function Detect-NR7($candles) {
    $n=$candles.Count; if ($n-lt8) { return "NONE" }
    $ranges=($candles|Select-Object -Last 7)|ForEach-Object{$_.high-$_.low}
    $currentRange=$candles[-1].high-$candles[-1].low
    $minRange=($ranges|Measure-Object -Minimum).Minimum
    $isNR7=($currentRange-le$minRange*1.001)
    $isIB=($candles[-1].high-le$candles[-2].high-and$candles[-1].low-ge$candles[-2].low)
    if ($isNR7-and$isIB){return "NR7+INSIDE-BAR(compressao-maxima)"}
    if ($isNR7){return "NR7(compressao-breakout-iminente)"}
    if ($isIB){return "INSIDE-BAR(compressao)"}
    return "NONE"
}

# ── VSA — Volume Spread Analysis (Tom Williams, "Master the Markets") ─────────

function Detect-VSA($candles) {
    $n=$candles.Count; if ($n-lt3) { return "NONE" }
    $c=$candles[-1]
    $spread=$c.high-$c.low
    $closePos=if($spread-gt0){($c.close-$c.low)/$spread}else{0.5}
    $vol=$candles|ForEach-Object{$_.volume}
    $avgVol=($vol|Select-Object -Last 20|Measure-Object -Average).Average
    $isHiVol=($c.volume-gt$avgVol*1.5)
    $isLoVol=($c.volume-lt$avgVol*0.5)
    $prevSpread=$candles[-2].high-$candles[-2].low
    $isWide=($spread-gt$prevSpread*1.3)
    $isNarrow=($spread-lt$prevSpread*0.5)

    # Demanda: spread largo + volume alto + fechamento perto do topo
    if ($isWide-and$isHiVol-and$closePos-gt0.7){return "VSA-DEMANDA(bullish)"}
    # Oferta: spread largo + volume alto + fechamento perto do fundo
    if ($isWide-and$isHiVol-and$closePos-lt0.3){return "VSA-OFERTA(bearish)"}
    # Absorcao: spread estreito + volume alto (grande player absorvendo)
    if ($isNarrow-and$isHiVol){return "VSA-ABSORCAO(reversao-possivel)"}
    # Sem demanda: spread estreito + volume baixo em rali
    if ($isNarrow-and$isLoVol-and$c.close-gt$c.open){return "VSA-SEM-DEMANDA(bear-fraqueza)"}
    return "NONE"
}

# ── Donchian Channel / Turtle Trading (Covel, Curtis Faith) ──────────────────
# Turtle: entrar no rompimento da maxima/minima de 20 periodos

function Calc-Donchian($candles, $period=20) {
    $s=$candles|Select-Object -Last $period
    $high=($s|Measure-Object -Property high -Maximum).Maximum
    $low =($s|Measure-Object -Property low  -Minimum).Minimum
    $mid=[math]::Round(($high+$low)/2,4)
    $last=$candles[-1].close
    $signal=if($last-ge$high){"BREAKOUT-ALTA(turtle-compra)"}elseif($last-le$low){"BREAKOUT-BAIXA(turtle-vende)"}else{"DENTRO"}
    return [PSCustomObject]@{ high=[math]::Round($high,4); low=[math]::Round($low,4); mid=$mid; signal=$signal }
}

# ── Wyckoff Method — fases de acumulacao/distribuicao ────────────────────────
# Richard Wyckoff: whales seguem padroes visiveis no price+volume

function Get-WyckoffPhase($candles) {
    $n=$candles.Count; if ($n-lt20){return "INDEFINIDO"}
    $s=$candles|Select-Object -Last 20
    $vol=$s|ForEach-Object{$_.volume}
    $avgVol=($vol|Measure-Object -Average).Average
    $prices=$s|ForEach-Object{$_.close}
    $pRange=($prices|Measure-Object -Maximum).Maximum - ($prices|Measure-Object -Minimum).Minimum
    $pFirst=$prices[0]; $pLast=$prices[-1]
    $lastVol=$s[-1].volume
    $lastSpread=$s[-1].high-$s[-1].low
    $avgSpread=($s|ForEach-Object{$_.high-$_.low}|Measure-Object -Average).Average
    $isNarrowRange=($pRange/($prices|Measure-Object -Average).Average)-lt0.05
    $priceUp=($pLast-gt$pFirst)
    $priceDown=($pLast-lt$pFirst)

    # Selling Climax (SC): queda forte + volume extremo + candle de reversao
    if ($priceDown-and$lastVol-gt$avgVol*2-and$lastSpread-gt$avgSpread*1.5-and$s[-1].close-gt($s[-1].open)){
        return "WYCKOFF-SC(selling-climax-reversao-bull)"
    }
    # Buying Climax (BC): alta forte + volume extremo = distribuicao comecando
    if ($priceUp-and$lastVol-gt$avgVol*2-and$lastSpread-gt$avgSpread*1.5-and$s[-1].close-lt($s[-1].open)){
        return "WYCKOFF-BC(buying-climax-distribuicao-bear)"
    }
    # Spring: toca minima do range com volume baixo (falso rompimento bullish)
    $rangeMin=($s|Measure-Object -Property low -Minimum).Minimum
    if ($s[-1].low-le$rangeMin*1.002-and$lastVol-lt$avgVol*0.7-and$s[-1].close-gt$s[-1].open){
        return "WYCKOFF-SPRING(acumulacao-bull)"
    }
    # Upthrust: toca maxima do range com volume baixo (falso rompimento bearish)
    $rangeMax=($s|Measure-Object -Property high -Maximum).Maximum
    if ($s[-1].high-ge$rangeMax*0.998-and$lastVol-lt$avgVol*0.7-and$s[-1].close-lt$s[-1].open){
        return "WYCKOFF-UPTHRUST(distribuicao-bear)"
    }
    if ($isNarrowRange){return "WYCKOFF-CONSOLIDACAO(range)"}
    return "NONE"
}

# ── SMC — Smart Money Concepts (ICT / Michael Huddleston) ────────────────────
# Order Blocks: ultimo candle oposto antes de movimento forte = zona institucional

function Get-SMC($candles) {
    $n=$candles.Count; if ($n-lt10){return [PSCustomObject]@{bullOB=0;bearOB=0;signal="NONE"}}
    # Bearish Order Block: ultimo candle bullish antes de queda forte
    $bearOB=0.0; $bullOB=0.0
    for ($i=$n-5;$i-ge1;$i--) {
        $move=[math]::Abs($candles[$i+1].close-$candles[$i+1].open)
        $avgMove=0.0; for ($j=[math]::Max(0,$i-5);$j-lt$i;$j++){$avgMove+=[math]::Abs($candles[$j].close-$candles[$j].open)}
        $avgMove=$avgMove/5
        if ($candles[$i].close-gt$candles[$i].open-and$candles[$i+1].close-lt$candles[$i+1].open-and$move-gt$avgMove*1.5){
            $bearOB=$candles[$i].high; break
        }
    }
    for ($i=$n-5;$i-ge1;$i--) {
        $move=[math]::Abs($candles[$i+1].close-$candles[$i+1].open)
        $avgMove=0.0; for ($j=[math]::Max(0,$i-5);$j-lt$i;$j++){$avgMove+=[math]::Abs($candles[$j].close-$candles[$j].open)}
        $avgMove=$avgMove/5
        if ($candles[$i].close-lt$candles[$i].open-and$candles[$i+1].close-gt$candles[$i+1].open-and$move-gt$avgMove*1.5){
            $bullOB=$candles[$i].low; break
        }
    }
    $last=$candles[-1].close
    $signal="NONE"
    if ($bearOB-gt0-and[math]::Abs($last-$bearOB)/$bearOB-lt0.005){$signal="PRECO-EM-BEARISH-OB(resistencia)"}
    elseif($bullOB-gt0-and[math]::Abs($last-$bullOB)/$bullOB-lt0.005){$signal="PRECO-EM-BULLISH-OB(suporte)"}
    return [PSCustomObject]@{ bullOB=[math]::Round($bullOB,4); bearOB=[math]::Round($bearOB,4); signal=$signal }
}

# ── On-Chain Proxy — Funding Rate (CoinEx API) ───────────────────────────────
# Funding rate positivo = maioria esta comprada (cuidado com long squeeze)
# Funding rate negativo = maioria esta vendida (cuidado com short squeeze)

function Get-FundingRate($market) {
    try {
        $r=Invoke-RestMethod -Uri ("https://api.coinex.com/v2/futures/funding-rate?market="+$market) -Method GET
        if ($r.code-eq0) {
            $fr=[double]$r.data.latest_funding_rate
            $frPct=[math]::Round($fr*100,4)
            $signal=if($fr-gt0.001){"LONGS-PAGANDO(short-favorecido)"}elseif($fr-lt-0.001){"SHORTS-PAGANDO(long-favorecido)"}else{"NEUTRO"}
            return [PSCustomObject]@{ rate=$frPct; signal=$signal }
        }
    } catch {}
    return [PSCustomObject]@{ rate=0; signal="INDISPONIVEL" }
}

# ── ATR Wilder Correto (suavizacao exponencial) ───────────────────────────────

function Calc-ATR-Wilder($candles, $period=14) {
    if ($candles.Count -lt $period+1) { return 0.0 }
    $tr=@()
    for ($i=1;$i-lt$candles.Count;$i++) {
        $c=$candles[$i];$p=$candles[$i-1]
        $tr+=[math]::Max($c.high-$c.low,[math]::Max([math]::Abs($c.high-$p.close),[math]::Abs($c.low-$p.close)))
    }
    $atr=($tr|Select-Object -First $period|Measure-Object -Average).Average
    foreach ($t in ($tr|Select-Object -Skip $period)) { $atr=($atr*($period-1)+$t)/$period }
    return [math]::Round($atr,5)
}

# ── Score Final ──────────────────────────────────────────────────────────────

function Calc-Score($tf) {
    $s=0; $r=@()

    # Estrutura (Murphy) — peso 2
    if ($tf.structure-eq"DOWNTREND"){$s-=2;$r+="estrutura-DOWN"}
    elseif ($tf.structure-eq"UPTREND"){$s+=2;$r+="estrutura-UP"}

    # EMA Cross 9/21
    if ($tf.ema9-lt$tf.ema21){$s-=1;$r+="EMA9<21(bear)"}else{$s+=1;$r+="EMA9>21(bull)"}

    # Preco vs EMA50
    if ($tf.close-lt$tf.ema50){$s-=1;$r+="<EMA50(bear)"}else{$s+=1;$r+=">EMA50(bull)"}

    # RSI 14
    if ($tf.rsi-lt30){$s+=2;$r+="RSI-oversold"}elseif($tf.rsi-gt70){$s-=2;$r+="RSI-overbought"}
    elseif($tf.rsi-lt45){$s-=1;$r+="RSI-baixo"}elseif($tf.rsi-gt55){$s+=1;$r+="RSI-alto"}

    # RSI 2 (Connors) — extremos de curto prazo
    if ($tf.rsi2-lt5){$s+=2;$r+="RSI2<5(extremo-bull)"}elseif($tf.rsi2-gt95){$s-=2;$r+="RSI2>95(extremo-bear)"}
    elseif($tf.rsi2-lt15){$s+=1;$r+="RSI2<15(bull)"}elseif($tf.rsi2-gt85){$s-=1;$r+="RSI2>85(bear)"}

    # ADX
    if ($tf.adx.adx-gt25) {
        $r+=("ADX="+$tf.adx.adx+"(trend)")
        if ($tf.adx.ndi-gt$tf.adx.pdi){$s-=1;$r+="-DI>+DI(bear)"}else{$s+=1;$r+="+DI>-DI(bull)"}
    } else { $r+=("ADX="+$tf.adx.adx+"(range)") }

    # MACD
    if ($tf.macd.macd-lt0){$s-=1;$r+="MACD<0(bear)"}else{$s+=1;$r+="MACD>0(bull)"}

    # Bollinger (preco perto de banda)
    if ($tf.close-le$tf.bb.lower){$s+=1;$r+="BB-lower(oversold)"}
    elseif($tf.close-ge$tf.bb.upper){$s-=1;$r+="BB-upper(overbought)"}

    # VWAP
    if ($null-ne$tf.vwap) {
        if ($tf.close-lt$tf.vwap.lower1){$s+=1;$r+="abaixo-VWAP1SD(bull)"}
        elseif($tf.close-gt$tf.vwap.upper1){$s-=1;$r+="acima-VWAP1SD(bear)"}
    }

    # Volume
    if ($tf.vol.signal-like"*FORTE*"-or$tf.vol.signal-like"*CLIMAX*"){$r+=("Vol="+$tf.vol.ratio+"x")}

    # Divergencia RSI
    if ($tf.divergence-eq"BULLISH-DIV"){$s+=2;$r+="RSI-BULLISH-DIV"}
    elseif($tf.divergence-eq"BEARISH-DIV"){$s-=2;$r+="RSI-BEARISH-DIV"}

    # Pullback
    if ($tf.pullback-like"*vender*"){$s-=1;$r+=$tf.pullback}
    elseif($tf.pullback-like"*comprar*"){$s+=1;$r+=$tf.pullback}

    # Padroes de candle
    foreach ($p in $tf.patterns) {
        if ($p-like"*bull*"){$s+=1;$r+="PADRAO:"+$p}
        if ($p-like"*bear*"){$s-=1;$r+="PADRAO:"+$p}
    }

    # Weinstein 4 fases
    if ($tf.weinstein-like"*FASE2*"){$s+=2;$r+=$tf.weinstein}
    elseif($tf.weinstein-like"*FASE4*"){$s-=2;$r+=$tf.weinstein}
    elseif($tf.weinstein-like"*FASE3*"){$s-=1;$r+=$tf.weinstein}
    elseif($tf.weinstein-like"*FASE1*"){$s+=1;$r+=$tf.weinstein}

    # VSA (Tom Williams)
    if ($tf.vsa-like"*DEMANDA*"){$s+=1;$r+=$tf.vsa}
    elseif($tf.vsa-like"*OFERTA*"){$s-=1;$r+=$tf.vsa}
    elseif($tf.vsa-like"*SEM-DEMANDA*"){$s-=1;$r+=$tf.vsa}

    # Donchian / Turtle (Covel/Curtis Faith)
    if ($tf.donchian.signal-like"*ALTA*"){$s+=2;$r+="TURTLE:"+$tf.donchian.signal}
    elseif($tf.donchian.signal-like"*BAIXA*"){$s-=2;$r+="TURTLE:"+$tf.donchian.signal}

    # NR7 — nao da direcao, mas sinaliza que breakout esta proximo
    if ($tf.nr7-ne"NONE"){$r+=$tf.nr7}

    # Wyckoff
    if ($tf.wyckoff-like"*bull*"-or$tf.wyckoff-like"*SPRING*"){$s+=2;$r+=$tf.wyckoff}
    elseif($tf.wyckoff-like"*bear*"-or$tf.wyckoff-like"*UPTHRUST*"-or$tf.wyckoff-like"*BC*"){$s-=2;$r+=$tf.wyckoff}
    elseif($tf.wyckoff-ne"NONE"-and$tf.wyckoff-ne"INDEFINIDO"){$r+=$tf.wyckoff}

    # SMC Order Blocks (ICT)
    if ($tf.smc.signal-like"*BEARISH-OB*"){$s-=1;$r+=$tf.smc.signal+" bearOB="+$tf.smc.bearOB}
    elseif($tf.smc.signal-like"*BULLISH-OB*"){$s+=1;$r+=$tf.smc.signal+" bullOB="+$tf.smc.bullOB}

    # Stochastic (George Lane) — Slow (14,3,3)
    if ($tf.stoch.signal-like"*OVERSOLD-CROSS-UP*"){$s+=2;$r+="STOCH:"+$tf.stoch.signal}
    elseif($tf.stoch.signal-like"*OVERBOUGHT-CROSS-DOWN*"){$s-=2;$r+="STOCH:"+$tf.stoch.signal}
    elseif($tf.stoch.signal-eq"OVERSOLD"){$s+=1;$r+="STOCH-OVERSOLD(K="+$tf.stoch.k+")"}
    elseif($tf.stoch.signal-eq"OVERBOUGHT"){$s-=1;$r+="STOCH-OVERBOUGHT(K="+$tf.stoch.k+")"}

    # OBV — Joe Granville (divergencias tem peso alto)
    if ($tf.obv.trend-like"*DIV-BULLISH*"){$s+=2;$r+="OBV:"+$tf.obv.trend}
    elseif($tf.obv.trend-like"*DIV-BEARISH*"){$s-=2;$r+="OBV:"+$tf.obv.trend}
    elseif($tf.obv.trend-like"*CONFIRMANDO-ALTA*"){$s+=1;$r+="OBV:CONFIRM-ALTA"}
    elseif($tf.obv.trend-like"*CONFIRMANDO-BAIXA*"){$s-=1;$r+="OBV:CONFIRM-BAIXA"}

    # Ichimoku (Hosoda) — filtro de tendencia forte
    if ($tf.ichimoku.bias-like"*ACIMA-NUVEM*"){$s+=2;$r+="ICHI:ACIMA-NUVEM(bullish)"}
    elseif($tf.ichimoku.bias-like"*ABAIXO-NUVEM*"){$s-=2;$r+="ICHI:ABAIXO-NUVEM(bearish)"}
    if ($tf.ichimoku.tk-eq"TK-BULL"){$s+=1;$r+="TK-BULL"}
    elseif($tf.ichimoku.tk-eq"TK-BEAR"){$s-=1;$r+="TK-BEAR"}

    # SuperTrend (ATR-based filter)
    if ($tf.supertrend.trend-like"*BULLISH*"){$s+=1;$r+="SUPERTREND:BULL"}
    elseif($tf.supertrend.trend-like"*BEARISH*"){$s-=1;$r+="SUPERTREND:BEAR"}

    # Parabolic SAR (Wilder)
    if ($tf.sar.trend-like"*BULL*"){$s+=1;$r+="SAR:BULL(SAR="+$tf.sar.sar+")"}
    elseif($tf.sar.trend-like"*BEAR*"){$s-=1;$r+="SAR:BEAR(SAR="+$tf.sar.sar+")"}

    # Bollinger Squeeze (John Carter) — nao da direcao, apenas alerta de breakout
    if ($tf.squeeze-like"*SQUEEZE-ATIVO*"){$r+="BB-SQUEEZE-ATIVO(breakout-iminente)"}

    $signal=if($s-le-7){"SHORT-FORTE"}elseif($s-le-3){"SHORT"}elseif($s-ge7){"LONG-FORTE"}elseif($s-ge3){"LONG"}else{"NEUTRO"}
    return [PSCustomObject]@{ score=$s; signal=$signal; reasons=$r }
}

# ── Swing Points (para analise de trendlines — camada Tori) ──────────────────

function Get-SwingPoints($candles, $lookback = 2) {
    $highs = @(); $lows = @()
    $n = $candles.Count
    for ($i = $lookback; $i -lt ($n - $lookback); $i++) {
        $isHigh = $true; $isLow = $true
        for ($j = 1; $j -le $lookback; $j++) {
            if ($candles[$i].high -le $candles[$i-$j].high -or $candles[$i].high -le $candles[$i+$j].high) { $isHigh = $false }
            if ($candles[$i].low  -ge $candles[$i-$j].low  -or $candles[$i].low  -ge $candles[$i+$j].low)  { $isLow  = $false }
        }
        if ($isHigh) { $highs += [PSCustomObject]@{ idx=$i; price=$candles[$i].high; barsAgo=($n-1-$i) } }
        if ($isLow)  { $lows  += [PSCustomObject]@{ idx=$i; price=$candles[$i].low;  barsAgo=($n-1-$i) } }
    }
    return [PSCustomObject]@{
        highs = ($highs | Select-Object -Last 6)
        lows  = ($lows  | Select-Object -Last 6)
    }
}

# ── Analise Completa ─────────────────────────────────────────────────────────

function Run-Analysis($market) {
    # Dados
    $c1h = Get-Candles $market "1hour" 100
    $c4h = Get-Candles $market "4hour" 80
    $c1d = Get-Candles $market "1day"  60
    $c1w = Get-Candles $market "1week" 52
    # Candles intraday para VWAP (5min, ultimas 8h = 96 candles)
    $c5m = Get-Candles $market "5min" 96

    function Build-TF($candles, $label) {
        $closes = $candles|ForEach-Object{$_.close}
        $bb2    = Calc-BollingerBands $closes
        $kc     = Calc-Keltner $closes $candles
        [PSCustomObject]@{
            label     = $label
            close     = $candles[-1].close
            ema9      = [math]::Round((Calc-EMA $closes 9),  4)
            ema21     = [math]::Round((Calc-EMA $closes 21), 4)
            ema50     = [math]::Round((Calc-EMA $closes 50), 4)
            ema200    = [math]::Round((Calc-EMA $closes 200),4)
            rsi       = [math]::Round((Calc-RSI $closes),    1)
            rsi2      = [math]::Round((Calc-RSI2 $closes),   1)
            adx       = Calc-ADX $candles
            atr       = Calc-ATR-Wilder $candles
            bb        = $bb2
            macd      = Calc-MACD $closes
            fib       = Calc-Fibonacci $candles 30
            vp        = Calc-VolumeProfile $candles 20
            vwap      = Calc-VWAP $candles
            donchian  = Calc-Donchian $candles 20
            orb       = Get-ORB $candles 4
            vol       = Get-VolumeSignal $candles
            structure = Get-MarketStructure $candles
            weinstein = Get-WeinsteinPhase $candles
            patterns  = Detect-CandlePatterns $candles
            nr7       = Detect-NR7 $candles
            vsa       = Detect-VSA $candles
            divergence= Detect-RSIDivergence $candles
            pullback  = Detect-Pullback $candles
            wyckoff   = Get-WyckoffPhase $candles
            smc       = Get-SMC $candles
            stoch     = Calc-Stochastic $candles
            obv       = Calc-OBV $candles
            ichimoku  = Calc-Ichimoku $candles
            supertrend= Calc-SuperTrend $candles
            keltner   = $kc
            squeeze   = Detect-BollingerSqueeze $bb2 $kc
            sar       = Calc-ParabolicSAR $candles
        }
    }

    $tf1h = Build-TF $c1h "1H"
    $tf4h = Build-TF $c4h "4H"
    $tf1d = Build-TF $c1d "1D"
    $tf1w = Build-TF $c1w "1W"

    # Swing points 4H para analise de trendlines (camada Tori)
    $swings4h = Get-SwingPoints $c4h 2

    # VWAP intraday real (usa candles 5min para maior precisao)
    $vwapIntraday = Calc-VWAP $c5m

    $sig1h = Calc-Score $tf1h
    $sig4h = Calc-Score $tf4h
    $sig1d = Calc-Score $tf1d

    # Elder Triple Screen
    $elder = Calc-ElderTripleScreen $tf1d $tf4h $tf1h

    # ICT Power of 3 — fase atual da sessao
    $po3 = Get-PowerOf3

    # Contexto de ciclo pos-halving (Rekt Capital + sazonalidade)
    $cycle = Get-CycleContext

    # On-chain proxy: Funding Rate (sinal de sentimento de futuros)
    $funding = Get-FundingRate $Market

    # ATR-based stop suggestion (Wilder: 2x ATR para crypto)
    $atrStop1h = [math]::Round($tf1h.atr * 2, 4)

    # Consenso ponderado (TF maior tem mais peso — Murphy)
    $totalScore = $sig1h.score + $sig4h.score*1.5 + $sig1d.score*2
    $consensus  = if($totalScore-le-6){"SHORT-FORTE"}elseif($totalScore-le-3){"SHORT"}elseif($totalScore-ge6){"LONG-FORTE"}elseif($totalScore-ge3){"LONG"}else{"NEUTRO/AGUARDAR"}

    $now=(Get-Date).ToString("HH:mm:ss")

    if (-not $Quiet) {
        Write-Host ""
        Write-Host ("=" * 58)
        Write-Host (" TECHAGENT v3.0 | $market | $now")
        Write-Host ("=" * 58)

        foreach ($tfObj in @($tf1d,$tf4h,$tf1h)) {
            $sig=if($tfObj.label-eq"1H"){$sig1h}elseif($tfObj.label-eq"4H"){$sig4h}else{$sig1d}
            Write-Host ""
            Write-Host ("-- "+$tfObj.label+" | Close="+$tfObj.close+" | "+$tfObj.structure+" | Score="+$sig.score+" -> "+$sig.signal)
            Write-Host ("   EMA: 9="+$tfObj.ema9+" 21="+$tfObj.ema21+" 50="+$tfObj.ema50+" 200="+$tfObj.ema200)
            Write-Host ("   RSI14="+$tfObj.rsi+" RSI2="+$tfObj.rsi2+" | ADX="+$tfObj.adx.adx+" +DI="+$tfObj.adx.pdi+" -DI="+$tfObj.adx.ndi)
            Write-Host ("   ATR="+$tfObj.atr+" | MACD="+$tfObj.macd.macd)
            Write-Host ("   BB: L="+$tfObj.bb.lower+" M="+$tfObj.bb.mid+" U="+$tfObj.bb.upper)
            Write-Host ("   VWAP: "+$tfObj.vwap.vwap+" | +1SD="+$tfObj.vwap.upper1+" -1SD="+$tfObj.vwap.lower1+" +2SD="+$tfObj.vwap.upper2+" -2SD="+$tfObj.vwap.lower2)
            Write-Host ("   Fib: H="+$tfObj.fib.high+" 23.6%="+$tfObj.fib.f236+" 38.2%="+$tfObj.fib.f382+" 50%="+$tfObj.fib.f500+" 61.8%="+$tfObj.fib.f618+" 78.6%="+$tfObj.fib.f786)
            Write-Host ("   Ext: 127%="+$tfObj.fib.ext127+" 161.8%="+$tfObj.fib.ext161)
            Write-Host ("   VolProfile: POC="+$tfObj.vp.poc+" VAH="+$tfObj.vp.vah+" VAL="+$tfObj.vp.val)
            Write-Host ("   ORB: "+$tfObj.orb.high+"/"+$tfObj.orb.low+" -> "+$tfObj.orb.signal)
            Write-Host ("   Volume: "+$tfObj.vol.ratio+"x | "+$tfObj.vol.signal)
            Write-Host ("   Candles: "+($tfObj.patterns-join" | "))
            Write-Host ("   Div: "+$tfObj.divergence+" | Pullback: "+$tfObj.pullback)
            Write-Host ("   Weinstein: "+$tfObj.weinstein+" | Wyckoff: "+$tfObj.wyckoff)
            Write-Host ("   VSA: "+$tfObj.vsa+" | NR7: "+$tfObj.nr7)
            Write-Host ("   Donchian: H="+$tfObj.donchian.high+" L="+$tfObj.donchian.low+" -> "+$tfObj.donchian.signal)
            Write-Host ("   SMC: bullOB="+$tfObj.smc.bullOB+" bearOB="+$tfObj.smc.bearOB+" | "+$tfObj.smc.signal)
            Write-Host ("   Stoch(14,3,3): K="+$tfObj.stoch.k+" D="+$tfObj.stoch.d+" | "+$tfObj.stoch.signal)
            Write-Host ("   OBV: "+$tfObj.obv.obv+" | "+$tfObj.obv.trend)
            Write-Host ("   Ichimoku: "+$tfObj.ichimoku.bias+" | TK="+$tfObj.ichimoku.tk+" | Cloud="+$tfObj.ichimoku.cloud)
            Write-Host ("   SuperTrend: "+$tfObj.supertrend.trend+" | SAR: "+$tfObj.sar.sar+" -> "+$tfObj.sar.trend)
            Write-Host ("   Keltner: L="+$tfObj.keltner.lower+" M="+$tfObj.keltner.mid+" U="+$tfObj.keltner.upper+" | "+$tfObj.squeeze)
            Write-Host ("   Score: "+($sig.reasons-join" | "))
        }

        Write-Host ""
        Write-Host ("-- ELDER TRIPLE SCREEN --")
        Write-Host ("   Screen1(1D): Tendencia="+$elder.trend)
        Write-Host ("   Screen2(4H): Pullback="+$elder.screen2ok)
        Write-Host ("   Screen3(1H): Trigger="+$elder.screen3)
        Write-Host ("   SINAL ATIVO: "+$elder.active)

        Write-Host ""
        Write-Host ("   VWAP Intraday(5M): "+$vwapIntraday.vwap+" | +1SD="+$vwapIntraday.upper1+" -1SD="+$vwapIntraday.lower1)
        Write-Host ("   Funding Rate: "+$funding.rate+"% | "+$funding.signal)
        Write-Host ("   Stop sugerido (2xATR 1H): "+$atrStop1h)
        Write-Host ("   Power of 3 (ICT): "+$po3)
        Write-Host ("   Ciclo: "+$cycle.monthsPostHalving+"m pos-halving (Apr2024) | "+$cycle.phase)
        Write-Host ("   Sazonal: "+$cycle.seasonal)

        Write-Host ""
        Write-Host ("=" * 58)
        Write-Host (" CONSENSO: $consensus | Score ponderado: "+[math]::Round($totalScore,1))
        Write-Host ("=" * 58)
        Write-Host ""
    }

    return [PSCustomObject]@{
        consensus   = $consensus
        totalScore  = [math]::Round($totalScore,1)
        elder       = $elder
        tf1h        = $tf1h
        tf4h        = $tf4h
        tf1d        = $tf1d
        tf1w        = $tf1w
        swings4h    = $swings4h
        atrStop1h   = $atrStop1h
        vwapIntraday= $vwapIntraday
        funding     = $funding
        po3         = $po3
        cycle       = $cycle
        timestamp   = $now
    }
}

# ── Loop / Execucao ───────────────────────────────────────────────────────────

if ($Once) {
    Run-Analysis $Market
} else {
    while ($true) {
        try { Run-Analysis $Market | Out-Null }
        catch { Write-Host ("ERRO: " + $_.Exception.Message) }
        Write-Host ("Proxima analise em " + $RefreshSecs + "s...")
        Start-Sleep -Seconds $RefreshSecs
    }
}
