# diag_urgent_stoploss_zero_check_2026_07_29.ps1 -- diagnostico ONE-SHOT, so
# leitura, URGENTE. Achado real: lib_trailing.ps1:642 chama CoinEx-SetStopLoss
# com parametros nomeados (-Market/-OrderId/-StopPrice) que NAO existem na
# assinatura real da funcao ($market,$price) -- PowerShell ignora
# silenciosamente os nomeados invalidos, $price fica $null,
# [math]::Round($null,4)=0, e o codigo envia stop_loss_price="0" pra CoinEx
# toda vez que o trailing avanca de fase (phase>0). Um SL=0 numa posicao LONG
# nunca dispara -- risco real de posicao aberta SEM protecao de stop na
# corretora AGORA. Este script compara trailing_state.stopCurrent (o que o
# journal ACHA que esta vigente) com o stop_loss_price REAL retornado pela
# API CoinEx pra cada posicao ativa com phase>0 (ja tentou avancar pelo
# menos uma vez, unico caminho que aciona o bug).

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== DIAG URGENTE: stop loss real na CoinEx vs trailing_state ===" -ForegroundColor Cyan
try {
    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total ativas: $($rows.Count)`n"

    $futPos = @()
    try { $futPos = @(CoinEx-GetPendingPositions) } catch { Write-Host "ERRO CoinEx-GetPendingPositions: $_" -ForegroundColor Red }

    $riskCount = 0
    foreach ($r in $rows) {
        $mkt = [string]$r.market
        $phase = [int]$r.phase
        $stopCurrent = [double]$r.stopCurrent

        $live = $futPos | Where-Object { $_.market -eq $mkt } | Select-Object -First 1
        if (-not $live) {
            Write-Host "${mkt}: sem match na CoinEx (pode ja ter fechado / spot)" -ForegroundColor DarkYellow
            continue
        }

        $realSL = if ($live.PSObject.Properties['stop_loss_price'] -and $live.stop_loss_price) { [double]$live.stop_loss_price } else { 0.0 }

        $status = if ($realSL -le 0) { "CRITICO: SEM STOP REAL NA CORRETORA (SL=0 ou ausente)" }
                  elseif ([math]::Abs($realSL - $stopCurrent) -gt ($stopCurrent * 0.01)) { "DESSINCRONIZADO (journal acha $stopCurrent, corretora tem $realSL)" }
                  else { "OK (sincronizado)" }

        $color = if ($realSL -le 0) { "Red" } elseif ($status -like "DESSINCRONIZADO*") { "Yellow" } else { "Green" }

        Write-Host "$mkt phase=$phase journal_stopCurrent=$stopCurrent corretora_stop_real=$realSL -> $status" -ForegroundColor $color
        if ($realSL -le 0) { $riskCount++ }
    }

    Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
    if ($riskCount -gt 0) {
        Write-Host "$riskCount posicao(oes) SEM STOP LOSS REAL NA CORRETORA -- RISCO ATIVO, precisa correcao manual imediata." -ForegroundColor Red
    } else {
        Write-Host "Nenhuma posicao com SL=0 confirmada neste snapshot." -ForegroundColor Green
    }
} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
