# apply_conviction_observations_2026_07_26.ps1 -- aplica docs/SETUP_SUPABASE_CONVICTION_OBSERVATIONS_2026_07_26.sql
# via RPC exec_sql (mesmo padrao de scripts/apply_beta_history_2026_07_26.ps1).
# Roda uma vez via workflow_dispatch (job apply-conviction-observations-schema).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_CONVICTION_OBSERVATIONS_2026_07_26.sql"
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

Write-Host "`nRe-testing the original failing read + upsert:" -ForegroundColor Cyan
$restHeaders = @{
    "Authorization"   = "Bearer $ServiceKey"
    "apikey"          = $ServiceKey
    "Accept-Profile"  = "manuheadfund"
    "Content-Profile" = "manuheadfund"
    "Content-Type"    = "application/json"
}
try {
    $testUrl = "$SupabaseUrl/rest/v1/conviction_observations?select=pk_id&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  conviction_observations read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  conviction_observations read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard." -ForegroundColor Yellow
}

try {
    $upsertHeaders = $restHeaders.Clone()
    $upsertHeaders["Prefer"] = "resolution=merge-duplicates,return=representation"
    $upsertUrl = "$SupabaseUrl/rest/v1/conviction_observations?on_conflict=pk_id"
    $testRecord = @{
        pk_id = "TESTUSDT_LONG_SCHEMA_CHECK"; ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        market = "TESTUSDT"; direction = "LONG"; conviction = 50.0; ready = $false
        tag = "below"; chg_24h = 0.0; axes = "{}"; mode = "OBSERVE"
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $upsertUrl -Headers $upsertHeaders -Method Post -Body $testRecord -ErrorAction Stop | Out-Null
    Write-Host "  conviction_observations upsert OK -- write path funcional" -ForegroundColor Green

    $delUrl = "$SupabaseUrl/rest/v1/conviction_observations?pk_id=eq.TESTUSDT_LONG_SCHEMA_CHECK"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  conviction_observations upsert FAILED: $_" -ForegroundColor Red
}
