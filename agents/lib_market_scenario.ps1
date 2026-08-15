# lib_market_scenario.ps1 -- Motor de CENARIO (2026-06-24)
#
# "Sempre ganhar" = identificar o cenario e aplicar a estrategia com EDGE:
#   CAPITULACAO -> comprar o fundo (LONG)   | BEAR  -> SHORT / caixa
#   BULL        -> LONG                       | NEUTRO-> esperar (sem edge)
# Ancorado em BEAR_MARKET.md (Fase 3 = capitulacao: volume extremo + RSI extremo)
# e Weinstein (estagios). PURO, zero LLM, fail-safe. Complementa lib_btc_regime_gate.

function Test-Capitulation {
    <#
      Detecta o FUNDO (Fase 3): RSI extremo oversold + volume CLIMATICO + queda profunda
      (abaixo da EMA200 = bear de verdade, nao pullback). Retorna { is_capitulation, reason }.
    #>
    param(
        [double]$Rsi,
        [double]$VolRatio,        # volume 3d / volume 20d
        [double]$Price,
        [double]$Ema200,
        [double]$RsiMax = 30,     # RSI <= 30 = oversold extremo
        [double]$VolMin = 1.8     # volume >= 1.8x = climax
    )
    if ($Price -le 0 -or $Ema200 -le 0) { return [pscustomobject]@{ is_capitulation=$false; reason="dados_invalidos" } }
    $oversold = ($Rsi -gt 0 -and $Rsi -le $RsiMax)
    $climax   = ($VolRatio -ge $VolMin)
    $deepBear = ($Price -lt $Ema200)
    if ($oversold -and $climax -and $deepBear) {
        return [pscustomobject]@{ is_capitulation=$true; reason="RSI $Rsi + vol ${VolRatio}x + abaixo EMA200" }
    }
    return [pscustomobject]@{ is_capitulation=$false; reason="sem climax (rsi=$Rsi vol=$VolRatio)" }
}

function Test-Euphoria {
    <#
      Detecta o TOPO (espelho de Test-Capitulation): RSI extremo overbought +
      volume CLIMATICO + preco ESTICADO acima da EMA200 (nao so acima dela --
      qualquer BULL saudavel fica acima da 200; euforia exige distancia real,
      caso contrario qualquer alta normal disparava falso positivo).

      Achado real (2026-08-14, owner pediu investigar SHORT no topo do
      ACEUSDT antes do crash de -31%): Test-PumpDumpGate ja liberava SHORT
      nesse momento (reaccumulation), mas Resolve-MarketScenario bloqueava
      sempre via BULL puro -- essa funcao fecha essa lacuna sem tocar na
      logica de BEAR/BULL/NEUTRO existente.
    #>
    param(
        [double]$Rsi,
        [double]$VolRatio,        # volume 3d / volume 20d
        [double]$Price,
        [double]$Ema200,
        [double]$RsiMin = 70,      # RSI >= 70 = overbought extremo
        [double]$VolMin = 1.8,     # volume >= 1.8x = climax
        [double]$StretchMinPct = 15.0  # preco >= 15% acima da EMA200 = esticado
    )
    if ($Price -le 0 -or $Ema200 -le 0) { return [pscustomobject]@{ is_euphoria=$false; reason="dados_invalidos" } }
    $overbought = ($Rsi -ge $RsiMin)
    $climax     = ($VolRatio -ge $VolMin)
    $stretchPct = (($Price - $Ema200) / $Ema200) * 100
    $stretched  = ($stretchPct -ge $StretchMinPct)
    if ($overbought -and $climax -and $stretched) {
        return [pscustomobject]@{ is_euphoria=$true; reason="RSI $Rsi + vol ${VolRatio}x + ${stretchPct}% acima EMA200" }
    }
    return [pscustomobject]@{ is_euphoria=$false; reason="sem climax de topo (rsi=$Rsi vol=$VolRatio stretch=${stretchPct}%)" }
}

