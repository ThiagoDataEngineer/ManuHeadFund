
# trailing_short.ps1 — SHORT TONUSDT com TechAgent integrado
# Stop trail: 3% acima do minimo | Fibonacci como alvos | ATR como referencia de stop

# Credenciais via env var (config.local.ps1 ou shell environment).
# NUNCA hardcode keys aqui. Ver SECURITY.md.
$accessId      = $env:COINEX_ACCESS_ID
$secretKey     = $env:COINEX_SECRET_KEY
if (-not $accessId -or -not $secretKey) {
    throw "COINEX_ACCESS_ID / COINEX_SECRET_KEY nao definidos. Carregar agents/config.local.ps1 antes."
}
$market        = "TONUSDT"
$trailPct      = 0.03
$checkSecs     = 60
$analysisSecs  = 60           # roda TechAgent a cada 1 min
$entryPrice    = 2.3279
$amount        = "138"
$lowestPrice   = 2.3205
$currentStop   = 2.3901
$script:stopId = 207800727445

# ── API ──────────────────────────────────────────────────────────────────────

function Get-Headers($method, $path, $body) {
    $ts     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $toSign = $method + $path + $body + $ts
    $hmac   = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secretKey)
    $sig    = [System.BitConverter]::ToString($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign))).Replace("-","").ToLower()
    return @{
        "X-COINEX-KEY"       = $accessId
        "X-COINEX-SIGN"      = $sig
        "X-COINEX-TIMESTAMP" = $ts
        "Content-Type"       = "application/json"
    }
}

function Invoke-CoinExPost($path, $bodyObj) {
    $json = $bodyObj | ConvertTo-Json -Compress
    $h    = Get-Headers "POST" $path $json
    return Invoke-RestMethod -Uri ("https://api.coinex.com" + $path) -Method POST -Headers $h -Body $json
}

function Remove-StopOrder($stopId) {
    $bodyObj = @{ market=$market; market_type="FUTURES"; stop_id=$stopId }
    $json = $bodyObj | ConvertTo-Json -Compress
    $h    = Get-Headers "POST" "/v2/futures/cancel-stop-order" $json
    return Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/cancel-stop-order" -Method POST -Headers $h -Body $json
}

function Get-ActiveStops() {
    $spath  = "/v2/futures/pending-stop-order?market=$market&market_type=FUTURES&page=1&limit=10"
    $ts     = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds().ToString()
    $toSign = "GET" + $spath + "" + $ts
    $hmac   = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secretKey)
    $sig    = [System.BitConverter]::ToString($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($toSign))).Replace("-","").ToLower()
    $sh     = @{ "X-COINEX-KEY"=$accessId; "X-COINEX-SIGN"=$sig; "X-COINEX-TIMESTAMP"=$ts; "Content-Type"="application/json" }
    return Invoke-RestMethod -Uri ("https://api.coinex.com" + $spath) -Method GET -Headers $sh
}

function Log($msg) {
    $t = (Get-Date).ToString("HH:mm:ss")
    Write-Host ($t + " | " + $msg)
}

# ── TechAgent — indicadores inline para nao depender de arquivo externo ────────

function Get-Candles($mkt, $period, $limit) {
    $r = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/kline?market=$mkt&period=$period&limit=$limit" -Method GET
    return $r.data | ForEach-Object {
        [PSCustomObject]@{ open=[double]$_.open; high=[double]$_.high; low=[double]$_.low; close=[double]$_.close; volume=[double]$_.volume }
    }
}

function Get-EMA($closes, $period) {
    $k = 2.0/($period+1); $ema=$closes[0]
    foreach ($c in $closes[1..($closes.Count-1)]) { $ema=$c*$k+$ema*(1-$k) }
    return $ema
}

