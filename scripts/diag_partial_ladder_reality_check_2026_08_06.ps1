# diag_partial_ladder_reality_check_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Owner reportou: "multi tpsl parece que nunca vi funcionando". Log real
# mostra ARBUSDT ciclo apos ciclo: "PARTIAL recomendado" -> "partial exit
# ladder -> success=True reason=already_registered" -- sempre "ja
# registrado", nunca "ok" (registro novo de verdade). Confirma se o
# registro em partial_exit_ladders e real (ladder de fato existe na
# CoinEx com multiplos niveis de TP) ou fantasma (achou que registrou mas
# a corretora so tem o TP unico original).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: ladder de saida parcial -- registro vs realidade ===" -ForegroundColor Cyan

foreach ($mkt in @("ARBUSDT", "NEARUSDT", "OPUSDT", "SOONUSDT", "PIPPINUSDT")) {
    Write-Host "--- $mkt ---" -ForegroundColor Yellow
    try {
        $rows = @(Get-StateRecords -Table "partial_exit_ladders" -Filter @{ market = $mkt })
        if ($rows.Count -eq 0) {
            Write-Host "  Nenhum registro em partial_exit_ladders."
        } else {
            foreach ($r in $rows) {
                Write-Host "  registered_at=$($r.registered_at) active=$($r.active)"
                Write-Host "  details: $($r.details | ConvertTo-Json -Compress -Depth 6)"
            }
        }
    } catch {
        Write-Host "  ERRO ao ler partial_exit_ladders: $_" -ForegroundColor Red
    }

    try {
        $realPos = @(CoinEx-GetPendingPositions -Market $mkt) | Select-Object -First 1
        if ($realPos) {
            Write-Host "  TP real na corretora (unico campo take_profit_price): $($realPos.take_profit_price)"
            $tpList = if ($realPos.PSObject.Properties['take_profit_list']) { $realPos.take_profit_list } else { $null }
            if ($tpList -and @($tpList).Count -gt 0) {
                Write-Host "  take_profit_list (ladder real, se existir): $($tpList | ConvertTo-Json -Compress -Depth 6)"
            } else {
                Write-Host "  take_profit_list VAZIO -- so existe o TP unico, NENHUM ladder de verdade na corretora" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "  ERRO ao consultar posicao real: $_" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "=== FIM DIAG ===" -ForegroundColor Cyan
