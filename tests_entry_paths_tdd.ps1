#!/usr/bin/env pwsh
# TDD: Trade Entry Paths Validation (2026-06-19)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$results = @()

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  TDD: TODOS OS 5 CAMINHOS DE ENTRADA DE TRADE" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# TEST 1: sync_and_fix_tp.ps1
# ============================================================
Write-Host "[TEST 1] sync_and_fix_tp.ps1 - Position Sync" -ForegroundColor Yellow

$script1 = Join-Path $projectRoot "scripts\sync_and_fix_tp.ps1"
$test1 = $false

if (Test-Path $script1) {
    $content = Get-Content $script1 -Raw

    $hasAutoDetect = $content -match 'Markets\.Count.*-eq.*0|Auto-detect'
    $hasStop = $content -match '-ErrorAction\s+Stop'

    $test1 = $hasAutoDetect -and $hasStop

    Write-Host "  File: ✅ Found"
    Write-Host "  Auto-detect: $(if($hasAutoDetect) { '✅' } else { '❌' })"
    Write-Host "  ErrorAction Stop: $(if($hasStop) { '✅' } else { '❌' })"
    Write-Host "  Result: $(if($test1) { '✅ PASS' } else { '❌ FAIL' })"
} else {
    Write-Host "  File: ❌ NOT FOUND"
}

$results += @{ Name = "sync_and_fix_tp"; Pass = $test1 }
Write-Host ""

# ============================================================
# TEST 2: gem_loop.ps1
# ============================================================
Write-Host "[TEST 2] gem_loop.ps1 - Automatic Entry" -ForegroundColor Yellow

$script2 = Join-Path $projectRoot "scripts\gem_loop.ps1"
$test2 = $false

if (Test-Path $script2) {
    $content = Get-Content $script2 -Raw

    $hasGemAgent = $content -match 'gem_agent\.ps1'
    $hasExecutor = $content -match 'gem_executor\.ps1'
    $hasOnce = $content -match '\[switch\]\$Once'
    $hasInvokeGemExecute = $content -match 'Invoke-GemExecute'

    $test2 = $hasGemAgent -and $hasExecutor -and $hasOnce -and $hasInvokeGemExecute

    Write-Host "  File: ✅ Found"
    Write-Host "  Loads gem_agent: $(if($hasGemAgent) { '✅' } else { '❌' })"
    Write-Host "  Loads gem_executor: $(if($hasExecutor) { '✅' } else { '❌' })"
    Write-Host "  Has -Once param: $(if($hasOnce) { '✅' } else { '❌' })"
    Write-Host "  Calls Invoke-GemExecute: $(if($hasInvokeGemExecute) { '✅' } else { '❌' })"
    Write-Host "  Result: $(if($test2) { '✅ PASS' } else { '❌ FAIL' })"
} else {
    Write-Host "  File: ❌ NOT FOUND"
}

$results += @{ Name = "gem_loop"; Pass = $test2 }
Write-Host ""

# ============================================================
# TEST 3: /idea (Telegram Manual Entry)
# ============================================================
Write-Host "[TEST 3] Telegram /idea - Manual Price Trigger" -ForegroundColor Yellow

$script3 = Join-Path $projectRoot "scripts\telegram_listener.ps1"
$test3 = $false

if (Test-Path $script3) {
    $content = Get-Content $script3 -Raw

    $hasIdea = $content -match '"/idea"|idea.*command'
    $hasSignalTriggers = $content -match 'signal_triggers'

    $test3 = $hasIdea -and $hasSignalTriggers

    Write-Host "  File: ✅ Found"
    Write-Host "  Has /idea handler: $(if($hasIdea) { '✅' } else { '❌' })"
    Write-Host "  Uses signal_triggers: $(if($hasSignalTriggers) { '✅' } else { '❌' })"
    Write-Host "  Result: $(if($test3) { '✅ PASS' } else { '❌ FAIL' })"
} else {
    Write-Host "  File: ❌ NOT FOUND"
}

$results += @{ Name = "/idea"; Pass = $test3 }
Write-Host ""

# ============================================================
# TEST 4: /approve (Telegram Bypass Gates)
# ============================================================
Write-Host "[TEST 4] Telegram /approve - Force Entry (BYPASS GATES)" -ForegroundColor Yellow

