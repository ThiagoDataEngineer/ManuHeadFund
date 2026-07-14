# diag_check_close_reason_2026_07_14.ps1 -- diagnostico real (nao teatro).
# exec_sql sempre retorna 'ok' mesmo pra SELECT (EXECUTE descarta o resultado) --
# scripts/apply_fix_close_reason_2026_07_14.ps1's Check-Column sempre reportava
# OK independente do resultado real. Este script forca um erro real via
# RAISE EXCEPTION se a coluna nao existir -- exec_sql PROPAGA excecoes (fim do
# BEGIN/END sem EXCEPTION handler), entao um throw aqui e prova real, nao teatro.

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
$url = "$SupabaseUrl/rest/v1/rpc/exec_sql"

function Assert-ColumnExists {
    param([string]$Schema, [string]$Table, [string]$Column)
    $sql = @"
DO `$`$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = '$Schema' AND table_name = '$Table' AND column_name = '$Column'
    ) THEN
        RAISE EXCEPTION 'COLUMN_MISSING: %.%.% does not exist', '$Schema', '$Table', '$Column';
    END IF;
END
`$`$;
"@
    $body = @{ sql = $sql } | ConvertTo-Json
    try {
        Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body -ErrorAction Stop | Out-Null
        Write-Host "  $Schema.$Table.$Column : EXISTS (confirmed via forced exception test)" -ForegroundColor Green
        return $true
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match "COLUMN_MISSING") {
            Write-Host "  $Schema.$Table.$Column : DOES NOT EXIST (RAISE EXCEPTION fired)" -ForegroundColor Red
        } else {
            Write-Host "  $Schema.$Table.$Column : check errored ($msg)" -ForegroundColor Yellow
        }
        return $false
    }
}

Write-Host "Real diagnostic (RAISE EXCEPTION based, not exec_sql's always-'ok' return):" -ForegroundColor Cyan
# 2026-07-14 rodada 2: primeira migracao so cobriu closeReason; PGRST204
# persistiu na rota real (Close-TrailingPosition) porque closedAt/exitPrice
# tambem faltavam e eu nao tinha auditado a funcao inteira. Cobre os 3 agora.
Assert-ColumnExists -Schema "manuheadfund" -Table "trailing_state" -Column "closeReason"
Assert-ColumnExists -Schema "manuheadfund" -Table "trailing_state" -Column "closedAt"
Assert-ColumnExists -Schema "manuheadfund" -Table "trailing_state" -Column "exitPrice"
Assert-ColumnExists -Schema "manuheadfund" -Table "trade_outcomes" -Column "close_reason"
Assert-ColumnExists -Schema "manuheadfund" -Table "trade_outcomes" -Column "market"
Assert-ColumnExists -Schema "manuheadfund" -Table "trade_outcomes" -Column "payload"

# Segundo teste: confirma que exec_sql roda como role com permissao de ALTER
$permSql = @"
DO `$`$
BEGIN
    IF NOT has_schema_privilege(current_user, 'manuheadfund', 'CREATE') THEN
        RAISE EXCEPTION 'NO_CREATE_PRIVILEGE: current_user=% lacks CREATE on manuheadfund', current_user;
    END IF;
END
`$`$;
"@
$permBody = @{ sql = $permSql } | ConvertTo-Json
Write-Host "`nPrivilege check (does exec_sql's role have ALTER/CREATE rights on manuheadfund):" -ForegroundColor Cyan
try {
    Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $permBody -ErrorAction Stop | Out-Null
    Write-Host "  CREATE privilege on manuheadfund: YES" -ForegroundColor Green
} catch {
    Write-Host "  CREATE privilege on manuheadfund: NO or check failed ($($_.Exception.Message))" -ForegroundColor Red
}
