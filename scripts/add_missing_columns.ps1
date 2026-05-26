$pat = $env:SUPABASE_PAT
if (-not $pat) { Write-Host "ERR: env SUPABASE_PAT nao setado" -ForegroundColor Red; exit 1 }
$here = $PSScriptRoot
$root = Split-Path $here -Parent
. (Join-Path $root "agents/lib_supabase_management.ps1")
. (Join-Path $root "agents/config.local.ps1")

$projectRef = ($env:SUPABASE_URL -replace "https?://", "" -replace "\..*", "")

$sql = @"
ALTER TABLE manuheadfund.trailing_positions
  ADD COLUMN IF NOT EXISTS "closedAt"    TEXT,
  ADD COLUMN IF NOT EXISTS "closeReason" TEXT,
  ADD COLUMN IF NOT EXISTS "exitPrice"   NUMERIC;

SELECT column_name FROM information_schema.columns
WHERE table_schema = 'manuheadfund' AND table_name = 'trailing_positions'
  AND column_name IN ('closedAt', 'closeReason', 'exitPrice')
ORDER BY column_name;
"@

Write-Host "Adicionando colunas closedAt, closeReason, exitPrice..."
$r = Invoke-SupabaseSql -Pat $pat -ProjectRef $projectRef -Sql $sql
Write-Host "Colunas confirmadas:"
$r | ForEach-Object { Write-Host "  - $($_.column_name)" }
Write-Host "OK"
