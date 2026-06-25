# lib_btc_regime_gate.ps1 -- BTC-core gate (2026-06-24)
#
# CAUSA REAL das perdas: o sistema comprou alt LONG durante BTC -20%/mes. Nosso
# BEAR_MARKET.md: em bear, alt sangra 2-4x o BTC. Regra de Ouro #7 (BTC-core) violada.
# Test-BtcRegimeGate (PURO) bloqueia LONG de alt quando BTC em downtrend confirmado.
# SHORT liberado (backtest BEAR_WEAK SHORT +3.2% EV). Fail-safe: dado ruim -> libera.

function Test-BtcRegimeGate {
    <#
      Direction       LONG|SHORT
      Price/Ema20/Ema50  do BTC daily
      Momentum30dPct  variacao % do BTC em 30d
      Retorna { allowed, reason, btc_bear }
    #>
    param(
        [string]$Direction = "LONG",
        [double]$Price,
        [double]$Ema20,
        [double]$Ema50,
        [double]$Momentum30dPct
    )
    # fail-safe: sem dados validos nao trava
    if ($Price -le 0 -or $Ema20 -le 0 -or $Ema50 -le 0) {
        return [pscustomobject]@{ allowed=$true; reason="btc_data_indisponivel"; btc_bear=$false }
    }
    # bear confirmado: abaixo de EMA20 E EMA50 E momentum 30d negativo
    $btcBear = ($Price -lt $Ema20) -and ($Price -lt $Ema50) -and ($Momentum30dPct -lt 0)
    if ($btcBear -and ("$Direction".ToUpper() -eq "LONG")) {
        return [pscustomobject]@{ allowed=$false; reason="btc_bear_blocks_long_alt"; btc_bear=$true }
    }
    return [pscustomobject]@{ allowed=$true; reason="ok"; btc_bear=$btcBear }
}

# Wire helper (I/O): busca indicadores BTC daily e roda o gate. Cache 10min p/ baratear.
$script:__btcRegimeCache = $null
$script:__btcRegimeCacheAt = [datetime]::MinValue
function Get-BtcRegimeGate {
    param([string]$Direction = "LONG", [int]$CacheMinutes = 10)
    try {
        if ($script:__btcRegimeCache -and ((Get-Date) - $script:__btcRegimeCacheAt).TotalMinutes -lt $CacheMinutes) {
            $m = $script:__btcRegimeCache
        } else {
            $r = Invoke-RestMethod "https://api.coinex.com/v2/futures/kline?market=BTCUSDT&period=1day&limit=60" -TimeoutSec 12 -ErrorAction Stop
            $closes = @($r.data | ForEach-Object { [double]$_.close })
            if ($closes.Count -lt 31) { return (Test-BtcRegimeGate -Direction $Direction -Price 0 -Ema20 0 -Ema50 0 -Momentum30dPct 0) }
            $price = $closes[-1]
            $k20=2/21.0; $e20=$closes[0]; foreach($c in $closes[1..($closes.Count-1)]){ $e20=$c*$k20+$e20*(1-$k20) }
            $k50=2/51.0; $e50=$closes[0]; foreach($c in $closes[1..($closes.Count-1)]){ $e50=$c*$k50+$e50*(1-$k50) }
            $mom30 = ($price - $closes[-31]) / $closes[-31] * 100
            $m = @{ price=$price; ema20=$e20; ema50=$e50; mom30=$mom30 }
            $script:__btcRegimeCache = $m; $script:__btcRegimeCacheAt = (Get-Date)
        }
        return Test-BtcRegimeGate -Direction $Direction -Price $m.price -Ema20 $m.ema20 -Ema50 $m.ema50 -Momentum30dPct $m.mom30
    } catch {
        return [pscustomobject]@{ allowed=$true; reason="btc_fetch_falhou"; btc_bear=$false }
    }
}
