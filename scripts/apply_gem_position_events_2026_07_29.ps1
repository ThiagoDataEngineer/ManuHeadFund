# apply_gem_position_events_2026_07_29.ps1 -- aplica
# docs/SETUP_SUPABASE_GEM_POSITION_EVENTS_2026_07_29.sql via RPC exec_sql
# (mesmo padrao de scripts/apply_trailing_birth_score_2026_07_29.ps1).
# Roda uma vez via workflow_dispatch (job apply-gem-position-events-schema).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_GEM_POSITION_EVENTS_2026_07_29.sql"
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
    $testUrl = "$SupabaseUrl/rest/v1/gem_position_events?select=id&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  gem_position_events read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  gem_position_events read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard." -ForegroundColor Yellow
}

try {
    $upsertHeaders = $restHeaders.Clone()
    $upsertHeaders["Prefer"] = "resolution=merge-duplicates,return=representation"
    $upsertUrl = "$SupabaseUrl/rest/v1/gem_position_events?on_conflict=id"
    $testRecord = @{
        id = "TEST_SCHEMA_CHECK"; market = "TESTUSDT"; side = "LONG"
        usd_size = 10.0; event_type = "OPEN"
        created_at = [datetime]::UtcNow.ToString("o")
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $upsertUrl -Headers $upsertHeaders -Method Post -Body $testRecord -ErrorAction Stop | Out-Null
    Write-Host "  gem_position_events upsert OK -- write path funcional" -ForegroundColor Green

    $delUrl = "$SupabaseUrl/rest/v1/gem_position_events?id=eq.TEST_SCHEMA_CHECK"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  gem_position_events upsert FAILED: $_" -ForegroundColor Red
}
