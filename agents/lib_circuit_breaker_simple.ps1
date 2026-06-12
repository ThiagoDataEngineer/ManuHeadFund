# lib_circuit_breaker_simple.ps1 — Circuit breaker -2% daily (SIMPLIFICADO)

function Get-DailyPnL {
    param([string]$JournalDir = $global:JOURNAL_DIR)
    if (-not $JournalDir) { $JournalDir = (Join-Path (Split-Path $PSScriptRoot) "journal") }

    $outcomeFile = Join-Path $JournalDir "trade_outcomes.jsonl"
    if (-not (Test-Path $outcomeFile)) { return 0.0 }

    $today = (Get-Date).Date
    $pnl = 0.0

    # Read JSONL line by line (not Raw, split by newline)
    Get-Content $outcomeFile | Where-Object { $_ -match '^\{' } | ForEach-Object {
        try {
            $obj = ConvertFrom-Json $_
            $exitDate = [datetime]::ParseExact($obj.exit_date, "yyyy-MM-dd", $null).Date
            if ($exitDate -eq $today) {
                $pnl += [double]$obj.pnl_usd
            }
        } catch { }
    }
    return $pnl
}

function Test-CircuitBreakerTriggered {
    param([double]$Capital = 3645.0, [double]$DailyLossThreshold = -0.02)
    $dailyPnL = Get-DailyPnL
    $threshold = $Capital * $DailyLossThreshold
    return ($dailyPnL -lt $threshold)
}

function Reset-CircuitBreaker {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
    Remove-Item $flagPath -ErrorAction SilentlyContinue
}

function Set-CircuitBreakerPause {
    $journalDir = if ($global:JOURNAL_DIR) { $global:JOURNAL_DIR } else { (Join-Path (Split-Path $PSScriptRoot) "journal") }
    if (-not (Test-Path $journalDir)) { mkdir $journalDir | Out-Null }
    $flagPath = Join-Path $journalDir "CIRCUIT_BREAKER_PAUSED.flag"
    Add-Content -Path $flagPath -Value "paused $(Get-Date)" -Encoding UTF8
}
