# lib_feedback_loop.ps1 -- Post-trade feedback loop (skeleton).
#
# Lifecycle:
#   1. Trade fecha (stop/target/max_days) -> Add-TradeOutcome
#   2. Cron weekly agrega outcomes por (regime, mode, score_bucket)
#   3. Get-RegimeAdjustment retorna weight_multiplier pra ajustar score em trades futuros
#
# Esta skeleton entrega:
#   - Persistencia (Add-TradeOutcome)
#   - Agregacao (Get-OutcomeStats)
#   - Adjustment signal (Get-RegimeAdjustment) -- conservative bayesian-like update
#
# Wire futuro (ONDA 2.4 fase 2):
#   - lib_trailing Update-TrailingStops chama Add-TradeOutcome ao fechar posicao
#   - orchestrator_v6 consulta Get-RegimeAdjustment + ajusta Mentor threshold

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# state_store p/ espelho Supabase de outcomes (cloud ground-truth). Carrega so
# se ainda nao disponivel — evita re-source quando ja carregado pelo runner.
if (-not (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
    $_fbStateStore = Join-Path $PSScriptRoot "lib_state_store.ps1"
    if (Test-Path $_fbStateStore) { . $_fbStateStore }
}

$script:DEFAULT_OUTCOME_PATH = Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl"
# Schema Supabase onde vive a tabela trade_outcomes (unico DDL existente:
# docs/SUPABASE_STATE_SCHEMA.md -> manuheadfund.trade_outcomes). Aplicado SO na
# chamada de espelho (save/restore), sem alterar o schema global que o trailing usa.
$script:SUPABASE_OUTCOME_SCHEMA = "manuheadfund"
$script:MIN_TRADES_ADJUSTMENT = 10
$script:BOOST_THRESHOLD_R = 0.30    # avg R >= 0.30 = BOOST
$script:REDUCE_THRESHOLD_R = 0.0    # avg R <= 0 = REDUCE


function Add-TradeOutcome {
    [CmdletBinding()]
    param(
        [string] $OutcomePath = $script:DEFAULT_OUTCOME_PATH,
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [double] $EntryPrice,
        [Parameter(Mandatory)] [double] $ExitPrice,
        [Parameter(Mandatory)] [double] $StopPrice,
        [Parameter(Mandatory)] [double] $TargetPrice,
        [Parameter(Mandatory)] [double] $R,           # R-multiple
        [Parameter(Mandatory)] [double] $Pnl,         # USD
        [Parameter(Mandatory)] [double] $DurationDays,
        [Parameter(Mandatory)] [string] $ExitReason,  # "target" | "stop_hit" | "trail_stop" | "max_days" | "manual"
        [string] $Regime = "",
        [double] $Score = 0
    )
    $dir = Split-Path $OutcomePath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $obj = [ordered]@{
        ts             = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        market         = $Market
        side           = $Side
        mode           = $Mode
        entry_price    = $EntryPrice
        exit_price     = $ExitPrice
        stop_price     = $StopPrice
        target_price   = $TargetPrice
        r              = $R
        pnl_usd        = $Pnl
        duration_days  = $DurationDays
        exit_reason    = $ExitReason
        regime         = $Regime
        score          = $Score
    }
    $line = $obj | ConvertTo-Json -Compress
    Add-Content -Path $OutcomePath -Value $line -Encoding UTF8

    # Espelho Supabase (cloud ground-truth). Best-effort: o JSONL local ja foi
    # gravado acima, entao falha aqui NUNCA bloqueia o fechamento do trade. Mas
    # tambem NUNCA falha em silencio — emite warning (licao do audit 2026-06-20).
    if ((Get-Command Test-StateBackend -ErrorAction SilentlyContinue) -and
        ((Test-StateBackend) -eq "supabase") -and
        (Get-Command Save-StateRecords -ErrorAction SilentlyContinue)) {
        $prevSchema = $global:STATE_STORE_SCHEMA
        try {
            $supaRow = ConvertTo-SupabaseOutcome -Outcome $obj
            # mira o schema da tabela trade_outcomes so nesta chamada
            $global:STATE_STORE_SCHEMA = $script:SUPABASE_OUTCOME_SCHEMA
            Save-StateRecords -Table "trade_outcomes" -Records @($supaRow)
        } catch {
            Write-Warning "[feedback_loop] Falha ao espelhar trade_outcome no Supabase (JSONL local gravado OK): $_"
        } finally {
            $global:STATE_STORE_SCHEMA = $prevSchema
        }
    }
}


function ConvertTo-SupabaseOutcome {
    # PURA. Mapeia o objeto de outcome local (schema JSONL) para as colunas da
    # tabela manuheadfund.trade_outcomes. O objeto integral vai em 'payload'
    # (JSONB) — lossless, preserva pnl_usd/duration_days/regime/score etc.
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Outcome)

    $get = {
        param($key)
        if ($null -eq $Outcome) { return $null }
        if ($Outcome -is [System.Collections.IDictionary]) {
            if ($Outcome.Contains($key)) { return $Outcome[$key] }
            return $null
        }
        $p = $Outcome.PSObject.Properties[$key]
        if ($p) { return $p.Value }
        return $null
    }

    # payload: copia integral como hashtable plano (ConvertTo-Json serializa em JSONB)
    $payload = @{}
    if ($Outcome -is [System.Collections.IDictionary]) {
        foreach ($k in $Outcome.Keys) { $payload[[string]$k] = $Outcome[$k] }
    } else {
        foreach ($p in $Outcome.PSObject.Properties) { $payload[$p.Name] = $p.Value }
    }

    # 2026-07-14 fix: id e PRIMARY KEY NOT NULL em manuheadfund.trade_outcomes;
    # esta funcao nunca preenchia, toda gravacao violava a constraint (achado
    # ao investigar o phantom-loop de trailing_state -- mesmo bug de auditoria
    # incompleta, campo obrigatorio nunca setado). Mesmo padrao de geracao de
    # lib_trade_journal_supabase.ps1 (ticks+market+guid, garante unicidade).
    $tsForId = & $get "ts"
    $ticks = try { ([datetime]::Parse([string]$tsForId)).Ticks } catch { [datetime]::UtcNow.Ticks }
    $idMarket = (& $get "market")
    $genId = "{0}|{1}|feedback_loop|{2}" -f $ticks, $idMarket, ([guid]::NewGuid().ToString().Substring(0,8))

    # 2026-07-19: pnl_percent/pnl_realized nunca eram mapeados aqui -- coluna
    # dedicada ficava sempre no DEFAULT 0 do Postgres (dado real preso so
    # dentro de payload JSONB, nunca consultavel via SELECT direto). Achado
    # investigando por que trade_outcomes tinha 19 linhas e zero com PnL.
    # pnl_usd (calculado corretamente por quem chama Add-TradeOutcome) vira
    # pnl_realized direto; pnl_percent e' derivado de entry/exit/side (LONG:
    # ganho quando exit>entry; SHORT: ganho quando exit<entry -- sinal invertido).
    $entryPrice = [double](& $get "entry_price")
    $exitPrice  = [double](& $get "exit_price")
    $side       = [string](& $get "side")
    $pnlUsd     = & $get "pnl_usd"
    $pnlPercent = if ($entryPrice -ne 0) {
        $rawPct = (($exitPrice - $entryPrice) / $entryPrice) * 100
        if ($side.ToUpper() -eq "SHORT") { -$rawPct } else { $rawPct }
    } else { 0.0 }

    return @{
        id           = $genId
        market       = [string](& $get "market")
        side         = [string](& $get "side")
        mode         = [string](& $get "mode")
        entry        = (& $get "entry_price")
        exit_price   = (& $get "exit_price")
        stop         = (& $get "stop_price")
        target       = (& $get "target_price")
        r_multiple   = (& $get "r")
        pnl_realized = if ($null -ne $pnlUsd) { [double]$pnlUsd } else { 0.0 }
        pnl_percent  = [Math]::Round($pnlPercent, 4)
        closed_at    = [string](& $get "ts")
        close_reason = [string](& $get "exit_reason")
        source       = "feedback_loop"
        payload      = $payload
    }
}


