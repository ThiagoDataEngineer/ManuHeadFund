# tests/test_rsi_manual.ps1
# Test RSI calculation manually (sem Pester)
# Criado: 2026-05-23

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

# Load libs
. "$root\agents\lib_chart_patterns.ps1"
. "$root\agents\lib_tori_proximity.ps1"

Write-Host "="*60 -ForegroundColor Cyan
Write-Host "RSI VALIDATION - PowerShell Implementations" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# Test 1: Uptrend
Write-Host "`nTEST 1: Uptrend (expect RSI > 70)" -ForegroundColor Yellow
$closes_up = @(0..29 | ForEach-Object { 100 + $_ * 2 })
$rsi_cp = _CP-CalcRsiArray -Closes $closes_up -Period 14
$rsi_tori = _ToriProx-CalcRSI -Closes $closes_up -Period 14

Write-Host "  Prices: $($closes_up[0..4] -join ', ')...$($closes_up[-5..-1] -join ', ')"
Write-Host "  _CP-CalcRsiArray last 5: $($rsi_cp[-5..-1] | ForEach-Object { [math]::Round($_, 1) } | Join-String -Separator ', ')"
Write-Host "  _CP-CalcRsiArray last: $([math]::Round($rsi_cp[-1], 1))"
Write-Host "  _ToriProx-CalcRSI: $([math]::Round($rsi_tori, 1))"

if ($rsi_cp[-1] -gt 70 -and $rsi_cp[-1] -lt 100) {
    Write-Host "  ✅ PASS: _CP-CalcRsiArray RSI > 70" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _CP-CalcRsiArray RSI = $($rsi_cp[-1]) (expected > 70)" -ForegroundColor Red
}

if ($rsi_tori -gt 70 -and $rsi_tori -lt 100) {
    Write-Host "  ✅ PASS: _ToriProx-CalcRSI RSI > 70" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _ToriProx-CalcRSI RSI = $rsi_tori (expected > 70)" -ForegroundColor Red
}

if ([math]::Abs($rsi_cp[-1] - $rsi_tori) -lt 0.1) {
    Write-Host "  ✅ PASS: Both implementations match" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: Implementations differ (CP=$($rsi_cp[-1]), Tori=$rsi_tori)" -ForegroundColor Red
}

# Test 2: Downtrend
Write-Host "`nTEST 2: Downtrend (expect RSI < 30)" -ForegroundColor Yellow
$closes_down = @(0..29 | ForEach-Object { 100 - $_ * 2 })
$rsi_cp = _CP-CalcRsiArray -Closes $closes_down -Period 14
$rsi_tori = _ToriProx-CalcRSI -Closes $closes_down -Period 14

Write-Host "  Prices: $($closes_down[0..4] -join ', ')...$($closes_down[-5..-1] -join ', ')"
Write-Host "  _CP-CalcRsiArray last 5: $($rsi_cp[-5..-1] | ForEach-Object { [math]::Round($_, 1) } | Join-String -Separator ', ')"
Write-Host "  _CP-CalcRsiArray last: $([math]::Round($rsi_cp[-1], 1))"
Write-Host "  _ToriProx-CalcRSI: $([math]::Round($rsi_tori, 1))"

if ($rsi_cp[-1] -lt 30 -and $rsi_cp[-1] -gt 0) {
    Write-Host "  ✅ PASS: _CP-CalcRsiArray RSI < 30" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _CP-CalcRsiArray RSI = $($rsi_cp[-1]) (expected < 30)" -ForegroundColor Red
}

if ($rsi_tori -lt 30 -and $rsi_tori -gt 0) {
    Write-Host "  ✅ PASS: _ToriProx-CalcRSI RSI < 30" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _ToriProx-CalcRSI RSI = $rsi_tori (expected < 30)" -ForegroundColor Red
}

if ([math]::Abs($rsi_cp[-1] - $rsi_tori) -lt 0.1) {
    Write-Host "  ✅ PASS: Both implementations match" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: Implementations differ (CP=$($rsi_cp[-1]), Tori=$rsi_tori)" -ForegroundColor Red
}

# Test 3: Sideways
Write-Host "`nTEST 3: Sideways (expect RSI ~50)" -ForegroundColor Yellow
$closes_side = @(0..29 | ForEach-Object { 100 + ($_ % 2) })
$rsi_cp = _CP-CalcRsiArray -Closes $closes_side -Period 14
$rsi_tori = _ToriProx-CalcRSI -Closes $closes_side -Period 14

Write-Host "  Prices: $($closes_side[0..9] -join ', ')...$($closes_side[-10..-1] -join ', ')"
Write-Host "  _CP-CalcRsiArray last 5: $($rsi_cp[-5..-1] | ForEach-Object { [math]::Round($_, 1) } | Join-String -Separator ', ')"
Write-Host "  _CP-CalcRsiArray last: $([math]::Round($rsi_cp[-1], 1))"
Write-Host "  _ToriProx-CalcRSI: $([math]::Round($rsi_tori, 1))"

