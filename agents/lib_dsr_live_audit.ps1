# lib_dsr_live_audit.ps1

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

function Invoke-DsrLiveAudit {
    param(
        [Parameter(Mandatory)] [double[]] $Returns,
        [Parameter(Mandatory)] [string] $Market,
        [bool] $ForwardValidated = $false,
        [string] $JournalDir = $global:JOURNAL_DIR,
        [datetime] $Now = (Get-Date)
    )

    if (-not (Test-Path $JournalDir)) {
        New-Item -ItemType Directory -Path $JournalDir -Force | Out-Null
    }

    $timestamp = $Now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $auditPath = Join-Path $JournalDir "dsr_live_audit.jsonl"

    $n = $Returns.Count
    $confidence = if ($n -lt 30) { "LOW" } elseif ($n -lt 60) { "MEDIUM" } else { "HIGH" }

    # Calculate Sharpe (simplified)
    $mean = ($Returns | Measure-Object -Average).Average
    $variance = (($Returns | ForEach-Object { ($_ - $mean) * ($_ - $mean) }) | Measure-Object -Average).Average
    $std = [Math]::Sqrt($variance)
    $sharpe = if ($std -gt 0) { $mean / $std } else { 0 }

    # DSR = min(Sharpe / sqrt(n), 1.0)
    $dsrValue = [Math]::Min([Math]::Abs($sharpe) / [Math]::Sqrt([Math]::Max($n, 1)), 1.0)

    $auditEntry = [ordered]@{
        timestamp = $timestamp
        market = $Market
        n_samples = $n
        sharpe = [Math]::Round($sharpe, 4)
        psr = [Math]::Round($sharpe / [Math]::Sqrt([Math]::Max($n, 1)), 4)
        dsr_value = [Math]::Round($dsrValue, 4)
        confidence = $confidence
        forward_validated = $ForwardValidated
    } | ConvertTo-Json -Compress

    Add-Content -Path $auditPath -Value $auditEntry -Encoding UTF8

    return [PSCustomObject]@{
        dsr_value = $dsrValue
        sharpe = $sharpe
        n_samples = $n
        confidence = $confidence
        forward_validated = $ForwardValidated
    }
}