function Resolve-MarketScenario {
    <#
      Classifica o cenario e diz a estrategia com edge. Ordem de prioridade:
        1) CAPITULACAO (fundo)  -> allow_long  (acumula)
        2) EUFORIA (topo)       -> allow_short (vende o topo esticado)
        3) BEAR (sem capit.)    -> allow_short (SHORT/caixa)
        4) BULL                 -> allow_long
        5) NEUTRO (chop)        -> espera (nada)
      Fail-safe: dados invalidos -> UNKNOWN, allow_long=true (nao trava por dado ruim).

      2026-08-14: EUFORIA adicionada (espelho de CAPITULACAO) -- achado real
      (ACEUSDT, pico 08-14 22h, RSI~95/vol 5.25x/momentum 150%, crash -31%
      na hora seguinte) mostrou que BULL bloqueava SHORT incondicionalmente
      mesmo com exaustao extrema medida, enquanto Test-PumpDumpGate ja
      liberava SHORT no mesmo momento (reaccumulation). Checada ANTES de
      BEAR/BULL pelo mesmo motivo que CAPITULACAO -- extremos tem prioridade
      sobre a leitura generica de tendencia.
    #>
    param(
        [double]$Price, [double]$Ema20, [double]$Ema50, [double]$Ema200,
        [double]$Rsi, [double]$Momentum30dPct, [double]$VolRatio
    )
    if ($Price -le 0 -or $Ema20 -le 0 -or $Ema50 -le 0) {
        return [pscustomobject]@{ scenario="UNKNOWN"; strategy="cautela"; allow_long=$true; allow_short=$false; reason="dados_invalidos"; momentum_30d=$Momentum30dPct }
    }

    $cap = Test-Capitulation -Rsi $Rsi -VolRatio $VolRatio -Price $Price -Ema200 $Ema200
    if ($cap.is_capitulation) {
        return [pscustomobject]@{ scenario="CAPITULACAO"; strategy="acumula_long_fundo"; allow_long=$true; allow_short=$false; reason=$cap.reason; momentum_30d=$Momentum30dPct }
    }

    $euph = Test-Euphoria -Rsi $Rsi -VolRatio $VolRatio -Price $Price -Ema200 $Ema200
    if ($euph.is_euphoria) {
        return [pscustomobject]@{ scenario="EUFORIA"; strategy="vende_topo_esticado"; allow_long=$false; allow_short=$true; reason=$euph.reason; momentum_30d=$Momentum30dPct }
    }

    $bear = ($Price -lt $Ema20) -and ($Price -lt $Ema50) -and ($Momentum30dPct -lt 0)
    if ($bear) {
        return [pscustomobject]@{ scenario="BEAR"; strategy="short_ou_caixa"; allow_long=$false; allow_short=$true; reason="abaixo EMA20+50, mom ${Momentum30dPct}%"; momentum_30d=$Momentum30dPct }
    }

    # 2026-07-23 FIX: Ema200 chegava como parametro mas nunca era usado aqui --
    # BTC podia estar 10%+ abaixo da SMA200 (bear estrutural real, Fase 4
    # Weinstein) e ainda classificar BULL so por um bounce de curto prazo acima
    # da EMA20 com momentum 30d positivo (confirmado ao vivo 2026-07-23: preco
    # $65074, EMA20 $64330, SMA200 $72593, dist_sma=-10.36%, mom30d=+3.74% ->
    # BULL). Isso liberava o TORI LONG sweep gerando candidatos LONG que o
    # TechAgent (LLM, ve 1W/1D completo) rejeitava com SHORT forte, travando
    # tudo no Quality Gate (direction_contradiction) -- sintoma pratico: SPOT
    # nunca abria. Fix: BULL agora exige tambem estar acima da SMA200 (com
    # folga de -5%, pra nao travar por ruido de dia-a-dia bem perto da linha).
    $aboveSma200 = ($Ema200 -le 0) -or (($Price - $Ema200) / $Ema200 -gt -0.05)
    $bull = ($Price -gt $Ema20) -and ($Momentum30dPct -gt 0) -and $aboveSma200
    if ($bull) {
        return [pscustomobject]@{ scenario="BULL"; strategy="long"; allow_long=$true; allow_short=$false; reason="acima EMA20, mom ${Momentum30dPct}%"; momentum_30d=$Momentum30dPct }
    }

    return [pscustomobject]@{ scenario="NEUTRO"; strategy="espera"; allow_long=$false; allow_short=$false; reason="chop sem direcao"; momentum_30d=$Momentum30dPct }
}

