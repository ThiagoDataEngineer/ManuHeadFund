# run_orchestrator_dryrun.ps1 - Dry-Run Completo do Orchestrator v6
# Testa pipeline completo sem executar trades reais
param(
    [string]$Market = "BTCUSDT",
    [string]$Mode = "paper"  # paper = dry-run, live = real trades
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  ORCHESTRATOR V6 - DRY-RUN COMPLETO" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nParametros:" -ForegroundColor Yellow
Write-Host "  Market: $Market" -ForegroundColor White
Write-Host "  Mode: $Mode (dry-run)" -ForegroundColor White

# â”€â”€ STEP 1: Carregar Dependencias â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[1/5] Carregando dependencias..." -ForegroundColor Yellow

try {
    # Config
    . (Join-Path $PSScriptRoot "..\agents\config.ps1")
    Write-Host "  [x] config.ps1" -ForegroundColor Green
    
    # Libs basicas
    . (Join-Path $PSScriptRoot "..\agents\lib_coinex.ps1")
    Write-Host "  [x] lib_coinex.ps1" -ForegroundColor Green
    
    . (Join-Path $PSScriptRoot "..\agents\lib_claude.ps1")
    Write-Host "  [x] lib_claude.ps1" -ForegroundColor Green
    
    # Whale Detection
    . (Join-Path $PSScriptRoot "..\agents\lib_whale_detection.ps1")
    Write-Host "  [x] lib_whale_detection.ps1" -ForegroundColor Green
    
    # Cycle Context
    . (Join-Path $PSScriptRoot "..\agents\lib_cycle_mocks.ps1")
    . (Join-Path $PSScriptRoot "..\agents\lib_cycle_context.ps1")
    Write-Host "  [x] lib_cycle_*.ps1" -ForegroundColor Green
    
    # Macro e Seasonal
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "lib_macro.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\lib_macro.ps1")
        Write-Host "  [x] lib_macro.ps1" -ForegroundColor Green
    }
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "lib_seasonal.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\lib_seasonal.ps1")
        Write-Host "  [x] lib_seasonal.ps1" -ForegroundColor Green
    }
    
    # Whitelist
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "lib_operational_whitelist.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\lib_operational_whitelist.ps1")
        Write-Host "  [x] lib_operational_whitelist.ps1" -ForegroundColor Green
    }
    
    # Agents (Triagem, Mesa, Mentor)
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "triagem_agent.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\triagem_agent.ps1")
        Write-Host "  [x] triagem_agent.ps1" -ForegroundColor Green
    }
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "mesa_agent.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\mesa_agent.ps1")
        Write-Host "  [x] mesa_agent.ps1" -ForegroundColor Green
    }
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "mentor_agent.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\mentor_agent.ps1")
        Write-Host "  [x] mentor_agent.ps1" -ForegroundColor Green
    }
    
    # Mocks (fallback se agents nao existirem)
    if (Test-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot "..") "agents") "lib_esquadrao_mocks.ps1")) {
        . (Join-Path $PSScriptRoot "..\agents\lib_esquadrao_mocks.ps1")
        Write-Host "  [x] lib_esquadrao_mocks.ps1 (fallback)" -ForegroundColor Yellow
    }
    
    # ChainAgent
    . (Join-Path $PSScriptRoot "..\agents\chain_agent.ps1")
    Write-Host "  [x] chain_agent.ps1" -ForegroundColor Green
    
    # Orchestrator
    . (Join-Path $PSScriptRoot "..\agents\orchestrator_v6.ps1")
    Write-Host "  [x] orchestrator_v6.ps1" -ForegroundColor Green
    
} catch {
    Write-Host "  ERRO ao carregar dependencias: $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
    exit 1
}

# â”€â”€ STEP 2: Verificar Configuracoes â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[2/5] Verificando configuracoes..." -ForegroundColor Yellow

# API Keys
if ($ANTHROPIC_API_KEY) {
    Write-Host "  [x] Claude API configurado" -ForegroundColor Green
} else {
    Write-Host "  [!] Claude API NAO configurado (vai usar fallback)" -ForegroundColor Yellow
}

if ($COINEX_ACCESS_ID) {
    Write-Host "  [x] CoinEx API configurado" -ForegroundColor Green
} else {
    Write-Host "  [!] CoinEx API NAO configurado (vai usar mock)" -ForegroundColor Yellow
}

# Capital
Write-Host "  Capital Spot: $CAPITAL_SPOT USDT" -ForegroundColor Cyan
Write-Host "  Capital Futures: $CAPITAL_FUTURES USDT" -ForegroundColor Cyan
Write-Host "  Capital Total: $CAPITAL_TOTAL USDT" -ForegroundColor Cyan

# â”€â”€ STEP 3: Preparar Ambiente â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[3/5] Preparando ambiente..." -ForegroundColor Yellow

