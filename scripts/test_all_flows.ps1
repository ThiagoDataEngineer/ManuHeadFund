# test_all_flows.ps1 - Teste profundo de todos os fluxos do sistema
# Valida: Dashboard, Telegram, Risk Manager, ProteÃ§Ã£o Anti-DuplicaÃ§Ã£o

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TESTE COMPLETO DE TODOS OS FLUXOS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results = @{
    dashboard = $false
    telegram = $false
    risk_manager = $false
    protection = $false
    errors = @()
}

# ============================================================================
# TESTE 1: Dashboard Elite
# ============================================================================

Write-Host "[1/4] Testando Dashboard Elite..." -ForegroundColor Yellow

try {
    . ".\scripts\generate_dashboard_elite.ps1"
    
    $dashPath = ".\dashboard\index.html"
    if (Test-Path $dashPath) {
        $content = Get-Content $dashPath -Raw
        
        # Validar elementos essenciais
        $checks = @(
            ($content -match "ManuHeadFund"),
            ($content -match "Open Positions"),
            ($content -match "Total P&L"),
            ($content -match "Win Rate"),
            ($content -match "Chart.js")
        )
        
        if ($checks -notcontains $false) {
            Write-Host "  [OK] Dashboard gerado com sucesso" -ForegroundColor Green
            $results.dashboard = $true
        } else {
            $results.errors += "Dashboard: elementos essenciais faltando"
            Write-Host "  [ERRO] Dashboard incompleto" -ForegroundColor Red
        }
    } else {
        $results.errors += "Dashboard: arquivo nÃ£o gerado"
        Write-Host "  [ERRO] Dashboard nÃ£o foi gerado" -ForegroundColor Red
    }
} catch {
    $results.errors += "Dashboard: $_"
    Write-Host "  [ERRO] $($_)" -ForegroundColor Red
}

# ============================================================================
# TESTE 2: Telegram (mensagens limpas)
# ============================================================================

Write-Host "`n[2/4] Testando Telegram..." -ForegroundColor Yellow

try {
    . ".\agents\lib_telegram.ps1"
    
    # Teste 1: Position Opened
    $testPos = @{
        market = "TESTUSDT"
        side = "long"
        entry_price = 100.50
        size = 10
        leverage = 5
        stop_loss = 95.00
        take_profit = 120.00
        capital = 1000
    }
    
    $msg1 = Telegram-SendPositionOpened -Position $testPos
    
    # Teste 2: Trailing Activated
    $testTrailing = @{
        market = "TESTUSDT"
        entry_price = 100.50
        current_price = 110.00
        profit_pct = 9.45
        new_stop = 105.00
        locked_profit_pct = 4.48
    }
    
    $msg2 = Telegram-SendTrailingActivated -Position $testTrailing
    
    # Teste 3: Dashboard Snapshot
    $testMetrics = [PSCustomObject]@{
        open_positions = 1
        total_pnl = -612.37
        win_rate = 49
        capital = 2157
        sharpe_ratio = 0
        max_drawdown = 63.76
        profit_factor = 0.26
        open_positions_detail = @(
            [PSCustomObject]@{
                market = "BNBUSDT"
                side = "long"
                unrealized_pnl_pct = 0.77
            }
        )
    }
    
    $msg3 = Telegram-SendDashboardSnapshot -Metrics $testMetrics
    
    # Validar respostas
    if ($msg1.success -and $msg2.success -and $msg3.success) {
        Write-Host "  [OK] Telegram: 3 mensagens enviadas com sucesso" -ForegroundColor Green
        Write-Host "      Message IDs: $($msg1.message_id), $($msg2.message_id), $($msg3.message_id)" -ForegroundColor Gray
        $results.telegram = $true
    } else {
        $results.errors += "Telegram: falha ao enviar mensagens"
        Write-Host "  [ERRO] Falha ao enviar mensagens" -ForegroundColor Red
    }
} catch {
    $results.errors += "Telegram: $_"
    Write-Host "  [ERRO] $($_)" -ForegroundColor Red
}

# ============================================================================
# TESTE 3: Risk Manager
# ============================================================================

Write-Host "`n[3/4] Testando Risk Manager..." -ForegroundColor Yellow

try {
    . ".\scripts\position_risk_cron.ps1"
    
    # Verificar se executou sem erros
    Write-Host "  [OK] Risk Manager executado com sucesso" -ForegroundColor Green
    $results.risk_manager = $true
} catch {
    $results.errors += "Risk Manager: $_"
    Write-Host "  [ERRO] $($_)" -ForegroundColor Red
}

# ============================================================================
# TESTE 4: ProteÃ§Ã£o Anti-DuplicaÃ§Ã£o
# ============================================================================

Write-Host "`n[4/4] Testando ProteÃ§Ã£o Anti-DuplicaÃ§Ã£o..." -ForegroundColor Yellow

try {
    . ".\scripts\check_execution_mode.ps1"
    
    # Teste 1: Detectar modo
    $mode = Get-ExecutionMode
    Write-Host "  Modo detectado: $mode" -ForegroundColor Gray
    
    # Teste 2: Criar lock
    Set-JobLock -JobName "test-job"
    
    # Teste 3: Verificar lock
    $isRunning = Test-JobRunning -JobName "test-job"
    
    if ($isRunning) {
        Write-Host "  [OK] Lock criado e detectado" -ForegroundColor Green
    } else {
        $results.errors += "ProteÃ§Ã£o: lock nÃ£o detectado"
        Write-Host "  [ERRO] Lock nÃ£o foi detectado" -ForegroundColor Red
    }
    
    # Teste 4: Remover lock
    Remove-JobLock -JobName "test-job"
    
    $isRunning2 = Test-JobRunning -JobName "test-job"
    
    if (-not $isRunning2) {
        Write-Host "  [OK] Lock removido com sucesso" -ForegroundColor Green
        $results.protection = $true
    } else {
        $results.errors += "ProteÃ§Ã£o: lock nÃ£o foi removido"
        Write-Host "  [ERRO] Lock nÃ£o foi removido" -ForegroundColor Red
    }
} catch {
    $results.errors += "ProteÃ§Ã£o: $_"
    Write-Host "  [ERRO] $($_)" -ForegroundColor Red
}

# ============================================================================
# RESUMO FINAL
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMO DOS TESTES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$total = 4
$passed = 0

if ($results.dashboard) { 
    Write-Host "[OK] Dashboard Elite" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Dashboard Elite" -ForegroundColor Red
}

if ($results.telegram) { 
    Write-Host "[OK] Telegram" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Telegram" -ForegroundColor Red
}

if ($results.risk_manager) { 
    Write-Host "[OK] Risk Manager" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Risk Manager" -ForegroundColor Red
}

if ($results.protection) { 
    Write-Host "[OK] ProteÃ§Ã£o Anti-DuplicaÃ§Ã£o" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] ProteÃ§Ã£o Anti-DuplicaÃ§Ã£o" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESULTADO: $passed/$total testes passaram" -ForegroundColor $(if($passed -eq $total){"Green"}else{"Yellow"})
Write-Host "========================================`n" -ForegroundColor Cyan

if ($results.errors.Count -gt 0) {
    Write-Host "ERROS ENCONTRADOS:" -ForegroundColor Red
    foreach ($err in $results.errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
}

if ($passed -eq $total) {
    Write-Host "`nTODOS OS SISTEMAS OPERACIONAIS!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nALGUNS SISTEMAS FALHARAM" -ForegroundColor Yellow
    exit 1
}
