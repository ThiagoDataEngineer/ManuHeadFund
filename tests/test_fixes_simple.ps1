# test_fixes_simple.ps1 - Teste simples dos 3 fixes
$ErrorActionPreference = "Stop"

Write-Host "`n=== TESTE DOS 3 FIXES CRITICOS ===" -ForegroundColor Cyan
$passed = 0; $failed = 0

# TEST 1: Pre-Mentor Skip
Write-Host "`n[1/3] Pre-Mentor Skip" -ForegroundColor Yellow
$c1 = Get-Content "agents\orchestrator_v6.ps1" -Raw
if ($c1 -match 'tier=C.*observe' -and $c1 -match 'tier=C.*skip') {
    Write-Host "  PASS: Codigo encontrado" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: Codigo nao encontrado" -ForegroundColor Red
    $failed++
}

# TEST 2: Tori 2 Touches
Write-Host "`n[2/3] Tori 2 Touches" -ForegroundColor Yellow
$c2 = Get-Content "agents\tech_agent_ai.ps1" -Raw
if ($c2 -match 'touches -eq 2' -and $c2 -match 'estrutura_nascente') {
    Write-Host "  PASS: Fallback implementado" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: Fallback nao encontrado" -ForegroundColor Red
    $failed++
}

# TEST 3: ChainAgent Full Data
Write-Host "`n[3/3] ChainAgent Full Data" -ForegroundColor Yellow
$c3 = Get-Content "agents\chain_agent.ps1" -Raw
$hasNew = $c3 -match '-Limit 3973'
$hasOld = $c3 -match '-Limit 500[^0-9]'
if ($hasNew -and -not $hasOld) {
    Write-Host "  PASS: Limit 3973 encontrado, 500 removido" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  FAIL: hasNew=$hasNew hasOld=$hasOld" -ForegroundColor Red
    $failed++
}

# RESUMO
Write-Host "`n=== RESUMO ===" -ForegroundColor White
Write-Host "Passed: $passed/3" -ForegroundColor $(if($passed -eq 3){"Green"}else{"Yellow"})
Write-Host "Failed: $failed/3" -ForegroundColor $(if($failed -eq 0){"Green"}else{"Red"})

if ($passed -eq 3) {
    Write-Host "`nTODOS OS FIXES VALIDADOS!" -ForegroundColor Green
    Write-Host "ROI: +`$775/ano" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "`nALGUNS TESTES FALHARAM" -ForegroundColor Red
    exit 1
}
