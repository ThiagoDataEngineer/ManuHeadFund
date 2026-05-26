# scripts/migrate_legacy_tables_to_schema.ps1
# Move tabelas existentes (candles, backtest_*) de public para schema manuheadfund.
# ALTER TABLE SET SCHEMA é atomic e instantaneo (nao copia dados, so renomeia metadado).
#
# Idempotente: skip se ja esta em manuheadfund.
#
# Uso:
#   $env:SUPABASE_PAT = "sbp_..."
#   .\scripts\migrate_legacy_tables_to_schema.ps1 [-DryRun]

param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/lib_supabase_management.ps1")
. (Join-Path $root "agents/config.local.ps1")

$pat = $env:SUPABASE_PAT
if (-not $pat) { Write-Host "ERR: env SUPABASE_PAT nao setado" -ForegroundColor Red; exit 1 }
$projectRef = ($env:SUPABASE_URL -replace "https?://", "" -replace "\..*", "")

$tablesToMove = @("candles", "backtest_runs", "backtest_signals", "backtest_trades")

Write-Host "=== Migrar tabelas legacy para schema manuheadfund ===" -ForegroundColor Cyan
Write-Host "ProjectRef: $projectRef" -ForegroundColor DarkGray
Write-Host "Tabelas: $($tablesToMove -join ', ')" -ForegroundColor DarkGray
Write-Host "DryRun: $($DryRun.IsPresent)" -ForegroundColor $(if ($DryRun) { "Yellow" } else { "Magenta" })
Write-Host ""

# Step 1: check current location
Write-Host "[1/3] Verificar localizacao atual..." -ForegroundColor Cyan
$listSql = @"
SELECT n.nspname AS schema_name, c.relname AS table_name
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND c.relname IN ('candles', 'backtest_runs', 'backtest_signals', 'backtest_trades')
ORDER BY c.relname;
"@
$current = @(Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $listSql)
foreach ($row in $current) {
    Write-Host ("    {0,-25} schema: {1}" -f $row.table_name, $row.schema_name) -ForegroundColor DarkGray
}

$toMove = @($current | Where-Object { $_.schema_name -eq "public" })
if ($toMove.Count -eq 0) {
    Write-Host "Todas as tabelas ja estao em manuheadfund. Nada a fazer." -ForegroundColor Green
    exit 0
}

Write-Host ""
Write-Host "[2/3] $($toMove.Count) tabelas em public, candidatas a movimentacao." -ForegroundColor Cyan
foreach ($t in $toMove) {
    Write-Host "    - public.$($t.table_name) -> manuheadfund.$($t.table_name)"
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: parando aqui sem executar ALTER TABLE." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "[3/3] Executando ALTER TABLE SET SCHEMA..." -ForegroundColor Magenta

$alterSql = ($toMove | ForEach-Object {
    "ALTER TABLE public.$($_.table_name) SET SCHEMA manuheadfund;"
}) -join "`n"

Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $alterSql | Out-Null
Write-Host "    OK ALTER TABLE concluido" -ForegroundColor Green

Write-Host ""
Write-Host "=== Verificacao pos-migracao ===" -ForegroundColor Cyan
$after = @(Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $listSql)
foreach ($row in $after) {
    $color = if ($row.schema_name -eq "manuheadfund") { "Green" } else { "Yellow" }
    Write-Host ("    {0,-25} schema: {1}" -f $row.table_name, $row.schema_name) -ForegroundColor $color
}

Write-Host ""
Write-Host "ROLLBACK (se necessario):" -ForegroundColor DarkYellow
Write-Host "  ALTER TABLE manuheadfund.candles SET SCHEMA public;" -ForegroundColor DarkGray
Write-Host "  (idem para outras)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "PROXIMO: atualizar backtest/db.py para enviar Accept-Profile manuheadfund" -ForegroundColor Yellow
