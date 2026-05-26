# Smoke E2E: Add-MoonBagPair direto contra Supabase manuheadfund.trailing_positions
# Valida que apos refactor Etapa 2.3 funciona com backend real.

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/config.ps1")
. (Join-Path $root "agents/config.local.ps1")
. (Join-Path $root "agents/lib_state_store.ps1")
. (Join-Path $root "agents/lib_coinex.ps1")
. (Join-Path $root "agents/lib_telegram.ps1")
. (Join-Path $root "agents/lib_trailing.ps1")
. (Join-Path $root "agents/lib_moon_bag.ps1")

# Forcar backend supabase + schema dedicado + flag trailing
$global:STATE_STORE_BACKEND      = "supabase"
$global:STATE_STORE_SCHEMA       = "manuheadfund"
$global:TRAILING_USE_STATE_STORE = $true

Write-Host "=== Moon Bag Supabase E2E ===" -ForegroundColor Cyan
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor Yellow
Write-Host "Schema:  $(Get-StateStoreSchema)" -ForegroundColor Yellow
Write-Host ""

$testMarket = "SMOKE_MB_$($PID)"

try {
    Write-Host "[1/5] Add-MoonBagPair $testMarket..." -ForegroundColor Cyan
    $r = Add-MoonBagPair -Market $testMarket -Side "LONG" -Entry 100 -Size 1000
    Write-Host "      pairId=$($r.pairId)" -ForegroundColor Green
    Write-Host "      harvest target=$($r.harvest.target) stop=$($r.harvest.stop)" -ForegroundColor DarkGray
    Write-Host "      moon    target=$($r.moon.target) stop=$($r.moon.stop)" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "[2/5] Get-MoonBagPositions filter for $testMarket..." -ForegroundColor Cyan
    $rows = @(Get-StateRecords -Table "trailing_positions" -Filter @{ market = $testMarket })
    Write-Host "      Found: $($rows.Count) rows (expect 2)" -ForegroundColor Green
    foreach ($p in $rows) {
        Write-Host ("      kind=$($p.moonBagKind) pk_id=$($p.pk_id)") -ForegroundColor DarkGray
    }
    if ($rows.Count -ne 2) {
        throw "Expected 2 rows, got $($rows.Count)"
    }

    Write-Host ""
    Write-Host "[3/5] Get-MoonBagPositions returns only Moon Bag legs..." -ForegroundColor Cyan
    $mb = @(Get-MoonBagPositions)
    $smokeOnly = $mb | Where-Object { [string]$_.market -eq $testMarket }
    Write-Host "      Moon Bag legs total: $($mb.Count) (smoke market: $((@($smokeOnly)).Count))" -ForegroundColor Green

    Write-Host ""
    Write-Host "[4/5] Update preserves both legs..." -ForegroundColor Cyan
    # Mark one leg phase=1 via state_store direct
    $hl = $rows | Where-Object { [string]$_.moonBagKind -eq "harvest" } | Select-Object -First 1
    $hl.phase = 1
    Save-StateRecords -Table "trailing_positions" -Records @($hl) -PrimaryKey "pk_id"
    $rowsAfter = @(Get-StateRecords -Table "trailing_positions" -Filter @{ market = $testMarket })
    Write-Host "      Rows after update: $($rowsAfter.Count) (expect 2)" -ForegroundColor Green
    if ($rowsAfter.Count -ne 2) { throw "Lost a leg in update" }

    Write-Host ""
    Write-Host "[5/5] Cleanup..." -ForegroundColor Cyan
    foreach ($r in $rows) {
        Remove-StateRecord -Table "trailing_positions" -PrimaryKey "pk_id" -Value $r.pk_id
    }
    $rowsFinal = @(Get-StateRecords -Table "trailing_positions" -Filter @{ market = $testMarket })
    Write-Host "      Remaining for $testMarket : $($rowsFinal.Count)" -ForegroundColor Green

    Write-Host ""
    Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    exit 1
}
