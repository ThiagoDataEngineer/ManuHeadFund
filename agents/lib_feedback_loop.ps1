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

$script:DEFAULT_OUTCOME_PATH = Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl"
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