function Get-RSI($closes, $period=14) {
    $g=0.0;$l=0.0
    for ($i=1;$i-le$period;$i++) {
        $d=$closes[$i]-$closes[$i-1]
        if ($d-gt0){$g+=$d}else{$l+=[math]::Abs($d)}
    }
    $ag=$g/$period;$al=$l/$period
    for ($i=$period+1;$i-lt$closes.Count;$i++) {
        $d=$closes[$i]-$closes[$i-1]
        if ($d-gt0){$ag=($ag*($period-1)+$d)/$period;$al=$al*($period-1)/$period}
        else{$ag=$ag*($period-1)/$period;$al=($al*($period-1)+[math]::Abs($d))/$period}
    }
    if ($al-eq0){return 100.0}
    return 100-(100/(1+$ag/$al))
}

function Get-ATR($candles, $period=14) {
    $tr=@()
    for ($i=1;$i-lt$candles.Count;$i++) {
        $c=$candles[$i];$p=$candles[$i-1]
        $tr+=[math]::Max($c.high-$c.low,[math]::Max([math]::Abs($c.high-$p.close),[math]::Abs($c.low-$p.close)))
    }
    $atr=($tr|Select-Object -First $period|Measure-Object -Average).Average
    foreach ($t in ($tr|Select-Object -Skip $period)){$atr=($atr*($period-1)+$t)/$period}
    return $atr
}

function Get-FibLevels($candles, $lookback=30) {
    $s=$candles|Select-Object -Last $lookback
    $h=[double]($s|Measure-Object -Property high -Maximum).Maximum
    $l=[double]($s|Measure-Object -Property low  -Minimum).Minimum
    $r=$h-$l
    return [PSCustomObject]@{
        high=$h; low=$l
        f382=[math]::Round($h-$r*0.382,4)
        f500=[math]::Round($h-$r*0.500,4)
        f618=[math]::Round($h-$r*0.618,4)
        ext127=[math]::Round($l-$r*0.272,4)
        ext161=[math]::Round($l-$r*0.618,4)
    }
}

function Get-WyckoffSignal($candles) {
    $n=$candles.Count; if ($n-lt5){return "NONE"}
    $s=$candles|Select-Object -Last 10
    $vol=$s|ForEach-Object{$_.volume}
    $avgVol=($vol|Measure-Object -Average).Average
    $c=$s[-1]; $spread=$c.high-$c.low
    $avgSpread=($s|ForEach-Object{$_.high-$_.low}|Measure-Object -Average).Average
    $closePos=if($spread-gt0){($c.close-$c.low)/$spread}else{0.5}
    if ($c.volume-gt$avgVol*2-and$spread-gt$avgSpread*1.5-and$closePos-lt0.3){return "WYCKOFF-BC(topo-dist)"}
    if ($c.volume-gt$avgVol*2-and$spread-gt$avgSpread*1.5-and$closePos-gt0.7){return "WYCKOFF-SC(fundo-rev)"}
    return "NONE"
}

function Get-WeinsteinPhase($candles) {
    $closes=$candles|ForEach-Object{$_.close}; $n=$closes.Count
    if ($n-lt30){return "?"}
    $ma30=Get-EMA $closes 30
    $ma30p=Get-EMA ($closes|Select-Object -First ($n-5)) 30
    $last=$closes[-1]
    $maTrend=if($ma30-gt$ma30p*1.002){"UP"}elseif($ma30-lt$ma30p*0.998){"DOWN"}else{"FLAT"}
    $above=($last-gt$ma30)
    if ($above-and$maTrend-eq"UP"){return "FASE2(alta)"}
    if (-not$above-and$maTrend-eq"DOWN"){return "FASE4(baixa)"}
    if ($above-and$maTrend-eq"FLAT"){return "FASE3(dist)"}
    if (-not$above-and$maTrend-eq"FLAT"){return "FASE1(acum)"}
    return "TRANSICAO"
}

# ── Killzones ICT (horarios de liquidez institucional) ───────────────────────
# Ref: WYCKOFF_SMC.md — London Open 07-09 UTC, NY Open 12-14 UTC

