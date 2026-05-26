# Smoke E2E: Get-CapitalContext direto contra Supabase manuheadfund
# Valida que apos refactor Etapa 2.1 funciona com backend real.

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/config.ps1")
. (Join-Path $root "agents/config.local.ps1")
. (Join-Path $root "agents/lib_state_store.ps1")
. (Join-Path $root "agents/lib_coinex.ps1")
. (Join-Path $root "agents/lib_capital_context.ps1")

# Forcar backend supabase + schema dedicado
$global:STATE_STORE_BACKEND = "supabase"
$global:STATE_STORE_SCHEMA  = "manuheadfund"

Write-Host "=== Capital Context Supabase E2E ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor Yellow
Write-Host "Schema:  $(Get-StateStoreSchema)" -ForegroundColor Yellow
Write-Host ""

try {
    Write-Host "[1/3] Force fresh fetch from CoinEx + save to Supabase..." -ForegroundColor Cyan
    $ctx1 = Get-CapitalContext -Force
    Write-Host ("      spot=$($ctx1.spot) futures=$($ctx1.futures) total=$($ctx1.total) source=$($ctx1.source)") -ForegroundColor Green

    Write-Host ""
    Write-Host "[2/3] Read back from Supabase (cache hit)..." -ForegroundColor Cyan
    $ctx2 = Get-CapitalContext -MaxAgeMinutes 60
    if ($ctx2.source -eq "cached") {
        Write-Host "      OK: cached" -ForegroundColor Green
        Write-Host ("      spot=$($ctx2.spot) total=$($ctx2.total)") -ForegroundColor DarkGray
    } else {
        Write-Host "      FAIL: source=$($ctx2.source) (expected cached)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "[3/3] Verify direct DB read..." -ForegroundColor Cyan
    $rows = @(Get-StateRecords -Table "capital_context")
    Write-Host "      Rows in manuheadfund.capital_context: $($rows.Count)" -ForegroundColor Green
    if ($rows.Count -gt 0) {
        Write-Host ("      DB row: spot=$($rows[0].spot) futures=$($rows[0].futures) total=$($rows[0].total)") -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
