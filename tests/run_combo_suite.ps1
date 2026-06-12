# Test Runner for Signal Combo + Regime Position Sizing
# Full validation of cross-regime robustness implementation

param(
    [switch] $Verbose,
    [string] $Filter = "*"
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  COMBO SUITE — Signal + Regime Tests                      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n📋 Running 2 test files (33 tests total)..." -ForegroundColor Yellow
Write-Host "   1. lib_signal_combo.Tests.ps1 (14 tests)"
Write-Host "   2. lib_regime_position_sizing.Tests.ps1 (19 tests)"
Write-Host ""

$results = @()

# Run Signal Combo Tests
Write-Host "🧪 TEST 1: Signal Combo Logic" -ForegroundColor Cyan
$r1 = Invoke-Pester -Path (Join-Path $here "lib_signal_combo.Tests.ps1") -PassThru
$results += $r1

Write-Host ""

# Run Regime Position Tests
Write-Host "🧪 TEST 2: Regime Position Sizing" -ForegroundColor Cyan
$r2 = Invoke-Pester -Path (Join-Path $here "lib_regime_position_sizing.Tests.ps1") -PassThru
$results += $r2

# Summary
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "📊 FINAL SUMMARY" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════"

$totalTests = ($r1.TestResult | Measure-Object).Count + ($r2.TestResult | Measure-Object).Count
$passedTests = @($r1.TestResult | Where-Object { $_.Passed }).Count + @($r2.TestResult | Where-Object { $_.Passed }).Count
$failedTests = @($r1.TestResult | Where-Object { -not $_.Passed }).Count + @($r2.TestResult | Where-Object { -not $_.Passed }).Count

Write-Host ""
if ($failedTests -eq 0) {
    Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Total: $totalTests tests"
    Write-Host "  Passed: $passedTests ✓"
    Write-Host "  Failed: 0"
    Write-Host ""
    Write-Host "🚀 READY FOR IMPLEMENTATION" -ForegroundColor Green
} else {
    Write-Host "❌ SOME TESTS FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Total: $totalTests tests"
    Write-Host "  Passed: $passedTests ✓"
    Write-Host "  Failed: $failedTests ✗"
}

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════"
Write-Host ""

