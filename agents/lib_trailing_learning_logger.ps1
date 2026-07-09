# lib_trailing_learning_logger.ps1
# Enrich trailing stop logs para auto-aprendizado do sistema
# Registra decisões, transições de fase, efetividade de stops
# 2026-07-08

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-TrailingDecision -- Registra cada decisão de trailing com contexto completo
# ─────────────────────────────────────────────────────────────────────────────
function Write-TrailingDecision {
    <#
    .SYNOPSIS
    Registra decisão de stop loss/take profit com telemetria completa para aprendizado.

    .PARAMETER Market
    Par de trading (ex: BTCUSDT)

    .PARAMETER Side
    LONG ou SHORT

    .PARAMETER Phase
    Fase atual (0, 1, 2, 3)

    .PARAMETER Entry
    Preço de entrada

    .PARAMETER CurrentPrice
    Preço atual do mercado

    .PARAMETER StopOld
    Stop loss anterior

    .PARAMETER StopNew
    Novo stop loss

    .PARAMETER TakeProfit
    Alvo (TP)

    .PARAMETER Peak
    Pico atingido

    .PARAMETER Regime
    Regime de mercado (BEAR_WEAK, BULL_STRONG, etc)

    .PARAMETER ATR
    Volatilidade atual

    .PARAMETER Changed
    Se houve mudança no SL

    .PARAMETER Reason
    Motivo da mudança (phase_transition, peak_update, etc)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [int] $Phase,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $StopOld,
        [Parameter(Mandatory)] [double] $StopNew,
        [double] $TakeProfit,
        [double] $Peak,
        [string] $Regime = "UNKNOWN",
        [double] $ATR = 0,
        [bool] $Changed = $false,
        [string] $Reason = "routine_update"
    )

    try {
        $timestamp = [datetime]::UtcNow.ToString("o")

        # Cálculos de contexto
        $profit_usd = if ($Side -eq "LONG") { ($CurrentPrice - $Entry) } else { ($Entry - $CurrentPrice) }
        $profit_pct = if ($Entry -gt 0) { ($profit_usd / $Entry) * 100 } else { 0 }

        $stop_distance = if ($Side -eq "LONG") { $CurrentPrice - $StopNew } else { $StopNew - $CurrentPrice }
        $stop_distance_pct = if ($CurrentPrice -gt 0) { ($stop_distance / $CurrentPrice) * 100 } else { 0 }

        $tp_distance = if ($Side -eq "LONG") { $TakeProfit - $CurrentPrice } else { $CurrentPrice - $TakeProfit }
        $tp_distance_pct = if ($CurrentPrice -gt 0) { ($tp_distance / $CurrentPrice) * 100 } else { 0 }

        # Razão risco/recompensa
        $rr_ratio = if ($tp_distance_pct -gt 0) { $stop_distance_pct / $tp_distance_pct } else { 0 }

        # Progresso em direção ao TP
        $entry_to_tp = [math]::Abs($TakeProfit - $Entry)
        $entry_to_current = [math]::Abs($CurrentPrice - $Entry)
        $progress_pct = if ($entry_to_tp -gt 0) { ($entry_to_current / $entry_to_tp) * 100 } else { 0 }

        # Registrar evento
        $trailingEvent = [PSCustomObject]@{
            ts = $timestamp
            market = $Market
            side = $Side
            phase = $Phase
            entry = [math]::Round($Entry, 8)
            current_price = [math]::Round($CurrentPrice, 8)
            sl_old = [math]::Round($StopOld, 8)
            sl_new = [math]::Round($StopNew, 8)
            sl_moved = if ($StopNew -ne $StopOld) { "yes" } else { "no" }
            tp = [math]::Round($TakeProfit, 8)
            peak = [math]::Round($Peak, 8)

            # Telemetria de lucro
            profit_usd = [math]::Round($profit_usd, 4)
            profit_pct = [math]::Round($profit_pct, 4)

            # Telemetria de risco
            stop_distance_usd = [math]::Round($stop_distance, 8)
            stop_distance_pct = [math]::Round($stop_distance_pct, 4)
            tp_distance_usd = [math]::Round($tp_distance, 8)
            tp_distance_pct = [math]::Round($tp_distance_pct, 4)
            rr_ratio = [math]::Round($rr_ratio, 4)

            # Telemetria de progressão
            progress_to_tp_pct = [math]::Round($progress_pct, 2)

            # Contexto de mercado
            regime = $Regime
            atr = [math]::Round($ATR, 8)

            # Motivo da decisão
            changed = $Changed
            reason = $Reason

            # Validação de saúde
            is_healthy = if ($stop_distance_pct -gt 0 -and $tp_distance_pct -gt 0) { "yes" } else { "no" }
        }

        # Salvar em JSONL
        $logPath = Join-Path $global:JOURNAL_DIR "trailing_learning.jsonl"
        $json = $trailingEvent | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $json -Encoding UTF8

        # Retornar para chaining
        return $trailingEvent
    }
    catch {
        Write-Warning "Erro ao registrar trailing decision para $Market : $_"
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-TrailingPhaseTransition -- Registra transição entre fases com análise
# ─────────────────────────────────────────────────────────────────────────────
function Write-TrailingPhaseTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [int] $PhaseFrom,
        [Parameter(Mandatory)] [int] $PhaseTo,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $CurrentPrice,
        [Parameter(Mandatory)] [double] $StopNew,
        [Parameter(Mandatory)] [double] $TakeProfit,
        [string] $Regime = "UNKNOWN",
        [double] $BufferApplied = 0,
        [string] $TriggerCondition = ""
    )

    try {
        $timestamp = [datetime]::UtcNow.ToString("o")

        $range = [math]::Abs($TakeProfit - $Entry)
        $progress = if ($range -gt 0) { (([math]::Abs($CurrentPrice - $Entry) / $range) * 100) } else { 0 }

        $transition = [PSCustomObject]@{
            ts = $timestamp
            market = $Market
            side = $Side
            phase_from = $PhaseFrom
            phase_to = $PhaseTo

            entry = [math]::Round($Entry, 8)
            current_price = [math]::Round($CurrentPrice, 8)
            target = [math]::Round($TakeProfit, 8)

            sl_new = [math]::Round($StopNew, 8)
            buffer_applied = [math]::Round($BufferApplied, 8)

            progress_pct = [math]::Round($progress, 2)
            regime = $Regime

            trigger = $TriggerCondition

            # Fase descriptions

            phase_from_name = @{0="Monitoring"; 1="Breakeven"; 2="Locking"; 3="Trailing"}[$PhaseFrom]
            phase_to_name = @{0="Monitoring"; 1="Breakeven"; 2="Locking"; 3="Trailing"}[$PhaseTo]
        }

        $logPath = Join-Path $global:JOURNAL_DIR "trailing_phase_transitions.jsonl"
        $json = $transition | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $json -Encoding UTF8

        return $transition
    }
    catch {
        Write-Warning "Erro ao registrar phase transition para $Market : $_"
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Write-TrailingEffectiveness -- Analisa efetividade do stop loss (ex-post)
# ─────────────────────────────────────────────────────────────────────────────
function Write-TrailingEffectiveness {
    <#
    .SYNOPSIS
    Registra avaliação ex-post de efetividade: stop protegeu ganhos ou liquidou?
    Usado ao fechar posição (TP ou SL).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Market,
        [Parameter(Mandatory)] [string] $Side,
        [Parameter(Mandatory)] [double] $Entry,
        [Parameter(Mandatory)] [double] $Exit,
        [Parameter(Mandatory)] [double] $ExitPrice,
        [Parameter(Mandatory)] [double] $StopLossAtExit,
        [Parameter(Mandatory)] [string] $ExitReason,  # "TP_HIT", "SL_HIT", "MANUAL"
        [Parameter(Mandatory)] [double] $MaxGain,     # Lucro máximo atingido antes de exit
        [double] $DurationMinutes = 0,
        [string] $Regime = "UNKNOWN"
    )

    try {
        $timestamp = [datetime]::UtcNow.ToString("o")

        $profit_realized = if ($Side -eq "LONG") { $Exit - $Entry } else { $Entry - $Exit }
        $profit_realized_pct = if ($Entry -gt 0) { ($profit_realized / $Entry) * 100 } else { 0 }

        $max_gain_pct = if ($Entry -gt 0) { ($MaxGain / $Entry) * 100 } else { 0 }

        # Drawdown from peak
        $loss_from_peak = $max_gain_pct - $profit_realized_pct

        # Avaliação de efetividade
        $was_sl_effective = if ($ExitReason -eq "TP_HIT") { "yes" } else { "maybe" }
        if ($ExitReason -eq "SL_HIT" -and $loss_from_peak -gt 3) {
            $was_sl_effective = "no_allowed_excessive_drawdown"
        }

        $effectiveness = [PSCustomObject]@{
            ts = $timestamp
            market = $Market
            side = $Side

            entry = [math]::Round($Entry, 8)
            exit_price = [math]::Round($ExitPrice, 8)
            exit_reason = $ExitReason

            profit_realized_usd = [math]::Round($profit_realized, 4)
            profit_realized_pct = [math]::Round($profit_realized_pct, 4)

            max_gain_pct = [math]::Round($max_gain_pct, 4)
            drawdown_from_peak_pct = [math]::Round($loss_from_peak, 4)

            sl_at_exit = [math]::Round($StopLossAtExit, 8)
            regime = $Regime

            duration_minutes = $DurationMinutes

            # Scoring
            sl_effectiveness = $was_sl_effective
            score = if ($ExitReason -eq "TP_HIT") {
                if ($loss_from_peak -lt 2) { 100 } elseif ($loss_from_peak -lt 5) { 85 } else { 70 }
            } elseif ($ExitReason -eq "SL_HIT") {
                if ($loss_from_peak -lt 3) { 80 } else { 60 }
            } else {
                50
            }
        }

        $logPath = Join-Path $global:JOURNAL_DIR "trailing_effectiveness.jsonl"
        $json = $effectiveness | ConvertTo-Json -Compress
        Add-Content -Path $logPath -Value $json -Encoding UTF8

        return $effectiveness
    }
    catch {
        Write-Warning "Erro ao registrar trailing effectiveness para $Market : $_"
        return $null
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Get-TrailingLearningStats -- Analisa logs pra feedback evolutivo
# ─────────────────────────────────────────────────────────────────────────────
function Get-TrailingLearningStats {
    <#
    .SYNOPSIS
    Analisa histórico de trailing para gerar insights de aprendizado.
    Usado por evolution engine pra ajustar buffers/thresholds.
    #>
    [CmdletBinding()]
    param(
        [int] $LastHours = 24,
        [string] $Market = "*"
    )

    try {
        $cutoff = [datetime]::UtcNow.AddHours(-$LastHours)

        $decisionPath = Join-Path $global:JOURNAL_DIR "trailing_learning.jsonl"
        $decisions = @()
        if (Test-Path $decisionPath) {
            $decisions = @(Get-Content $decisionPath -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue |
                          Where-Object { [datetime]$_.ts -gt $cutoff -and ($_.market -like $Market) })
        }

        $effectPath = Join-Path $global:JOURNAL_DIR "trailing_effectiveness.jsonl"
        $effectiveness = @()
        if (Test-Path $effectPath) {
            $effectiveness = @(Get-Content $effectPath -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue |
                             Where-Object { [datetime]$_.ts -gt $cutoff -and ($_.market -like $Market) })
        }

        # Agregação
        $stats = [PSCustomObject]@{
            period_hours = $LastHours
            decision_count = $decisions.Count

            # Por regime
            regimes = @{}

            # Fase distribution
            phase_distribution = @{
                phase_0 = ($decisions | Where-Object phase -eq 0).Count
                phase_1 = ($decisions | Where-Object phase -eq 1).Count
                phase_2 = ($decisions | Where-Object phase -eq 2).Count
                phase_3 = ($decisions | Where-Object phase -eq 3).Count
            }

            # Média de RR ratio por fase
            rr_by_phase = @{
                phase_0 = [math]::Round(($decisions | Where-Object phase -eq 0 | Measure-Object -Property rr_ratio -Average).Average, 4)
                phase_1 = [math]::Round(($decisions | Where-Object phase -eq 1 | Measure-Object -Property rr_ratio -Average).Average, 4)
                phase_2 = [math]::Round(($decisions | Where-Object phase -eq 2 | Measure-Object -Property rr_ratio -Average).Average, 4)
                phase_3 = [math]::Round(($decisions | Where-Object phase -eq 3 | Measure-Object -Property rr_ratio -Average).Average, 4)
            }

            # Efetividade
            total_exits = $effectiveness.Count
            tp_hits = ($effectiveness | Where-Object exit_reason -eq "TP_HIT").Count
            sl_hits = ($effectiveness | Where-Object exit_reason -eq "SL_HIT").Count

            tp_hit_pct = if ($total_exits -gt 0) { ($tp_hits / $total_exits) * 100 } else { 0 }
            avg_profit_pct = [math]::Round(($effectiveness | Measure-Object -Property profit_realized_pct -Average).Average, 2)
            avg_drawdown = [math]::Round(($effectiveness | Measure-Object -Property drawdown_from_peak_pct -Average).Average, 2)
            avg_effectiveness_score = [math]::Round(($effectiveness | Measure-Object -Property score -Average).Average, 1)

            # Recomendações
            recommendations = @()
        }

        # Gerar recomendações baseadas em padrões
        if ($stats.tp_hit_pct -lt 60) {
            $stats.recommendations += "⚠ TP hit rate < 60% — considerado aumentar buffer em fase 3 (trailing)"
        }
        if ($stats.avg_drawdown -gt 5) {
            $stats.recommendations += "⚠ Drawdown from peak > 5% — stops muito amplos em fase 2/3"
        }
        if ($stats.rr_by_phase.phase_3 -lt 0.5) {
            $stats.recommendations += "✓ Phase 3 RR ratio < 0.5 — trailing está protegendo bem"
        }

        return $stats
    }
    catch {
        Write-Warning "Erro ao gerar trailing stats: $_"
        return $null
    }
}

# Funções disponíveis: Write-TrailingDecision, Write-TrailingPhaseTransition, Write-TrailingEffectiveness, Get-TrailingLearningStats