if ($rsi_cp[-1] -gt 40 -and $rsi_cp[-1] -lt 60) {
    Write-Host "  ✅ PASS: _CP-CalcRsiArray RSI ~50" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _CP-CalcRsiArray RSI = $($rsi_cp[-1]) (expected 40-60)" -ForegroundColor Red
}

if ($rsi_tori -gt 40 -and $rsi_tori -lt 60) {
    Write-Host "  ✅ PASS: _ToriProx-CalcRSI RSI ~50" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _ToriProx-CalcRSI RSI = $rsi_tori (expected 40-60)" -ForegroundColor Red
}

if ([math]::Abs($rsi_cp[-1] - $rsi_tori) -lt 0.1) {
    Write-Host "  ✅ PASS: Both implementations match" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: Implementations differ (CP=$($rsi_cp[-1]), Tori=$rsi_tori)" -ForegroundColor Red
}

# Test 4: BTC-like
Write-Host "`nTEST 4: BTC-like volatility (expect RSI 50-80)" -ForegroundColor Yellow
$closes_btc = @(
    100, 102, 101, 105, 103, 108, 106, 110, 108, 112,
    115, 113, 118, 116, 120, 118, 122, 120, 125, 123,
    128, 126, 130, 128, 132, 130, 135, 133, 138, 136
)
$rsi_cp = _CP-CalcRsiArray -Closes $closes_btc -Period 14
$rsi_tori = _ToriProx-CalcRSI -Closes $closes_btc -Period 14

Write-Host "  Prices: $($closes_btc[0..4] -join ', ')...$($closes_btc[-5..-1] -join ', ')"
Write-Host "  _CP-CalcRsiArray last 5: $($rsi_cp[-5..-1] | ForEach-Object { [math]::Round($_, 1) } | Join-String -Separator ', ')"
Write-Host "  _CP-CalcRsiArray last: $([math]::Round($rsi_cp[-1], 1))"
Write-Host "  _ToriProx-CalcRSI: $([math]::Round($rsi_tori, 1))"

if ($rsi_cp[-1] -gt 0 -and $rsi_cp[-1] -lt 100 -and $rsi_cp[-1] -gt 50) {
    Write-Host "  ✅ PASS: _CP-CalcRsiArray RSI valid and bullish" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _CP-CalcRsiArray RSI = $($rsi_cp[-1]) (expected 50-100)" -ForegroundColor Red
}

if ($rsi_tori -gt 0 -and $rsi_tori -lt 100 -and $rsi_tori -gt 50) {
    Write-Host "  ✅ PASS: _ToriProx-CalcRSI RSI valid and bullish" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _ToriProx-CalcRSI RSI = $rsi_tori (expected 50-100)" -ForegroundColor Red
}

if ([math]::Abs($rsi_cp[-1] - $rsi_tori) -lt 0.1) {
    Write-Host "  ✅ PASS: Both implementations match" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: Implementations differ (CP=$($rsi_cp[-1]), Tori=$rsi_tori)" -ForegroundColor Red
}

# Test 5: Edge case - insufficient history
Write-Host "`nTEST 5: Insufficient history (expect RSI = 50.0)" -ForegroundColor Yellow
$closes_short = @(100, 101, 102, 103, 104)
$rsi_cp = _CP-CalcRsiArray -Closes $closes_short -Period 14
$rsi_tori = _ToriProx-CalcRSI -Closes $closes_short -Period 14

Write-Host "  Prices: $($closes_short -join ', ')"
Write-Host "  _CP-CalcRsiArray: $($rsi_cp -join ', ')"
Write-Host "  _ToriProx-CalcRSI: $([math]::Round($rsi_tori, 1))"

$all_50 = $true
foreach ($val in $rsi_cp) {
    if ($val -ne 50.0) { $all_50 = $false; break }
}

if ($all_50) {
    Write-Host "  ✅ PASS: _CP-CalcRsiArray returns 50.0 for all values" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _CP-CalcRsiArray should return 50.0 for insufficient history" -ForegroundColor Red
}

if ($rsi_tori -eq 50.0) {
    Write-Host "  ✅ PASS: _ToriProx-CalcRSI returns 50.0" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL: _ToriProx-CalcRSI = $rsi_tori (expected 50.0)" -ForegroundColor Red
}

# Summary
Write-Host "`n" + ("="*60) -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host ("="*60) -ForegroundColor Cyan
Write-Host "If all tests PASS: PowerShell RSI implementations are CORRECT ✅" -ForegroundColor Green
Write-Host "If any test FAILS: PowerShell RSI has the same bug as Python ❌" -ForegroundColor Red
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "  1. If PASS: Proceed to re-run Python backtests" -ForegroundColor White
Write-Host "  2. If FAIL: Fix PowerShell RSI before continuing" -ForegroundColor White
