# diag_orphan_full_record_v2_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# v1 (diag_orphan_null_origin_root_cause) devolveu vazio pro registro
# completo -- suspeita: $rows[0] | ConvertTo-Json pode ter falhado
# silenciosamente, ou o Write-Host de um objeto grande truncou. Tambem
# remove created_at (coluna nao existe, achado real do erro 42703).
# Alem disso: confirma se active=true ainda e verdade pra estas 2 posicoes
# agora (podem ja ter fechado desde ontem).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG v2: registro completo SOONUSDT/PIPPINUSDT (sem filtro active) ===" -ForegroundColor Cyan

$cfg = Get-SupabaseRequestHeaders -Method "GET"
foreach ($mkt in @("SOONUSDT", "PIPPINUSDT")) {
    try {
        # SEM filtro active= -- pega qualquer registro, ativo ou nao, pra
        # nao perder o dado se a posicao ja fechou desde ontem.
        $uri = "$($cfg.url)/rest/v1/trailing_state?select=*&market=eq.$mkt"
        $rows = @(Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30)
        Write-Host "--- $mkt : $($rows.Count) registro(s) encontrado(s) (qualquer active) ---" -ForegroundColor Yellow
        foreach ($r in $rows) {
            Write-Host "  pk_id=$($r.pk_id) active=$($r.active) mode='$($r.mode)' source='$($r.source)' phase=$($r.phase)"
            Write-Host "  openedAt=$($r.openedAt) updatedAt=$($r.updatedAt) closedAt=$($r.closedAt) closeReason=$($r.closeReason)"
            Write-Host "  entry=$($r.entry) stop=$($r.stop) stopCurrent=$($r.stopCurrent) target=$($r.target) peak=$($r.peak)"
            $originJson = try { $r.origin | ConvertTo-Json -Compress } catch { "ERRO_CONVERT: $_" }
            Write-Host "  origin=$originJson"
            Write-Host ""
        }
    } catch {
        Write-Host "  ERRO em ${mkt}: $_" -ForegroundColor Red
    }
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
