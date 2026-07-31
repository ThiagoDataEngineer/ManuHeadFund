# apply_llm_usage_2026_07_30.ps1 -- aplica
# docs/SETUP_SUPABASE_LLM_USAGE_2026_07_30.sql via RPC exec_sql
# (mesmo padrao de scripts/apply_gem_position_events_2026_07_29.ps1).
# Roda uma vez via workflow_dispatch (job apply-llm-usage-schema).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_LLM_USAGE_2026_07_30.sql"
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

Write-Host "`nRe-testing read + insert:" -ForegroundColor Cyan
$restHeaders = @{
    "Authorization"   = "Bearer $ServiceKey"
    "apikey"          = $ServiceKey
    "Accept-Profile"  = "manuheadfund"
    "Content-Profile" = "manuheadfund"
    "Content-Type"    = "application/json"
}
try {
    $testUrl = "$SupabaseUrl/rest/v1/llm_usage?select=id&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  llm_usage read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  llm_usage read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard." -ForegroundColor Yellow
}

try {
    $insertHeaders = $restHeaders.Clone()
    $insertHeaders["Prefer"] = "return=representation"
    $insertUrl = "$SupabaseUrl/rest/v1/llm_usage"
    $testRecord = @{
        agent = "TEST_SCHEMA_CHECK"; model = "test-model"
        input_tokens = 1; output_tokens = 1; cost_usd = 0.0
    } | ConvertTo-Json
    $inserted = Invoke-RestMethod -Uri $insertUrl -Headers $insertHeaders -Method Post -Body $testRecord -ErrorAction Stop
    Write-Host "  llm_usage insert OK -- write path funcional" -ForegroundColor Green

    $testId = $inserted[0].id
    $delUrl = "$SupabaseUrl/rest/v1/llm_usage?id=eq.$testId"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  llm_usage insert FAILED: $_" -ForegroundColor Red
}
