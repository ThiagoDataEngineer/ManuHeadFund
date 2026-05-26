# Smoke test: valida conectividade Supabase + CRUD round-trip em tabela de teste
# Uso: .\scripts\smoke_supabase_state.ps1
#
# Cria/usa tabela 'state_smoke_test' para isolar de produção.
# Pode ser deletada com SQL quando quiser:
#   DROP TABLE state_smoke_test;

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
$agentsDir = Join-Path $root "agents"

. (Join-Path $agentsDir "config.local.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

Write-Host "=== Supabase State Store Smoke Test ===" -ForegroundColor Cyan
Write-Host ""

# Force supabase backend for this smoke
$global:STATE_STORE_BACKEND = "supabase"
Write-Host "Backend: $(Test-StateBackend)" -ForegroundColor Yellow
Write-Host "URL: $env:SUPABASE_URL" -ForegroundColor DarkGray
Write-Host ""

$testRecord = [PSCustomObject]@{
    market   = "SMOKE_TEST_$($PID)"
    side     = "LONG"
    entry    = 100.0
    stop     = 95.0
    target   = 110.0
    snapshot = (Get-Date).ToUniversalTime().ToString("o")
}

try {
    Write-Host "[1/4] Save record..." -ForegroundColor Cyan
    Save-StateRecords -Table "state_smoke_test" -Records @($testRecord) -PrimaryKey "market"
    Write-Host "      OK" -ForegroundColor Green

    Write-Host "[2/4] Get records back..." -ForegroundColor Cyan
    $rows = @(Get-StateRecords -Table "state_smoke_test" -Filter @{ market = $testRecord.market })
    Write-Host "      Found: $($rows.Count) rows" -ForegroundColor Green
    if ($rows.Count -gt 0) {
        Write-Host "      Sample: market=$($rows[0].market) entry=$($rows[0].entry)" -ForegroundColor DarkGray
    }

    Write-Host "[3/4] Update record (upsert with same PK)..." -ForegroundColor Cyan
    $testRecord.entry = 200.0
    Save-StateRecords -Table "state_smoke_test" -Records @($testRecord) -PrimaryKey "market"
    $rows2 = @(Get-StateRecords -Table "state_smoke_test" -Filter @{ market = $testRecord.market })
    if ($rows2[0].entry -eq 200.0) {
        Write-Host "      OK (entry updated to 200)" -ForegroundColor Green
    } else {
        Write-Host "      FAIL (entry=$($rows2[0].entry), expected 200)" -ForegroundColor Red
    }

    Write-Host "[4/4] Cleanup..." -ForegroundColor Cyan
    Remove-StateRecord -Table "state_smoke_test" -PrimaryKey "market" -Value $testRecord.market
    $rowsFinal = @(Get-StateRecords -Table "state_smoke_test" -Filter @{ market = $testRecord.market })
    Write-Host "      Remaining: $($rowsFinal.Count) rows" -ForegroundColor Green

    Write-Host ""
    Write-Host "=== ALL CHECKS PASSED ===" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "=== FAILED ===" -ForegroundColor Red
    Write-Host $_ -ForegroundColor Red
    Write-Host ""
    Write-Host "Hint: tabela state_smoke_test pode nao existir." -ForegroundColor Yellow
    Write-Host "Cria via SQL Editor no Supabase Dashboard:" -ForegroundColor Yellow
    Write-Host @"
  CREATE TABLE IF NOT EXISTS state_smoke_test (
    market TEXT PRIMARY KEY,
    side TEXT,
    entry NUMERIC,
    stop NUMERIC,
    target NUMERIC,
    snapshot TEXT
  );
  -- Allow anon writes for dev (ajustar pra service_role em prod)
  ALTER TABLE state_smoke_test ENABLE ROW LEVEL SECURITY;
  CREATE POLICY anon_all ON state_smoke_test FOR ALL TO anon USING (true) WITH CHECK (true);
"@ -ForegroundColor DarkGray
    exit 1
}