function _LoadOutcomes {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $out = @()
    foreach ($line in Get-Content $Path -Encoding UTF8) {
        if (-not $line) { continue }
        try { $out += ($line | ConvertFrom-Json) } catch {}
    }
    return @($out)
}


function Get-OutcomeStats {
    [CmdletBinding()]
    param(
        [string] $OutcomePath = $script:DEFAULT_OUTCOME_PATH,
        [string] $Mode = "",
        [string] $Regime = "",
        [string] $Market = ""
    )
    $rows = _LoadOutcomes -Path $OutcomePath
    if ($Mode) { $rows = @($rows | Where-Object { $_.mode -eq $Mode }) }
    if ($Regime) { $rows = @($rows | Where-Object { $_.regime -eq $Regime }) }
    if ($Market) { $rows = @($rows | Where-Object { $_.market -eq $Market }) }
    if ($rows.Count -eq 0) {
        return [PSCustomObject]@{ n=0; win_rate=0; avg_r=0; total_pnl=0 }
    }
    $wins = @($rows | Where-Object { [double]$_.r -gt 0 })
    $winRate = [Math]::Round($wins.Count / $rows.Count, 3)
    $rVals = @($rows | ForEach-Object { [double]$_.r })
    $pnlVals = @($rows | ForEach-Object { [double]$_.pnl_usd })
    $avgR = if ($rVals.Count -gt 0) { [Math]::Round(($rVals | Measure-Object -Average).Average, 3) } else { 0 }
    $totalPnl = if ($pnlVals.Count -gt 0) { [Math]::Round(($pnlVals | Measure-Object -Sum).Sum, 2) } else { 0 }
    return [PSCustomObject]@{
        n          = $rows.Count
        win_rate   = $winRate
        avg_r      = $avgR
        total_pnl  = $totalPnl
        n_wins     = $wins.Count
    }
}


