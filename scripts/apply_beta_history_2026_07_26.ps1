# apply_beta_history_2026_07_26.ps1 -- aplica docs/SETUP_SUPABASE_BETA_HISTORY_2026_07_26.sql
# via RPC exec_sql (mesmo padrao de scripts/apply_fix_mce_gate_2026_07_17.ps1).
# Roda uma vez via workflow_dispatch (job apply-beta-history-schema em trading-pipeline.yml).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_BETA_HISTORY_2026_07_26.sql"
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

# Teste real: repete a leitura que estava falhando (PGRST205) + testa um
# upsert completo (mesmo caminho real que Publish-BetaToSupabase usa).
Write-Host "`nRe-testing the original failing read + upsert:" -ForegroundColor Cyan
$restHeaders = @{
    "Authorization"  = "Bearer $ServiceKey"
    "apikey"         = $ServiceKey
    "Accept-Profile"  = "manuheadfund"
    "Content-Profile" = "manuheadfund"
    "Content-Type"    = "application/json"
}
try {
    $testUrl = "$SupabaseUrl/rest/v1/beta_history?select=market&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  beta_history read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  beta_history read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard (mesmo caso do incidente 2026-07-14)." -ForegroundColor Yellow
}

try {
    $upsertHeaders = $restHeaders.Clone()
    $upsertHeaders["Prefer"] = "resolution=merge-duplicates,return=representation"
    $upsertUrl = "$SupabaseUrl/rest/v1/beta_history?on_conflict=market"
    $testRecord = @{ market = "TESTUSDT_SCHEMA_CHECK"; beta = 1.0; beta_1d = 1.0; beta_4h = 1.0; beta_1h = 1.0; timestamp = [datetime]::UtcNow.ToString("o") } | ConvertTo-Json
    Invoke-RestMethod -Uri $upsertUrl -Headers $upsertHeaders -Method Post -Body $testRecord -ErrorAction Stop | Out-Null
    Write-Host "  beta_history upsert OK -- write path funcional" -ForegroundColor Green

    # Limpa o registro de teste
    $delUrl = "$SupabaseUrl/rest/v1/beta_history?market=eq.TESTUSDT_SCHEMA_CHECK"
    Invoke-RestMethod -Uri $delUrl -Headers $restHeaders -Method Delete -ErrorAction Stop | Out-Null
    Write-Host "  registro de teste removido" -ForegroundColor Green
} catch {
    Write-Host "  beta_history upsert FAILED: $_" -ForegroundColor Red
}
