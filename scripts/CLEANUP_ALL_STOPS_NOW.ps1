#!/usr/bin/env pwsh
# CLEANUP_ALL_STOPS_NOW.ps1
# Reconcilia os stops SPOT ao estado CORRETO, reusando a propria aplicacao.
# 2026-06-20 (original: hardcoded) | 2026-06-28 REESCRITO p/ usar o money-path real.
#
# CAUSA RAIZ da versao antiga (mesma doenca do exit intelligence): markets/posicoes
# HARDCODED (BASED/MET qty stale), endpoint errado /v2/spot/place-order (404) e
# "recriar 4 ordens" que eram fantasmas. Recriava stop p/ posicao que nao existe mais.
#
# AGORA delega ao motor ja comprovado (lib_spot_stop_guard, ground truth = corretora):
#   1) ORPHAN SWEEP: cancela stops pendentes em mercados que NAO temos mais saldo
#      (sobra de posicao vendida) -- varre holdings reais + registro de trailing.
#   2) SYNC: Get-SpotHoldingsForStop (saldo real + stop desejado do registro) ->
#      Sync-SpotStopsToExchange (PLACE faltante / CANCEL duplicata / UPDATE quando o
#      trail subiu / FALLBACK gap). Idempotente (anti bug-178) e dust-guarded.
# Endpoint/ccy/dedup corretos via CoinEx-PlaceSpotStopOrder. Zero hardcode.

[CmdletBinding()]
param(
    [double]$MinUsd = 5.0,
    [switch]$DryRun     # -DryRun: so mostra o que faria, nao cancela/coloca nada
)

$ErrorActionPreference = "Stop"

. agents/config.local.ps1
. agents/config.ps1
. agents/lib_coinex.ps1
. agents/lib_telegram.ps1
. agents/lib_spot_stop_guard.ps1
try { . agents/lib_trailing.ps1 } catch {}

Write-Host ""
Write-Host "=== RECONCILIACAO DE STOPS SPOT (via aplicacao) ===" -ForegroundColor Cyan
if ($DryRun) { Write-Host "MODO DRY-RUN: nada sera alterado na corretora." -ForegroundColor Yellow }
Write-Host ""

# ----------------------------------------------------------------------------
# Mapa de saldo real: market -> qty (available + frozen). Ground truth.
# ----------------------------------------------------------------------------
$stable = @("USDT","USDC","USD","DAI","TUSD","BUSD")
$heldQty = @{}
$bal = try { CoinEx-Get "/v2/assets/spot/balance" } catch { $null }
if ($bal -and $bal.code -eq 0) {
    foreach ($c in @($bal.data)) {
        $ccy = "$($c.ccy)".ToUpper()
        if ($ccy -in $stable) { continue }
        $q = ([double]$c.available) + ([double]$c.frozen)
        if ($q -gt 0) { $heldQty["${ccy}USDT"] = $q }
    }
}

# Universo de mercados a inspecionar: holdings reais + registro de trailing
# (inclui inativos -- e justamente onde ficam stops orfaos de posicao vendida).
$candidateMarkets = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in $heldQty.Keys) { [void]$candidateMarkets.Add($m) }
if (Get-Command Get-TrailingPositions -ErrorAction SilentlyContinue) {
    try { foreach ($p in @(Get-TrailingPositions)) { if ($p.market) { [void]$candidateMarkets.Add("$($p.market)") } } } catch {}
}

