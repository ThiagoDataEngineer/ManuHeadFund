# apply_trailing_sltp_source_2026_08_06.ps1 -- aplica
# docs/SETUP_SUPABASE_TRAILING_SLTP_SOURCE_2026_08_06.sql via RPC exec_sql
# (mesmo padrao de scripts/apply_trailing_birth_score_2026_07_29.ps1).
# Roda uma vez via workflow_dispatch (job apply-trailing-sltp-source-schema).

param(
    [Parameter(Mandatory=$false)][string]$SupabaseUrl = $env:SUPABASE_URL,
    [Parameter(Mandatory=$false)][string]$ServiceKey = $env:SUPABASE_SERVICE_KEY
)

if (-not $SupabaseUrl) { throw "SUPABASE_URL environment variable not set" }
if (-not $ServiceKey) { throw "SUPABASE_SERVICE_KEY environment variable not set" }

$headers = @{
    "Authorization" = "Bearer $ServiceKey"
    "Content-Type"  = "application/json"
    "apikey"        = $ServiceKey
}

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_TRAILING_SLTP_SOURCE_2026_08_06.sql"
if (-not (Test-Path $sqlPath)) { throw "SQL file not found: $sqlPath" }
$sql = Get-Content $sqlPath -Raw

$url = "$SupabaseUrl/rest/v1/rpc/exec_sql"
$body = @{ sql = $sql } | ConvertTo-Json

Write-Host "Applying migration: $sqlPath" -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ErrorAction Stop | Out-Null
    Write-Host "Migration applied OK" -ForegroundColor Green
} catch {
    Write-Host "Migration FAILED: $_" -ForegroundColor Red
    throw
}

Write-Host "`nRe-testing read + upsert:" -ForegroundColor Cyan
$restHeaders = @{
    "Authorization"   = "Bearer $ServiceKey"
    "apikey"          = $ServiceKey
    "Accept-Profile"  = "manuheadfund"
    "Content-Profile" = "manuheadfund"
    "Content-Type"    = "application/json"
}
try {
    $testUrl = "$SupabaseUrl/rest/v1/trailing_state?select=pk_id,sl_source,tp_source,stop_pct_used&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  trailing_state (sl_source/tp_source/stop_pct_used cols) read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  trailing_state read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard." -ForegroundColor Yellow
}

try {
    $upsertHeaders = $restHeaders.Clone()
    $upsertHeaders["Prefer"] = "resolution=merge-duplicates,return=representation"
    $upsertUrl = "$SupabaseUrl/rest/v1/trailing_state?on_conflict=pk_id"
    $testRecord = @{
        pk_id = "TEST_SCHEMA_CHECK"; market = "TESTUSDT"; side = "LONG"
        entry = 100; stop = 90; target = 130; active = $false
        sl_source = "fixed_pct"; tp_source = "fixed_pct"; stop_pct_used = 0.08
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $upsertUrl -Headers $upsertHeaders -Method Post -Body $testRecord -ErrorAction Stop | Out-Null
    Write-Host "  trailing_state upsert (sl_source/tp_source/stop_pct_used cols) OK -- write path funcional" -ForegroundColor Green

    $delUrl = "$SupabaseUrl/rest/v1/trailing_state?pk_id=eq.TEST_SCHEMA_CHECK"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  trailing_state upsert FAILED: $_" -ForegroundColor Red
}
