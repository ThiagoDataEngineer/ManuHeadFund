# apply_trailing_origin_backfill_2026_08_06.ps1 -- APLICA (escreve Supabase),
# NUNCA toca ordem/posicao real na corretora.
#
# Achado real: ARBUSDT/NEARUSDT/OPUSDT (abertas via regime_surf ANTES do fix
# de Register-PositionTrailing/-Origin, commit c0f9f6e) tem origin.asset_
# class="UNKNOWN" no trailing_state -- trailing_stop_monitor.ps1 usa isso pra
# decidir $tuIsFutures, entao NUNCA chama CoinEx-ModifyPositionStopLoss (push
# real) pra essas posicoes, so atualiza o journal (aparencia de progresso sem
# a protecao real mudar na CoinEx). Corrige origin.asset_class=FUTURES so nos
# registros ATIVOS confirmados como FUTURES reais (CoinEx-GetPendingPositions,
# fonte de verdade) -- so grava no Supabase, zero chamada de ordem/posicao.
#
# Uso: -DryRun (default $true) so mostra o que faria, sem escrever.
#      -DryRun:$false aplica de verdade.

param(
    [bool] $DryRun = $true
)

$agentsDir = Join-Path (Join-Path $PSScriptRoot "..") "agents"
$configLocalPath = Join-Path $agentsDir "config.local.ps1"
if (Test-Path $configLocalPath) { . $configLocalPath }
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_state_store.ps1")
. (Join-Path $agentsDir "lib_trailing_origin_backfill.ps1")

$env:STATE_STORE_SCHEMA = "manuheadfund"

Write-Host "=== APPLY: backfill de origin.asset_class=FUTURES (DryRun=$DryRun) ===" -ForegroundColor Cyan

try {
    $realPositions = @(CoinEx-GetPendingPositions)
    $realFuturesMarkets = @{}
    foreach ($p in $realPositions) { $realFuturesMarkets[[string]$p.market] = $true }
    Write-Host "Posicoes FUTURES reais confirmadas na corretora: $($realFuturesMarkets.Keys -join ', ')`n"

    $rows = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
    Write-Host "Total registros ativos no trailing_state: $($rows.Count)`n"

    $toFix = @()
    foreach ($r in $rows) {
        $mkt = [string]$r.market
        $isRealFutures = $realFuturesMarkets.ContainsKey($mkt)
        $needsBackfill = Test-OriginNeedsBackfill -JournalOrigin $r.origin -IsRealFutures $isRealFutures

        if ($needsBackfill) {
            $newOrigin = Resolve-BackfilledOrigin -JournalOrigin $r.origin
            $toFix += [PSCustomObject]@{ pk_id = $r.pk_id; market = $mkt; new_origin = $newOrigin }
            Write-Host ("  [PRECISA FIX] {0} -> origin.asset_class={1} trade_style={2}" -f $mkt, $newOrigin.asset_class, $newOrigin.trade_style) -ForegroundColor Yellow
        }
    }

    Write-Host "`nTotal a corrigir: $($toFix.Count)"

    if ($toFix.Count -eq 0) {
        Write-Host "Nada a fazer." -ForegroundColor Green
    } elseif ($DryRun) {
        Write-Host "`nDRY RUN -- nenhuma escrita feita. Rode com -DryRun:`$false pra aplicar." -ForegroundColor Yellow
    } else {
        foreach ($fix in $toFix) {
            try {
                $record = @{ pk_id = $fix.pk_id; origin = $fix.new_origin }
                Save-StateRecords -Table "trailing_state" -Records @($record) -PrimaryKey "pk_id"
                Write-Host "  [OK] $($fix.market) origin corrigido" -ForegroundColor Green
            } catch {
                Write-Host "  [ERRO] $($fix.market): $_" -ForegroundColor Red
            }
        }

        # Confirma leitura de volta
        Write-Host "`n--- Confirmando leitura de volta ---" -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        $rows2 = @(Get-StateRecords -Table "trailing_state" -Filter @{ active = $true })
        foreach ($fix in $toFix) {
            $updated = $rows2 | Where-Object { $_.pk_id -eq $fix.pk_id } | Select-Object -First 1
            if ($updated) {
                Write-Host ("  {0} origin agora: {1}" -f $fix.market, ($updated.origin | ConvertTo-Json -Compress))
            }
        }
    }

} catch {
    Write-Host "ERRO: $_" -ForegroundColor Red
}

Write-Host "`n=== FIM APPLY ===" -ForegroundColor Cyan
