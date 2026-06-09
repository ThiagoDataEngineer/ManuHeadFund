# lib_direction_learning.ps1 -- Motor de aprendizado bidirecional (sinais -> outcome)
# 2026-06-08: aprende com o historico REAL quais vies (LONG/SHORT) e source (regime/
# bear_trap/bull_trap) funcionam em cada regime. Fecha o loop decisao->outcome.
#
# Filosofia (alinhada a Lopez de Prado / DSR / effective_n do projeto):
#   - 1 run NAO e fato. So ajusta confianca com N trades suficientes (MinTrades).
#   - Sem dados suficientes -> multiplier NEUTRO (1.0). Nunca overfita poucos trades.
#   - Zero LLM, 100% deterministico (barato).
#
# "Se nao e compra, pode ser venda": Get-BiasRecommendation pesa sinais LONG vs SHORT
# multiplicados pelo que historicamente funcionou naquele contexto.

# ─────────────────────────────────────────────────────────────────────────────
# _WinRateToMultiplier (PURA) -- converte win_rate em multiplier de conviction.
# Unificado: multiplier = clamp(0.5, 1.5, 0.5 + win_rate). win_rate 0.5 -> 1.0 neutro.
# reliable=false -> 1.0 (nao ajusta sem dados).
# ─────────────────────────────────────────────────────────────────────────────
function _WinRateToMultiplier {
    param([double]$WinRate, [bool]$Reliable)
    if (-not $Reliable) { return 1.0 }
    $m = 0.5 + $WinRate
    if ($m -lt 0.5) { $m = 0.5 }
    if ($m -gt 1.5) { $m = 1.5 }
    return [math]::Round($m, 3)
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-DirectionStats (PURA) -- agrega trades por chave "source|direction|regime".
# Input: Trades[] com {direction, source, regime, win, pnl_pct}.
# Output: array de { key, source, direction, regime, n, wins, win_rate, avg_pnl_pct,
#                    sum_pnl, reliable }
# ─────────────────────────────────────────────────────────────────────────────
function Get-DirectionStats {
    param(
        [object[]]$Trades,
        [int]$MinTrades = 8
    )
    if (-not $Trades -or @($Trades).Count -eq 0) { return @() }

    $groups = @{}
    foreach ($t in $Trades) {
        if (-not $t) { continue }
        $src = if ($t.source)    { [string]$t.source }    else { "regime" }
        $dir = if ($t.direction) { [string]$t.direction } else { "LONG" }
        $reg = if ($t.regime)    { [string]$t.regime }    else { "UNKNOWN" }
        $key = "$src|$dir|$reg"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [PSCustomObject]@{
                key=$key; source=$src; direction=$dir; regime=$reg
                n=0; wins=0; sum_pnl=0.0
            }
        }
        $g = $groups[$key]
        $g.n++
        if ([bool]$t.win) { $g.wins++ }
        if ($null -ne $t.pnl_pct) { $g.sum_pnl += [double]$t.pnl_pct }
    }

    $out = @()
    foreach ($g in $groups.Values) {
        $wr  = if ($g.n -gt 0) { [math]::Round($g.wins / $g.n, 4) } else { 0 }
        $avg = if ($g.n -gt 0) { [math]::Round($g.sum_pnl / $g.n, 4) } else { 0 }
        $out += [PSCustomObject]@{
            key=$g.key; source=$g.source; direction=$g.direction; regime=$g.regime
            n=$g.n; wins=$g.wins; win_rate=$wr; avg_pnl_pct=$avg
            sum_pnl=[math]::Round($g.sum_pnl,4); reliable=($g.n -ge $MinTrades)
        }
    }
    return $out
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-LearnedMultiplier (PURA) -- multiplier de conviction p/ (source,direction,regime).
# Sem stat confiavel -> 1.0 (neutro). Senao deriva de win_rate.
# ─────────────────────────────────────────────────────────────────────────────
function Get-LearnedMultiplier {
    param(
        [object[]]$Stats,
        [string]$Source,
        [string]$Direction,
        [string]$Regime
    )
    if (-not $Stats) { return 1.0 }
    $key = "$Source|$Direction|$Regime"
    $stat = $Stats | Where-Object { $_.key -eq $key } | Select-Object -First 1
    if (-not $stat) { return 1.0 }
    return _WinRateToMultiplier -WinRate ([double]$stat.win_rate) -Reliable ([bool]$stat.reliable)
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-BiasRecommendation (PURA) -- "se nao e compra, pode ser venda".
# Pesa sinais LONG vs SHORT * multiplier historico (agregado por direction+regime).
# Output: { direction(LONG|SHORT|NEUTRAL); long_score; short_score; reason }
# ─────────────────────────────────────────────────────────────────────────────
function Get-BiasRecommendation {
    param(
        [int]$SignalsLong  = 0,
        [int]$SignalsShort = 0,
        [object[]]$Stats   = @(),
        [string]$Regime    = ""
    )
    # Multiplier agregado por direction+regime (soma todas as sources)
    $multLong  = _AggregatedMultiplier -Stats $Stats -Direction "LONG"  -Regime $Regime
    $multShort = _AggregatedMultiplier -Stats $Stats -Direction "SHORT" -Regime $Regime

    $longScore  = $SignalsLong  * $multLong
    $shortScore = $SignalsShort * $multShort

    if ($longScore -gt $shortScore) {
        $dir = "LONG"
    } elseif ($shortScore -gt $longScore) {
        $dir = "SHORT"
    } else {
        $dir = "NEUTRAL"
    }

    $reason = "LONG=$SignalsLong x$multLong=$([math]::Round($longScore,2)) vs SHORT=$SignalsShort x$multShort=$([math]::Round($shortScore,2)) (regime=$Regime) -> $dir"
    return [PSCustomObject]@{
        direction   = $dir
        long_score  = [math]::Round($longScore,3)
        short_score = [math]::Round($shortScore,3)
        mult_long   = $multLong
        mult_short  = $multShort
        reason      = $reason
    }
}

# Helper: multiplier agregado por direction+regime (todas as sources somadas)
function _AggregatedMultiplier {
    param([object[]]$Stats, [string]$Direction, [string]$Regime)
    if (-not $Stats) { return 1.0 }
    $matching = @($Stats | Where-Object { $_.direction -eq $Direction -and $_.regime -eq $Regime })
    if ($matching.Count -eq 0) { return 1.0 }
    $totN = 0; $totWins = 0
    foreach ($s in $matching) { $totN += [int]$s.n; $totWins += [int]$s.wins }
    if ($totN -eq 0) { return 1.0 }
    $wr = $totWins / $totN
    # reliable agregado: soma de n >= 8 (mesmo MinTrades default)
    return _WinRateToMultiplier -WinRate $wr -Reliable ($totN -ge 8)
}

# ─────────────────────────────────────────────────────────────────────────────
# Join-SignalOutcomes (PURA) -- fecha o loop: junta snapshots de sinais + outcomes.
# Match por trade_id (preferencial) ou market+entry_date (fallback).
# So retorna trades JA fechados (com outcome). Alimenta Get-DirectionStats.
# ─────────────────────────────────────────────────────────────────────────────
function Join-SignalOutcomes {
    param(
        [object[]]$Snapshots,
        [object[]]$Outcomes
    )
    if (-not $Snapshots -or -not $Outcomes) { return @() }

    # Indexa outcomes por trade_id e por market|date
    $byId = @{}
    $byMktDate = @{}
    foreach ($o in $Outcomes) {
        if (-not $o) { continue }
        if ($o.PSObject.Properties['trade_id'] -and $o.trade_id) { $byId["$($o.trade_id)"] = $o }
        $mkt = if ($o.PSObject.Properties['market']) { "$($o.market)" } else { "" }
        $dt  = if ($o.PSObject.Properties['entry_date']) { "$($o.entry_date)" } else { "" }
        if ($mkt -and $dt) { $byMktDate["$mkt|$dt"] = $o }
    }

    $out = @()
    foreach ($s in $Snapshots) {
        if (-not $s) { continue }
        $match = $null
        if ($s.PSObject.Properties['trade_id'] -and $s.trade_id -and $byId.ContainsKey("$($s.trade_id)")) {
            $match = $byId["$($s.trade_id)"]
        } else {
            $mkt = if ($s.PSObject.Properties['market']) { "$($s.market)" } else { "" }
            $dt  = if ($s.PSObject.Properties['entry_date']) { "$($s.entry_date)" } else { "" }
            if ($mkt -and $dt -and $byMktDate.ContainsKey("$mkt|$dt")) { $match = $byMktDate["$mkt|$dt"] }
        }
        if (-not $match) { continue }  # trade ainda aberto / sem outcome

        $out += [PSCustomObject]@{
            trade_id  = if ($s.PSObject.Properties['trade_id']) { $s.trade_id } else { $null }
            market    = if ($s.PSObject.Properties['market'])   { $s.market }   else { $null }
            direction = $s.direction
            source    = if ($s.PSObject.Properties['source'])   { $s.source }   else { "regime" }
            regime    = if ($s.PSObject.Properties['regime'])   { $s.regime }   else { "UNKNOWN" }
            win       = [bool]$match.win
            pnl_pct   = if ($match.PSObject.Properties['pnl_pct']) { [double]$match.pnl_pct } else { 0 }
        }
    }
    return $out
}