function Get-Killzone() {
    $utcH = [DateTime]::UtcNow.Hour
    $utcM = [DateTime]::UtcNow.Minute
    $utcDec = $utcH + $utcM/60.0
    if ($utcDec -ge 7  -and $utcDec -lt 9)  { return "LONDON-OPEN(alta-vol)" }
    if ($utcDec -ge 12 -and $utcDec -lt 14) { return "NY-OPEN(maior-vol-dia)" }
    if ($utcDec -ge 16 -and $utcDec -lt 17) { return "LONDON-CLOSE(reversao-freq)" }
    if ($utcDec -ge 21 -and $utcDec -lt 22) { return "NY-CLOSE(fechamento)" }
    if ($utcDec -ge 0  -and $utcDec -lt 4)  { return "ASIA(range-baixo-vol)" }
    return "FORA-KILLZONE"
}

# ── Fair Value Gap / Imbalance (SMC/ICT) ─────────────────────────────────────
# Ref: WYCKOFF_SMC.md — 3 candles: gap entre max[i-2] e min[i] = imbalance
# Preco tende a preencher o FVG antes de continuar

function Detect-FVG($candles) {
    $n = $candles.Count; if ($n -lt 3) { return "NONE" }
    $fvgs = @()
    for ($i = 2; $i -lt [math]::Min($n, 10); $i++) {
        $c0 = $candles[$n-$i-1]; $c2 = $candles[$n-$i+1]
        # FVG Bullish: min do candle atual > max do candle 2 posicoes atras
        if ($c2.low -gt $c0.high) {
            $fvgs += [PSCustomObject]@{ type="FVG-BULL"; upper=$c2.low; lower=$c0.high; age=$i }
        }
        # FVG Bearish: max do candle atual < min do candle 2 posicoes atras
        if ($c2.high -lt $c0.low) {
            $fvgs += [PSCustomObject]@{ type="FVG-BEAR"; upper=$c0.low; lower=$c2.high; age=$i }
        }
    }
    if ($fvgs.Count -eq 0) { return "NONE" }
    $nearest = $fvgs | Sort-Object age | Select-Object -First 1
    $last = $candles[-1].close
    $filled = ($last -ge $nearest.lower -and $last -le $nearest.upper)
    $status = if ($filled) { "DENTRO(preenchendo)" } else { "ABERTO" }
    return ($nearest.type + " " + [math]::Round($nearest.lower,4) + "-" + [math]::Round($nearest.upper,4) + " " + $status)
}

# ── BOS / CHoCH (SMC — Break of Structure / Change of Character) ─────────────
# Ref: WYCKOFF_SMC.md
# BOS = confirmacao de tendencia | CHoCH = primeiro sinal de reversao

function Detect-BOS-CHoCH($candles) {
    $n = $candles.Count; if ($n -lt 6) { return "INDEFINIDO" }
    $s = $candles | Select-Object -Last 10
    $highs = $s | ForEach-Object { $_.high }
    $lows  = $s | ForEach-Object { $_.low }
    $last  = $candles[-1].close
    $prevHH = ($highs | Select-Object -First ($highs.Count-2) | Measure-Object -Maximum).Maximum
    $prevLL = ($lows  | Select-Object -First ($lows.Count-2)  | Measure-Object -Minimum).Minimum
    # BOS Bearish: preco quebra o ultimo fundo com fechamento
    if ($last -lt $prevLL) { return "BOS-BEAR(continuacao-queda)" }
    # CHoCH Bullish: preco quebra o ultimo topo em downtrend
    $structure = if (($highs[-1] -lt $highs[-3]) -and ($lows[-1] -lt $lows[-3])) { "DOWN" } else { "UP" }
    if ($structure -eq "DOWN" -and $last -gt $prevHH) { return "CHoCH-BULL(reversao-possivel)" }
    if ($structure -eq "UP"   -and $last -lt $prevLL) { return "CHoCH-BEAR(reversao-possivel)" }
    return "TENDENCIA-INTACTA"
}

