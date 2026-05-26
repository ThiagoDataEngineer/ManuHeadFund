# Verifica se todas as colunas usadas pelo codigo existem na tabela Supabase
$pat = $env:SUPABASE_PAT
if (-not $pat) { Write-Host "ERR: env SUPABASE_PAT nao setado" -ForegroundColor Red; exit 1 }
$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/lib_supabase_management.ps1")
. (Join-Path $root "agents/config.local.ps1")

$projectRef = ($env:SUPABASE_URL -replace "https?://", "" -replace "\..*", "")

# Colunas que o codigo usa (lib_trailing.ps1, lib_trailing_adaptive.ps1, lib_moon_bag.ps1)
$expectedCols = @(
    "pk_id", "market", "side", "entry", "stop", "target", "size",
    "orderId", "source", "mode", "max_days", "dd_threshold_pct",
    "phase", "peak", "stopCurrent", "active", "openedAt", "updatedAt",
    "currentPrice", "moonBagPairId", "moonBagKind",
    "layer4Advisory", "layer4AdvisoryReason", "lastLayer4Review",
    "moonBagAdvisory", "moonBagAdvisoryReason", "lastMoonBagReview",
    "lastMentorReview", "entryRegime",
    "closedAt", "closeReason", "exitPrice"
)

$sql = "SELECT column_name FROM information_schema.columns WHERE table_schema = 'manuheadfund' AND table_name = 'trailing_positions' ORDER BY column_name;"
$existing = @(Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $sql | ForEach-Object { $_.column_name })

Write-Host "=== Schema completeness check ===" -ForegroundColor Cyan
Write-Host "Colunas existentes: $($existing.Count)"
Write-Host ""

$missing = @()
foreach ($col in $expectedCols) {
    if ($existing -notcontains $col) {
        $missing += $col
        Write-Host "  MISSING: $col" -ForegroundColor Red
    }
}

if ($missing.Count -eq 0) {
    Write-Host "OK: todas as colunas esperadas existem" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Adicionando $($missing.Count) colunas faltantes..." -ForegroundColor Yellow
    $alterSql = ($missing | ForEach-Object { "ADD COLUMN IF NOT EXISTS `"$_`" TEXT" }) -join ",`n  "
    $addSql = "ALTER TABLE manuheadfund.trailing_positions`n  $alterSql;"
    Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $addSql | Out-Null
    Write-Host "OK: colunas adicionadas" -ForegroundColor Green
}
