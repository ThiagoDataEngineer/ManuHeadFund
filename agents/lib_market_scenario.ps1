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

function Resolve-MarketScenario {
    <#
      Classifica o cenario e diz a estrategia com edge. Ordem de prioridade:
        1) CAPITULACAO (fundo)  -> allow_long  (acumula)
        2) BEAR (sem capit.)    -> allow_short (SHORT/caixa)
        3) BULL                 -> allow_long
        4) NEUTRO (chop)        -> espera (nada)
      Fail-safe: dados invalidos -> UNKNOWN, allow_long=true (nao trava por dado ruim).
    #>
    param(
        [double]$Price, [double]$Ema20, [double]$Ema50, [double]$Ema200,
        [double]$Rsi, [double]$Momentum30dPct, [double]$VolRatio
    )
    if ($Price -le 0 -or $Ema20 -le 0 -or $Ema50 -le 0) {
        return [pscustomobject]@{ scenario="UNKNOWN"; strategy="cautela"; allow_long=$true; allow_short=$false; reason="dados_invalidos" }
    }

    $cap = Test-Capitulation -Rsi $Rsi -VolRatio $VolRatio -Price $Price -Ema200 $Ema200
    if ($cap.is_capitulation) {
        return [pscustomobject]@{ scenario="CAPITULACAO"; strategy="acumula_long_fundo"; allow_long=$true; allow_short=$false; reason=$cap.reason }
    }

    $bear = ($Price -lt $Ema20) -and ($Price -lt $Ema50) -and ($Momentum30dPct -lt 0)
    if ($bear) {
        return [pscustomobject]@{ scenario="BEAR"; strategy="short_ou_caixa"; allow_long=$false; allow_short=$true; reason="abaixo EMA20+50, mom ${Momentum30dPct}%" }
    }

    $bull = ($Price -gt $Ema20) -and ($Momentum30dPct -gt 0)
    if ($bull) {
        return [pscustomobject]@{ scenario="BULL"; strategy="long"; allow_long=$true; allow_short=$false; reason="acima EMA20, mom ${Momentum30dPct}%" }
    }

    return [pscustomobject]@{ scenario="NEUTRO"; strategy="espera"; allow_long=$false; allow_short=$false; reason="chop sem direcao" }
}

# Wire I/O: busca indicadores BTC e resolve cenario (cache 10min).
$script:__scenCache = $null; $script:__scenCacheAt = [datetime]::MinValue
function Get-MarketScenario {
    param([int]$CacheMinutes = 10)
    try {
        if ($script:__scenCache -and ((Get-Date) - $script:__scenCacheAt).TotalMinutes -lt $CacheMinutes) { return $script:__scenCache }
        $r = Invoke-RestMethod "https://api.coinex.com/v2/futures/kline?market=BTCUSDT&period=1day&limit=60" -TimeoutSec 12 -ErrorAction Stop
        $cs = @($r.data | ForEach-Object { [pscustomobject]@{ c=[double]$_.close; v=[double]$_.volume } })
        $closes = @($cs | ForEach-Object { $_.c })
        if ($closes.Count -lt 31) { return (Resolve-MarketScenario -Price 0 -Ema20 0 -Ema50 0 -Ema200 0 -Rsi 0 -Momentum30dPct 0 -VolRatio 0) }
        $price=$closes[-1]
        $k20=2/21.0;$e20=$closes[0];foreach($c in $closes[1..($closes.Count-1)]){$e20=$c*$k20+$e20*(1-$k20)}
        $k50=2/51.0;$e50=$closes[0];foreach($c in $closes[1..($closes.Count-1)]){$e50=$c*$k50+$e50*(1-$k50)}
        $e200=($closes|Measure-Object -Average).Average  # proxy (60 candles); aproxima EMA200
        $g=0;$l=0;for($i=$closes.Count-14;$i -lt $closes.Count;$i++){$d=$closes[$i]-$closes[$i-1];if($d -gt 0){$g+=$d}else{$l+=[math]::Abs($d)}}
        $rsi=if($l -eq 0){100}else{[math]::Round(100-100/(1+($g/14)/($l/14)),1)}
        $mom30=($price-$closes[-31])/$closes[-31]*100
        $vols=@($cs|ForEach-Object{$_.v}); $v20=($vols[($vols.Count-20)..($vols.Count-1)]|Measure-Object -Average).Average; $v3=($vols[($vols.Count-3)..($vols.Count-1)]|Measure-Object -Average).Average
        $volRatio=if($v20 -gt 0){[math]::Round($v3/$v20,2)}else{1}
        $sc = Resolve-MarketScenario -Price $price -Ema20 $e20 -Ema50 $e50 -Ema200 $e200 -Rsi $rsi -Momentum30dPct $mom30 -VolRatio $volRatio
        $script:__scenCache=$sc; $script:__scenCacheAt=(Get-Date)
        return $sc
    } catch {
        return [pscustomobject]@{ scenario="UNKNOWN"; strategy="cautela"; allow_long=$true; allow_short=$false; reason="fetch_falhou" }
    }
}
