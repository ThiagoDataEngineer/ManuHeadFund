# diag_partial_ladder_raw_response_2026_07_31.ps1 -- diagnostico ONE-SHOT,
# investiga por que Register-PartialExitLadder reporta success=true mas o
# resultado real na CoinEx (confirmado via diag_urgent_dogeusdt_multi_sell)
# continua mostrando 1 TP so (is_all=true), nao os 2 niveis parciais
# esperados (qty_pct 50%+25% da policy "atual"). Chama
# CoinEx-PlaceMultiExitLadder direto com os MESMOS inputs reais do
# DOGEUSDT (nao mexe no TP atual antes -- so registra de novo em cima,
# operacao idempotente do lado da CoinEx) e imprime a resposta CRUA de
# cada nivel (response.code/message), que o log de producao nao expoe.

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")

$MKT = "DOGEUSDT"

Write-Host "=== DIAG: resposta crua de CoinEx-PlaceMultiExitLadder ($MKT) ===" -ForegroundColor Cyan

$pos = CoinEx-GetPosition -market $MKT
if (-not $pos) {
    Write-Host "Sem posicao ativa em $MKT." -ForegroundColor Red
    exit 1
}
Write-Host "Posicao real: side=$($pos.side) open_interest=$($pos.open_interest) entry=$($pos.avg_entry_price)" -ForegroundColor Yellow

$entry = [decimal]$pos.avg_entry_price
$totalAmount = [decimal]$pos.open_interest
$stopDistance = [decimal]0.00007850999999999  # mesmo valor real usado em producao (|entry - stopCurrent|)

$tpLevels = @(
    [PSCustomObject]@{ type = "rr_multiple"; rr_multiple = 1.0; qty_pct = 50.0 }
    [PSCustomObject]@{ type = "rr_multiple"; rr_multiple = 2.0; qty_pct = 25.0 }
)
$ladder = [PSCustomObject]@{
    template_id   = "diag_partial_$MKT"
    tp_levels     = $tpLevels
    sl_levels     = @()
    stop_distance = $stopDistance
}

Write-Host "`n--- Chamando CoinEx-PlaceMultiExitLadder ---" -ForegroundColor Yellow
$result = CoinEx-PlaceMultiExitLadder -Market $MKT -PositionSide ([string]$pos.side).ToLower() `
    -TotalAmount $totalAmount -Entry $entry -Ladder $ladder

Write-Host "`n--- tp_orders (resposta CRUA por nivel) ---" -ForegroundColor Yellow
foreach ($o in @($result.tp_orders)) {
    Write-Host ("level_index={0} trigger_price={1} qty={2}" -f $o.level_index, $o.trigger_price, $o.qty)
    Write-Host ("  response: " + ($o.response | ConvertTo-Json -Depth 5 -Compress))
}

Write-Host "`n--- Posicao apos a chamada (take_profit_list real) ---" -ForegroundColor Yellow
Start-Sleep -Seconds 2
$posAfter = CoinEx-GetPosition -market $MKT
Write-Host ($posAfter | Select-Object take_profit_price, take_profit_list | ConvertTo-Json -Depth 5)

Write-Host "`n=== FIM ===" -ForegroundColor Cyan
