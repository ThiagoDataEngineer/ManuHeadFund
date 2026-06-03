# weekly_metrics_faro_short.ps1
# Weekly monitoring dashboard for FARO aggressive + SHORT vol_climax
# Run: pwsh .\scripts\weekly_metrics_faro_short.ps1

param(
    [string]$JournalPath = ".\journal",
    [string]$LogsPath = ".\logs"
)

function Get-FaroMetrics {
    param([string]$Path)

    $gemSignalsFile = Join-Path $Path "gem_signals.csv"
    $decisionsFile = Join-Path $Path "decisions.csv"

    $faroGems = @()
    $faroWins = @()

    if (Test-Path $gemSignalsFile) {
        $faroGems = @(Get-Content $gemSignalsFile | ConvertFrom-Csv -ErrorAction SilentlyContinue)
        $faroWins = @($faroGems | Where-Object { $_.status -eq "WIN" })
    }

    return @{
        total_gems = $faroGems.Count
        wins = $faroWins.Count
        win_rate = if ($faroGems.Count -gt 0) { [math]::Round(($faroWins.Count / $faroGems.Count) * 100, 1) } else { 0 }
        false_positives = 0  # calculated from obs that didn't pump
    }
}

function Get-ShortMetrics {
    param([string]$Path)

    $obsFile = Join-Path $Path "observations.csv"
    $observations = @()

    if (Test-Path $obsFile) {
        $observations = @(Get-Content $obsFile | ConvertFrom-Csv -ErrorAction SilentlyContinue | Where-Object { $_.signal_type -eq "vol_climax" })
    }

    return @{
        total_signals = $observations.Count
        avg_rsi = if ($observations.Count -gt 0) { [math]::Round(($observations.rsi | Measure-Object -Average).Average, 1) } else { 0 }
        avg_vol_ratio = if ($observations.Count -gt 0) { [math]::Round(($observations.vol_ratio | Measure-Object -Average).Average, 2) } else { 0 }
        avg_adx = if ($observations.Count -gt 0) { [math]::Round(($observations.adx | Measure-Object -Average).Average, 1) } else { 0 }
    }
}

# DASHBOARD
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "📊 WEEKLY METRICS — FARO Aggressive + SHORT vol_climax" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$faroMetrics = Get-FaroMetrics $JournalPath
$shortMetrics = Get-ShortMetrics $JournalPath

Write-Host "🎯 FARO V3 (Score 28, Paper Mode)" -ForegroundColor Yellow
Write-Host "   Total gems captured: $($faroMetrics.total_gems)" -ForegroundColor Gray
Write-Host "   Wins: $($faroMetrics.wins)" -ForegroundColor Gray
Write-Host "   Win rate: $($faroMetrics.win_rate)%" -ForegroundColor Gray

Write-Host ""
Write-Host "🔍 SHORT vol_climax (Observation Only)" -ForegroundColor Yellow
Write-Host "   Signals collected: $($shortMetrics.total_signals)" -ForegroundColor Gray
Write-Host "   Avg RSI: $($shortMetrics.avg_rsi)" -ForegroundColor Gray
Write-Host "   Avg vol ratio: $($shortMetrics.avg_vol_ratio)x" -ForegroundColor Gray
Write-Host "   Avg ADX: $($shortMetrics.avg_adx)" -ForegroundColor Gray

Write-Host ""
Write-Host "✅ CHECKLIST STATUS:" -ForegroundColor Cyan
Write-Host ""

# FARO Checklist
Write-Host "FARO (Week 1):" -ForegroundColor Yellow
Write-Host "   [$(if ($faroMetrics.total_gems -ge 2) { '✓' } else { ' ' })] Hit rate: 2+ pumps? ($($faroMetrics.total_gems) captured)" -ForegroundColor Gray
Write-Host "   [ ] False positives: ≤ 2/week?" -ForegroundColor Gray
Write-Host "   [ ] Win rate: ≥ 50%?" -ForegroundColor Gray

Write-Host ""
Write-Host "SHORT vol_climax (Weeks 2-4):" -ForegroundColor Yellow
Write-Host "   [$(if ($shortMetrics.total_signals -ge 50) { '✓' } else { ' ' })] Collect 50+ signals? ($($shortMetrics.total_signals) collected)" -ForegroundColor Gray
Write-Host "   [ ] Gate stability: metrics consistent?" -ForegroundColor Gray
Write-Host "   [ ] Ready to deploy in BEAR_STRONG?" -ForegroundColor Gray

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Last updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss BRT')" -ForegroundColor Gray
Write-Host ""