# ── Liquidity Sweep (ICT) ─────────────────────────────────────────────────────
# Ref: WYCKOFF_SMC.md — Equal Lows/Highs varridos antes de reversao

function Detect-LiquiditySweep($candles) {
    $n = $candles.Count; if ($n -lt 5) { return "NONE" }
    $s = $candles | Select-Object -Last 10
    $highs = $s | ForEach-Object { $_.high }
    $lows  = $s | ForEach-Object { $_.low }
    $lastC = $candles[-1]
    # Equal Lows: 2+ fundos proximos (tolerancia 0.1%)
    $prevLows = $lows | Select-Object -SkipLast 1
    $equalLows = $prevLows | Where-Object { [math]::Abs($_ - $prevLows[-1]) / $prevLows[-1] -lt 0.001 }
    # Se ultimo candle tocou abaixo de equal lows mas fechou acima = sweep bullish
    if ($equalLows.Count -ge 1) {
        $eqLow = ($equalLows | Measure-Object -Minimum).Minimum
        if ($lastC.low -lt $eqLow -and $lastC.close -gt $eqLow) {
            return ("SSL-SWEEP(stop-hunt-bulls-reversao-possivel) @ " + [math]::Round($eqLow,4))
        }
    }
    # Equal Highs: sweep de sell-side (perigoso para short)
    $prevHighs = $highs | Select-Object -SkipLast 1
    $equalHighs = $prevHighs | Where-Object { [math]::Abs($_ - $prevHighs[-1]) / $prevHighs[-1] -lt 0.001 }
    if ($equalHighs.Count -ge 1) {
        $eqHigh = ($equalHighs | Measure-Object -Maximum).Maximum
        if ($lastC.high -gt $eqHigh -and $lastC.close -lt $eqHigh) {
            return ("BSL-SWEEP(stop-hunt-shorts-PERIGO-SHORT) @ " + [math]::Round($eqHigh,4))
        }
    }
    return "NONE"
}

# ── Mini analise para o loop principal ───────────────────────────────────────

function Get-MiniAnalysis($mkt) {
    try {
        $c1h = Get-Candles $mkt "1hour" 60
        $c4h = Get-Candles $mkt "4hour" 40
        $cl1h = $c1h|ForEach-Object{$_.close}
        $cl4h = $c4h|ForEach-Object{$_.close}

        $e9_1h  = [math]::Round((Get-EMA $cl1h 9),  4)
        $e21_1h = [math]::Round((Get-EMA $cl1h 21), 4)
        $e50_1h = [math]::Round((Get-EMA $cl1h 50), 4)
        $rsi_1h = [math]::Round((Get-RSI $cl1h),    1)
        $atr_1h = [math]::Round((Get-ATR $c1h),     5)
        $fib_1h = Get-FibLevels $c1h 30
        $wck_1h = Get-WyckoffSignal $c1h

        $e9_4h  = [math]::Round((Get-EMA $cl4h 9),  4)
        $e21_4h = [math]::Round((Get-EMA $cl4h 21), 4)
        $rsi_4h = [math]::Round((Get-RSI $cl4h),    1)
        $w4h    = Get-WeinsteinPhase $c4h

        $trend1h  = if ($e9_1h-lt$e21_1h){"DOWN"}else{"UP"}
        $trend4h  = if ($e9_4h-lt$e21_4h){"DOWN"}else{"UP"}
        $shortFav = ($trend1h-eq"DOWN"-and$rsi_1h-lt60)
        $kz       = Get-Killzone
        $fvg      = Detect-FVG $c1h
        $bos      = Detect-BOS-CHoCH $c1h
        $sweep    = Detect-LiquiditySweep $c1h

        return [PSCustomObject]@{
            trend1h=$trend1h; trend4h=$trend4h; rsi1h=$rsi_1h; rsi4h=$rsi_4h
            atr1h=$atr_1h; fib=$fib_1h; wyckoff=$wck_1h; weinstein=$w4h
            shortFavoravel=$shortFav; e50_1h=$e50_1h
            killzone=$kz; fvg=$fvg; bos=$bos; sweep=$sweep
        }
    } catch { return $null }
}