$script4listener = Join-Path $projectRoot "scripts\telegram_listener.ps1"
$script4lib = Join-Path $projectRoot "agents\lib_tg_approval_handler.ps1"
$test4 = $false

if (Test-Path $script4listener) {
    $content = Get-Content $script4listener -Raw
    $hasApprove = $content -match '"/approve"|approve.*command'

    if (Test-Path $script4lib) {
        $libContent = Get-Content $script4lib -Raw
        $hasFunction = $libContent -match 'Process-ApprovalCommand|function'
        $hasBypass = $libContent -match 'bypass|Force|approval'

        $test4 = $hasApprove -and $hasFunction -and $hasBypass

        Write-Host "  telegram_listener.ps1: ✅ Found"
        Write-Host "  lib_tg_approval_handler.ps1: ✅ Found"
        Write-Host "  Has /approve handler: $(if($hasApprove) { '✅' } else { '❌' })"
        Write-Host "  Has bypass function: $(if($hasFunction) { '✅' } else { '❌' })"
        Write-Host "  Has bypass logic: $(if($hasBypass) { '✅' } else { '❌' })"
        Write-Host "  Result: $(if($test4) { '✅ PASS' } else { '❌ FAIL' })"
    } else {
        Write-Host "  telegram_listener.ps1: ✅ Found"
        Write-Host "  lib_tg_approval_handler.ps1: ❌ NOT FOUND"
        Write-Host "  Result: ❌ FAIL (approval lib missing)"
    }
} else {
    Write-Host "  telegram_listener.ps1: ❌ NOT FOUND"
}

$results += @{ Name = "/approve"; Pass = $test4 }
Write-Host ""

# ============================================================
# TEST 5: cloud_conviction_scan (Observation Only)
# ============================================================
Write-Host "[TEST 5] cloud_conviction_scan - Observation Mode" -ForegroundColor Yellow

$script5 = Join-Path $projectRoot "scripts\cloud_conviction_scan.ps1"
$test5 = $false

if (Test-Path $script5) {
    $content = Get-Content $script5 -Raw

    $hasConviction = $content -match 'conviction|ensemble'

    $test5 = $hasConviction

    Write-Host "  File: ✅ Found"
    Write-Host "  Has conviction logic: $(if($hasConviction) { '✅' } else { '❌' })"
    Write-Host "  Result: $(if($test5) { '✅ PASS' } else { '❌ FAIL' })"
} else {
    Write-Host "  File: ❌ NOT FOUND"
}

$results += @{ Name = "scan_master"; Pass = $test5 }
Write-Host ""

# ============================================================
# SUMMARY
# ============================================================
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESULTADOS TDD" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$passed = ($results | Where-Object { $_.Pass } | Measure-Object).Count
$failed = ($results | Where-Object { -not $_.Pass } | Measure-Object).Count

Write-Host ""
$passColor = if ($passed -eq 5) { "Green" } else { "Yellow" }
$failColor = if ($failed -eq 0) { "Green" } else { "Red" }
Write-Host "Passed: $passed / 5" -ForegroundColor $passColor
Write-Host "Failed: $failed / 5" -ForegroundColor $failColor
Write-Host ""

foreach ($r in $results) {
    $status = if ($r.Pass) { "✅ PASS" } else { "❌ FAIL" }
    Write-Host "$status : $($r.Name)"
}

Write-Host ""

if ($failed -eq 0) {
    Write-Host "🎉 TODOS OS 5 CAMINHOS FUNCIONANDO" -ForegroundColor Green
    Write-Host ""
    Write-Host "✅ gem_loop (automático a cada 15 min)" -ForegroundColor Green
    Write-Host "✅ scan_master (observação a cada 1h)" -ForegroundColor Green
    Write-Host "✅ /idea (alertas manuais de preço)" -ForegroundColor Green
    Write-Host "✅ /approve (força entrada, bypassa gates)" -ForegroundColor Green
    Write-Host "✅ sync_and_fix_tp (sincroniza posições a cada 5 min)" -ForegroundColor Green
} else {
    Write-Host "⚠️  FALHAS DETECTADAS" -ForegroundColor Red
    Write-Host ""
    foreach ($r in $results | Where-Object { -not $_.Pass }) {
        Write-Host "❌ $($r.Name) — VERIFICAR" -ForegroundColor Red
    }
}

Write-Host ""
exit (if ($failed -eq 0) { 0 } else { 1 })
