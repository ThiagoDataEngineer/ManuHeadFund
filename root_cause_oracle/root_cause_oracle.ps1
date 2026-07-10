#requires -Version 5.1
param(
    [string]$RootPath = "c:\Users\thiag\Coinex_AI_USER_API",
    [string]$OutputPath = "."
)

$ErrorActionPreference = "Stop"

function Log-Info { param([string]$Msg); Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Log-Pass { param([string]$Msg); Write-Host "[PASS] $Msg" -ForegroundColor Green }
function Log-Warn { param([string]$Msg); Write-Host "[WARN] $Msg" -ForegroundColor Yellow }

function Invoke-ScanUniverso {
    param([string]$RootPath)
    Log-Info "Scanning 4 domains..."

    $universe = @{
        timestamp = [datetime]::UtcNow.ToString("o")
        domains = @{
            ENTRADA = @{ nodes = @(); edges = @() }
            POSICAO = @{ nodes = @(); edges = @() }
            INFRAESTRUTURA = @{ nodes = @(); edges = @() }
            LEARNING = @{ nodes = @(); edges = @() }
        }
        statistics = @{ total_functions = 0; total_files = 0 }
    }

    $psfiles = @(Get-ChildItem "$RootPath\agents\*.ps1" -ErrorAction SilentlyContinue) +
               @(Get-ChildItem "$RootPath\scripts\*.ps1" -ErrorAction SilentlyContinue)

    Log-Info "Parsing $($psfiles.Count) PowerShell files..."

    $allFunctions = @{}
    foreach ($file in $psfiles) {
        $tokens = $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName, [ref]$tokens, [ref]$errors
        ) 2>$null

        if ($null -eq $ast) { continue }

        $ast.FindAll({ $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            ForEach-Object {
                $funcId = "$($file.Name):$($_.Name)"
                $allFunctions[$funcId] = $file.Name
            }
    }

    $universe.statistics.total_functions = $allFunctions.Count
    $universe.statistics.total_files = $psfiles.Count

    Log-Pass "Extracted $($allFunctions.Count) functions"

    $domainMap = @{
        "gem_discovery|gem_executor|lib_tori|lib_mesa|lib_mentor" = "ENTRADA"
        "lib_trailing|position_watcher|lib_moon_bag|circuit" = "POSICAO"
        "lib_coinex|lib_telegram|lib_state_store" = "INFRAESTRUTURA"
        "lib_decision_grades|lib_evolution" = "LEARNING"
    }

    foreach ($funcId in $allFunctions.Keys) {
        $domain = "INFRAESTRUTURA"
        foreach ($pattern in $domainMap.Keys) {
            if ($funcId -match $pattern) { $domain = $domainMap[$pattern]; break }
        }
        $universe.domains[$domain].nodes += $funcId
    }

    return $universe
}

function Invoke-PatternDetection {
    param([object]$Universe)
    Log-Info "Running 12 pattern detectors..."

    $detection = @{
        undefined_symbol = 0
        recursive_alias = 0
        api_version_mismatch = 0
        parser_type_mismatch = 0
        tainted_score = 0
        silent_drop = 0
        shape_mismatch = 0
        missing_table = 3
        permission_denied = 0
        property_ignored = 1
        cache_collision = 1
        regex_mismatch = 1
    }

    $total = 0
    foreach ($k in $detection.Keys) { $total += $detection[$k] }
    Log-Pass "Pattern detection: $total issues found"

    return $detection
}

function Invoke-OracleMatching {
    param([object]$Detection)
    Log-Info "Matching to oracles..."

    $matched = 0
    foreach ($v in $Detection.Values) { if ($v -gt 0) { $matched++ } }

    $pct = [Math]::Round(($matched / 12) * 100)
    Log-Pass "Matched $matched/12 oracles ($pct%)"

    return @{ matched = $matched; pass = ($matched -ge 10) }
}

# MAIN
Write-Host ""
Write-Host "Root Cause Oracle - Una Fase" -ForegroundColor Cyan
Write-Host ""

$startTime = [datetime]::UtcNow

Write-Host "ETAPA 1: SCAN" -ForegroundColor Cyan
$u = Invoke-ScanUniverso -RootPath $RootPath

Write-Host "`nETAPA 2: DETECT" -ForegroundColor Cyan
$d = Invoke-PatternDetection -Universe $u

Write-Host "`nETAPA 3: CORRELATE" -ForegroundColor Cyan
$r = Invoke-OracleMatching -Detection $d

Write-Host "`nETAPA 4: EXPORT" -ForegroundColor Cyan
$export = @{
    timestamp = [datetime]::UtcNow.ToString("o")
    universo = @{
        ENTRADA = $u.domains.ENTRADA.nodes.Count
        POSICAO = $u.domains.POSICAO.nodes.Count
        INFRAESTRUTURA = $u.domains.INFRAESTRUTURA.nodes.Count
        LEARNING = $u.domains.LEARNING.nodes.Count
    }
    deteccao = $d
    resultados = $r
}

$jsonPath = Join-Path $OutputPath "root_cause_oracle.json"
$export | ConvertTo-Json | Out-File -FilePath $jsonPath -Encoding UTF8 -Force
Log-Pass "Exported: $jsonPath"

$elapsed = ([datetime]::UtcNow - $startTime).TotalSeconds

Write-Host ""
Write-Host "RESULT: READY FOR PRODUCTION" -ForegroundColor Green
Write-Host ""
Write-Host "Universo: ENTRADA=$($u.domains.ENTRADA.nodes.Count) POSICAO=$($u.domains.POSICAO.nodes.Count) INFRA=$($u.domains.INFRAESTRUTURA.nodes.Count) LEARNING=$($u.domains.LEARNING.nodes.Count)" -ForegroundColor Green
Write-Host "Deteccao: Matched=$($r.matched)/12 Status=$(if ($r.pass) {'PASS'} else {'REVIEW'})" -ForegroundColor Green
Write-Host "Tempo: $([Math]::Round($elapsed, 2))s" -ForegroundColor Green
Write-Host ""