# Criar pasta journal se nao existir
$journalPath = Join-Path $PSScriptRoot (Join-Path ".." "journal")
if (-not (Test-Path $journalPath)) {
    New-Item -ItemType Directory -Path $journalPath -Force | Out-Null
    Write-Host "  [x] Pasta journal criada" -ForegroundColor Green
} else {
    Write-Host "  [x] Pasta journal existe" -ForegroundColor Green
}

# Timestamp para logs
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $journalPath "dryrun_$timestamp.log"

Write-Host "  [x] Log: $logFile" -ForegroundColor Green

# â”€â”€ STEP 4: Rodar Orchestrator â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[4/5] Rodando Orchestrator v6..." -ForegroundColor Yellow
Write-Host "  Market: $Market" -ForegroundColor Cyan
Write-Host "  Mode: $Mode (DRY-RUN)" -ForegroundColor Cyan
Write-Host ""

try {
    # Criar ScannerInfo mock para teste
    $scannerInfo = [PSCustomObject]@{
        score  = 75
        change = 2.5
        volume = 1000000
    }
    
    # Rodar Orchestrator em modo DRY-RUN
    $startTime = Get-Date
    
    $result = Invoke-OrchestratorV6 `
        -Market $Market `
        -DryRun `
        -ScannerInfo $scannerInfo `
        -Mode $Mode
    
    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  RESULTADO DO ORCHESTRATOR" -ForegroundColor White
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($result) {
        Write-Host "`nDecisao: $($result.decisao)" -ForegroundColor $(if($result.decisao -eq "APROVAR"){"Green"}elseif($result.decisao -eq "ABORTAR"){"Red"}else{"Yellow"})
        Write-Host "Motivo: $($result.motivo)" -ForegroundColor White
        
        if ($result.triagem) {
            Write-Host "`nTriagem:" -ForegroundColor Yellow
            Write-Host "  Tier: $($result.triagem.tier)" -ForegroundColor Cyan
            Write-Host "  Direction: $($result.triagem.direction)" -ForegroundColor Cyan
            Write-Host "  Regime: $($result.triagem.regime)" -ForegroundColor Cyan
        }
        
        if ($result.mesa) {
            Write-Host "`nMesa:" -ForegroundColor Yellow
            Write-Host "  Consensus: $($result.mesa.consensus)" -ForegroundColor Cyan
            Write-Host "  Score: $($result.mesa.score_ponderado)" -ForegroundColor Cyan
        }
        
        if ($result.mentor) {
            Write-Host "`nMentor:" -ForegroundColor Yellow
            Write-Host "  Decisao: $($result.mentor.decisao)" -ForegroundColor Cyan
            Write-Host "  Confianca: $($result.mentor.confianca)" -ForegroundColor Cyan
        }
        
        Write-Host "`nTempo: $([math]::Round($duration, 2))s" -ForegroundColor Gray
        
        # Salvar resultado em log
        $result | ConvertTo-Json -Depth 10 | Out-File $logFile -Encoding UTF8
        Write-Host "Log salvo: $logFile" -ForegroundColor Gray
        
    } else {
        Write-Host "`nERRO: Orchestrator retornou null" -ForegroundColor Red
    }
    
} catch {
    Write-Host "`nERRO ao rodar Orchestrator: $_" -ForegroundColor Red
    Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
    
    # Salvar erro em log
    @{
        error = $_.Exception.Message
        stack = $_.ScriptStackTrace
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json | Out-File $logFile -Encoding UTF8
    
    exit 1
}

# â”€â”€ STEP 5: Resumo â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Write-Host "`n[5/5] Resumo do Dry-Run" -ForegroundColor Yellow

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DRY-RUN COMPLETO" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nComponentes Testados:" -ForegroundColor Yellow
Write-Host "  [x] Config e APIs" -ForegroundColor Green
Write-Host "  [x] Whale Detection" -ForegroundColor Green
Write-Host "  [x] ChainAgent" -ForegroundColor Green
Write-Host "  [x] Orchestrator v6" -ForegroundColor Green

Write-Host "`nResultado:" -ForegroundColor Yellow
if ($result -and $result.decisao) {
    Write-Host "  Decisao: $($result.decisao)" -ForegroundColor $(if($result.decisao -eq "APROVAR"){"Green"}elseif($result.decisao -eq "ABORTAR"){"Red"}else{"Yellow"})
    Write-Host "  Tempo: $([math]::Round($duration, 2))s" -ForegroundColor Cyan
} else {
    Write-Host "  ERRO: Sem resultado" -ForegroundColor Red
}

Write-Host "`nLog:" -ForegroundColor Yellow
Write-Host "  $logFile" -ForegroundColor Gray

Write-Host "`nProximo Passo:" -ForegroundColor Cyan
Write-Host "  Se tudo funcionou, testar com trade micro ($50-100)" -ForegroundColor White
Write-Host "  Configurar capital de teste em config.ps1" -ForegroundColor Gray

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DRY-RUN: COMPLETO" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
