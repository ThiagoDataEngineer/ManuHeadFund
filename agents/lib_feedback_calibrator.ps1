# lib_feedback_calibrator.ps1 -- Feedback loop: coleta outcomes, calibra parametros

function Get-OutcomesStats {
    [CmdletBinding()]
    param(
        [string]$OutcomesFile,
        [int]$Days = 7
    )

    if (-not (Test-Path $OutcomesFile)) { return $null }

    $cutoff = (Get-Date).AddDays(-$Days)
    $outcomes = @()

    try {
        Get-Content $OutcomesFile | Where-Object { $_.Trim() } | ForEach-Object {
            $o = $_ | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $o) { return }
            if ([datetime]$o.entry_date -lt $cutoff) { return }
            $outcomes += $o
        }
    } catch { }

    if ($outcomes.Count -eq 0) { return $null }

    $wins = @($outcomes | Where-Object { $_.win -eq $true })
    $losses = @($outcomes | Where-Object { $_.win -ne $true })
    $pnl_usd = ($outcomes | Measure-Object pnl_usd -Sum).Sum
    $pnl_pcts = $outcomes | ForEach-Object { $_.pnl_pct }
    $avg_pnl_pct = ($pnl_pcts | Measure-Object -Average).Average

    @{
        trades          = $outcomes.Count
        wins            = $wins.Count
        losses          = $losses.Count
        win_rate        = if ($outcomes.Count -gt 0) { $wins.Count / $outcomes.Count } else { 0 }
        pnl_total_usd   = [math]::Round($pnl_usd, 2)
        pnl_avg_usd     = [math]::Round($pnl_usd / $outcomes.Count, 2)
        pnl_avg_pct     = [math]::Round($avg_pnl_pct, 2)
        avg_loss_pct    = if ($losses.Count -gt 0) {
            [math]::Round(($losses | Measure-Object pnl_pct -Average).Average, 3)
        } else { 0 }
        best_pnl        = ($outcomes | Measure-Object pnl_usd -Max).Maximum
        worst_pnl       = ($outcomes | Measure-Object pnl_usd -Min).Minimum
    }
}

function Get-CalibratedParams {
    [CmdletBinding()]
    param(
        [hashtable]$Stats,
        [hashtable]$CurrentParams = @{}
    )

    if (-not $Stats -or $Stats.trades -lt 5) {
        return $CurrentParams  # precisamos de minimo 5 trades pra calibrar
    }

    $calibrated = $CurrentParams.Clone()
    $changes = @()

    # 1) Threshold entrada (score minimo pra sinal)
    $wr = $Stats.win_rate
    # 2026-07-02 FIX: ?? e PS7-only; quebrava o parse do arquivo inteiro em PS 5.1
    $currentThreshold = if ($null -ne $CurrentParams['THRESHOLD_ENTRADA']) { $CurrentParams['THRESHOLD_ENTRADA'] } else { 70 }
    $newThreshold = $currentThreshold

    if ($wr -lt 0.35) {
        $newThreshold = [math]::Min($currentThreshold + 10, 80)  # leve no veto
        $changes += @{ param="THRESHOLD_ENTRADA"; old=$currentThreshold; new=$newThreshold; reason="low_wr_$([int]($wr*100))pct" }
    } elseif ($wr -gt 0.50) {
        $newThreshold = [math]::Max($currentThreshold - 5, 60)  # pode relaxar um pouco
        $changes += @{ param="THRESHOLD_ENTRADA"; old=$currentThreshold; new=$newThreshold; reason="good_wr_$([int]($wr*100))pct" }
    }

    $calibrated['THRESHOLD_ENTRADA'] = $newThreshold

    # 2) Stop loss width (apertar se avg loss > stop width atual)
    $avgLoss = [math]::Abs($Stats.avg_loss_pct)
    $currentStop = if ($null -ne $CurrentParams['STOP_LOSS_PCT']) { $CurrentParams['STOP_LOSS_PCT'] } else { 2.0 }
    $newStop = $currentStop

    if ($avgLoss -gt $currentStop) {
        $newStop = [math]::Max($currentStop - 0.5, 1.0)
        $changes += @{ param="STOP_LOSS_PCT"; old=$currentStop; new=$newStop; reason="avg_loss_$avgLoss exceeds_stop" }
    }

    $calibrated['STOP_LOSS_PCT'] = $newStop

    # 3) Target profit (RR 1:5 com stop novo)
    $newTarget = $newStop * 5
    $calibrated['TARGET_PROFIT_PCT'] = [math]::Round($newTarget, 2)

    # 4) Regime allocation (SHORT vs LONG)
    $pnl = $Stats.pnl_total_usd
    $shortRatio = if ($null -ne $CurrentParams['SHORT_RATIO']) { $CurrentParams['SHORT_RATIO'] } else { 0.5 }

    if ($pnl -gt 20 -and $Stats.wins -gt $Stats.losses) {
        # Win rate positivo, mantém allocation
        $newRatio = $shortRatio
    } elseif ($pnl -lt -10) {
        # Losing streak, aumenta SHORT (memo diz SHORT +3.2% EV em BEAR)
        $newRatio = [math]::Min($shortRatio + 0.10, 0.85)
        $changes += @{ param="SHORT_RATIO"; old=$shortRatio; new=$newRatio; reason="losing_streak" }
    }

    $calibrated['SHORT_RATIO'] = [math]::Round($newRatio, 2)

    @{
        stats       = $Stats
        calibrated  = $calibrated
        changes     = $changes
    }
}

function Write-CalibrationReport {
    [CmdletBinding()]
    param(
        [hashtable]$Calibration,
        [string]$OutputFile
    )

    $report = @{
        timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        stats       = $Calibration.stats
        calibrated  = $Calibration.calibrated
        changes     = $Calibration.changes
    }

    $report | ConvertTo-Json | Add-Content $OutputFile
}

# Export-ModuleMember nao necessario em dot-source; comentado para compatibilidade Pester
