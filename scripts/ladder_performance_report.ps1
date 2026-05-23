# ladder_performance_report.ps1 — Agrega performance de ladder exits por (template_id x regime)
# Lê journal/ladder_tracker.csv + ladder_hits.csv
# Output: journal/ladder_performance_YYYY-MM-DD.json
# UTF-8 BOM, pure aggregation, no dependencies

param(
    [Parameter()] [string] $JournalDir = $(Join-Path $PSScriptRoot "..\journal"),
    [Parameter()] [datetime] $AsOfDate = (Get-Date)
)

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
function Ensure-Directory {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Parse-CsvSafely {
    param(
        [string] $FilePath,
        [scriptblock] $Processor = { $_ }
    )
    if (-not (Test-Path $FilePath)) {
        return @()
    }
    try {
        $rows = Import-Csv -Path $FilePath -ErrorAction Stop
        if ($null -eq $rows) { return @() }
        if ($rows -isnot [array]) { $rows = @($rows) }
        return $rows | ForEach-Object $Processor
    } catch {
        Write-Host "  [Warning] Falha ao ler $FilePath`: $_" -ForegroundColor Yellow
        return @()
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Main: Read data
# ─────────────────────────────────────────────────────────────────────────────
Ensure-Directory $JournalDir

$ladderTrackerFile = Join-Path $JournalDir "ladder_tracker.csv"
$ladderHitsFile = Join-Path $JournalDir "ladder_hits.csv"

$tracker = Parse-CsvSafely -FilePath $ladderTrackerFile
$hits = Parse-CsvSafely -FilePath $ladderHitsFile

# ─────────────────────────────────────────────────────────────────────────────
# Parse tracker: template_id, regime, entry_price, take_profit_levels, stop_loss
# Parse hits: template_id, regime, hit_level, profit_realized_R
# ─────────────────────────────────────────────────────────────────────────────
$inv = [System.Globalization.CultureInfo]::InvariantCulture

# Agrupa tracker por (template_id, regime)
$byTemplate = @{}
foreach ($t in $tracker) {
    if ([string]::IsNullOrEmpty($t.template_id) -or [string]::IsNullOrEmpty($t.regime)) {
        continue
    }
    $key = "$($t.template_id)__$($t.regime)"
    if (-not $byTemplate.ContainsKey($key)) {
        $byTemplate[$key] = @{
            template_id = $t.template_id
            regime = $t.regime
            total_setups = 0
            hit_count = 0
            hit_details = @()
        }
    }
    $byTemplate[$key].total_setups += 1
}

# Agrupa hits por (template_id, regime) e calcula profit
foreach ($h in $hits) {
    if ([string]::IsNullOrEmpty($h.template_id) -or [string]::IsNullOrEmpty($h.regime)) {
        continue
    }
    $key = "$($h.template_id)__$($h.regime)"

    if ($byTemplate.ContainsKey($key)) {
        $byTemplate[$key].hit_count += 1

        # Calcula realized profit (em R)
        $profitR = 0.0
        if (-not [string]::IsNullOrEmpty($h.profit_realized_R)) {
            $profitStr = $h.profit_realized_R -replace ',', '.'
            [double]::TryParse($profitStr, [System.Globalization.NumberStyles]::Any, $inv, [ref] $profitR) | Out-Null
        }

        $level = if (-not [string]::IsNullOrEmpty($h.hit_level)) { [int]$h.hit_level } else { 0 }

        $byTemplate[$key].hit_details += [PSCustomObject]@{
            hit_level       = $level
            profit_r        = $profitR
            timestamp       = $h.timestamp
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Calcula metricas por template
# ─────────────────────────────────────────────────────────────────────────────
$results = @()

foreach ($entry in $byTemplate.GetEnumerator()) {
    $data = $entry.Value

    $winRate = if ($data.total_setups -gt 0) {
        [math]::Round(($data.hit_count / $data.total_setups) * 100, 2)
    } else {
        0.0
    }

    # Calcula average R realizado vs expected (assuming 1R expected por hit)
    $avgRRealized = 0.0
    if ($data.hit_details.Count -gt 0) {
        $sumR = ($data.hit_details | Measure-Object -Property profit_r -Sum).Sum
        $avgRRealized = [math]::Round($sumR / $data.hit_details.Count, 3)
    }

    # Calcula runner survival (quantos hits em level >= 2)
    $runnerCount = ($data.hit_details | Where-Object { $_.hit_level -ge 2 }).Count
    $runnerSurvival = if ($data.hit_details.Count -gt 0) {
        [math]::Round(($runnerCount / $data.hit_details.Count) * 100, 2)
    } else {
        0.0
    }

    # Max profit R observado
    $maxProfitR = if ($data.hit_details.Count -gt 0) {
        ($data.hit_details | Measure-Object -Property profit_r -Maximum).Maximum
    } else {
        0.0
    }

    # Min profit R observado
    $minProfitR = if ($data.hit_details.Count -gt 0) {
        ($data.hit_details | Measure-Object -Property profit_r -Minimum).Minimum
    } else {
        0.0
    }

    $results += [PSCustomObject]@{
        template_id              = $data.template_id
        regime                   = $data.regime
        sample_size              = $data.total_setups
        win_rate_pct             = $winRate
        avg_r_realized_vs_expected = $avgRRealized
        runner_survival_pct      = $runnerSurvival
        max_profit_r             = $maxProfitR
        min_profit_r             = $minProfitR
        hit_count                = $data.hit_count
        generated_at             = (Get-Date).ToUniversalTime().ToString("o")
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Output JSON
# ─────────────────────────────────────────────────────────────────────────────
$outputFileName = "ladder_performance_{0:yyyy-MM-dd}.json" -f $AsOfDate
$outputPath = Join-Path $JournalDir $outputFileName

$output = [PSCustomObject]@{
    report_date = $AsOfDate.ToString("yyyy-MM-dd")
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    templates_count = $results.Count
    data = $results
}

$output | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding utf8 -Force

Write-Host "  [OK] Relatorio gravado: $outputPath" -ForegroundColor Green
Write-Host "  [Summary] $($results.Count) template(s) analisado(s)" -ForegroundColor Cyan

# Opcional: imprime resumo
if ($results.Count -gt 0) {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ LADDER PERFORMANCE SUMMARY                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    $results | Sort-Object -Property sample_size -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Host ("  {0,-15} {1,-10} win_rate={2,6}% avg_R={3,7:F3} runner={4,6}% n={5}" -f `
            $_.template_id, $_.regime, $_.win_rate_pct, $_.avg_r_realized_vs_expected, $_.runner_survival_pct, $_.sample_size)
    }
}

return [PSCustomObject]@{
    output_path = $outputPath
    templates_count = $results.Count
    results = $results
}
