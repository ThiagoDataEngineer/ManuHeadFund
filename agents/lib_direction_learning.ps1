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

# state_store p/ espelho Supabase (schema manuheadfund). Lazy-load: so carrega se
# ainda nao disponivel (evita re-source quando o runner ja carregou).
if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
    $_dlStateStore = Join-Path $PSScriptRoot "lib_state_store.ps1"
    if (Test-Path $_dlStateStore) { . $_dlStateStore }
}

# ─────────────────────────────────────────────────────────────────────────────
# _Mirror-LearningToSupabase -- helper best-effort compartilhado por TODOS os
# espelhos de aprendizado (learned_multipliers, evolution_*, mce_agg, grades_agg).
# Fecha o schema em "manuheadfund" so nesta chamada (nao mexe no schema global que
# o trailing usa). NUNCA lanca: falha do Supabase nao pode quebrar o write local.
# No backend "local" (default fora da nuvem) e no-op silencioso.
# ─────────────────────────────────────────────────────────────────────────────
function _Mirror-LearningToSupabase {
    param(
        [Parameter(Mandatory)] [string] $Table,
        [Parameter(Mandatory)] [string] $PrimaryKey,
        [object[]] $Records
    )
    $recs = @($Records | Where-Object { $null -ne $_ })
    if ($recs.Count -eq 0) { return }
    if (-not (Get-Command Test-StateBackend -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) { return }
    if ((Test-StateBackend) -ne "supabase") { return }   # local = no-op

    $prevSchema = $global:STATE_STORE_SCHEMA
    try {
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        Save-StateRecords -Table $Table -Records $recs -PrimaryKey $PrimaryKey
    } catch {
        Write-Warning "[learning-mirror] espelho '$Table' no Supabase falhou (local gravado OK): $($_.Exception.Message)"
    } finally {
        $global:STATE_STORE_SCHEMA = $prevSchema
    }
}

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
# ─────────────────────────────────────────────────────────────────────────────
# Get-SnapshotDate (PURA) -- extrai data yyyy-MM-dd de um snapshot/outcome.
# Prefere entry_date; senao deriva do ts. Robusto a locale: ts pode vir ISO
# ("2026-06-09T01:25:35Z") OU formato US ("06/15/2026 05:05:05") pois snapshots
# antigos foram gravados com ToString() dependente de cultura. Usa REGEX (nao
# [datetime]::Parse, que embaralha mes/dia conforme a cultura da maquina).
# ─────────────────────────────────────────────────────────────────────────────
function Get-SnapshotDate {
    param([object]$Snapshot)
    if (-not $Snapshot) { return "" }
    # 1) entry_date explicito (ja yyyy-MM-dd)
    if ($Snapshot.PSObject.Properties['entry_date'] -and $Snapshot.entry_date) {
        $ed = "$($Snapshot.entry_date)".Trim()
        if ($ed -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
    }
    # 2) deriva do ts (ou entry_ts -- schema real de trade_outcomes.jsonl
    # usa entry_ts, nao ts nem entry_date; ver ConvertTo-SupabaseOutcome)
    $rawTs = if ($Snapshot.PSObject.Properties['ts'] -and $Snapshot.ts) { $Snapshot.ts }
             elseif ($Snapshot.PSObject.Properties['entry_ts'] -and $Snapshot.entry_ts) { $Snapshot.entry_ts }
             else { $null }
    if ($rawTs) {
        $ts = "$rawTs".Trim()
        # ISO: 2026-06-09T...
        if ($ts -match '^(\d{4})-(\d{2})-(\d{2})') { return "$($Matches[1])-$($Matches[2])-$($Matches[3])" }
        # US locale: MM/dd/yyyy ...
        if ($ts -match '^(\d{1,2})/(\d{1,2})/(\d{4})') {
            $mo = "{0:00}" -f [int]$Matches[1]
            $dy = "{0:00}" -f [int]$Matches[2]
            return "$($Matches[3])-$mo-$dy"
        }
    }
    return ""
}

# ─────────────────────────────────────────────────────────────────────────────
# _DateToInt (interno) -- yyyy-MM-dd -> dias absolutos p/ comparar tolerancia.
# ─────────────────────────────────────────────────────────────────────────────
function _DateToInt {
    param([string]$YmdDate)
    if ($YmdDate -match '^(\d{4})-(\d{2})-(\d{2})$') {
        try {
            $dt = [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
            return [int]$dt.ToOADate()
        } catch { return $null }
    }
    return $null
}

function Join-SignalOutcomes {
    param(
        [object[]]$Snapshots,
        [object[]]$Outcomes,
        [int]$ToleranceDays = 1
    )
    if (-not $Snapshots -or -not $Outcomes) { return @() }

    # Indexa outcomes por trade_id e por market -> lista de {date_int, outcome}
    $byId = @{}
    $byMkt = @{}
    foreach ($o in $Outcomes) {
        if (-not $o) { continue }
        if ($o.PSObject.Properties['trade_id'] -and $o.trade_id) { $byId["$($o.trade_id)"] = $o }
        # 2026-07-23 FIX: schema real de trade_outcomes.jsonl usa "symbol",
        # nao "market" (ver ConvertTo-SupabaseOutcome) -- Join-SignalOutcomes
        # nunca casava nenhum outcome real, motor de aprendizado direcional
        # nunca aprendia de fato em producao (0 matches sempre).
        $mkt = if ($o.PSObject.Properties['market'] -and $o.market) { "$($o.market)" }
               elseif ($o.PSObject.Properties['symbol'] -and $o.symbol) { "$($o.symbol)" }
               else { "" }
        $dInt = _DateToInt (Get-SnapshotDate -Snapshot $o)
        if ($mkt -and $null -ne $dInt) {
            if (-not $byMkt.ContainsKey($mkt)) { $byMkt[$mkt] = @() }
            $byMkt[$mkt] += [PSCustomObject]@{ date_int = $dInt; outcome = $o }
        }
    }

    # DEDUP: cada outcome (trade real) contribui no MAXIMO 1x. N snapshots do mesmo
    # trade (varios ciclos de scan antes da entrada) NAO podem inflar n. Isto e
    # mandatorio: effective_n = trades distintos (Lopez de Prado / memoria do projeto).
    $consumed = @{}
    function _OutcomeKey($o) {
        if ($o.PSObject.Properties['trade_id'] -and $o.trade_id) { return "id:$($o.trade_id)" }
        $m = if ($o.PSObject.Properties['market'] -and $o.market) { "$($o.market)" }
             elseif ($o.PSObject.Properties['symbol'] -and $o.symbol) { "$($o.symbol)" }
             else { "?" }
        $d = Get-SnapshotDate -Snapshot $o
        return "$m|$d"
    }

    $out = @()
    foreach ($s in $Snapshots) {
        if (-not $s) { continue }

        # So ENTRADAS reais geram stats de entrada (VETAR/SKIP nunca viraram trade).
        $decision = if ($s.PSObject.Properties['decision']) { "$($s.decision)".ToUpper() } else { "APROVAR" }
        if ($decision -ne "APROVAR") { continue }

        $match = $null
        # 1) match exato por trade_id
        if ($s.PSObject.Properties['trade_id'] -and $s.trade_id -and $byId.ContainsKey("$($s.trade_id)")) {
            $match = $byId["$($s.trade_id)"]
        } else {
            # 2) match por market + data (tolerancia +-ToleranceDays)
            $mkt = if ($s.PSObject.Properties['market']) { "$($s.market)" } else { "" }
            $sInt = _DateToInt (Get-SnapshotDate -Snapshot $s)
            if ($mkt -and $null -ne $sInt -and $byMkt.ContainsKey($mkt)) {
                $best = $null; $bestDiff = [int]::MaxValue
                foreach ($cand in $byMkt[$mkt]) {
                    $diff = [math]::Abs($cand.date_int - $sInt)
                    if ($diff -le $ToleranceDays -and $diff -lt $bestDiff) {
                        $best = $cand.outcome; $bestDiff = $diff
                    }
                }
                $match = $best
            }
        }
        if (-not $match) { continue }  # trade ainda aberto / sem outcome

        # DEDUP: se este outcome ja foi contabilizado por outro snapshot, pula.
        $okey = _OutcomeKey $match
        if ($consumed.ContainsKey($okey)) { continue }
        $consumed[$okey] = $true

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
# Get-GateKey (PURA) -- normaliza a FRASE de veto da LLM numa chave canonica.
# 2026-06-23 Evolucao A: skip_quality chaveava pela frase inteira (unica cada vez)
# -> 1092 chaves com n~1, counterfactual nao agregava. Mapeia padroes conhecidos;
# fallback = slug das 1as palavras (agrupa parcial, nunca a frase toda).
# ─────────────────────────────────────────────────────────────────────────────
function Get-GateKey {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "unknown" }
    $t = $Text.ToLowerInvariant()
    # padroes ordenados (mais especifico primeiro)
    $patterns = @(
        @{ rx = 'mesa consensus forte';                key = 'mesa_consensus_forte' }
        @{ rx = 'self-?consistency';                   key = 'self_consistency' }
        @{ rx = '\bfqs\b';                             key = 'fqs' }
        @{ rx = '\bbeta\b';                            key = 'beta' }
        @{ rx = 'r:?r|risk.?reward|target.*(acima|invertid)|stop.*invertid'; key = 'rr' }
        @{ rx = '\btori\b';                            key = 'tori' }
        @{ rx = 'drawdown|\bdd\b';                     key = 'drawdown' }
        @{ rx = 'alpha.?corr|correlation';             key = 'alpha_corr' }
        @{ rx = 'blacklist';                           key = 'blacklist' }
        @{ rx = 'regime|bear|bull';                    key = 'regime' }
    )
    foreach ($p in $patterns) {
        if ($t -match $p.rx) { return $p.key }
    }
    # fallback: slug das primeiras 4 palavras
    $words = ($t -replace '[^a-z0-9 ]',' ') -split '\s+' | Where-Object { $_ } | Select-Object -First 4
    $slug = ($words -join '_')
    if ($slug.Length -gt 38) { $slug = $slug.Substring(0,38) }
    if (-not $slug) { return "unknown" }
    return $slug
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
        $gateRaw = if ($s.PSObject.Properties['gate'] -and $s.gate) { [string]$s.gate } else { "unknown" }
        $gate = Get-GateKey $gateRaw   # 2026-06-23 Evolucao A: normaliza p/ agregar
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
    $nowUtc = (Get-Date).ToUniversalTime()
    return [ordered]@{
        ts                 = $nowUtc.ToString("o")
        entry_date         = $nowUtc.ToString("yyyy-MM-dd")
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

# ─────────────────────────────────────────────────────────────────────────────
# Write-SignalSkip (I/O) -- persiste rejeicoes em Supabase (ou local JSONL fallback).
# 2026-06-09: Supabase pra sincronizar entre daemons locais e GH Actions learning job.
# Usado p/ counterfactual: depois quando moeda sobe, avalia se veto custou oportunidade.
# ─────────────────────────────────────────────────────────────────────────────
function Write-SignalSkip {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [string]$Direction,
        [Parameter(Mandatory)] [string]$Gate,
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [string]$Regime,
        [string]$Source = "regime"
    )
    $skip = [ordered]@{
        ts            = (Get-Date).ToUniversalTime().ToString("o")
        market        = $Market
        direction     = $Direction
        gate          = $Gate
        entry_price   = $EntryPrice
        regime        = $Regime
        source        = $Source
    }

    # Try Supabase first (if available)
    if (Get-Command Save-StateRecords -ErrorAction SilentlyContinue) {
        try {
            Save-StateRecords -Table "trade_rejections" -Records @($skip) -PrimaryKey "ts"
            return $true
        } catch {
            # Supabase failed, fallback to local
        }
    }

    # Fallback: local JSONL
    $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $PSScriptRoot ".." "journal" }
    $path = Join-Path $base "signal_skips.jsonl"
    try {
        $dir = Split-Path -Parent $path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $path -Value ($skip | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
        return $true
    } catch {
        Write-Host "  [SIGNAL-SKIP] falha ao gravar: $_" -ForegroundColor Yellow
        return $false
    }
}

# ═════════════════════════════════════════════════════════════════════════════
# JOB DE APRENDIZADO + CONSUMO -- computa stats do historico e aplica nas decisoes.
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# Read-JsonLines (I/O) -- le JSONL tolerante (ignora linhas invalidas).
# ─────────────────────────────────────────────────────────────────────────────
# ═════════════════════════════════════════════════════════════════════════════
# AUTO-REGISTRO DE OUTCOME -- fecha o gap "#2": ao FECHAR posicao, grava outcome
# no MESMO schema que Join-SignalOutcomes le. Sem isto, volume nunca cresce e o
# aprendizado fica eternamente "nao confiavel".
# ═════════════════════════════════════════════════════════════════════════════

# ─────────────────────────────────────────────────────────────────────────────
# New-LearningOutcome (PURA) -- monta outcome join-compativel a partir de uma
# posicao fechada. pnl_pct respeita o lado (LONG/SHORT). win = pnl_pct > 0.
# ─────────────────────────────────────────────────────────────────────────────
function New-LearningOutcome {
    param(
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [string]$Side,        # LONG | SHORT
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [double]$ExitPrice,
        [Parameter(Mandatory)] [string]$OpenedAt,    # "yyyy-MM-dd HH:mm:ss" ou ISO
        [string]$CloseReason = "manual",
        [string]$OrderId     = "",
        [string]$Regime      = "UNKNOWN",
        [string]$Source      = "regime"
    )
    $side = $Side.ToUpper()
    $pnl = if ($EntryPrice -gt 0) {
        if ($side -eq "SHORT") { ($EntryPrice - $ExitPrice) / $EntryPrice * 100 }
        else                   { ($ExitPrice - $EntryPrice) / $EntryPrice * 100 }
    } else { 0 }
    $pnl = [math]::Round($pnl, 4)

    # entry_date a partir de OpenedAt (reusa parser robusto via objeto temporario)
    $entryDate = Get-SnapshotDate -Snapshot ([PSCustomObject]@{ ts = $OpenedAt })
    $tid = if ($OrderId) { $OrderId } else { "$Market-$($entryDate -replace '-','')" }

    return [ordered]@{
        ts          = (Get-Date).ToUniversalTime().ToString("o")
        trade_id    = $tid
        market      = $Market
        direction   = $side
        entry_date  = $entryDate
        entry_price = $EntryPrice
        exit_price  = $ExitPrice
        pnl_pct     = $pnl
        win         = ($pnl -gt 0)
        close_reason= $CloseReason
        regime      = $Regime
        source      = $Source
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Add-LearningOutcome (I/O) -- append idempotente em trade_outcomes.jsonl.
# Idempotencia por trade_id (nao grava o mesmo trade 2x). Fail-safe: nunca lanca.
# ─────────────────────────────────────────────────────────────────────────────
function Add-LearningOutcome {
    param(
        [string]$OutcomePath,
        [Parameter(Mandatory)] [string]$Market,
        [Parameter(Mandatory)] [string]$Side,
        [Parameter(Mandatory)] [double]$EntryPrice,
        [Parameter(Mandatory)] [double]$ExitPrice,
        [Parameter(Mandatory)] [string]$OpenedAt,
        [string]$CloseReason = "manual",
        [string]$OrderId     = "",
        [string]$Regime      = "UNKNOWN",
        [string]$Source      = "regime"
    )
    try {
        if (-not $OutcomePath) {
            $base = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { Join-Path $PSScriptRoot ".." "journal" }
            $OutcomePath = Join-Path $base "trade_outcomes.jsonl"
        }
        $rec = New-LearningOutcome -Market $Market -Side $Side -EntryPrice $EntryPrice `
            -ExitPrice $ExitPrice -OpenedAt $OpenedAt -CloseReason $CloseReason `
            -OrderId $OrderId -Regime $Regime -Source $Source

        # Idempotencia: pula se trade_id ja existe no arquivo
        if (Test-Path $OutcomePath) {
            $existing = Read-JsonLines -Path $OutcomePath
            foreach ($e in $existing) {
                if ($e -and $e.PSObject.Properties['trade_id'] -and "$($e.trade_id)" -eq "$($rec.trade_id)") {
                    return $false
                }
            }
        }
        $dir = Split-Path -Parent $OutcomePath
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $OutcomePath -Value ($rec | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
        return $true
    } catch {
        Write-Host "  [LEARNING-OUTCOME] falha ao gravar: $_" -ForegroundColor Yellow
        return $false
    }
}

function Read-JsonLines {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return @() }
    $out = @()
    foreach ($ln in (Get-Content -Path $Path -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        try { $out += ($ln | ConvertFrom-Json) } catch { }
    }
    return $out
}

# ─────────────────────────────────────────────────────────────────────────────
# Save-LearnedStats / Get-LearnedStats (I/O) -- persiste learned_multipliers.json.
# ─────────────────────────────────────────────────────────────────────────────
function Save-LearnedStats {
    param([object[]]$Stats, [string]$Path)
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $payload = @{ updated_at = (Get-Date).ToUniversalTime().ToString("o"); stats = @($Stats) }
        ($payload | ConvertTo-Json -Depth 6) | Set-Content -Path $Path -Encoding UTF8
    } catch { return $false }

    # Espelho Supabase (schema manuheadfund) — best-effort. O JSONL local ACIMA e o
    # ground-truth local; falha aqui NUNCA quebra o save. Formato AGREGADO por chave
    # (source|direction|regime) — pequeno de gravar, rapido de ler. Read-back na nuvem
    # em Get-LearnedStats (sem journal local no runner). Ver [[project_trades_via_app_journal_furado]].
    _Mirror-LearningToSupabase -Table "learned_multipliers" -PrimaryKey "key" -Records @(
        @($Stats) | ForEach-Object {
            if ($null -eq $_) { return }
            @{
                key         = [string]$_.key
                source      = [string]$_.source
                direction   = [string]$_.direction
                regime      = [string]$_.regime
                n           = [int]$_.n
                wins        = [int]$_.wins
                win_rate    = [double]$_.win_rate
                avg_pnl_pct = [double]$_.avg_pnl_pct
                sum_pnl     = [double]$_.sum_pnl
                reliable    = [bool]$_.reliable
                updated_at  = (Get-Date).ToUniversalTime().ToString("o")
            }
        }
    )
    return $true
}

function Get-LearnedStats {
    param([string]$Path)
    # 1) Fonte local (ground-truth fora da nuvem)
    if ($Path -and (Test-Path $Path)) {
        try {
            $obj = Get-Content $Path -Raw | ConvertFrom-Json
            if ($obj -and $obj.PSObject.Properties['stats']) {
                $local = @($obj.stats)
                if ($local.Count -gt 0) { return $local }
            }
        } catch { }
    }
    # 2) Read-back Supabase (fecha o loop na NUVEM — o runner nao tem journal local).
    #    So quando o local esta vazio/ausente E backend=supabase.
    return (_Get-LearningFromSupabase -Table "learned_multipliers")
}

# ─────────────────────────────────────────────────────────────────────────────
# _Get-LearningFromSupabase -- read-back best-effort do schema manuheadfund.
# Retorna @() se backend local, tabela ausente, ou erro. Nunca lanca.
# ─────────────────────────────────────────────────────────────────────────────
function _Get-LearningFromSupabase {
    param([Parameter(Mandatory)] [string] $Table, [hashtable] $Filter = @{})
    if (-not (Get-Command Test-StateBackend -ErrorAction SilentlyContinue)) { return @() }
    if (-not (Get-Command Get-StateRecords -ErrorAction SilentlyContinue)) { return @() }
    if ((Test-StateBackend) -ne "supabase") { return @() }
    $prevSchema = $global:STATE_STORE_SCHEMA
    try {
        $global:STATE_STORE_SCHEMA = "manuheadfund"
        return @(Get-StateRecords -Table $Table -Filter $Filter)
    } catch {
        Write-Warning "[learning-mirror] read-back '$Table' do Supabase falhou: $($_.Exception.Message)"
        return @()
    } finally {
        $global:STATE_STORE_SCHEMA = $prevSchema
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Apply-LearnedConviction (PURA) -- ajusta conviction base pelo multiplier aprendido.
# Clamp [0,100]. Sem dados confiaveis -> mantem (multiplier 1.0).
# ─────────────────────────────────────────────────────────────────────────────
function Apply-LearnedConviction {
    param(
        [int]$BaseConviction,
        [object[]]$Stats,
        [string]$Source,
        [string]$Direction,
        [string]$Regime
    )
    $m = Get-LearnedMultiplier -Stats $Stats -Source $Source -Direction $Direction -Regime $Regime
    $adj = [int][math]::Round($BaseConviction * $m)
    if ($adj -lt 0)   { $adj = 0 }
    if ($adj -gt 100) { $adj = 100 }
    return $adj
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-CounterfactualSkips (I/O via fetcher injetavel) -- avalia NAO-ENTRADAS.
# Para cada VETAR antigo (>= MinAgeHours), busca preco atual e monta skip record
# p/ Get-SkipQualityStats. PriceFetcher e scriptblock {param($market) <preco>}.
# ─────────────────────────────────────────────────────────────────────────────
function Get-CounterfactualSkips {
    param(
        [object[]]$Snapshots,
        [scriptblock]$PriceFetcher,
        [int]$MinAgeHours = 24,
        [double]$MinReturnPct = 3
    )
    if (-not $Snapshots -or -not $PriceFetcher) { return @() }
    $now = Get-Date
    $out = @()
    # 2026-07-07 fix travamento boot scan_master: cache de preco por market. Antes,
    # cada snapshot elegivel (podia ser centenas/milhares) disparava 1 CoinEx-GetTicker
    # sequencial -> com timeout 15s/chamada o boot ficava minutos/horas congelado
    # (self_heal marcava zumbi_log_parado). Agora 1 fetch por market unico.
    $priceCache = @{}
    foreach ($s in $Snapshots) {
        if (-not $s) { continue }
        $decision = if ($s.PSObject.Properties['decision']) { "$($s.decision)" } else { "" }
        if ($decision -ne "VETAR" -and $decision -ne "SKIP") { continue }  # so nao-entradas
        # idade
        $ts = $null
        if ($s.PSObject.Properties['ts'] -and $s.ts) { try { $ts = [datetime]::Parse($s.ts) } catch {} }
        if (-not $ts) { continue }
        if (($now - $ts).TotalHours -lt $MinAgeHours) { continue }  # ainda cedo p/ avaliar
        $entry = if ($s.PSObject.Properties['entry_price']) { [double]$s.entry_price } else { 0 }
        if ($entry -le 0) { continue }
        $mkt = if ($s.PSObject.Properties['market']) { "$($s.market)" } else { "" }
        if (-not $mkt) { continue }
        $exit = $null
        if ($priceCache.ContainsKey($mkt)) {
            $exit = $priceCache[$mkt]
        } else {
            try { $exit = [double](& $PriceFetcher $mkt) } catch { $exit = $null }
            $priceCache[$mkt] = $exit   # cacheia inclusive falha (null) p/ nao re-tentar
        }
        if (-not $exit -or $exit -le 0) { continue }
        $out += [PSCustomObject]@{
            gate        = if ($s.PSObject.Properties['gate'] -and $s.gate) { "$($s.gate)" } else { "veto" }
            direction   = if ($s.PSObject.Properties['direction']) { "$($s.direction)" } else { "LONG" }
            regime      = if ($s.PSObject.Properties['regime']) { "$($s.regime)" } else { "UNKNOWN" }
            entry_price = $entry
            exit_price  = $exit
            market      = $mkt
        }
    }
    return $out
}

# ─────────────────────────────────────────────────────────────────────────────
# Invoke-LearningUpdate (I/O orquestrador) -- fecha o ciclo periodico:
# le snapshots + outcomes -> join -> Get-DirectionStats -> persiste learned stats.
# Retorna resumo. Chamado periodicamente pelo scan_master.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-LearningUpdate {
    param(
        [string]$SnapshotsPath,
        [string]$OutcomesPath,
        [string]$OutPath,
        [int]$MinTrades = 8
    )
    $snaps = Read-JsonLines -Path $SnapshotsPath
    $outs  = Read-JsonLines -Path $OutcomesPath
    $joined = Join-SignalOutcomes -Snapshots $snaps -Outcomes $outs
    $stats  = Get-DirectionStats -Trades $joined -MinTrades $MinTrades
    if ($OutPath) { Save-LearnedStats -Stats $stats -Path $OutPath | Out-Null }
    return [PSCustomObject]@{
        snapshots = @($snaps).Count
        outcomes  = @($outs).Count
        joined    = @($joined).Count
        keys      = @($stats).Count
        reliable_keys = @($stats | Where-Object { $_.reliable }).Count
    }
}
