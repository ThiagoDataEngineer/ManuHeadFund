# tests\test_trailing_stale_price.ps1
# TDD: guarda de preco defasado (stale price) no trailing stop.
# Runner PowerShell puro (PASS/FAIL) - nao depende de Pester.
# 2026-05-29

$ErrorActionPreference = 'Stop'
$agents = Join-Path (Split-Path $PSScriptRoot -Parent) "agents"

. (Join-Path $agents "lib_price_freshness.ps1")
. (Join-Path $agents "lib_trailing_stop_intelligent.ps1")

$script:pass = 0; $script:fail = 0
function Check($name, $cond) {
    if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:fail++ }
}

# Candles validos (uptrend) reaproveitados em todos os casos
$candles = @()
$b = 100.0
foreach ($i in 0..29) {
    $candles += [PSCustomObject]@{ high=($b+2); low=($b-2); close=($b+0.5); open=$b }
    $b += 0.3
}

$pos = [PSCustomObject]@{ market="TESTUSDT"; avg_entry_price="100.0"; leverage="3"; side="long" }

Write-Host "=== CASO 1: preco FRESCO -> trailing calcula normal ==="
function CoinEx-GetTickerFresh($market) {
    return [PSCustomObject]@{ ticker = [PSCustomObject]@{ last = "110.0" }; fetched_at = (Get-Date); is_fresh = $true }
}
$r1 = Calculate-TrailingStopPrice -Position $pos -Candles $candles -CurrentStopLoss 95.0 -MaxPriceAgeSeconds 60
Check "Fresco: nao marcado como stale" ($r1.stale -ne $true)
Check "Fresco: PnL calculado (~10%)" ([math]::Abs($r1.pnl_pct - 10.0) -lt 0.5)
Check "Fresco: should_update = true (lucro>3%)" ($r1.should_update -eq $true)

Write-Host ""
Write-Host "=== CASO 2: preco DEFASADO (5 min) -> fail-closed, nao move stop ==="
function CoinEx-GetTickerFresh($market) {
    return [PSCustomObject]@{ ticker = [PSCustomObject]@{ last = "110.0" }; fetched_at = (Get-Date).AddSeconds(-300); is_fresh = $false }
}
$r2 = Calculate-TrailingStopPrice -Position $pos -Candles $candles -CurrentStopLoss 95.0 -MaxPriceAgeSeconds 60
Check "Stale: marcado como stale=true" ($r2.stale -eq $true)
Check "Stale: should_update = false" ($r2.should_update -eq $false)
Check "Stale: stop NAO movido (mantem 95)" ($r2.new_stop_price -eq 95.0)
Check "Stale: reason menciona stale" ($r2.reason -match "(?i)stale")

Write-Host ""
Write-Host "=== CASO 3: threshold customizado (idade 90s, limite 120s) -> ainda fresco ==="
function CoinEx-GetTickerFresh($market) {
    return [PSCustomObject]@{ ticker = [PSCustomObject]@{ last = "110.0" }; fetched_at = (Get-Date).AddSeconds(-90); is_fresh = $true }
}
$r3 = Calculate-TrailingStopPrice -Position $pos -Candles $candles -CurrentStopLoss 95.0 -MaxPriceAgeSeconds 120
Check "Threshold custom: nao stale dentro do limite" ($r3.stale -ne $true)
Check "Threshold custom: should_update = true" ($r3.should_update -eq $true)

Write-Host ""
Write-Host "=== RESULTADO: $script:pass passou, $script:fail falhou ==="
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
