# test_github_actions_local.ps1 - Simula GitHub Actions localmente
# Testa se os scripts funcionam no ambiente GitHub Actions

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TESTE GITHUB ACTIONS (SIMULAÇÃO LOCAL)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$results = @{
    config_creation = $false
    risk_manager = $false
    dashboard = $false
    health_check = $false
    errors = @()
}

# ============================================================================
# SIMULAR AMBIENTE GITHUB ACTIONS
# ============================================================================

Write-Host "[SETUP] Simulando ambiente GitHub Actions..." -ForegroundColor Yellow

# Definir variável que GitHub Actions usa
$env:GITHUB_ACTIONS = "true"

# Criar diretório temporário para teste
$testDir = Join-Path $env:TEMP "github_actions_test"
if (Test-Path $testDir) {
    Remove-Item $testDir -Recurse -Force
}
New-Item -ItemType Directory -Path $testDir -Force | Out-Null

# Copiar arquivos necessários
Write-Host "  Copiando arquivos..." -ForegroundColor Gray
Copy-Item -Path ".\agents" -Destination $testDir -Recurse -Force
Copy-Item -Path ".\scripts" -Destination $testDir -Recurse -Force
Copy-Item -Path ".\config" -Destination $testDir -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item -Path ".\journal" -Destination $testDir -Recurse -Force -ErrorAction SilentlyContinue

Set-Location $testDir

Write-Host "[OK] Ambiente preparado`n" -ForegroundColor Green

# ============================================================================
# TESTE 1: Criar Config (como GitHub Actions faz)
# ============================================================================

Write-Host "[1/4] Testando criação de config..." -ForegroundColor Yellow

try {
    # Carregar credenciais reais
    . "$PSScriptRoot\..\agents\config.local.ps1"
    
    # Criar config no formato GitHub Actions
    $configContent = @"
# config.local.ps1 - GitHub Actions
`$env:COINEX_ACCESS_ID = "$($env:COINEX_ACCESS_ID)"
`$env:COINEX_SECRET_KEY = "$($env:COINEX_SECRET_KEY)"
`$env:TELEGRAM_BOT_TOKEN = "$($env:TELEGRAM_BOT_TOKEN)"
`$env:TELEGRAM_CHAT_ID = "$($env:TELEGRAM_CHAT_ID)"
"@
    
    New-Item -ItemType Directory -Path "agents" -Force | Out-Null
    $configContent | Out-File "agents/config.local.ps1" -Encoding UTF8 -Force
    
    # Verificar se config foi criado
    if (Test-Path "agents/config.local.ps1") {
        Write-Host "  [OK] Config criado" -ForegroundColor Green
        
        # Testar se config é válido
        . ".\agents\config.local.ps1"
        
        if ($env:COINEX_ACCESS_ID -and $env:TELEGRAM_BOT_TOKEN) {
            Write-Host "  [OK] Config válido (variáveis exportadas)" -ForegroundColor Green
            $results.config_creation = $true
        } else {
            throw "Config não exportou variáveis"
        }
    } else {
        throw "Config não foi criado"
    }
} catch {
    $results.errors += "Config: $_"
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# TESTE 2: Risk Manager
# ============================================================================

Write-Host "`n[2/4] Testando Risk Manager..." -ForegroundColor Yellow

try {
    # Verificar se config existe
    if (-not (Test-Path "agents/config.local.ps1")) {
        throw "Config não encontrado"
    }
    
    # Executar script
    & ./scripts/position_risk_cron.ps1
    
    Write-Host "  [OK] Risk Manager executado" -ForegroundColor Green
    $results.risk_manager = $true
} catch {
    $results.errors += "Risk Manager: $_"
    Write-Host "  [ERRO] $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# ============================================================================
# TESTE 3: Dashboard Generator
# ============================================================================

Write-Host "`n[3/4] Testando Dashboard Generator..." -ForegroundColor Yellow

try {
    # Verificar se config existe
    if (-not (Test-Path "agents/config.local.ps1")) {
        throw "Config não encontrado"
    }
    
    # Executar script
    & ./scripts/generate_dashboard_elite.ps1
    
    # Verificar se dashboard foi gerado
    if (Test-Path "dashboard/index.html") {
        Write-Host "  [OK] Dashboard gerado" -ForegroundColor Green
        $results.dashboard = $true
    } else {
        throw "Dashboard não foi gerado"
    }
} catch {
    $results.errors += "Dashboard: $_"
    Write-Host "  [ERRO] $_" -ForegroundColor Red
    Write-Host "  Stack: $($_.ScriptStackTrace)" -ForegroundColor Gray
}

# ============================================================================
# TESTE 4: Health Check
# ============================================================================

Write-Host "`n[4/4] Testando Health Check..." -ForegroundColor Yellow

try {
    # Verificar CoinEx API
    $coinexResponse = Invoke-RestMethod -Uri "https://api.coinex.com/v2/ping" -Method Get
    Write-Host "  [OK] CoinEx API: OK" -ForegroundColor Green
    
    # Verificar Telegram API
    $token = $env:TELEGRAM_BOT_TOKEN
    $telegramResponse = Invoke-RestMethod -Uri "https://api.telegram.org/bot$token/getMe" -Method Get
    Write-Host "  [OK] Telegram API: OK - Bot: $($telegramResponse.result.username)" -ForegroundColor Green
    
    $results.health_check = $true
} catch {
    $results.errors += "Health Check: $_"
    Write-Host "  [ERRO] $_" -ForegroundColor Red
}

# ============================================================================
# LIMPEZA
# ============================================================================

Write-Host "`n[CLEANUP] Limpando ambiente de teste..." -ForegroundColor Gray
Set-Location $PSScriptRoot\..
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue

# Remover variável de ambiente
Remove-Item Env:\GITHUB_ACTIONS -ErrorAction SilentlyContinue

# ============================================================================
# RESUMO
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESUMO DOS TESTES" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$total = 4
$passed = 0

if ($results.config_creation) { 
    Write-Host "[OK] Config Creation" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Config Creation" -ForegroundColor Red
}

if ($results.risk_manager) { 
    Write-Host "[OK] Risk Manager" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Risk Manager" -ForegroundColor Red
}

if ($results.dashboard) { 
    Write-Host "[OK] Dashboard Generator" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Dashboard Generator" -ForegroundColor Red
}

if ($results.health_check) { 
    Write-Host "[OK] Health Check" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FALHOU] Health Check" -ForegroundColor Red
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "RESULTADO: $passed/$total testes passaram" -ForegroundColor $(if($passed -eq $total){"Green"}else{"Yellow"})
Write-Host "========================================`n" -ForegroundColor Cyan

if ($results.errors.Count -gt 0) {
    Write-Host "ERROS ENCONTRADOS:" -ForegroundColor Red
    foreach ($err in $results.errors) {
        Write-Host "  - $err" -ForegroundColor Red
    }
    Write-Host ""
}

if ($passed -eq $total) {
    Write-Host "✅ GITHUB ACTIONS VAI FUNCIONAR!" -ForegroundColor Green
    Write-Host "Todos os testes passaram. O sistema está pronto." -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️ ALGUNS TESTES FALHARAM" -ForegroundColor Yellow
    Write-Host "Corrija os erros antes de confiar no GitHub Actions." -ForegroundColor Yellow
    exit 1
}