# ----------------------------------------------------------------------------
# STEP 1: ORPHAN SWEEP -- cancela stops em mercados sem saldo real (poeira/zerado).
# Stop de posicao que ja foi vendida nunca dispara util -> so polui. Remove.
# ----------------------------------------------------------------------------
Write-Host "[STEP 1] Varredura de stops orfaos (mercado sem saldo real)..." -ForegroundColor Yellow
$canceledOrphans = 0
foreach ($market in $candidateMarkets) {
    # tem saldo real acima de poeira? entao NAO e orfao -> deixa o SYNC cuidar.
    $qty = [double]($heldQty[$market])
    $last = 0.0
    try { $tk = Invoke-RestMethod "https://api.coinex.com/v2/spot/ticker?market=$market" -TimeoutSec 6 -ErrorAction Stop; if ($tk.data) { $last = [double]$tk.data[0].last } } catch {}
    $notional = if ($last -gt 0) { $qty * $last } else { 0 }
    if ($notional -ge $MinUsd) { continue }   # posicao viva -> pula (Sync reconcilia)

    try {
        $pending = CoinEx-Get "/v2/spot/pending-stop-order?market=$market&market_type=SPOT&page=1&limit=100" -ErrorAction SilentlyContinue
        $orders = @($pending.data)
        if ($orders.Count -gt 0) {
            Write-Host "  [$market] sem saldo ($([math]::Round($notional,2)) USD) mas tem $($orders.Count) stop(s) -> orfaos" -ForegroundColor DarkYellow
            foreach ($o in $orders) {
                $sid = if ($o.PSObject.Properties['stop_id']) { $o.stop_id } else { $o.order_id }
                if ($DryRun) { Write-Host "    [dry] cancelaria stop_id $sid" -ForegroundColor Gray; continue }
                try {
                    CoinEx-CancelStopOrder -Market $market -StopId $sid -MarketType "SPOT" -ErrorAction Stop | Out-Null
                    $canceledOrphans++
                    Write-Host "    cancelado stop_id $sid" -ForegroundColor Green
                } catch { Write-Host "    erro ao cancelar $sid : $_" -ForegroundColor Red }
                Start-Sleep -Milliseconds 100
            }
        }
    } catch {}
}
Write-Host "  Orfaos cancelados: $canceledOrphans" -ForegroundColor Green
Write-Host ""

# ----------------------------------------------------------------------------
# STEP 2: SYNC -- coloca/atualiza/deduplica o stop CORRETO p/ cada holding real.
# Reusa Get-SpotHoldingsForStop (saldo real + stop desejado do registro) e
# Sync-SpotStopsToExchange (idempotente, anti-178, fallback de gap).
# ----------------------------------------------------------------------------
Write-Host "[STEP 2] Sync dos stops corretos (saldo real x registro)..." -ForegroundColor Green
$holdings = @(Get-SpotHoldingsForStop -MinUsd $MinUsd)
Write-Host "  Holdings com stop a garantir: $($holdings.Count)" -ForegroundColor Cyan

$placed = 0; $updated = 0; $dedup = 0; $dust = 0; $fallback = 0
if (-not $DryRun) {
    $results = @(Sync-SpotStopsToExchange -Positions $holdings)
    foreach ($r in $results) {
        switch ($r.action) {
            "PLACE"         { $placed++;  Write-Host "  PLACE  $($r.market): $($r.detail)" -ForegroundColor Green }
            "UPDATE"        { $updated++; Write-Host "  UPDATE $($r.market): $($r.detail)" -ForegroundColor Green }
            "CANCEL"        { $dedup++;   Write-Host "  CANCEL $($r.market): $($r.detail)" -ForegroundColor DarkYellow }
            "FALLBACK_SELL" { $fallback++;Write-Host "  FALLBACK_SELL $($r.market): $($r.detail)" -ForegroundColor Magenta }
            "SKIP_DUST"     { $dust++ }
            default         { if (-not $r.ok) { Write-Host "  $($r.action) $($r.market): $($r.detail)" -ForegroundColor Red } }
        }
    }
} else {
    foreach ($h in $holdings) { Write-Host "  [dry] garantiria stop $($h.market) @ $($h.stop_price) (qty $($h.qty))" -ForegroundColor Gray }
}

Write-Host ""
Write-Host "=== RECONCILIACAO COMPLETA ===" -ForegroundColor Green
Write-Host "  Orfaos cancelados : $canceledOrphans" -ForegroundColor Green
Write-Host "  Stops colocados   : $placed" -ForegroundColor Green
Write-Host "  Stops atualizados : $updated" -ForegroundColor Green
Write-Host "  Duplicatas limpas : $dedup" -ForegroundColor Green
Write-Host "  Fallback (gap)    : $fallback" -ForegroundColor Green
Write-Host "  Poeira ignorada   : $dust" -ForegroundColor Green
Write-Host ""

if (-not $DryRun) {
    try {
        Send-TelegramAlert -Message "RECONCILIACAO STOPS: $canceledOrphans orfaos cancelados, $placed colocados, $updated atualizados, $dedup duplicatas limpas, $fallback fallback. Estado correto via aplicacao." | Out-Null
    } catch {}
}
