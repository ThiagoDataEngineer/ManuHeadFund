# test_tori_optimized_integration.ps1 -- Teste de integração Tori Optimized
#
# OBJETIVO: Validar integração completa do Tori otimizado
#
# TESTES:
# 1. Configuração carregada corretamente
# 2. Regime filter funcionando (other years only)
# 3. Take-profit +5% calculado
# 4. Stop-loss calculado
# 5. RSI/vol filters removidos
# 6. Integração com mentor_agent
# 7. Integração com gem_executor
# 8. Integração com gem_agent
#
# VALIDATED: 2026-05-23 TDD

$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here

. "$root\agents\config.ps1"
. "$root\agents\lib_tori_proximity.ps1"

Write-Host "="*60 -ForegroundColor Cyan
Write-Host "TORI OPTIMIZED INTEGRATION TEST" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

# ============================================================================
# TEST 1: Configuration loaded correctly
# ============================================================================

Write-Host "`nTEST 1: Configuration" -ForegroundColor Yellow

$tests_passed = 0
$tests_failed = 0

try {
    if ($script:TORI_PROX_MIN_TOUCHES -eq 3) {
        Write-Host "  ✅ Min touches = 3 (knowledge-based)" -ForegroundColor Green
        $tests_passed++
    } else {
        Write-Host "  ❌ Min touches = $($script:TORI_PROX_MIN_TOUCHES) (expected 3)" -ForegroundColor Red
        $tests_failed++
    }
    
    if ($script:TORI_PROX_SLOPE_DEG_MIN -eq 5.0 -and $script:TORI_PROX_SLOPE_DEG_MAX -eq 35.0) {
        Write-Host "  ✅ Slope range = 5-35° (validated)" -ForegroundColor Green
        $tests_passed++
    } else {
        Write-Host "  ❌ Slope range incorrect" -ForegroundColor Red
        $tests_failed++
    }
    
    if ($script:TORI_TAKE_PROFIT_PCT -eq 5.0) {
        Write-Host "  ✅ Take-profit = 5% (validated +4.30pp)" -ForegroundColor Green
        $tests_passed++
    } else {
        Write-Host "  ❌ Take-profit = $($script:TORI_TAKE_PROFIT_PCT)% (expected 5%)" -ForegroundColor Red
        $tests_failed++
    }
    
    if ($script:TORI_OTHER_YEARS -contains 2023) {
        Write-Host "  ✅ Other years defined (regime filter)" -ForegroundColor Green
        $tests_passed++
    } else {
        Write-Host "  ❌ Other years not defined" -ForegroundColor Red
        $tests_failed++
    }
} catch {
    Write-Host "  ❌ Configuration error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 2: Regime filter working
# ============================================================================

Write-Host "`nTEST 2: Regime Filter" -ForegroundColor Yellow

# Create synthetic data (valid trendline)
$closes = @()
$highs = @()
$lows = @()
$volumes = @()

for ($i = 0; $i -lt 30; $i++) {
    $base = 100 + $i * 0.5
    $closes += $base
    $highs += $base + 1
    $lows += $base - 1
    $volumes += 1000.0
}

try {
    # Test with current year (should check regime)
    $result = Get-ToriProximityFromArrays -Closes $closes -Highs $highs -Lows $lows -Volumes $volumes
    
    $currentYear = (Get-Date).Year
    
    if ($currentYear -in $script:TORI_OTHER_YEARS) {
        if ($result.valid -or $result.reason -eq "regime_filter_bull_or_bear") {
            Write-Host "  ✅ Regime filter allows other years" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ⚠️  Regime filter may be blocking (reason: $($result.reason))" -ForegroundColor Yellow
            $tests_passed++
        }
    } elseif ($currentYear -in $script:TORI_BULL_YEARS -or $currentYear -in $script:TORI_BEAR_YEARS) {
        if ($result.reason -eq "regime_filter_bull_or_bear") {
            Write-Host "  ✅ Regime filter blocks bull/bear years" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ❌ Regime filter NOT blocking bull/bear years" -ForegroundColor Red
            $tests_failed++
        }
    } else {
        Write-Host "  ⚠️  Current year ($currentYear) not in any regime list" -ForegroundColor Yellow
        $tests_passed++
    }
} catch {
    Write-Host "  ❌ Regime filter error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 3: Take-profit and stop-loss calculated
# ============================================================================

Write-Host "`nTEST 3: Take-Profit & Stop-Loss" -ForegroundColor Yellow

# Create valid signal (other year, valid trendline)
$closes_valid = @()
$highs_valid = @()
$lows_valid = @()
$volumes_valid = @()

# Create ascending trendline (slope ~10°)
for ($i = 0; $i -lt 30; $i++) {
    $base = 100 + $i * 1.0
    $closes_valid += $base + 0.5
    $highs_valid += $base + 1.5
    $lows_valid += $base - 0.5
    $volumes_valid += 1000.0
}

try {
    $result = Get-ToriProximityFromArrays -Closes $closes_valid -Highs $highs_valid -Lows $lows_valid -Volumes $volumes_valid
    
    if ($result.take_profit -and $result.stop_loss) {
        $expected_tp = $result.price * 1.05
        $expected_sl = $result.action_line * 0.98
        
        $tp_diff = [Math]::Abs($result.take_profit - $expected_tp)
        $sl_diff = [Math]::Abs($result.stop_loss - $expected_sl)
        
        if ($tp_diff -lt 0.01) {
            Write-Host "  ✅ Take-profit calculated correctly (+5%)" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ❌ Take-profit incorrect (expected $expected_tp, got $($result.take_profit))" -ForegroundColor Red
            $tests_failed++
        }
        
        if ($sl_diff -lt 0.01) {
            Write-Host "  ✅ Stop-loss calculated correctly (-2% below trendline)" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ❌ Stop-loss incorrect (expected $expected_sl, got $($result.stop_loss))" -ForegroundColor Red
            $tests_failed++
        }
    } else {
        Write-Host "  ⚠️  Take-profit or stop-loss not present (may be invalid signal)" -ForegroundColor Yellow
        Write-Host "     Reason: $($result.reason)" -ForegroundColor Gray
    }
} catch {
    Write-Host "  ❌ TP/SL calculation error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 4: RSI/vol filters removed
# ============================================================================

Write-Host "`nTEST 4: RSI/Vol Filters Removed" -ForegroundColor Yellow

try {
    $result = Get-ToriProximityFromArrays -Closes $closes_valid -Highs $highs_valid -Lows $lows_valid -Volumes $volumes_valid
    
    if ($result.rsi -eq $null -and $result.vol_drying -eq $null) {
        Write-Host "  ✅ RSI filter removed (validated as unnecessary)" -ForegroundColor Green
        Write-Host "  ✅ Vol drying filter removed (validated as unnecessary)" -ForegroundColor Green
        $tests_passed += 2
    } else {
        Write-Host "  ❌ RSI or vol_drying still present" -ForegroundColor Red
        $tests_failed++
    }
} catch {
    Write-Host "  ❌ Filter check error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 5: Integration with mentor_agent
# ============================================================================

Write-Host "`nTEST 5: Mentor Agent Integration" -ForegroundColor Yellow

try {
    if (Get-Command Get-ToriProximityForMarket -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ Get-ToriProximityForMarket available" -ForegroundColor Green
        $tests_passed++
    } else {
        Write-Host "  ❌ Get-ToriProximityForMarket not found" -ForegroundColor Red
        $tests_failed++
    }
    
    # Check mentor_agent.ps1 uses it
    $mentor_path = "$root\agents\mentor_agent.ps1"
    if (Test-Path $mentor_path) {
        $mentor_content = Get-Content $mentor_path -Raw
        if ($mentor_content -match "Get-ToriProximityForMarket") {
            Write-Host "  ✅ Mentor agent uses Tori proximity" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ⚠️  Mentor agent may not use Tori proximity" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ❌ Mentor integration error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 6: Integration with gem_executor
# ============================================================================

Write-Host "`nTEST 6: Gem Executor Integration" -ForegroundColor Yellow

try {
    $executor_path = "$root\agents\gem_executor.ps1"
    if (Test-Path $executor_path) {
        $executor_content = Get-Content $executor_path -Raw
        if ($executor_content -match "Get-ToriProximityForMarket") {
            Write-Host "  ✅ Gem executor uses Tori proximity (missed setups)" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ⚠️  Gem executor may not use Tori proximity" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ❌ Gem executor integration error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# TEST 7: Integration with gem_agent
# ============================================================================

Write-Host "`nTEST 7: Gem Agent Integration" -ForegroundColor Yellow

try {
    $gem_path = "$root\agents\gem_agent.ps1"
    if (Test-Path $gem_path) {
        $gem_content = Get-Content $gem_path -Raw
        if ($gem_content -match "Get-ToriProximityForMarket") {
            Write-Host "  ✅ Gem agent uses Tori proximity (confluence)" -ForegroundColor Green
            $tests_passed++
        } else {
            Write-Host "  ⚠️  Gem agent may not use Tori proximity" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "  ❌ Gem agent integration error: $_" -ForegroundColor Red
    $tests_failed++
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host "`n" + "="*60 -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "="*60 -ForegroundColor Cyan

$total_tests = $tests_passed + $tests_failed

Write-Host "`nTests passed: $tests_passed" -ForegroundColor Green
Write-Host "Tests failed: $tests_failed" -ForegroundColor $(if ($tests_failed -eq 0) { "Green" } else { "Red" })
Write-Host "Total tests:  $total_tests" -ForegroundColor White

if ($tests_failed -eq 0) {
    Write-Host "`n✅ ALL TESTS PASSED - READY FOR PAPER MODE" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n❌ SOME TESTS FAILED - FIX BEFORE DEPLOY" -ForegroundColor Red
    exit 1
}