# ── Stop Update (create first, then cancel) ──────────────────────────────────

function Update-Stop($newStop) {
    $newStr = [math]::Round($newStop, 4).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $create = Invoke-CoinExPost "/v2/futures/stop-order" @{
        market="$market"; market_type="FUTURES"; side="buy"; type="market"
        amount="$amount"; trigger_price=$newStr; trigger_price_type="mark_price"
    }
    if ($create.code -ne 0) { Log ("ERRO stop: " + $create.message); return $false }
    $newId = $create.data.stop_id
    Log ("Novo stop: ID=" + $newId + " preco=" + $newStr)
    $cancel = Remove-StopOrder $script:stopId
    if ($cancel.code -eq 0) { Log ("Cancelado: ID=" + $script:stopId) }
    else { Log ("Aviso cancel: " + $cancel.message) }
    $script:stopId = $newId
    return $true
}

# ── Inicio ───────────────────────────────────────────────────────────────────

Log "=============================="
Log " TRAILING SHORT + TECHAGENT"
Log (" Entrada: " + $entryPrice + " | Stop: " + $currentStop + " | ID: " + $script:stopId)
Log " Trail: 3% acima do minimo"
Log " Fib: alvos automaticos ativados"
Log "=============================="

$lastAnalysisTime = [DateTime]::MinValue

