# configure_github_secrets_simple.ps1 - TDD: Configurar secrets via GitHub API
# RED: Script que falha sem token
# GREEN: Script que cria secrets com sucesso
# REFACTOR: Otimizar e validar

$ErrorActionPreference = "Stop"

Write-Host "`n=== TDD: CONFIGURAR GITHUB SECRETS ===" -ForegroundColor Cyan

# ============================================================================
# STEP 1: Carregar credenciais locais
# ============================================================================

Write-Host "[1/4] Carregando credenciais..." -ForegroundColor Yellow

. "$PSScriptRoot\..\agents\config.local.ps1"

$secrets = @{
    "COINEX_ACCESS_ID"    = $env:COINEX_ACCESS_ID
    "COINEX_SECRET_KEY"   = $env:COINEX_SECRET_KEY
    "TELEGRAM_BOT_TOKEN"  = $env:TELEGRAM_BOT_TOKEN
    "TELEGRAM_CHAT_ID"    = $env:TELEGRAM_CHAT_ID
}

Write-Host "  COINEX_ACCESS_ID: $($env:COINEX_ACCESS_ID)" -ForegroundColor Gray
Write-Host "  TELEGRAM_CHAT_ID: $($env:TELEGRAM_CHAT_ID)" -ForegroundColor Gray
Write-Host "[OK] Credenciais carregadas`n" -ForegroundColor Green

# ============================================================================
# STEP 2: Solicitar GitHub Token
# ============================================================================

Write-Host "[2/4] GitHub Personal Access Token" -ForegroundColor Yellow
Write-Host "  Crie em: https://github.com/settings/tokens/new" -ForegroundColor Gray
Write-Host "  Scopes: repo, workflow`n" -ForegroundColor Gray

$token = Read-Host "Cole seu token aqui"

if (-not $token) {
    Write-Host "[ERRO] Token não fornecido" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Token recebido`n" -ForegroundColor Green

# ============================================================================
# STEP 3: Testar acesso ao repositório
# ============================================================================

Write-Host "[3/4] Testando acesso ao repositório..." -ForegroundColor Yellow

$owner = "ThiagoDataEngineer"
$repo = "ManuHeadFund"
$headers = @{
    "Authorization" = "Bearer $token"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

try {
    $repoUrl = "https://api.github.com/repos/$owner/$repo"
    $repoInfo = Invoke-RestMethod -Uri $repoUrl -Headers $headers -Method Get
    Write-Host "  Repositório: $($repoInfo.full_name)" -ForegroundColor Gray
    Write-Host "  Privado: $($repoInfo.private)" -ForegroundColor Gray
    Write-Host "[OK] Acesso confirmado`n" -ForegroundColor Green
} catch {
    Write-Host "[ERRO] Falha ao acessar repositório: $_" -ForegroundColor Red
    Write-Host "Verifique se o token tem permissões corretas" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# STEP 4: Criar secrets (método simplificado via gh CLI simulation)
# ============================================================================

Write-Host "[4/4] Criando secrets..." -ForegroundColor Yellow
Write-Host "  NOTA: GitHub API requer criptografia com libsodium" -ForegroundColor Gray
Write-Host "  Alternativa: usar interface web do GitHub`n" -ForegroundColor Gray

# Mostrar instruções para configuração manual
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "CONFIGURAÇÃO MANUAL DOS SECRETS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Acesse: https://github.com/$owner/$repo/settings/secrets/actions`n" -ForegroundColor Yellow

$i = 1
foreach ($secretName in $secrets.Keys) {
    Write-Host "[$i/4] $secretName" -ForegroundColor Green
    Write-Host "  Name: $secretName" -ForegroundColor Gray
    Write-Host "  Value: $($secrets[$secretName])" -ForegroundColor White
    Write-Host ""
    $i++
}

Write-Host "========================================" -ForegroundColor Yellow
Write-Host "PRÓXIMOS PASSOS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "1. Copie cada secret acima" -ForegroundColor Gray
Write-Host "2. Cole no GitHub (link acima)" -ForegroundColor Gray
Write-Host "3. Habilite Actions: https://github.com/$owner/$repo/settings/actions" -ForegroundColor Gray
Write-Host "4. Aguarde primeira execução (15min)`n" -ForegroundColor Gray

# Abrir navegador automaticamente
Write-Host "Deseja abrir o GitHub no navegador? (S/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "S" -or $response -eq "s") {
    Start-Process "https://github.com/$owner/$repo/settings/secrets/actions"
    Write-Host "[OK] Navegador aberto" -ForegroundColor Green
}

Write-Host "`n=== CONFIGURAÇÃO PREPARADA ===" -ForegroundColor Green
