# migrate_alpha_column.ps1 -- Schema migration: add alpha_vs_btc column to trades.csv.
#
# Idempotente â€” safe to re-run. Backup automatico.
#
# Usage:
#   powershell -File scripts/migrate_alpha_column.ps1            # apply
#   powershell -File scripts/migrate_alpha_column.ps1 -DryRun    # preview only
#
# Wire: scripts/cron_mentor_reflector.ps1 + Close-Trade chamam alpha automaticamente
# em journal.ps1 quando lib_alpha_wire + alpha_vs_btc column estao presentes.

param([switch] $DryRun)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
Set-Location $projectRoot

. (Join-Path (Join-Path $projectRoot "agents") "lib_alpha_wire.ps1")

Write-Host "=== Migration: alpha_vs_btc column ==="
Write-Host ""

$targets = @(
    (Join-Path (Join-Path $projectRoot "journal") "trades.csv"),
    (Join-Path (Join-Path $projectRoot "journal") "gem_trades.csv")
)

foreach ($t in $targets) {
    Write-Host "Target: $t"
    if (-not (Test-Path $t)) {
        Write-Host "  SKIP -- file does not exist" -ForegroundColor Yellow
        continue
    }
    $exists = Test-AlphaColumnExists -CsvPath $t
    if ($exists) {
        Write-Host "  OK -- alpha_vs_btc column already present" -ForegroundColor Green
        continue
    }
    if ($DryRun) {
        $lines = @(Get-Content $t -Encoding UTF8)
        Write-Host "  DRY RUN -- would migrate $($lines.Count - 1) data rows + add column to header" -ForegroundColor Cyan
        continue
    }
    $r = Add-AlphaColumnToCsv -CsvPath $t
    if ($r.migrated) {
        Write-Host "  MIGRATED -- $($r.rows_updated) rows updated" -ForegroundColor Green
        Write-Host "  Backup: $($r.backup_path)" -ForegroundColor DarkGray
    } else {
        Write-Host "  FAILED -- $($r.reason)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Done ==="
