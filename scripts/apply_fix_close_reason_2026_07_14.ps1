# apply_fix_close_reason_2026_07_14.ps1 -- aplica docs/SETUP_SUPABASE_FIX_CLOSE_REASON_2026_07_14.sql
# via RPC exec_sql (mesmo padrao de scripts/init_supabase_schema.ps1).
# Roda uma vez via workflow_dispatch (job apply-close-reason-fix em trading-pipeline.yml).

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

$sqlPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs\SETUP_SUPABASE_FIX_CLOSE_REASON_2026_07_14.sql"
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

# Verificacao: confirma que as colunas/tabela existem agora
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
$ok1 = Check-Column -TableName "trailing_state" -ColumnName "closeReason"
$ok2 = Check-Column -TableName "trade_outcomes" -ColumnName "close_reason"

if (-not ($ok1 -and $ok2)) {
    Write-Host "`nWARNING: verification inconclusive (exec_sql RPC may not return rows for SELECT). Check Supabase Dashboard manually if in doubt." -ForegroundColor Yellow
}
