# lib_triple_barrier_backtest.ps1 -- Backtest REAL (2026-06-24)
#
# Substitui o backtest FAKE (backtest_regime_l_s.ps1 estimava pnl do score com formula
# inventada -> "SHORT +3.2% EV" nunca foi real). Aqui: triple-barrier de Lopez de Prado
# no caminho de preco REAL. Anti-overfit: effective_n = dias distintos (nao trades).
# PURO, testavel. O runner (Invoke-ScenarioBacktest) usa candles reais da CoinEx.

function Invoke-TripleBarrier {
    <#
      Simula uma entrada ate bater stop, alvo ou timeout, no caminho de preco real.
      Bars: sequencia FORWARD a partir da entrada, cada { h, l, c }.
      SHORT: stop ACIMA (h>=stop=loss), alvo ABAIXO (l<=target=win).
      LONG : stop ABAIXO (l<=stop=loss), alvo ACIMA (h>=target=win).
      Retorna { outcome(target|stop|timeout), exit_price, pnl_pct, bars_held }.
    #>
    param(
        [array]$Bars,
        [double]$Entry,
        [double]$Stop,
        [double]$Target,
        [string]$Direction = "SHORT"
    )
    $isShort = ("$Direction".ToUpper() -eq "SHORT")
    $i = 0
    foreach ($b in @($Bars)) {
        $i++
        $h = [double]$b.h; $l = [double]$b.l
        if ($isShort) {
            $hitStop   = ($h -ge $Stop)
            $hitTarget = ($l -le $Target)
        } else {
            $hitStop   = ($l -le $Stop)
            $hitTarget = ($h -ge $Target)
        }
        # se ambos na mesma barra, conservador: assume STOP primeiro (pior caso)
        if ($hitStop) {
            $pnl = if ($isShort) { ($Entry - $Stop) / $Entry * 100 } else { ($Stop - $Entry) / $Entry * 100 }
            return [pscustomobject]@{ outcome="stop"; exit_price=$Stop; pnl_pct=[math]::Round($pnl,3); bars_held=$i }
        }
        if ($hitTarget) {
            $pnl = if ($isShort) { ($Entry - $Target) / $Entry * 100 } else { ($Target - $Entry) / $Entry * 100 }
            return [pscustomobject]@{ outcome="target"; exit_price=$Target; pnl_pct=[math]::Round($pnl,3); bars_held=$i }
        }
    }
    # timeout: sai no ultimo close
    $exit = if (@($Bars).Count) { [double]$Bars[-1].c } else { $Entry }
    $pnl = if ($isShort) { ($Entry - $exit) / $Entry * 100 } else { ($exit - $Entry) / $Entry * 100 }
    return [pscustomobject]@{ outcome="timeout"; exit_price=$exit; pnl_pct=[math]::Round($pnl,3); bars_held=@($Bars).Count }
}

function Measure-BacktestEdge {
    <#
      Agrega trades com controle anti-overfit: effective_n = DIAS distintos (nao trades),
      pra nao inflar significancia com cluster de trades no mesmo dia (Branch A finding).
      Retorna { n_trades, effective_n, win_rate, avg_pnl_pct, total_pnl_pct, expectancy }.
    #>
    param([array]$Trades)
    $n = @($Trades).Count
    if ($n -eq 0) {
        return [pscustomobject]@{ n_trades=0; effective_n=0; win_rate=0; avg_pnl_pct=0; total_pnl_pct=0; expectancy=0 }
    }
    $wins = @($Trades | Where-Object { $_.win }).Count
    $pnls = @($Trades | ForEach-Object { [double]$_.pnl_pct })
    $days = @($Trades | ForEach-Object { "$($_.date)" } | Sort-Object -Unique).Count
    $avg = ($pnls | Measure-Object -Average).Average
    return [pscustomobject]@{
        n_trades    = $n
        effective_n = $days
        win_rate    = [math]::Round($wins / $n, 4)
        avg_pnl_pct = [math]::Round($avg, 3)
        total_pnl_pct = [math]::Round(($pnls | Measure-Object -Sum).Sum, 3)
        expectancy  = [math]::Round($avg, 3)
    }
}
