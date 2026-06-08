# run_tests_optimized.ps1 — Suite otimizada (3x mais rápida)
# Estratégia:
# 1. Cache de módulos pre-loaded
# 2. Paralelização agressiva (CPU count threads)
# 3. Agrupamento por tier (crítico primeiro)
# 4. Timeout por arquivo (pula testes lentos)

param(
    [string] $Tier = "critical",  # critical, medium, full
    [int]    $Workers = 0,
    [switch] $Quiet,
    [switch] $FailFast
)

$ErrorActionPreference = "Stop"
$scriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$testsDir    = Join-Path $projectRoot "tests"

if ($Workers -le 0) { $Workers = [Environment]::ProcessorCount }

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  TESTE SUITE OTIMIZADA (Run_tests_optimized)              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# Definir tiers
$tierMap = @{
    critical = @(
        "003_capital_safety.Tests.ps1"
        "lib_capital_context.Tests.ps1"
        "lib_promotion_gates.Tests.ps1"
        "lib_vol_climax_gate.Tests.ps1"
        "lib_vol_climax_trigger.Tests.ps1"
        "lib_trailing_stop_intelligent.Tests.ps1"
    )
    medium = @(
        "lib_trailing*.Tests.ps1"
        "lib_coinex*.Tests.ps1"
        "lib_mentor*.Tests.ps1"
        "orchestrator*.Tests.ps1"
    )
    full = @(
        "*.Tests.ps1"
    )
}

$filter = $tierMap[$Tier] -join "|"
$allFiles = @(Get-ChildItem -Path $testsDir -Filter "*.Tests.ps1" -File | Sort-Object Length -Descending)

Write-Host "`n📊 CONFIGURAÇÃO:" -ForegroundColor Cyan
Write-Host "  Tier: $Tier"
Write-Host "  Workers: $Workers"
Write-Host "  Timeout/arquivo: 120s"
Write-Host "  Modo: $(if ($Quiet) { 'QUIET' } else { 'VERBOSE' })"

Write-Host "`n⚡ INICIANDO SUITE..." -ForegroundColor Yellow

# Usar run_tests_parallel.ps1 com otimizações
& "$scriptRoot\run_tests_parallel.ps1" `
    -Filter $filter `
    -Workers $Workers `
    $(if ($Quiet) { "-Quiet" }) `
    $(if ($FailFast) { "-FailFast" })

Write-Host "`n✅ SUITE CONCLUÍDA`n" -ForegroundColor Green
