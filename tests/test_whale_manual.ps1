# test_whale_manual.ps1 - Teste manual TDD para whale detection
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\agents\lib_whale_detection.ps1"

Write-Host "`n=== TESTE WHALE DETECTION (TDD) ===" -ForegroundColor Cyan
$passed = 0; $failed = 0

# TEST 1: Detecta whale > 100 BTC
Write-Host "`n[1/5] Detecta whale > 100 BTC" -ForegroundColor Yellow
$tx1 = @{
    hash = "test1"
    inputs = @( @{ prev_out = @{ addr = "whale"; value = 48639420000 } } )  # 486 BTC
    out = @( @{ addr = "other"; value = 48639420000 } )
}
$r1 = Test-WhaleTransaction -Transaction $tx1 -MinBtc 100
if ($r1.isWhale -and $r1.btcAmount -gt 400) {
    Write-Host "  PASS: $($r1.btcAmount) BTC detectado" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: isWhale=$($r1.isWhale) btc=$($r1.btcAmount)" -ForegroundColor Red
    $failed++
}

# TEST 2: Exchange deposit = BEARISH
Write-Host "`n[2/5] Exchange deposit = BEARISH" -ForegroundColor Yellow
$tx2 = @{
    hash = "test2"
    inputs = @( @{ prev_out = @{ addr = "whale_addr"; value = 10000000000 } } )
    out = @( @{ addr = "34xp4vRoCGJym3xR7yCVPFHoCNxv4Twseo"; value = 10000000000 } )  # Binance
}
$r2 = Test-WhaleTransaction -Transaction $tx2 -MinBtc 100
if ($r2.signal -eq "BEARISH") {
    Write-Host "  PASS: Signal=$($r2.signal) Impact=$($r2.scoreImpact)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: Signal=$($r2.signal) (esperado BEARISH)" -ForegroundColor Red
    $failed++
}

# TEST 3: Exchange withdrawal = BULLISH
Write-Host "`n[3/5] Exchange withdrawal = BULLISH" -ForegroundColor Yellow
$tx3 = @{
    hash = "test3"
    inputs = @( @{ prev_out = @{ addr = "bc1qgdjqv0av3q56jvd82tkdjpy7gdp9ut8tlqmgrpmv24sq90ecnvqqjwvw97"; value = 15000000000 } } )  # Coinbase
    out = @( @{ addr = "whale_addr"; value = 15000000000 } )
}
$r3 = Test-WhaleTransaction -Transaction $tx3 -MinBtc 100
if ($r3.signal -eq "BULLISH") {
    Write-Host "  PASS: Signal=$($r3.signal) Impact=$($r3.scoreImpact)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: Signal=$($r3.signal) (esperado BULLISH)" -ForegroundColor Red
    $failed++
}

# TEST 4: Ignora < 100 BTC
Write-Host "`n[4/5] Ignora transactions < 100 BTC" -ForegroundColor Yellow
$tx4 = @{
    hash = "small"
    inputs = @( @{ prev_out = @{ value = 5000000000 } } )  # 50 BTC
    out = @( @{ value = 5000000000 } )
}
$r4 = Test-WhaleTransaction -Transaction $tx4 -MinBtc 100
if (-not $r4.isWhale) {
    Write-Host "  PASS: isWhale=$($r4.isWhale) (correto)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: isWhale=$($r4.isWhale) (esperado false)" -ForegroundColor Red
    $failed++
}

# TEST 5: Agrega múltiplas transactions
Write-Host "`n[5/5] Agrega múltiplas transactions" -ForegroundColor Yellow
$txs = @(
    [PSCustomObject]@{ btcAmount = 150; signal = "BEARISH"; scoreImpact = -10 }
    [PSCustomObject]@{ btcAmount = 200; signal = "BEARISH"; scoreImpact = -15 }
    [PSCustomObject]@{ btcAmount = 100; signal = "BULLISH"; scoreImpact = 10 }
)
$r5 = Get-WhaleSignals -Transactions $txs
if ($r5.netSignal -eq "BEARISH" -and $r5.totalBtc -eq 450) {
    Write-Host "  PASS: netSignal=$($r5.netSignal) totalBtc=$($r5.totalBtc)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: netSignal=$($r5.netSignal) totalBtc=$($r5.totalBtc)" -ForegroundColor Red
    $failed++
}

# RESUMO
Write-Host "`n=== RESUMO ===" -ForegroundColor White
Write-Host "Passed: $passed/5" -ForegroundColor $(if($passed -eq 5){"Green"}else{"Yellow"})
Write-Host "Failed: $failed/5" -ForegroundColor $(if($failed -eq 0){"Green"}else{"Red"})

if ($passed -eq 5) {
    Write-Host "`nTODOS OS TESTES PASSARAM! TDD VALIDADO" -ForegroundColor Green
    Write-Host "Proximo: Integrar no ChainAgent" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nALGUNS TESTES FALHARAM" -ForegroundColor Red
    exit 1
}
