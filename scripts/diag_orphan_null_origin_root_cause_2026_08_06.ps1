# diag_orphan_null_origin_root_cause_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Owner pediu origem REAL (nao suposicao) de por que SOONUSDT/PIPPINUSDT
# tem origin=null (nem o fallback UNKNOWN de Add-TrailingPosition, que
# SEMPRE grava pelo menos @{asset_class="UNKNOWN";trade_style="UNKNOWN"}).
# Confirmado no codigo: TODO caminho que chama Add-TrailingPosition (via
# Register-OrphanPosition ou direto) grava origin nao-null sempre. origin
# NULL sugere um registro criado ANTES do campo origin existir (commit
# 2026-07-18) que nunca foi migrado -- so foi ATUALIZADO em campos
# parciais desde entao (Update-AllTrailingStops so seta stopCurrent/phase/
# updatedAt, nunca origin) sem nunca reescrever origin. Puxa o registro
# COMPLETO (todos os campos) pra confirmar idade e padrao real.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: registro COMPLETO de SOONUSDT/PIPPINUSDT (origin=null) ===" -ForegroundColor Cyan

$cfg = Get-SupabaseRequestHeaders -Method "GET"
foreach ($mkt in @("SOONUSDT", "PIPPINUSDT")) {
    try {
        $uri = "$($cfg.url)/rest/v1/trailing_state?select=*&market=eq.$mkt&active=eq.true"
        $rows = @(Invoke-RestMethod -Uri $uri -Method GET -Headers $cfg.headers -TimeoutSec 30)
        Write-Host "--- $mkt (registro completo cru) ---" -ForegroundColor Yellow
        if ($rows.Count -eq 0) {
            Write-Host "  Nenhum registro ativo." -ForegroundColor Red
            continue
        }
        $rows[0] | ConvertTo-Json -Depth 8 | Write-Host
        Write-Host ""
    } catch {
        Write-Host "  ERRO em ${mkt}: $_" -ForegroundColor Red
    }
}

# Historico de mudancas: se existir uma tabela/journal de auditoria, tenta
# achar QUANDO este registro foi criado pela 1a vez (nao so updated_at).
Write-Host "--- Verificando se ha rastro de quando o registro foi CRIADO (nao so atualizado) ---" -ForegroundColor Yellow
foreach ($mkt in @("SOONUSDT", "PIPPINUSDT")) {
    try {
        $uri2 = "$($cfg.url)/rest/v1/trailing_state?select=market,openedAt,updatedAt,created_at,pk_id,mode,source,phase,peak,stop,stopCurrent,birth_score,birth_mesa_sinal,closeReason&market=eq.$mkt&active=eq.true"
        $r2 = @(Invoke-RestMethod -Uri $uri2 -Method GET -Headers $cfg.headers -TimeoutSec 30)
        if ($r2.Count -gt 0) {
            Write-Host "  $mkt : $($r2[0] | ConvertTo-Json -Compress)"
        }
    } catch {
        Write-Host "  ERRO em ${mkt}: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
