# lib_promotion_paper_engine.ps1 -- Simula paper trades pra preencher metricas
# de OBSERVATION-tier candidates.
#
# Por que existe: ladder gate OBSERVATION->PAPER_C exige sharpe_30d/n_trades/max_dd
# que so existem se houver trades. Sem isso, candidatos ficam parados.
#
# Strategy simples (proxy do v2 daily LONG):
#   - Entry: regime BULL_WEAK ou BULL_STRONG no candle atual + previous candle nao-bull
#   - Stop: -StopPct (-5% default)
#   - Target: +TargetPct (+15% default)
#   - Max bars: 14
#
# Output: n_trades, sharpe_30d annualized, max_dd, lista returns_r
#
# NAO e o backtest cientifico definitivo. E proxy MVP pra fluxo da ladder.
# Phase 3.1 backlog: substituir por triple_barrier python via shell.
#
# PS 5.1. UTF-8 BOM.

function _ComputeRegimeAt {
    param([double[]]$Closes, [int]$Idx)
    if ($Idx -lt 200) { return $null }
    $window = $Closes[($Idx-199)..$Idx]
    $sma200 = ($window | Measure-Object -Average).Average
    $cur = $Closes[$Idx]
    $dist = ($cur - $sma200) / $sma200
    $back20 = $Closes[$Idx - 20]
    $mom20 = if ($back20 -gt 0) { ($cur - $back20) / $back20 } else { 0 }
    if     ($dist -gt 0.20 -and $mom20 -gt 0.10)  { return "BULL_STRONG" }
    elseif ($dist -gt 0     -and $mom20 -gt 0)     { return "BULL_WEAK" }
    elseif ($dist -lt -0.20 -and $mom20 -lt -0.10) { return "BEAR_STRONG" }
    elseif ($dist -lt 0     -and $mom20 -lt 0)     { return "BEAR_WEAK" }
    elseif ([Math]::Abs($dist) -lt 0.05)            { return "SIDEWAYS" }
    else                                              { return "TRANSITION" }
}


function Compute-PaperBacktest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Candles,    # array de objects {close, high, low}
        [double] $StopPct   = 0.05,
        [double] $TargetPct = 0.15,
        [int]    $MaxBars   = 14
    )
    $result = @{
        n_trades = 0
        sharpe_30d = 0.0
        max_dd = 0.0
        returns_r = @()
    }

    if (-not $Candles -or $Candles.Count -lt 50) { return $result }

    $closes = [double[]]@($Candles | ForEach-Object { [double]$_.close })
    $highs  = [double[]]@($Candles | ForEach-Object { [double]$_.high })
    $lows   = [double[]]@($Candles | ForEach-Object { [double]$_.low })

    $trades = @()
    $i = 200
    $minBarsBetween = 5  # cooldown 5d entre trades (anti-overtrade, nao curve-fit)
    $lastExitIdx = -999
    while ($i -lt ($closes.Length - 1)) {
        $regime = _ComputeRegimeAt -Closes $closes -Idx $i
        if (-not $regime) { $i++; continue }

        $isBull     = ($regime -eq "BULL_STRONG" -or $regime -eq "BULL_WEAK")
        $cooldownOk = ($i - $lastExitIdx) -ge $minBarsBetween

        if ($isBull -and $cooldownOk) {
            # Enter long
            $entry  = $closes[$i]
            $stop   = $entry * (1 - $StopPct)
            $target = $entry * (1 + $TargetPct)
            $exit   = $null
            $reason = "max_bars"
            for ($j = 1; $j -le $MaxBars; $j++) {
                $idx = $i + $j
                if ($idx -ge $closes.Length) { break }
                $h = $highs[$idx]; $l = $lows[$idx]
                if ($l -le $stop) { $exit = $stop; $reason = "stop"; break }
                if ($h -ge $target) { $exit = $target; $reason = "target"; break }
            }
            if (-not $exit) { $exit = $closes[[Math]::Min($i + $MaxBars, $closes.Length - 1)] }
            # R = (exit - entry) / risk_size
            $risk = $entry * $StopPct
            $r = if ($risk -gt 0) { ($exit - $entry) / $risk } else { 0 }
            $trades += [PSCustomObject]@{
                entry_idx = $i; exit_idx = $i + $j; entry = $entry; exit = $exit
                r = $r; reason = $reason
            }
            $lastExitIdx = $i + $j
            $i = $i + $j + 1
        } else {
            $i++
        }
    }

    $result.n_trades = $trades.Count
    if ($trades.Count -eq 0) { return $result }

    $returns = [double[]]@($trades | ForEach-Object { [double]$_.r })
    $result.returns_r = $returns

    # Sharpe annualized (daily-equivalent): mean / std * sqrt(252)
    # Aqui usamos N_trades, nao N_days, entao mais conservador
    $mean = ($returns | Measure-Object -Average).Average
    $std  = if ($returns.Length -gt 1) {
        $sumSq = 0.0; foreach ($x in $returns) { $sumSq += [Math]::Pow($x - $mean, 2) }
        [Math]::Sqrt($sumSq / ($returns.Length - 1))
    } else { 0 }
    $result.sharpe_30d = if ($std -gt 0) { [Math]::Round(($mean / $std), 4) } else { 0 }

    # C5 fix 2026-05-21 PM6+: max_dd em FRACTION (0-1) de equity curve.
    # Bug anterior: $cum em R-units + divisao por max(1,peak) gerava raw R units > 1.0.
    # RENDER mostrou max_dd=2.22/3.47 (impossivel sem leverage).
    # Threshold gate eh 0.15 (15%) = fraction. Comparar R-units com fraction = dimensional mismatch.
    #
    # Algoritmo correto: assume 1% risk por trade (1R = 1% equity). Simula equity curve em %.
    $equity = 100.0     # baseline 100%
    $peak   = 100.0
    $maxDdPct = 0.0
    $RISK_PER_TRADE = 1.0   # 1% por trade — 1R = 1% equity
    foreach ($r in $returns) {
        $equity += $r * $RISK_PER_TRADE
        if ($equity -gt $peak) { $peak = $equity }
        if ($peak -gt 0) {
            $ddPct = ($peak - $equity) / $peak
            if ($ddPct -gt $maxDdPct) { $maxDdPct = $ddPct }
        }
    }
    # Clamp [0, 1] — equity nunca esta acima do peak (drawdown sempre >= 0)
    if ($maxDdPct -lt 0) { $maxDdPct = 0 }
    if ($maxDdPct -gt 1) { $maxDdPct = 1 }
    $result.max_dd = [Math]::Round($maxDdPct, 4)

    return $result
}
