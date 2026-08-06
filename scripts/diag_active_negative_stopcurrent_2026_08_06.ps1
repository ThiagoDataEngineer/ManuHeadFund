# diag_active_negative_stopcurrent_2026_08_06.ps1 -- ONE-SHOT, so leitura.
#
# Causa raiz confirmada: Layer 1 Adaptive Trailing (ATR placeholder
# hardcoded 100.0) corrompia stopCurrent pra numero negativo em ativos
# baratos, na transicao de fase 0->1. Ja desativado (commit 46d1466). Este
# script varre TODAS as posicoes ATIVAS agora (nao so as 2 ja fechadas
# investigadas) pra confirmar se ha dano real em aberto precisando de
# correcao manual imediata na corretora.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG: posicoes ATIVAS com stopCurrent negativo/invalido AGORA ===" -ForegroundColor Cyan

try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total ativas: $($rows.Count)`n"

    $realPositions = @(CoinEx-GetPendingPositions)

    $foundBad = $false
    foreach ($r in $rows) {
        $stopCur = try { [double]$r.stopCurrent } catch { $null }
        $entry = try { [double]$r.entry } catch { $null }

        $isBad = ($null -ne $stopCur) -and ($stopCur -lt 0)
        # Tambem sinaliza se o stop journal estiver MUITO fora de qualquer
        # relacao razoavel com o entry (ex: > 50x o entry ou < 1/50 do entry)
        # -- pode indicar a mesma classe de corrupcao sem ficar negativo.
        $isSuspicious = $false
        if (-not $isBad -and $entry -gt 0 -and $null -ne $stopCur -and $stopCur -gt 0) {
            $ratio = $stopCur / $entry
            if ($ratio -gt 50 -or $ratio -lt 0.02) { $isSuspicious = $true }
        }

        if ($isBad -or $isSuspicious) {
            $foundBad = $true
            $flag = if ($isBad) { "NEGATIVO" } else { "SUSPEITO (fora de escala)" }
            Write-Host ("  [$flag] {0} side={1} entry={2} stopCurrent(journal)={3} mode={4} source={5}" -f `
                $r.market, $r.side, $entry, $stopCur, $r.mode, $r.source) -ForegroundColor Red

            # Confirma o SL REAL na corretora (fonte de verdade -- o journal
            # pode estar corrompido sem que a corretora tenha recebido o
            # valor ruim, ja que o motor unificado sempre esteve em HOLD
            # pra essas posicoes ate o fix de origin de ontem).
            $real = $realPositions | Where-Object { $_.market -eq $r.market } | Select-Object -First 1
            if ($real) {
                Write-Host ("    SL REAL na corretora: {0} (TP real: {1})" -f $real.stop_loss_price, $real.take_profit_price) -ForegroundColor Yellow
            } else {
                Write-Host "    Posicao nao encontrada na corretora (ja fechou?)" -ForegroundColor DarkYellow
            }
        }
    }

    if (-not $foundBad) {
        Write-Host "Nenhuma posicao ativa com stopCurrent negativo ou fora de escala encontrada." -ForegroundColor Green
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM DIAG ===" -ForegroundColor Cyan
