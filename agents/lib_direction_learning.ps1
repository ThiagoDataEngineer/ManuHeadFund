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

# ═════════════════════════════════════════════════════════════════════════════
# COUNTERFACTUAL LEARNING -- aprender com NAO-ENTRADAS que eram otimas.
# "Se rejeitei e a moeda fez o movimento que eu teria operado, o gate custou $$$."
# O melhor aprendizado: falsos negativos (missed winners).
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Get-ForwardReturn (PURA) -- % que TERIAMOS ganho na direcao avaliada.
# ─────────────────────────────────────────────────────────────────────────────
function Get-ForwardReturn {
    param([double]$EntryPrice, [double]$ExitPrice, [string]$Direction)
    if ($EntryPrice -le 0) { return 0 }
    $raw = ($ExitPrice - $EntryPrice) / $EntryPrice * 100
    if ($Direction -eq "SHORT") { return [math]::Round(-$raw, 4) }
    return [math]::Round($raw, 4)
}

# ─────────────────────────────────────────────────────────────────────────────
# Test-MissedWinner (PURA) -- o skip foi otimo (missed) ou correto (good)?
# missed_winner: forward return >= MinReturn (teria lucrado, gate custou).
# good_skip: forward return <= -MinReturn (teria perdido, gate acertou).
# entre os dois: inconclusive (movimento pequeno).
# ─────────────────────────────────────────────────────────────────────────────
function Test-MissedWinner {
    param([double]$EntryPrice, [double]$ExitPrice, [string]$Direction, [double]$MinReturnPct = 3)
    $fwd = Get-ForwardReturn -EntryPrice $EntryPrice -ExitPrice $ExitPrice -Direction $Direction
    $missed = ($fwd -ge $MinReturnPct)
    $good   = ($fwd -le (-$MinReturnPct))
    $verdict = if ($missed) { "missed_winner" } elseif ($good) { "good_skip" } else { "inconclusive" }
    return [PSCustomObject]@{
        forward_return_pct = $fwd
        missed_winner      = $missed
        good_skip          = $good
        verdict            = $verdict
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-SkipQualityStats (PURA) -- agrega rejeicoes por gate p/ achar quais custam
# oportunidade. costly=true quando missed_rate alto e amostra suficiente.
# Input: Skips[] com {gate, direction, regime, entry_price, exit_price}.
# Output: { key, gate, direction, regime, n, missed_winners, good_skips, missed_rate, costly }
# ─────────────────────────────────────────────────────────────────────────────
function Get-SkipQualityStats {
    param(
        [object[]]$Skips,
        [double]$MinReturnPct = 3,
        [int]$MinSamples = 8,
        [double]$CostlyThreshold = 0.5  # missed_rate acima disto = gate custando oportunidade
    )
    if (-not $Skips -or @($Skips).Count -eq 0) { return @() }

    $groups = @{}
    foreach ($s in $Skips) {
        if (-not $s) { continue }
        $gate = if ($s.PSObject.Properties['gate'] -and $s.gate) { [string]$s.gate } else { "unknown" }
        $dir  = if ($s.PSObject.Properties['direction'] -and $s.direction) { [string]$s.direction } else { "LONG" }
        $reg  = if ($s.PSObject.Properties['regime'] -and $s.regime) { [string]$s.regime } else { "UNKNOWN" }
        $key  = "$gate|$dir|$reg"
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [PSCustomObject]@{ key=$key; gate=$gate; direction=$dir; regime=$reg; n=0; missed=0; good=0 }
        }
        $mw = Test-MissedWinner -EntryPrice ([double]$s.entry_price) -ExitPrice ([double]$s.exit_price) -Direction $dir -MinReturnPct $MinReturnPct
        $g = $groups[$key]
        $g.n++
        if ($mw.missed_winner) { $g.missed++ }
        if ($mw.good_skip)     { $g.good++ }
    }

    $out = @()
    foreach ($g in $groups.Values) {
        $rate = if ($g.n -gt 0) { [math]::Round($g.missed / $g.n, 4) } else { 0 }
        $costly = ($g.n -ge $MinSamples) -and ($rate -ge $CostlyThreshold)
        $out += [PSCustomObject]@{
            key=$g.key; gate=$g.gate; direction=$g.direction; regime=$g.regime
            n=$g.n; missed_winners=$g.missed; good_skips=$g.good
            missed_rate=$rate; costly=$costly
        }
    }
    return $out
}

# ═════════════════════════════════════════════════════════════════════════════
# SIGNAL SNAPSHOT -- captura a decisao + sinais no momento, p/ alimentar o loop.
# Sem isso o motor nao tem o que aprender. Liga decisao -> outcome (futuro).
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# New-SignalSnapshot (PURA) -- monta o registro normalizado da decisao.
# Captura APROVAR e VETAR/SKIP. entry_price e crucial p/ counterfactual depois.
# ─────────────────────────────────────────────────────────────────────────────
function New-SignalSnapshot {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [string]$Direction,
        [Parameter(Mandatory)] [string]$Source,
        [Parameter(Mandatory)] [string]$Regime,
        [Parameter(Mandatory)] [string]$Decision,     # APROVAR | VETAR | SKIP
        [Parameter(Mandatory)] [double]$EntryPrice,
        [string]$MesaConsensus    = "",
        [bool]$ReversalVsRegime   = $false,
        [int]$SignalsLong         = 0,
        [int]$SignalsShort        = 0,
        [int]$Conviction          = 0,
        [string]$Gate             = "",
        [string]$TradeId          = ""
    )
    return [ordered]@{
        ts                 = (Get-Date).ToUniversalTime().ToString("o")
        trade_id           = $TradeId
        market             = $Market
        direction          = $Direction
        source             = $Source
        regime             = $Regime
        decision           = $Decision
        entry_price        = $EntryPrice
        mesa_consensus     = $MesaConsensus
        reversal_vs_regime = $ReversalVsRegime
        signals_long       = $SignalsLong
        signals_short      = $SignalsShort
        conviction         = $Conviction
        gate               = $Gate
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-SignalSnapshot (I/O) -- append JSONL. Default journal/signal_snapshots.jsonl.
# ─────────────────────────────────────────────────────────────────────────────
function Write-SignalSnapshot {
    param(
        [Parameter(Mandatory)] [object]$Entry,
        [string]$Path
    )
    if (-not $Path) {
        $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $PSScriptRoot ".." "journal" }
        $Path = Join-Path $base "signal_snapshots.jsonl"
    }
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $Path -Value ($Entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
        return $true
    } catch {
        Write-Host "  [SIGNAL-SNAPSHOT] falha ao gravar: $_" -ForegroundColor Yellow
        return $false
    }
}
