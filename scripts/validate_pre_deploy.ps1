# validate_pre_deploy.ps1 -- Pre-deploy / pre-commit validation suite
#
# Roda checks essenciais antes de deploy/commit:
#   1. Runspace libs audit (Test-RunspaceLibsComplete)
#   2. Pester smoke (5 suites criticas)
#   3. Python smoke (pytest -x first failure)
#   4. Journal integridade (decisions.csv, observations.csv schemas)
#
# Exit code: 0 = all OK, >0 = falhou (numero indica check)
#
# Uso:
#   pwsh -File scripts\validate_pre_deploy.ps1               # full
#   pwsh -File scripts\validate_pre_deploy.ps1 -SkipPester   # quick
#   pwsh -File scripts\validate_pre_deploy.ps1 -Verbose      # detalhes

param(
    [switch]$SkipPester,
    [switch]$SkipPython,
    [switch]$VerboseOutput
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

$results = @()
$exitCode = 0

function Add-Result {
    param([string]$Check, [bool]$Pass, [string]$Detail = "")
    $results += [PSCustomObject]@{ Check = $Check; Pass = $Pass; Detail = $Detail }
    $color = if ($Pass) { "Green" } else { "Red" }
    $icon = if ($Pass) { "OK" } else { "FAIL" }
    Write-Host ("  [{0,-4}] {1,-30} {2}" -f $icon, $Check, $Detail) -ForegroundColor $color
}

Write-Host ""
Write-Host "=== VALIDATE PRE-DEPLOY $(Get-Date -Format 'HH:mm:ss') ===" -ForegroundColor Cyan
Write-Host ""

# 1. Runspace audit
Write-Host "[1] Runspace libs audit..." -ForegroundColor Cyan
try {
    . (Join-Path $projectRoot "agents\lib_runspace_audit.ps1")
    $audit = Test-RunspaceLibsComplete `
        -OrchestratorPath (Join-Path $projectRoot "agents\orchestrator_v6.ps1") `
        -ParallelPath (Join-Path $projectRoot "agents\lib_orchestrator_parallel.ps1") `
        -AgentsDir (Join-Path $projectRoot "agents")
    if ($audit.all_covered) {
        Add-Result -Check "runspace_audit" -Pass $true -Detail "$($audit.covered_refs.Count)/$($audit.total_refs) refs covered"
    } else {
        Add-Result -Check "runspace_audit" -Pass $false -Detail "MISSING: $($audit.missing_libs -join ', ')"
        $exitCode = 1
    }
} catch {
    Add-Result -Check "runspace_audit" -Pass $false -Detail "EXCEPTION: $_"
    $exitCode = 1
}

# 2. Pester smoke (5 suites criticas)
if (-not $SkipPester) {
    Write-Host ""
    Write-Host "[2] Pester smoke (suites criticas)..." -ForegroundColor Cyan
    $critSuites = @(
        "mentor_debate.Tests.ps1",
        "lib_claude_cascade.Tests.ps1",
        "orchestrator_v6_live_execution.Tests.ps1",
        "lib_promotion_gates.Tests.ps1",
        "lib_runspace_audit.Tests.ps1"
    )
    $paths = $critSuites | ForEach-Object { Join-Path $projectRoot "tests\$_" } | Where-Object { Test-Path $_ }
    try {
        $r = Invoke-Pester -Path $paths -PassThru -Quiet 2>$null
        if ($r.FailedCount -eq 0) {
            Add-Result -Check "pester_smoke" -Pass $true -Detail "P=$($r.PassedCount) F=0"
        } else {
            Add-Result -Check "pester_smoke" -Pass $false -Detail "P=$($r.PassedCount) F=$($r.FailedCount)"
            $exitCode = 2
        }
    } catch {
        Add-Result -Check "pester_smoke" -Pass $false -Detail "EXCEPTION: $_"
        $exitCode = 2
    }
}

# 3. Python smoke
if (-not $SkipPython) {
    Write-Host ""
    Write-Host "[3] Python pytest smoke..." -ForegroundColor Cyan
    try {
        Push-Location (Join-Path $projectRoot "backtest")
        $pyOut = & python -m pytest tests/test_drawdown_source_aware.py tests/test_metrics_simons.py -q --tb=no 2>&1 | Out-String
        Pop-Location
        if ($pyOut -match '(\d+) passed') {
            $pyPass = [int]$Matches[1]
            if ($pyOut -match 'failed' -and $pyOut -notmatch '0 failed') {
                Add-Result -Check "pytest_smoke" -Pass $false -Detail $pyOut.Split("`n")[-2]
                $exitCode = 3
            } else {
                Add-Result -Check "pytest_smoke" -Pass $true -Detail "$pyPass passed"
            }
        } else {
            Add-Result -Check "pytest_smoke" -Pass $false -Detail "no test output parsed"
            $exitCode = 3
        }
    } catch {
        Add-Result -Check "pytest_smoke" -Pass $false -Detail "EXCEPTION: $_"
        $exitCode = 3
    }
}

# 4. Journal integridade
Write-Host ""
Write-Host "[4] Journal schema integrity..." -ForegroundColor Cyan
$expectedSchemas = @{
    "decisions.csv"   = "timestamp,market,decision,reason,abort_stage,regime,direction,scanner_score,whitelist_tier,mesa_consensus,mentor_decision,paper_only,provider_used"
    "observations.csv"= "timestamp,market,regime,direction,dow_brt,whitelist_tier,whitelist_reason,scanner_score,mesa_consensus,mesa_sinal,mentor_decision,mentor_confidence,entry_price,stop_price,target_price,atr_proxy_pct,mode"
}
foreach ($f in $expectedSchemas.Keys) {
    $path = Join-Path $projectRoot "journal\$f"
    if (-not (Test-Path $path)) {
        Add-Result -Check "schema_$f" -Pass $true -Detail "file ausente (ok pre-cycle)"
        continue
    }
    $firstLine = (Get-Content $path -TotalCount 1 -Encoding UTF8) -replace "^﻿", ""
    if ($firstLine -eq $expectedSchemas[$f]) {
        Add-Result -Check "schema_$f" -Pass $true -Detail "header match"
    } else {
        Add-Result -Check "schema_$f" -Pass $false -Detail "header drift"
        $exitCode = 4
    }
}

Write-Host ""
Write-Host "=== RESULT ===" -ForegroundColor Cyan
$pass = ($results | Where-Object { $_.Pass }).Count
$fail = ($results | Where-Object { -not $_.Pass }).Count
$color = if ($exitCode -eq 0) { "Green" } else { "Red" }
Write-Host ("  Passed: {0} | Failed: {1} | Exit: {2}" -f $pass, $fail, $exitCode) -ForegroundColor $color
exit $exitCode
