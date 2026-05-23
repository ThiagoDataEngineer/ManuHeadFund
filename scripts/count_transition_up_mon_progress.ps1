[CmdletBinding()]
param(
    [string]$TradesJsonPath = $null,
    [DateTime]$SinceDate    = ([DateTime]::Parse("2023-01-01T00:00:00Z")),
    [int]$Target            = 30,
    [string]$OutputPath     = $null
)

# count_transition_up_mon_progress.ps1 - Contador progresso TRANSITION_UP + Mon + LONG pos-2023
#
# CONTRATO:
#   Test-DayIsMondayBRT -Timestamp <string> -> bool
#     Converte UTC -> BRT (UTC-3) e retorna true se DoW resultante e Monday.
#
#   Get-TransitionUpMonTrades -Trades <array> [-SinceDate <DateTime>] -> array
#     Filtra trades: regime=TRANSITION_UP, direction=LONG, entry_ts em Mon BRT, entry_ts >= SinceDate (UTC).
#
#   Measure-SubsetupMetrics -Trades <array> -> PSCustomObject
#     Retorna { trades, exp, pf, wr }. Lista vazia -> zeros.
#
#   Format-ProgressReport -Count <int> -Target <int> -Metrics <PSCustomObject> -> PSCustomObject
#     Retorna { count, target, missing, exp, pf, wr, status }.
#     status = VIABLE se count >= target, senao NEEDS_MORE_DATA.
#
# CRITERIO VIABLE: count >= 30 (n_holdout minimo)
#
# Tested in: tests/count_transition_up_mon_progress.Tests.ps1 (Pester 3.x).
#
# Uso programatico (dot-source):
#   . scripts/count_transition_up_mon_progress.ps1
#   $trades   = Get-Content journal/trades_dump.json | ConvertFrom-Json
#   $filtered = Get-TransitionUpMonTrades -Trades $trades -SinceDate ([DateTime]::Parse("2023-01-01"))
#   $metrics  = Measure-SubsetupMetrics -Trades $filtered
#   $report   = Format-ProgressReport -Count $filtered.Count -Target 30 -Metrics $metrics

function Test-DayIsMondayBRT {
    param([Parameter(Mandatory=$true)]$Timestamp)
    # Aceita string ISO 8601 OU [DateTime] (ConvertFrom-Json pode auto-converter)
    if ($Timestamp -is [DateTime]) {
        $dto = [DateTimeOffset]::new($Timestamp, [TimeSpan]::Zero)
    } elseif ($Timestamp -is [DateTimeOffset]) {
        $dto = $Timestamp
    } else {
        $dto = [DateTimeOffset]::Parse([string]$Timestamp, [Globalization.CultureInfo]::InvariantCulture)
    }
    $brt = $dto.UtcDateTime.AddHours(-3)
    return $brt.DayOfWeek -eq [DayOfWeek]::Monday
}

