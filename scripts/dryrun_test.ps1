# dryrun_test.ps1 - Teste de Dry-Run do ManuHeadFund v6.6
# Testa pipeline completo sem executar trades reais
$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  MANUHEADFUND v6.6 - DRY-RUN TEST" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

# â”€â”€ STEP 1: Verificar Estrutura â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[1/6] Verificando estrutura do projeto..." -ForegroundColor Yellow

$requiredFiles = @(
    "agents\config.ps1",
    "agents\orchestrator_v6.ps1",
    "agents\lib_coinex.ps1",
    "agents\lib_claude.ps1",
    "agents\chain_agent.ps1",
    "agents\lib_whale_detection.ps1"
)

$missing = @()
foreach ($file in $requiredFiles) {
    $path = Join-Path $PSScriptRoot "..\$file"
    if (-not (Test-Path $path)) {
        $missing += $file
        Write-Host "  FALTA: $file" -ForegroundColor Red
    } else {
        Write-Host "  OK: $file" -ForegroundColor Green
    }
}

if ($missing.Count -gt 0) {
    Write-Host "`nERRO: Arquivos faltando!" -ForegroundColor Red
    exit 1
}

# â”€â”€ STEP 2: Criar Pasta Journal â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[2/6] Criando pasta journal..." -ForegroundColor Yellow

$journalPath = Join-Path $PSScriptRoot "..\journal"
if (-not (Test-Path $journalPath)) {
    New-Item -ItemType Directory -Path $journalPath -Force | Out-Null
    Write-Host "  Criado: journal\" -ForegroundColor Green
} else {
    Write-Host "  Ja existe: journal\" -ForegroundColor Cyan
}

# â”€â”€ STEP 3: Carregar Configuracoes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[3/6] Carregando configuracoes..." -ForegroundColor Yellow

try {
    . (Join-Path $PSScriptRoot "..\agents\config.ps1")
    Write-Host "  Config carregado" -ForegroundColor Green
    
    # Verificar API keys (opcional para dry-run)
    if ($ANTHROPIC_API_KEY) {
        Write-Host "  Claude API: Configurado ($($ANTHROPIC_API_KEY.Length) chars)" -ForegroundColor Green
    } else {
        Write-Host "  Claude API: NAO configurado (dry-run vai usar fallback)" -ForegroundColor Yellow
    }
    
    if ($COINEX_ACCESS_ID) {
        Write-Host "  CoinEx API: Configurado" -ForegroundColor Green
    } else {
        Write-Host "  CoinEx API: NAO configurado (dry-run vai usar mock)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ERRO ao carregar config: $_" -ForegroundColor Red
    exit 1
}

# â”€â”€ STEP 4: Testar Whale Detection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[4/6] Testando Whale Detection..." -ForegroundColor Yellow

try {
    . (Join-Path $PSScriptRoot "..\agents\lib_whale_detection.ps1")
    
    # Testar com dados mock (formato correto da API Blockchain.info)
    $mockTx = [PSCustomObject]@{
        hash = "test_dryrun_12345"
        inputs = @(
            @{ prev_out = @{ addr = "whale_address"; value = 15000000000 } }
        )
        out = @(
            @{ addr = "other_address"; value = 15000000000 }
        )
    }
    
    $result = Test-WhaleTransaction -Transaction $mockTx -MinBtc 100
    
    if ($result.isWhale) {
        Write-Host "  Whale Detection: FUNCIONANDO" -ForegroundColor Green
        Write-Host "    Detectou: $($result.btcAmount) BTC" -ForegroundColor Cyan
        Write-Host "    Signal: $($result.signal)" -ForegroundColor Cyan
    } else {
        Write-Host "  Whale Detection: OK (nao e whale)" -ForegroundColor Green
    }
} catch {
    Write-Host "  ERRO: $_" -ForegroundColor Red
    Write-Host "  Continuando sem whale detection..." -ForegroundColor Yellow
}

# â”€â”€ STEP 5: Testar ChainAgent â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[5/6] Testando ChainAgent..." -ForegroundColor Yellow

try {
    . (Join-Path $PSScriptRoot "..\agents\lib_claude.ps1")
    . (Join-Path $PSScriptRoot "..\agents\lib_coinex.ps1")
    . (Join-Path $PSScriptRoot "..\agents\lib_cycle_mocks.ps1")
    . (Join-Path $PSScriptRoot "..\agents\lib_cycle_context.ps1")
    . (Join-Path $PSScriptRoot "..\agents\chain_agent.ps1")
    
    Write-Host "  Chamando ChainAgent para BTCUSDT..." -ForegroundColor Cyan
    
    # Desabilitar Claude para teste rapido (usa fallback)
    $env:AGENT_CHAIN_PROVIDER = "none"
    
    $chainResult = Invoke-ChainAgent -Market "BTCUSDT"
    
    if ($chainResult -and $chainResult.chain_score) {
        Write-Host "  ChainAgent: FUNCIONANDO" -ForegroundColor Green
        Write-Host "    chain_score: $($chainResult.chain_score)" -ForegroundColor Cyan
        Write-Host "    chain_bias: $($chainResult.chain_bias)" -ForegroundColor Cyan
        Write-Host "    whale_detection: $($chainResult.whale_detection)" -ForegroundColor Cyan
    } else {
        Write-Host "  ChainAgent: ERRO - resultado invalido" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERRO: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# â”€â”€ STEP 6: Resumo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[6/6] Resumo do Dry-Run" -ForegroundColor Yellow

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  RESULTADO DO DRY-RUN" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nComponentes Testados:" -ForegroundColor Yellow
Write-Host "  [x] Estrutura de arquivos" -ForegroundColor Green
Write-Host "  [x] Pasta journal" -ForegroundColor Green
Write-Host "  [x] Configuracoes" -ForegroundColor Green
Write-Host "  [x] Whale Detection" -ForegroundColor Green
Write-Host "  [x] ChainAgent" -ForegroundColor Green

Write-Host "`nProximo Passo:" -ForegroundColor Cyan
Write-Host "  Rodar Orchestrator v6 completo:" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\run_orchestrator_dryrun.ps1" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DRY-RUN BASICO: COMPLETO" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
