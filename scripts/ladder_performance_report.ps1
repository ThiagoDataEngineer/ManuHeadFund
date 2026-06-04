# ladder_performance_report.ps1 -- Agrega performance ladder por template x regime
# PS 5.1. UTF-8 BOM.
param(
    [string]   $JournalDir = (Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "..\journal"),
    [datetime] $AsOfDate   = (Get-Date)
)

$trackerFile = Join-Path $JournalDir "ladder_tracker.csv"
$hitsFile    = Join-Path $JournalDir "ladder_hits.csv"
$outputFile  = Join-Path $JournalDir ("ladder_performance_" + $AsOfDate.ToString("yyyyMMdd") + ".json")

$results         = @()
$templates_count = 0

try {
    if ((Test-Path $trackerFile) -and (Test-Path $hitsFile)) {
        $tracker = Import-Csv $trackerFile -EA SilentlyContinue
        $hits    = Import-Csv $hitsFile    -EA SilentlyContinue

        $groups = $tracker | Group-Object template_id
        $templates_count = $groups.Count

        foreach ($g in $groups) {
            $tplId      = $g.Name
            $tplEntries = @($g.Group)
            $tplHits    = @($hits | Where-Object { $_.template_id -eq $tplId })

            $hitCount  = $tplHits.Count
            $totalR    = if ($hitCount -gt 0) { ($tplHits | Measure-Object -Property profit_realized_R -Sum).Sum } else { 0 }
            $avgR      = if ($hitCount -gt 0) { [math]::Round($totalR / $hitCount, 3) } else { 0 }

            $results += [PSCustomObject]@{
                template_id    = $tplId
                regime         = ($tplEntries | Select-Object -First 1).regime
                entries        = $tplEntries.Count
                hits           = $hitCount
                total_R        = [math]::Round([double]$totalR, 3)
                avg_R          = $avgR
                generated_at   = $AsOfDate.ToString("o")
            }
        }
    }
} catch {}

$report = [PSCustomObject]@{
    output_path      = $outputFile
    templates_count  = $templates_count
    as_of_date       = $AsOfDate.ToString("o")
    results          = $results
    generated_at     = (Get-Date).ToString("o")
}

$report | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputFile -Encoding utf8 -Force
return $report