function Get-TransitionUpMonTrades {
    param(
        [Parameter(Mandatory=$true)][array]$Trades,
        [DateTime]$SinceDate = [DateTime]::MinValue
    )
    $out = New-Object System.Collections.ArrayList
    foreach ($t in $Trades) {
        if ($t.regime    -ne "TRANSITION_UP") { continue }
        if ($t.direction -ne "LONG")          { continue }
        if (-not (Test-DayIsMondayBRT -Timestamp $t.entry_ts)) { continue }
        if ($t.entry_ts -is [DateTime]) {
            $utc = [DateTime]::SpecifyKind($t.entry_ts, [DateTimeKind]::Utc)
        } else {
            $utc = [DateTimeOffset]::Parse([string]$t.entry_ts, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
        }
        if ($utc -lt $SinceDate) { continue }
        [void]$out.Add($t)
    }
    return $out.ToArray()
}

function Measure-SubsetupMetrics {
    param([array]$Trades = @())
    if (-not $Trades -or $Trades.Count -eq 0) {
        return [PSCustomObject]@{ trades = 0; exp = 0.0; pf = 0.0; wr = 0.0 }
    }
    $rs = @()
    foreach ($t in $Trades) { $rs += [double]$t.result_r }
    $n = $rs.Count
    $sum = 0.0
    foreach ($r in $rs) { $sum += $r }
    $mean = $sum / $n

    $gp = 0.0; $gl = 0.0; $wins = 0
    foreach ($r in $rs) {
        if ($r -gt 0) { $gp += $r; $wins++ }
        else          { $gl += [math]::Abs($r) }
    }
    $pf = if ($gl -gt 0) { $gp / $gl } else { 0.0 }
    $wr = if ($n -gt 0) { ($wins / [double]$n) * 100.0 } else { 0.0 }

    return [PSCustomObject]@{
        trades = $n
        exp    = [math]::Round($mean, 4)
        pf     = [math]::Round($pf, 4)
        wr     = [math]::Round($wr, 2)
    }
}

function Format-ProgressReport {
    param(
        [Parameter(Mandatory=$true)][int]$Count,
        [int]$Target = 30,
        [Parameter(Mandatory=$true)][PSCustomObject]$Metrics
    )
    $missing = [math]::Max(0, $Target - $Count)
    $status = if ($Count -ge $Target) { "VIABLE" } else { "NEEDS_MORE_DATA" }
    return [PSCustomObject]@{
        count   = $Count
        target  = $Target
        missing = $missing
        exp     = $Metrics.exp
        pf      = $Metrics.pf
        wr      = $Metrics.wr
        status  = $status
    }
}

# ============================================================================
# CLI mode - so executa quando o script eh chamado diretamente (nao dot-sourced)
# ============================================================================
if ($MyInvocation.InvocationName -ne "." -and $MyInvocation.InvocationName -ne "&") {
    if (-not $TradesJsonPath) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        $TradesJsonPath = Join-Path $here "..\journal\transition_up_trades_dump.json"
    }
    if (-not (Test-Path $TradesJsonPath)) {
        Write-Warning "Arquivo de trades nao encontrado: $TradesJsonPath"
        Write-Warning "Gere o dump primeiro via Python: python backtest/dump_transition_up_trades.py"
        return
    }

    $raw = Get-Content $TradesJsonPath -Raw -Encoding UTF8
    $parsed = $raw | ConvertFrom-Json
    # ConvertFrom-Json retorna Object[] direto; @() wrappa em array de 1 elemento (bug PS 5.1)
    if ($parsed -is [array]) { $trades = $parsed } else { $trades = @($parsed) }

    $filtered = Get-TransitionUpMonTrades -Trades $trades -SinceDate $SinceDate
    $metrics  = Measure-SubsetupMetrics  -Trades $filtered
    $report   = Format-ProgressReport    -Count $filtered.Count -Target $Target -Metrics $metrics

    Write-Host ""
    Write-Host "TRANSITION_UP + Mon + LONG (post-$($SinceDate.ToString('yyyy-MM-dd'))):" -ForegroundColor Cyan
    Write-Host "  trades: $($report.count) / $($report.target) (faltam $($report.missing))"
    Write-Host "  exp: +$($report.exp) R | pf: $($report.pf) | wr: $($report.wr)%"
    $statusColor = if ($report.status -eq 'VIABLE') { 'Green' } else { 'Yellow' }
    Write-Host "  status: $($report.status)" -ForegroundColor $statusColor

    if (-not $OutputPath) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        $OutputPath = Join-Path $here "..\journal\transition_up_mon_progress.json"
    }
    $snap = [PSCustomObject]@{
        timestamp_utc    = (Get-Date).ToUniversalTime().ToString("o")
        since_date       = $SinceDate.ToString("o")
        trades_source    = $TradesJsonPath
        report           = $report
    }
    $snap | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host "Snapshot saved: $OutputPath"
}
