# lib_kelly_graduation.ps1 -- Auto-activator pra $global:USE_KELLY_SIZING.
#
# Criterios pra graduate Kelly:
#   - >= MinTrades (default 10) outcomes acumulados
#   - win_rate >= MinWinRate (default 0.40)
#   - avg_r >= MinAvgR (default 0.0 = nao loss-making)
#
# Quando criterios passam, cria journal/USE_KELLY_SIZING.flag que sera lido
# por config.local.ps1 (ou scan_master init) pra setar $global:USE_KELLY_SIZING=$true.
#
# Cron daily roda Test-KellyGraduationCriteria + Enable-KellySizing se passar.

if (-not $global:JOURNAL_DIR) {
    $global:JOURNAL_DIR = Join-Path (Split-Path $PSScriptRoot -Parent) "journal"
}

$script:KELLY_FLAG_PATH = Join-Path $global:JOURNAL_DIR "USE_KELLY_SIZING.flag"


function Test-KellyGraduationCriteria {
    [CmdletBinding()]
    param(
        [string] $OutcomePath = (Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl"),
        [int] $MinTrades = 10,
        [double] $MinWinRate = 0.40,
        [double] $MinAvgR = 0.0
    )
    $stats = if (Get-Command Get-OutcomeStats -ErrorAction SilentlyContinue) {
        Get-OutcomeStats -OutcomePath $OutcomePath
    } else {
        [PSCustomObject]@{ n = 0; win_rate = 0; avg_r = 0 }
    }

    $passes = $true
    $failures = @()

    if ([int]$stats.n -lt $MinTrades) {
        $passes = $false
        $failures += "insufficient_trades_$($stats.n)_lt_$MinTrades"
    }
    if ([double]$stats.win_rate -lt $MinWinRate) {
        $passes = $false
        $failures += "win_rate_$($stats.win_rate)_lt_$MinWinRate"
    }
    if ([double]$stats.avg_r -lt $MinAvgR) {
        $passes = $false
        $failures += "avg_r_$($stats.avg_r)_lt_$MinAvgR"
    }

    return [PSCustomObject]@{
        passes    = $passes
        n_trades  = [int]$stats.n
        win_rate  = [double]$stats.win_rate
        avg_r     = [double]$stats.avg_r
        reason    = if ($passes) { "all_criteria_passed" } else { ($failures -join "|") }
        criteria  = @{
            min_trades   = $MinTrades
            min_win_rate = $MinWinRate
            min_avg_r    = $MinAvgR
        }
    }
}


function Enable-KellySizing {
    [CmdletBinding()]
    param(
        [string] $FlagPath = $script:KELLY_FLAG_PATH,
        [string] $Reason = "graduation_criteria_passed"
    )
    $dir = Split-Path $FlagPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $already = Test-Path $FlagPath
    @{
        enabled_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        reason     = $Reason
    } | ConvertTo-Json | Out-File $FlagPath -Encoding utf8 -Force

    return [PSCustomObject]@{
        enabled       = $true
        flag_path     = $FlagPath
        was_already   = $already
        reason        = $Reason
    }
}


function Invoke-KellyGraduationAudit {
    # Wrapper: roda Test-KellyGraduationCriteria + Enable-KellySizing se passar.
    # Output suitable pra cron + log.
    [CmdletBinding()]
    param(
        [string] $OutcomePath = (Join-Path $global:JOURNAL_DIR "trade_outcomes.jsonl"),
        [string] $FlagPath = $script:KELLY_FLAG_PATH
    )
    $check = Test-KellyGraduationCriteria -OutcomePath $OutcomePath
    Write-Host "[Kelly Audit] n=$($check.n_trades) win_rate=$($check.win_rate) avg_r=$($check.avg_r) passes=$($check.passes)" -ForegroundColor Cyan
    if (-not $check.passes) {
        Write-Host "  Reason: $($check.reason)" -ForegroundColor DarkYellow
        return [PSCustomObject]@{ action = "wait"; check = $check }
    }
    $en = Enable-KellySizing -FlagPath $FlagPath -Reason "auto_graduated_n_$($check.n_trades)"
    Write-Host "[Kelly Audit] FLAG ENABLED: $($en.flag_path)" -ForegroundColor Green
    return [PSCustomObject]@{ action = "enabled"; check = $check; enable = $en }
}
