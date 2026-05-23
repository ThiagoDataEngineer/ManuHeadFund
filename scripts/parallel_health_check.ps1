# parallel_health_check.ps1 -- Audita 7d de paper trade pra decidir se -Parallel
# pode virar default. Le decisions.csv + master_*.log.
#
# Criterios pra "estavel" (todos precisam passar):
#   - decisions.csv tem >= 10 decisions ultimos 7d
#   - 0 fallback "Parallel orchestrator falhou" no log
#   - >= 3 ciclos com "Parallel orchestrator: N/M resultados em Xs" + X < 120s
#   - 0 tipo "ERROR" no log relacionado a runspace/parallel
#
# Uso:
#   .\scripts\parallel_health_check.ps1           # audita, sugere acao
#   .\scripts\parallel_health_check.ps1 -Enable   # cria journal/PARALLEL_DEFAULT_ENABLED.flag
#   .\scripts\parallel_health_check.ps1 -Disable  # remove flag

param([switch]$Enable, [switch]$Disable)

$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$journalDir  = Join-Path $projectRoot "journal"
$logDir      = Join-Path $projectRoot "logs"
$flagFile    = Join-Path $journalDir "PARALLEL_DEFAULT_ENABLED.flag"

if ($Disable) {
    if (Test-Path $flagFile) {
        Remove-Item $flagFile -Force
        Write-Host "[OK] Flag removida. -Parallel volta a ser opt-in (CLI ou config)." -ForegroundColor Yellow
    } else { Write-Host "Flag ja nao existe." }
    exit 0
}

# Auditoria
$decCsv = Join-Path $journalDir "decisions.csv"
$cutoff = (Get-Date).AddDays(-7)
$decCount = 0
if (Test-Path $decCsv) {
    try {
        $rows = Import-Csv $decCsv -ErrorAction Stop
        $decCount = @($rows | Where-Object {
            try { [DateTime]::Parse($_.timestamp).ToUniversalTime() -ge $cutoff.ToUniversalTime() } catch { $false }
        }).Count
    } catch {}
}

$logs = Get-ChildItem $logDir -Filter "master_*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cutoff } | Sort-Object LastWriteTime
$parallelOk = 0; $parallelFail = 0; $parallelErrors = 0; $latencies = @()
foreach ($lf in $logs) {
    $content = Get-Content $lf.FullName -ErrorAction SilentlyContinue
    foreach ($line in $content) {
        if ($line -match 'Parallel orchestrator falhou') { $parallelFail++ }
        elseif ($line -match 'Parallel orchestrator:\s*(\d+)/\d+\s*resultados em ([\d,\.]+)s') {
            $parallelOk++
            $latStr = $matches[2] -replace ',', '.'
            [double]$lat = 0
            if ([double]::TryParse($latStr, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lat)) {
                $latencies += $lat
            }
        }
        elseif ($line -match '\[ERROR\].*(runspace|RunspacePool|orchestrator_parallel)') { $parallelErrors++ }
    }
}

$avgLat = if ($latencies.Count -gt 0) { [Math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 0 }
$maxLat = if ($latencies.Count -gt 0) { [Math]::Round(($latencies | Measure-Object -Maximum).Maximum, 1) } else { 0 }

# Avaliacao
$criteria = @{
    "decisions >= 10"               = $decCount -ge 10
    "0 fallback parallel falhou"    = $parallelFail -eq 0
    ">= 3 ciclos parallel OK"       = $parallelOk -ge 3
    "0 ERROR runspace/parallel"     = $parallelErrors -eq 0
    "avg latency < 120s"            = $latencies.Count -gt 0 -and $avgLat -lt 120
}
$allPass = $true
foreach ($k in $criteria.Keys) { if (-not $criteria[$k]) { $allPass = $false } }

Write-Host ""
Write-Host "=== Parallel Health Check ===" -ForegroundColor Cyan
Write-Host "Janela: ultimos 7 dias (desde $($cutoff.ToString('yyyy-MM-dd HH:mm')))"
Write-Host ""
Write-Host "Metricas:" -ForegroundColor Yellow
Write-Host "  decisions.csv      : $decCount rows"
Write-Host "  parallel cycles OK : $parallelOk"
Write-Host "  parallel fallbacks : $parallelFail"
Write-Host "  parallel errors    : $parallelErrors"
Write-Host "  latency avg/max    : ${avgLat}s / ${maxLat}s"
Write-Host ""
Write-Host "Criterios:" -ForegroundColor Yellow
foreach ($k in $criteria.Keys) {
    $color = if ($criteria[$k]) { "Green" } else { "Red" }
    $mark  = if ($criteria[$k]) { "[OK]" } else { "[FAIL]" }
    Write-Host ("  $mark $k") -ForegroundColor $color
}
Write-Host ""

$flagPresent = Test-Path $flagFile
if ($allPass) {
    Write-Host "VERDICT: STABLE -- -Parallel safe to enable as default" -ForegroundColor Green
    if ($Enable -or $allPass -and -not $flagPresent) {
        if ($Enable) {
            @{ enabled_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ");
               criteria_passed = $true; latency_avg_s = $avgLat } | ConvertTo-Json |
                Out-File $flagFile -Encoding utf8 -Force
            Write-Host "[OK] Flag criada: $flagFile" -ForegroundColor Green
            Write-Host "Proximo run de scan_master usa -Parallel automatico."
        } else {
            Write-Host "Rode com -Enable pra criar a flag (ou crie manualmente)."
        }
    } elseif ($flagPresent) {
        Write-Host "Flag JA presente: $flagFile"
    }
} else {
    Write-Host "VERDICT: NOT STABLE YET -- aguardar mais dados" -ForegroundColor Yellow
    if ($Enable) {
        Write-Host "ABORT: -Enable bloqueado pq criterios falham. Force via 'New-Item $flagFile' se realmente quiser." -ForegroundColor Red
        exit 1
    }
}
Write-Host ""
Write-Host "Flag atual: $(if ($flagPresent) { 'ATIVA' } else { 'INATIVA' })"
exit 0
