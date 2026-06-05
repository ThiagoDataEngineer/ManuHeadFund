# run_tests_parallel.ps1 -- Executa a suite Pester em PROCESSOS ISOLADOS paralelos.
# Cada arquivo de teste roda em seu proprio processo powershell.exe (isolamento TOTAL:
# zero poluicao de escopo inter-arquivo, que e o problema do Pester 3.x rodando tudo
# no mesmo processo). Resultados agregados via NUnit XML.
#
# Esta e a FONTE DE VERDADE da suite: numero limpo, sem falsos positivos de poluicao.
#
# Uso:
#   pwsh -File scripts\run_tests_parallel.ps1                  # auto workers (= CPU count)
#   pwsh -File scripts\run_tests_parallel.ps1 -Workers 8       # 8 workers
#   pwsh -File scripts\run_tests_parallel.ps1 -Filter "tori*"  # so arquivos que batem
#   pwsh -File scripts\run_tests_parallel.ps1 -FailFast        # para na 1a falha de arquivo
#   pwsh -File scripts\run_tests_parallel.ps1 -Quiet           # so resumo + falhas
#
# PS 5.1. UTF-8 BOM.

param(
    [int]    $Workers  = 0,
    [string] $Filter   = "*.Tests.ps1",
    [switch] $FailFast,
    [switch] $Quiet
)

$ErrorActionPreference = "Stop"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$testsDir    = Join-Path $projectRoot "tests"
$pwshExe     = (Get-Process -Id $PID).Path   # mesmo powershell.exe que invocou

if ($Workers -le 0) { $Workers = [Environment]::ProcessorCount }

# Ordena por tamanho desc (arquivos grandes/lentos primeiro -> melhor balanceamento)
$files = @(Get-ChildItem -Path $testsDir -Filter $Filter -File | Sort-Object Length -Descending)
if ($files.Count -eq 0) {
    Write-Host "Nenhum arquivo de teste para filtro '$Filter'." -ForegroundColor Yellow
    exit 0
}

# Dir temp para os NUnit XMLs
$xmlDir = Join-Path $env:TEMP ("pester_par_" + [guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null

Write-Host "=== PESTER PARALLEL (processos isolados) ===" -ForegroundColor Cyan
Write-Host "Arquivos: $($files.Count) | Workers: $Workers | Isolamento: processo/arquivo" -ForegroundColor Gray
$swTotal = [System.Diagnostics.Stopwatch]::StartNew()

# Parser do NUnit XML do Pester 3.x: root <test-results total= failures= inconclusive=>
function Read-NUnitResult {
    param([string]$XmlPath, [string]$TestFile)
    $res = [PSCustomObject]@{
        file = Split-Path $TestFile -Leaf; passed = 0; failed = -1; inconc = 0; fail_names = @()
    }
    if (-not (Test-Path $XmlPath)) { $res.fail_names = @("NO_XML (processo morreu ou erro de parse)"); return $res }
    try {
        [xml]$xml = Get-Content $XmlPath -Raw
        $root = $xml.'test-results'
        $total   = [int]$root.total
        $failures= [int]$root.failures
        $errors  = [int]$root.errors
        $inconc  = [int]$root.inconclusive
        $res.failed = $failures + $errors
        $res.passed = $total - $res.failed - $inconc
        $res.inconc = $inconc
        if ($res.failed -gt 0) {
            $cases = $xml.SelectNodes("//test-case[@success='False']")
            foreach ($c in $cases) { $res.fail_names += $c.name }
        }
    } catch {
        $res.fail_names = @("XML_PARSE_ERROR: $($_.Exception.Message)")
    }
    return $res
}

# Lanca processos respeitando o limite de workers
$running = @()   # @{ proc; file; xml }
$results = @()
$idx = 0

function Start-OneTest {
    param($File)
    $xmlPath = Join-Path $xmlDir ((Split-Path $File.FullName -Leaf) -replace '\.ps1$','.xml')
    $cmd = "Invoke-Pester -Path '$($File.FullName)' -OutputFile '$xmlPath' -OutputFormat NUnitXml -Quiet *> `$null"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $pwshExe
    $psi.Arguments = "-NoProfile -NonInteractive -Command `"$cmd`""
    $psi.WorkingDirectory = $projectRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    return [PSCustomObject]@{ proc = $proc; file = $File.FullName; xml = $xmlPath; started = Get-Date }
}

$done = 0
$totPass = 0; $totFail = 0; $totInconc = 0
$failedFiles = @()
$abort = $false

while (($idx -lt $files.Count -or $running.Count -gt 0) -and -not $abort) {
    # Preenche slots livres
    while ($running.Count -lt $Workers -and $idx -lt $files.Count) {
        $running += (Start-OneTest -File $files[$idx])
        $idx++
    }
    # Coleta os que terminaram
    $stillRunning = @()
    foreach ($job in $running) {
        if ($job.proc.HasExited) {
            $r = Read-NUnitResult -XmlPath $job.xml -TestFile $job.file
            $done++
            $totPass += [Math]::Max(0,$r.passed); $totFail += [Math]::Max(0,$r.failed); $totInconc += $r.inconc
            $isFail = ($r.failed -ne 0)
            if ($isFail) { $failedFiles += $r }
            if (-not $Quiet -or $isFail) {
                $tag = if ($isFail) { "[FAIL]" } else { "[ OK ]" }
                $col = if ($isFail) { "Red" } else { "Green" }
                $sec = [math]::Round(((Get-Date) - $job.started).TotalSeconds, 1)
                Write-Host ("{0} {1,-52} P:{2,-4} F:{3,-3} ({4}s) [{5}/{6}]" -f $tag,$r.file,$r.passed,$r.failed,$sec,$done,$files.Count) -ForegroundColor $col
            }
            if ($FailFast -and $isFail) { $abort = $true }
        } else {
            $stillRunning += $job
        }
    }
    $running = $stillRunning
    if ($running.Count -ge $Workers -or ($idx -ge $files.Count -and $running.Count -gt 0)) {
        Start-Sleep -Milliseconds 120
    }
}

# Se FailFast abortou, mata processos remanescentes
if ($abort) {
    foreach ($job in $running) { try { $job.proc.Kill() } catch {} }
    Write-Host "`nFAILFAST: abortado." -ForegroundColor Yellow
}

$swTotal.Stop()
Remove-Item $xmlDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n=== RESUMO (isolado, sem poluicao) ===" -ForegroundColor Cyan
Write-Host ("Passed: {0}  Failed: {1}  Inconclusive: {2}" -f $totPass,$totFail,$totInconc) -ForegroundColor $(if ($totFail -eq 0) { "Green" } else { "Red" })
Write-Host ("Tempo: {0}s | Workers: {1}" -f [math]::Round($swTotal.Elapsed.TotalSeconds,1), $Workers) -ForegroundColor Gray

if ($failedFiles.Count -gt 0) {
    Write-Host "`n=== ARQUIVOS COM FALHA REAL ($($failedFiles.Count)) ===" -ForegroundColor Red
    foreach ($ff in ($failedFiles | Sort-Object { $_.failed } -Descending)) {
        Write-Host ("  [{0}] {1}" -f $ff.failed, $ff.file) -ForegroundColor Red
        foreach ($fn in ($ff.fail_names | Select-Object -First 6)) {
            Write-Host ("       - {0}" -f $fn) -ForegroundColor DarkGray
        }
    }
    exit 1
}
Write-Host "`nSUITE LIMPA: zero falhas reais (cada arquivo isolado)." -ForegroundColor Green
exit 0