# Wire I/O: busca indicadores BTC e resolve cenario (cache 10min).
$script:__scenCache = $null; $script:__scenCacheAt = [datetime]::MinValue
function Get-MarketScenario {
    param([int]$CacheMinutes = 10)
    try {
        if ($script:__scenCache -and ((Get-Date) - $script:__scenCacheAt).TotalMinutes -lt $CacheMinutes) { return $script:__scenCache }
        # 2026-07-15 fix: 60 -> 250 candles. O proxy antigo (media simples de 60)
        # dizia dist=-2.5% quando a SMA200 REAL dava -12.2% (medido ao vivo em
        # 2026-07-15 01:55 UTC) -- distorcia bear_severity e a fronteira
        # BULL/NEUTRO/CAPITULACAO. 250 candles = SMA200 verdadeira + folga.
        $r = Invoke-RestMethod "https://api.coinex.com/v2/futures/kline?market=BTCUSDT&period=1day&limit=250" -TimeoutSec 12 -ErrorAction Stop
        $cs = @($r.data | ForEach-Object { [pscustomobject]@{ c=[double]$_.close; v=[double]$_.volume } })
        $closes = @($cs | ForEach-Object { $_.c })
        if ($closes.Count -lt 31) { return (Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 0 -Momentum30dPct 0 -VolRatio 0) }
        $price=$closes[-1]
        $k20=2/21.0;$e20=$closes[0];foreach($c in $closes[1..($closes.Count-1)]){$e20=$c*$k20+$e20*(1-$k20)}
        $k50=2/51.0;$e50=$closes[0];foreach($c in $closes[1..($closes.Count-1)]){$e50=$c*$k50+$e50*(1-$k50)}
        # SMA200 real quando ha 200+ candles; senao media do que houver (fallback
        # gracioso p/ mercados novos -- BTCUSDT sempre tem 250).
        $smaWin=[math]::Min(200,$closes.Count)
        $e200=($closes[($closes.Count-$smaWin)..($closes.Count-1)]|Measure-Object -Average).Average
        $g=0;$l=0;for($i=$closes.Count-14;$i -lt $closes.Count;$i++){$d=$closes[$i]-$closes[$i-1];if($d -gt 0){$g+=$d}else{$l+=[math]::Abs($d)}}
        $rsi=if($l -eq 0){100}else{[math]::Round(100-100/(1+($g/14)/($l/14)),1)}
        $mom30=($price-$closes[-31])/$closes[-31]*100
        $vols=@($cs|ForEach-Object{$_.v}); $v20=($vols[($vols.Count-20)..($vols.Count-1)]|Measure-Object -Average).Average; $v3=($vols[($vols.Count-3)..($vols.Count-1)]|Measure-Object -Average).Average
        $volRatio=if($v20 -gt 0){[math]::Round($v3/$v20,2)}else{1}
        $sc = Resolve-MarketScenario -Price $price -Ema20 $e20 -Ema50 $e50 -Ema200 $e200 -Rsi $rsi -Momentum30dPct $mom30 -VolRatio $volRatio

        # 2026-07-14: bear_severity (WEAK/STRONG/NONE) -- mesma formula de
        # backtest/regime_change_monitor.py:45-50 (dist=SMA200, mom20=20d),
        # replicada aqui pra nao depender de $global:CURRENT_REGIME (nunca
        # atribuido em producao) nem de journal/regime_state.json (gitignored,
        # inacessivel no runner efemero da nuvem). 2026-07-15: e200 agora e
        # SMA200 REAL (250 candles), mesma janela do monitor original.
        $mom20 = if ($closes.Count -ge 21 -and $closes[-21] -gt 0) { ($price - $closes[-21]) / $closes[-21] } else { 0 }
        $distSma = if ($e200 -gt 0) { ($price - $e200) / $e200 } else { 0 }
        $bearSeverity = "NONE"
        if ($distSma -lt -0.20 -and $mom20 -lt -0.10) { $bearSeverity = "STRONG" }
        elseif ($distSma -lt 0 -and $mom20 -lt 0) { $bearSeverity = "WEAK" }
        $sc | Add-Member -MemberType NoteProperty -Name "mom20" -Value ([math]::Round($mom20*100,2)) -Force
        $sc | Add-Member -MemberType NoteProperty -Name "dist_sma" -Value ([math]::Round($distSma*100,2)) -Force
        $sc | Add-Member -MemberType NoteProperty -Name "bear_severity" -Value $bearSeverity -Force

        $script:__scenCache=$sc; $script:__scenCacheAt=(Get-Date)
        return $sc
    } catch {
        return [pscustomobject]@{ scenario="UNKNOWN"; strategy="cautela"; allow_long=$true; allow_short=$false; reason="fetch_falhou" }
    }
}
