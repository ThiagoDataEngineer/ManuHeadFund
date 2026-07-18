# apply_fix_mce_gate_2026_07_17.ps1 -- aplica docs/SETUP_SUPABASE_FIX_MCE_GATE_2026_07_17.sql
# via RPC exec_sql (mesmo padrao de scripts/apply_fix_close_reason_2026_07_14.ps1).
# Roda uma vez via workflow_dispatch (job apply-mce-gate-fix em trading-pipeline.yml).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_FIX_MCE_GATE_2026_07_17.sql"
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

# Verificacao: confirma que a coluna existe agora
function Check-Column {
    param([string]$TableName, [string]$ColumnName)
    $checkSql = "SELECT column_name FROM information_schema.columns WHERE table_schema='manuheadfund' AND table_name='$TableName' AND column_name='$ColumnName';"
    $checkBody = @{ sql = $checkSql } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $checkBody -ErrorAction Stop
        $found = ($r -and @($r).Count -gt 0)
        Write-Host "  $TableName.$ColumnName : $(if ($found) { 'OK' } else { 'MISSING' })" -ForegroundColor $(if ($found) { 'Green' } else { 'Red' })
        return $found
    } catch {
        Write-Host "  $TableName.$ColumnName : check failed ($_)" -ForegroundColor Yellow
        return $false
    }
}

Write-Host "`nVerification:" -ForegroundColor Cyan
$ok1 = Check-Column -TableName "mce_counterfactual_agg" -ColumnName "gate"
$ok2 = Check-Column -TableName "evolution_params" -ColumnName "faro_signals_needed"
$ok3 = Check-Column -TableName "evolution_params" -ColumnName "tori_confluence_threshold"

if (-not ($ok1 -and $ok2 -and $ok3)) {
    Write-Host "`nWARNING: verification inconclusive (exec_sql RPC may not return rows for SELECT). Check Supabase Dashboard manually if in doubt." -ForegroundColor Yellow
}

# Teste real: repete as leituras que estavam falhando (42703 / PGRST204)
Write-Host "`nRe-testing the original failing reads:" -ForegroundColor Cyan
$restHeaders = @{
    "Authorization" = "Bearer $ServiceKey"
    "apikey"        = $ServiceKey
}
try {
    $testUrl = "$SupabaseUrl/rest/v1/mce_counterfactual_agg?select=gate&limit=1"
    Invoke-RestMethod -Uri $testUrl -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  mce_counterfactual_agg.gate read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  mce_counterfactual_agg.gate read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard (mesmo caso do incidente 2026-07-14)." -ForegroundColor Yellow
}
try {
    $testUrl2 = "$SupabaseUrl/rest/v1/evolution_params?select=faro_signals_needed&limit=1"
    Invoke-RestMethod -Uri $testUrl2 -Headers $restHeaders -Method Get -ErrorAction Stop | Out-Null
    Write-Host "  evolution_params.faro_signals_needed read OK -- schema cache reloaded successfully" -ForegroundColor Green
} catch {
    Write-Host "  evolution_params.faro_signals_needed read STILL FAILS: $_" -ForegroundColor Red
    Write-Host "  Pode precisar de restart manual do PostgREST via Supabase Dashboard (mesmo caso do incidente 2026-07-14)." -ForegroundColor Yellow
}
