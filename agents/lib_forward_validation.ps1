# lib_forward_validation.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-WalkForwardTest {
    param(
        [Parameter(Mandatory)] [double] $BacktestMetric,
        [Parameter(Mandatory)] [double] $ForwardMetric,
        [Parameter(Mandatory)] [string] $MetricName,
        [int] $OverfitThreshold = 30,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $valPath = Join-Path $JournalDir "forward_validation.jsonl"

    # Calculate forward error %
    $error_pct = if ($BacktestMetric -gt 0) {
        [Math]::Abs(($BacktestMetric - $ForwardMetric) / $BacktestMetric) * 100
    } else { 0 }

    $passes = $error_pct -le $OverfitThreshold
    $reason = if ($passes) { "OK" } else { "Overfitting detected: $error_pct% error > threshold $OverfitThreshold%" }

    # Log
    $entry = [ordered]@{
        timestamp = $timestamp
        metric_name = $MetricName
        backtest_value = $BacktestMetric
        forward_value = $ForwardMetric
        forward_error_pct = [Math]::Round($error_pct, 2)
        overfit_threshold = $OverfitThreshold
        passes = $passes
        reason = $reason
    } | ConvertTo-Json -Compress

    Add-Content -Path $valPath -Value $entry -Encoding UTF8

    return [PSCustomObject]@{
        passes = $passes
        reason = $reason
        forward_error_pct = [Math]::Round($error_pct, 2)
        metric_name = $MetricName
        backtest_value = $BacktestMetric
        forward_value = $ForwardMetric
    }
}
