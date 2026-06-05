# run_tests_parallel.ps1 -- Executa a suite Pester em paralelo via RunspacePool
# Divide os N arquivos de teste em W workers concorrentes. ~3-4x mais rapido que sequencial.
#
# Uso:
#   pwsh -File scripts\run_tests_parallel.ps1                  # auto workers (= CPU count)
#   pwsh -File scripts\run_tests_parallel.ps1 -Workers 8       # 8 workers
#   pwsh -File scripts\run_tests_parallel.ps1 -Filter "tori*"  # so arquivos que batem
#   pwsh -File scripts\run_tests_parallel.ps1 -FailFast        # para na primeira falha de arquivo
#
# PS 5.1. UTF-8 BOM.

param(
    [int]    $Workers  = 0,           # 0 = auto (numero de CPUs logicos)
    [string] $Filter   = "*.Tests.ps1",
    [switch] $FailFast,
    [switch] $Quiet                    # so mostra resumo final + falhas
)

$ErrorActionPreference = "Stop"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$testsDir    = Join-Path $projectRoot "tests"

if ($Workers -le 0) {
    $Workers = [Environment]::ProcessorCount
}

$files = @(Get-ChildItem -Path $testsDir -Filter $Filter -File | Sort-Object Length -Descending)
if ($files.Count -eq 0) {
    Write-Host "Nenhum arquivo de teste encontrado para filtro '$Filter'." -ForegroundColor Yellow
    exit 0
}

Write-Host "=== PESTER PARALLEL RUNNER ===" -ForegroundColor Cyan
Write-Host "Arquivos: $($files.Count) | Workers: $Workers | Tests dir: $testsDir" -ForegroundColor Gray
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

# Scriptblock executado em cada runspace: roda 1 arquivo de teste isolado.
# Cada runspace tem seu proprio escopo (isolamento entre arquivos), e importa Pester.
$worker = {
    param($TestFile)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Import-Module Pester -MinimumVersion 3.4.0 -ErrorAction SilentlyContinue
        $r = Invoke-Pester -Path $TestFile -PassThru -Quiet
        $failNames = @($r.TestResult | Where-Object { $_.Result -eq 'Failed' } | ForEach-Object { $_.Name })
        $sw.Stop()
        return [PSCustomObject]@{
            file       = Split-Path $TestFile -Leaf
            passed     = $r.PassedCount
            failed     = $r.FailedCount
            inconc     = $r.InconclusiveCount
            elapsed_ms = $sw.ElapsedMilliseconds
            fail_names = $failNames
            stderr     = ""
            ok         = ($r.FailedCount -eq 0)
        }
    } catch {
        $sw.Stop()
        return [PSCustomObject]@{
            file       = Split-Path $TestFile -Leaf
            passed     = 0; failed = -1; inconc = 0
            elapsed_ms = $sw.ElapsedMilliseconds
            fail_names = @("RUNNER_ERROR: $($_.Exception.Message)")
            stderr     = "$_"
            ok         = $false
        }
    }
}

$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$iss.ImportPSModule(@("Pester"))
$pool = [RunspaceFactory]::CreateRunspacePool(1, $Workers, $iss, $Host)
$pool.Open()
$jobs = @()
foreach ($f in $files) {
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($worker).AddArgument($f.FullName)
    $jobs += [PSCustomObject]@{ ps = $ps; handle = $ps.BeginInvoke(); file = $f.Name }
}

# Coleta resultados conforme completam
$totPass = 0; $totFail = 0; $totInconc = 0
$failedFiles = @()
$done = 0
while ($jobs | Where-Object { -not $_.handle.IsCompleted }) {
    foreach ($job in ($jobs | Where-Object { $_.handle.IsCompleted -and -not $_.collected })) {
        $res = $job.ps.EndInvoke($job.handle)[0]
        $job.ps.Dispose()
        $job | Add-Member -NotePropertyName collected -NotePropertyValue $true -Force
        $done++

        $totPass += $res.passed
        $totFail += [Math]::Max(0, $res.failed)
        $totInconc += $res.inconc

        if ($res.failed -gt 0 -or -not $res.ok) {
            $failedFiles += $res
            $tag = "[FAIL]"
            $color = "Red"
        } else {
            $tag = "[ OK ]"
            $color = "Green"
        }
        if (-not $Quiet -or $res.failed -gt 0) {
            $sec = [math]::Round($res.elapsed_ms / 1000, 1)
            Write-Host ("{0} {1,-55} P:{2,-4} F:{3,-3} ({4}s) [{5}/{6}]" -f $tag, $res.file, $res.passed, $res.failed, $sec, $done, $files.Count) -ForegroundColor $color
        }
        if ($FailFast -and $res.failed -gt 0) {
            Write-Host "`nFAILFAST: parando na primeira falha ($($res.file))" -ForegroundColor Yellow
            $pool.Close(); $pool.Dispose()
            exit 1
        }
    }
    Start-Sleep -Milliseconds 100
}
# Coleta remanescentes
foreach ($job in ($jobs | Where-Object { -not $_.collected })) {
    $res = $job.ps.EndInvoke($job.handle)[0]
    $job.ps.Dispose()
    $totPass += $res.passed
    $totFail += [Math]::Max(0, $res.failed)
    $totInconc += $res.inconc
    if ($res.failed -gt 0 -or -not $res.ok) { $failedFiles += $res }
}

$pool.Close(); $pool.Dispose()
$swTotal.Stop()

Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
Write-Host ("Passed: {0}  Failed: {1}  Inconclusive: {2}" -f $totPass, $totFail, $totInconc) -ForegroundColor $(if ($totFail -eq 0) { "Green" } else { "Red" })
Write-Host ("Tempo total: {0}s (vs ~360s sequencial)" -f [math]::Round($swTotal.Elapsed.TotalSeconds, 1)) -ForegroundColor Gray

if ($failedFiles.Count -gt 0) {
    Write-Host "`n=== ARQUIVOS COM FALHA ($($failedFiles.Count)) ===" -ForegroundColor Red
    foreach ($ff in ($failedFiles | Sort-Object { $_.failed } -Descending)) {
        Write-Host ("  [{0}] {1}" -f $ff.failed, $ff.file) -ForegroundColor Red
        foreach ($fn in ($ff.fail_names | Select-Object -First 5)) {
            Write-Host ("       - {0}" -f $fn) -ForegroundColor DarkGray
        }
    }
    exit 1
}
exit 0