while ($true) {
    try {
        # ── Ticker ──
        $ticker = Invoke-RestMethod -Uri "https://api.coinex.com/v2/futures/ticker?market=$market" -Method GET
        $mark   = [double]$ticker.data[0].mark_price
        $last   = [double]$ticker.data[0].last

        # ── Verifica stop ativo ──
        $stops = Get-ActiveStops
        if ($stops.data.Count -eq 0) {
            Log "NENHUM STOP ATIVO - posicao pode ter fechado"
            break
        }

        # ── PnL ──
        $pnl    = [math]::Round(($entryPrice - $mark) * [double]$amount, 2)
        $pnlPct = [math]::Round(($entryPrice - $mark) / $entryPrice * 100, 2)

        # ── Atualiza minima ──
        if ($mark -lt $lowestPrice) { $lowestPrice = $mark }
        $newStop = [math]::Round($lowestPrice * (1 + $trailPct), 4)

        # ── TechAgent (a cada analysisSecs) ──
        $runAnalysis = ([DateTime]::Now - $lastAnalysisTime).TotalSeconds -ge $analysisSecs
        if ($runAnalysis) {
            $ta = Get-MiniAnalysis $market
            $lastAnalysisTime = [DateTime]::Now
            if ($ta) {
                Log ("--- TECHAGENT ---")
                Log ("  Killzone: " + $ta.killzone)
                Log ("  1H: " + $ta.trend1h + " EMA50=" + $ta.e50_1h + " RSI=" + $ta.rsi1h + " ATR=" + $ta.atr1h)
                Log ("  4H: " + $ta.trend4h + " Weinstein=" + $ta.weinstein + " RSI=" + $ta.rsi4h)
                Log ("  Wyckoff: " + $ta.wyckoff + " | Short favoravel: " + $ta.shortFavoravel)
                Log ("  SMC: BOS/CHoCH=" + $ta.bos + " | FVG=" + $ta.fvg)
                Log ("  Sweep: " + $ta.sweep)
                Log ("  Fib alvos: ext127=" + $ta.fib.ext127 + " ext161=" + $ta.fib.ext161)
                Log ("  Fib resist: 38%=" + $ta.fib.f382 + " 50%=" + $ta.fib.f500 + " 61.8%=" + $ta.fib.f618)
                Log ("  Stop ATR sugerido (2x): " + [math]::Round($ta.atr1h*2,4))

                # ── Alertas baseados em Fibonacci ──
                # Extensoes sao alvos para o short
                if ($mark -le $ta.fib.ext127 + 0.005) {
                    Log ("*** FIB ALVO 127% ATINGIDO (" + $ta.fib.ext127 + ") - considere tightening stop ***")
                }
                if ($mark -le $ta.fib.ext161 + 0.005) {
                    Log ("*** FIB ALVO 161.8% ATINGIDO (" + $ta.fib.ext161 + ") - zona de exaustao ***")
                }

                # Retracements sao resistencias para o short — alerta se preco se aproxima
                $distF382 = [math]::Round(($ta.fib.f382 - $mark) / $mark * 100, 2)
                if ($distF382 -gt 0 -and $distF382 -lt 1.5) {
                    Log ("ATENCAO: Preco a " + $distF382 + "% da resistencia Fib 38.2% (" + $ta.fib.f382 + ")")
                }

                # Killzone — aumenta atenção em horários de alta liquidez
                if ($ta.killzone -like "*OPEN*") {
                    Log ("*** KILLZONE ATIVA: " + $ta.killzone + " - movimentos direcionais esperados ***")
                }

                # BSL Sweep = stop hunt nos shorts = PERIGO IMEDIATO
                if ($ta.sweep -like "*BSL*") {
                    Log ("!!! BSL SWEEP DETECTADO: smart money varrendo stops de shorts - RISCO ALTO !!!")
                    Log ("    " + $ta.sweep)
                }

                # CHoCH = primeiro sinal de reversao da queda
                if ($ta.bos -like "*CHoCH-BULL*") {
                    Log ("*** CHoCH BULLISH: estrutura mudando - short pode estar terminando ***")
                }

                # FVG aberto acima do preco = magnete para subida (resistencia para short)
                if ($ta.fvg -like "*FVG-BULL*" -and $ta.fvg -like "*ABERTO*") {
                    Log ("ATENCAO FVG-BULL aberto: imbalance acima atrai preco - resistencia para short")
                }

                # Wyckoff: Buying Climax = perigoso para short (reversao)
                if ($ta.wyckoff -like "*SC*") {
                    Log ("WYCKOFF SELLING CLIMAX: possivel fundo - avaliar saida do short")
                }
                if ($ta.wyckoff -like "*BC*") {
                    Log ("WYCKOFF BUYING CLIMAX: possivel topo - short favorecido")
                }

                # Weinstein Fase 2 no 4H = tendencia macro contra o short
                if ($ta.weinstein -like "*FASE2*") {
                    Log ("WEINSTEIN FASE2 no 4H: tendencia macro de ALTA - short apenas intraday")
                }
            }
        }

        # ── Trail ou Log ──
        if ($newStop -lt $currentStop) {
            $ok = Update-Stop $newStop
            if ($ok) {
                Log ("STOP DESCEU " + $currentStop + " -> " + $newStop + " | Min=" + $lowestPrice + " | PnL=" + $pnl + " (" + $pnlPct + "%)")
                $currentStop = $newStop
            }
        } else {
            Log ("Mark=" + $last + " Min=" + $lowestPrice + " Stop=" + $currentStop + " PnL=" + $pnl + " (" + $pnlPct + "%)")
        }

        # ── Stop atingido ──
        if ($mark -ge $currentStop) {
            Log "!! STOP ATINGIDO !!"
            Start-Sleep -Seconds 5
            break
        }

    } catch {
        Log ("ERRO: " + $_.Exception.Message)
    }

    Start-Sleep -Seconds $checkSecs
}

Log "TRAILING SHORT ENCERRADO"