function Get-RegimeAdjustment {
    # Retorna weight_multiplier (0.5 .. 1.5) pra ajustar score em proximo trade.
    # BOOST se avg_r >= BOOST_THRESHOLD_R; REDUCE se avg_r <= REDUCE_THRESHOLD_R; NEUTRAL otherwise.
    # Conservative bayesian-like: multiplier escala linearmente entre thresholds.
    [CmdletBinding()]
    param(
        [string] $OutcomePath = $script:DEFAULT_OUTCOME_PATH,
        [Parameter(Mandatory)] [string] $Regime,
        [int] $MinTrades = $script:MIN_TRADES_ADJUSTMENT
    )
    $stats = Get-OutcomeStats -OutcomePath $OutcomePath -Regime $Regime
    if ($stats.n -lt $MinTrades) {
        return [PSCustomObject]@{
            regime              = $Regime
            n                   = $stats.n
            action              = "NEUTRAL"
            weight_multiplier   = 1.0
            reason              = "insufficient_trades_$($stats.n)_lt_$MinTrades"
        }
    }
    $avgR = [double]$stats.avg_r
    if ($avgR -ge $script:BOOST_THRESHOLD_R) {
        # Linear scale: r=0.3 -> 1.1, r=1.0+ -> 1.5
        $mult = [Math]::Min(1.5, 1.0 + (($avgR - $script:BOOST_THRESHOLD_R) * 0.6))
        $action = "BOOST"
    } elseif ($avgR -le $script:REDUCE_THRESHOLD_R) {
        # r=0 -> 1.0, r=-1.0 -> 0.5
        $mult = [Math]::Max(0.5, 1.0 + ($avgR * 0.5))
        $action = "REDUCE"
    } else {
        $mult = 1.0
        $action = "NEUTRAL"
    }
    return [PSCustomObject]@{
        regime              = $Regime
        n                   = $stats.n
        avg_r               = $avgR
        win_rate            = $stats.win_rate
        action              = $action
        weight_multiplier   = [Math]::Round($mult, 3)
        reason              = "computed_from_$($stats.n)_trades"
    }
}
