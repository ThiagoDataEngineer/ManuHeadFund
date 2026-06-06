# lib_dsr_confidence_advanced.ps1 — DSR Confidence: Walk-forward validation
# PROBLEMA: Hoje apenas detecta 30+ trades = MEDIUM; sem validação forward
# SOLUÇÃO: 3 niveis (LOW/MEDIUM/HIGH) + walk-forward vs backtest

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Get-DsrConfidenceLevel {
    <#
    .SYNOPSIS
    Determina nível de confiança na borda (DSR) baseado em:
    1. Sample size (trades)
    2. Win rate estabilidade
    3. Walk-forward error (backtest vs forward)
    #>
    param(
        [Parameter(Mandatory)] [array] $TradeHistory,
        [int] $BacktestSharpe = 0,
        [int] $ForwardSharpe = 0,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    $tradeCount = $TradeHistory.Count
    $wins = ($TradeHistory | Where-Object { $_.win }).Count
    $winRate = if ($tradeCount -gt 0) { $wins / $tradeCount } else { 0 }

    # === Nível: baseado em sample size ===
    if ($tradeCount -lt 10) {
        $level = "LOW"
        $confidence = [Math]::Round(($tradeCount / 10) * 30, 0)  # Max 30%
    } elseif ($tradeCount -lt 30) {
        $level = "MEDIUM"
        $confidence = [Math]::Round(30 + (($tradeCount - 10) / 20) * 40, 0)  # 30-70%
    } else {
        $level = "HIGH"
        $confidence = [Math]::Round(70 + (($tradeCount - 30) / 100) * 30, 0)  # 70-100%
    }

    # === Walk-forward validation ===
    $walkForwardError = 0
    $overfit = "N/A"
    if ($BacktestSharpe -gt 0 -and $ForwardSharpe -gt 0) {
        $walkForwardError = [Math]::Abs(($BacktestSharpe - $ForwardSharpe) / [Math]::Max($BacktestSharpe, 0.01)) * 100
        $overfit = if ($walkForwardError -lt 20) {
            "LOW (robust)"
        } elseif ($walkForwardError -lt 50) {
            "MEDIUM (watch)"
        } else {
            "HIGH (overfitted!)"
        }
    }

    return [PSCustomObject]@{
        level = $level
        confidence_pct = [Math]::Min($confidence, 100)
        trade_count = $tradeCount
        win_rate = [Math]::Round($winRate, 3)
        backtest_sharpe = $BacktestSharpe
        forward_sharpe = $ForwardSharpe
        walk_forward_error_pct = [Math]::Round($walkForwardError, 1)
        overfit_risk = $overfit
        recommendation = switch ($level) {
            "LOW" { "Edge fraca — continue coletando dados (target 30+ trades)" }
            "MEDIUM" { "Edge moderada — validar em 30 dias forward" }
            "HIGH" { "Edge forte — pronto pra expand position" }
        }
    }
}

function Test-WalkForwardValidation {
    <#
    .SYNOPSIS
    Compara backtest Sharpe vs forward Sharpe.
    Se error > 30%, edge é suspeito (overfitted).
    #>
    param(
        [Parameter(Mandatory)] [string] $Signal,
        [Parameter(Mandatory)] [double] $BacktestSharpe,
        [Parameter(Mandatory)] [double] $ForwardSharpe,
        [double] $MaxErrorPct = 30,
        [string] $JournalDir = $global:JOURNAL_DIR
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $dsrLogPath = Join-Path $JournalDir "dsr_validation_audit.jsonl"

    # Calcula error
    $error = [Math]::Abs(($BacktestSharpe - $ForwardSharpe) / [Math]::Max($BacktestSharpe, 0.01)) * 100
    $passes = $error -le $MaxErrorPct

    $entry = [ordered]@{
        timestamp = $timestamp
        signal = $Signal
        backtest_sharpe = [Math]::Round($BacktestSharpe, 2)
        forward_sharpe = [Math]::Round($ForwardSharpe, 2)
        error_pct = [Math]::Round($error, 1)
        max_error_pct = $MaxErrorPct
        passes = $passes
        verdict = if ($passes) { "ROBUST" } else { "OVERFITTED" }
    } | ConvertTo-Json -Compress

    Add-Content -Path $dsrLogPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        signal = $Signal
        backtest_sharpe = $BacktestSharpe
        forward_sharpe = $ForwardSharpe
        error_pct = [Math]::Round($error, 1)
        passes = $passes
        verdict = if ($passes) { "ROBUST" } else { "OVERFITTED — reject edge" }
        timestamp = $timestamp
    }
}

function Get-DsrRecommendedSize {
    <#
    .SYNOPSIS
    Ajusta position size baseado em nível DSR.
    LOW confidence = 0.5x
    MEDIUM = 0.8x
    HIGH = 1.0x
    #>
    param(
        [Parameter(Mandatory)] [string] $DsrLevel,
        [Parameter(Mandatory)] [double] $BasePositionUsd
    )

    $multiplier = switch ($DsrLevel) {
        "LOW" { 0.5 }
        "MEDIUM" { 0.8 }
        "HIGH" { 1.0 }
        default { 0.5 }
    }

    $finalSize = $BasePositionUsd * $multiplier

    return [PSCustomObject]@{
        dsr_level = $DsrLevel
        base_position_usd = $BasePositionUsd
        multiplier = $multiplier
        final_size_usd = [Math]::Round($finalSize, 2)
    }
}
