# apply_decision_reflections_2026_07_28.ps1 -- aplica
# docs/SETUP_SUPABASE_DECISION_REFLECTIONS_2026_07_28.sql via RPC exec_sql
# (mesmo padrao de scripts/apply_mentor_shadow_observations_2026_07_27.ps1).
# Roda uma vez via workflow_dispatch (job apply-decision-reflections-schema).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_DECISION_REFLECTIONS_2026_07_28.sql"
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
    $testUrl = "$SupabaseUrl/rest/v1/decision_reflections?select=trade_id&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  decision_reflections read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  decision_reflections read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard." -ForegroundColor Yellow
}

try {
    $upsertHeaders = $restHeaders.Clone()
    $upsertHeaders["Prefer"] = "resolution=merge-duplicates,return=representation"
    $upsertUrl = "$SupabaseUrl/rest/v1/decision_reflections?on_conflict=trade_id"
    $testRecord = @{
        trade_id = "TEST_SCHEMA_CHECK"; market = "TESTUSDT"; entry_date_utc = "2026-07-28"
        mentor_veredicto = "EXECUTAR"; mentor_confidence = 50.0; mentor_mensagem = "schema check"
        mesa_sinal = "LONG"; tier = "GEM"; status = "pending"
        added_at = [datetime]::UtcNow.ToString("o")
    } | ConvertTo-Json
    Invoke-RestMethod -Uri $upsertUrl -Headers $upsertHeaders -Method Post -Body $testRecord -ErrorAction Stop | Out-Null
    Write-Host "  decision_reflections upsert OK -- write path funcional" -ForegroundColor Green

    $delUrl = "$SupabaseUrl/rest/v1/decision_reflections?trade_id=eq.TEST_SCHEMA_CHECK"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  decision_reflections upsert FAILED: $_" -ForegroundColor Red
}
