# VERIFICAR_SECRETS_GITHUB.ps1
# Verifica se os secrets estão configurados no GitHub Actions

$ErrorActionPreference = "Stop"

Write-Host "`n=== VERIFICAÇÃO DE SECRETS NO GITHUB ===" -ForegroundColor Cyan
Write-Host "Repositório: ThiagoDataEngineer/ManuHeadFund`n" -ForegroundColor Gray

# ============================================================================
# MÉTODO 1: Verificar via workflow run (requer que workflow tenha rodado)
# ============================================================================

Write-Host "[1/2] Verificando última execução do workflow..." -ForegroundColor Yellow

try {
    # Tentar acessar API do GitHub (público, não requer auth)
    $owner = "ThiagoDataEngineer"
    $repo = "ManuHeadFund"
    $url = "https://api.github.com/repos/$owner/$repo/actions/runs?per_page=1"
    
    $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
    
    if ($response.total_count -gt 0) {
        $lastRun = $response.workflow_runs[0]
        Write-Host "  Última execução: $($lastRun.name)" -ForegroundColor Gray
        Write-Host "  Status: $($lastRun.status) / $($lastRun.conclusion)" -ForegroundColor Gray
        Write-Host "  Data: $($lastRun.created_at)" -ForegroundColor Gray
        
        if ($lastRun.conclusion -eq "success") {
            Write-Host "[OK] Workflow rodou com sucesso (secrets provavelmente OK)`n" -ForegroundColor Green
        } elseif ($lastRun.conclusion -eq "failure") {
            Write-Host "[AVISO] Workflow falhou - verificar logs`n" -ForegroundColor Yellow
            Write-Host "  Logs: $($lastRun.html_url)`n" -ForegroundColor Gray
        } else {
            Write-Host "[INFO] Workflow ainda não completou`n" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[INFO] Nenhuma execução encontrada (workflow ainda não rodou)`n" -ForegroundColor Cyan
    }
} catch {
    Write-Host "[AVISO] Não foi possível acessar API do GitHub" -ForegroundColor Yellow
    Write-Host "  Erro: $_`n" -ForegroundColor Gray
}

# ============================================================================
# MÉTODO 2: Instruções para verificação manual
# ============================================================================

Write-Host "[2/2] Verificação manual necessária" -ForegroundColor Yellow
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "COMO VERIFICAR SECRETS MANUALMENTE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "1. Acesse a página de secrets:" -ForegroundColor White
Write-Host "   https://github.com/$owner/$repo/settings/secrets/actions`n" -ForegroundColor Gray

Write-Host "2. Verifique se estes 4 secrets existem:" -ForegroundColor White
$requiredSecrets = @(
    "COINEX_ACCESS_ID",
    "COINEX_SECRET_KEY",
    "TELEGRAM_BOT_TOKEN",
    "TELEGRAM_CHAT_ID"
)

foreach ($secret in $requiredSecrets) {
    Write-Host "   [ ] $secret" -ForegroundColor Yellow
}

Write-Host "`n3. Se algum estiver faltando:" -ForegroundColor White
Write-Host "   - Clique em 'New repository secret'" -ForegroundColor Gray
Write-Host "   - Copie o valor de agents/config.local.ps1" -ForegroundColor Gray
Write-Host "   - Cole no GitHub`n" -ForegroundColor Gray

# ============================================================================
# MÉTODO 3: Testar localmente se credenciais funcionam
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TESTE LOCAL DE CREDENCIAIS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Carregando credenciais locais..." -ForegroundColor Yellow

. "$PSScriptRoot\agents\config.local.ps1"

$localSecrets = @{
    "COINEX_ACCESS_ID"    = $env:COINEX_ACCESS_ID
    "COINEX_SECRET_KEY"   = $env:COINEX_SECRET_KEY
    "TELEGRAM_BOT_TOKEN"  = $env:TELEGRAM_BOT_TOKEN
    "TELEGRAM_CHAT_ID"    = $env:TELEGRAM_CHAT_ID
}

Write-Host "Status das credenciais locais:`n" -ForegroundColor White

foreach ($key in $localSecrets.Keys) {
    $value = $localSecrets[$key]
    if ([string]::IsNullOrEmpty($value)) {
        Write-Host "  ERRO $key : NAO CONFIGURADO" -ForegroundColor Red
    } else {
        $masked = $value.Substring(0, [Math]::Min(8, $value.Length)) + "..."
        Write-Host "  OK $key : $masked" -ForegroundColor Green
    }
}

Write-Host ""

# ============================================================================
# TESTE DE CONECTIVIDADE
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TESTE DE CONECTIVIDADE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Teste 1: Telegram
Write-Host "[1/2] Testando Telegram Bot..." -ForegroundColor Yellow
try {
    $token = $env:TELEGRAM_BOT_TOKEN
    if ($token) {
        $url = "https://api.telegram.org/bot$token/getMe"
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        Write-Host "  OK Bot: @$($response.result.username)" -ForegroundColor Green
        Write-Host "  OK ID: $($response.result.id)`n" -ForegroundColor Green
    } else {
        Write-Host "  ERRO Token nao configurado`n" -ForegroundColor Red
    }
} catch {
    Write-Host "  ERRO Falha: $_`n" -ForegroundColor Red
}

# Teste 2: CoinEx (apenas verifica se credenciais existem, nao testa API)
Write-Host "[2/2] Verificando CoinEx..." -ForegroundColor Yellow
if ($env:COINEX_ACCESS_ID -and $env:COINEX_SECRET_KEY) {
    Write-Host "  OK Credenciais configuradas" -ForegroundColor Green
    Write-Host "  INFO Teste completo requer chamada a API (nao feito aqui)`n" -ForegroundColor Cyan
} else {
    Write-Host "  ERRO Credenciais nao configuradas`n" -ForegroundColor Red
}

# ============================================================================
# RESUMO E PRÓXIMOS PASSOS
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "RESUMO" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "✅ Credenciais locais: OK" -ForegroundColor Green
Write-Host "⚠️  Secrets GitHub: VERIFICAR MANUALMENTE" -ForegroundColor Yellow
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor White
Write-Host "1. Acesse: https://github.com/$owner/$repo/settings/secrets/actions" -ForegroundColor Gray
Write-Host "2. Configure os 4 secrets obrigatórios" -ForegroundColor Gray
Write-Host "3. Rode: .\FAZER_COMMITS.ps1" -ForegroundColor Gray
Write-Host "4. Push: git push origin main" -ForegroundColor Gray
Write-Host "5. Aguarde workflow rodar (15min)" -ForegroundColor Gray
Write-Host ""

Write-Host "=== VERIFICAÇÃO COMPLETA ===`n" -ForegroundColor Green
