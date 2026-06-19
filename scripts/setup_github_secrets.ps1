#!/usr/bin/env pwsh
# setup_github_secrets.ps1
# Configura GitHub Secrets automaticamente (credenciais de config.local.ps1)
# Requer: GitHub CLI (gh) instalado e autenticado

param(
    [string]$Owner = "ThiagoDataEngineer",
    [string]$Repo = "ManuHeadFund"
)

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  CONFIGURANDO GITHUB SECRETS AUTOMATICAMENTE              ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# STEP 1: Carregar credenciais
# ───────────────────────────────────────────────────────────────────────
Write-Host "[STEP 1] Carregando credenciais..." -ForegroundColor Yellow

$configPath = "agents/config.local.ps1"
if (-not (Test-Path $configPath)) {
    Write-Host "  ✗ Arquivo não encontrado: $configPath" -ForegroundColor Red
    exit 1
}

try {
    . $configPath
    $SUPABASE_URL = $env:SUPABASE_URL
    $SUPABASE_SERVICE_KEY = $env:SUPABASE_SERVICE_KEY

    if (-not $SUPABASE_URL -or -not $SUPABASE_SERVICE_KEY) {
        Write-Host "  ✗ Credenciais vazias" -ForegroundColor Red
        exit 1
    }

    Write-Host "  ✓ SUPABASE_URL: $SUPABASE_URL" -ForegroundColor Green
    Write-Host "  ✓ SUPABASE_SERVICE_KEY: $($SUPABASE_SERVICE_KEY.Substring(0,50))..." -ForegroundColor Green
} catch {
    Write-Host "  ✗ Erro ao carregar config: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# STEP 2: Verificar GitHub CLI
# ───────────────────────────────────────────────────────────────────────
Write-Host "[STEP 2] Verificando GitHub CLI..." -ForegroundColor Yellow

$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCmd) {
    Write-Host "  ✗ GitHub CLI (gh) não encontrado" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Opção 1: Instalar GitHub CLI" -ForegroundColor Yellow
    Write-Host "    https://cli.github.com/" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Opção 2: Usar manual setup" -ForegroundColor Yellow
    Write-Host "    Veja: SETUP_GITHUB_SECRETS.md" -ForegroundColor Gray
    exit 1
}

Write-Host "  ✓ GitHub CLI encontrado: $($ghCmd.Source)" -ForegroundColor Green
Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# STEP 3: Verificar autenticação
# ───────────────────────────────────────────────────────────────────────
Write-Host "[STEP 3] Verificando autenticação..." -ForegroundColor Yellow

try {
    $status = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ✗ Não autenticado no GitHub" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Execute: gh auth login" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "  ✓ Autenticado" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Erro ao verificar autenticação: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# STEP 4: Adicionar secrets
# ───────────────────────────────────────────────────────────────────────
Write-Host "[STEP 4] Adicionando secrets..." -ForegroundColor Yellow

$fullRepo = "$Owner/$Repo"

# SUPABASE_URL
Write-Host "  Adicionando SUPABASE_URL..." -ForegroundColor Cyan
try {
    & gh secret set SUPABASE_URL -R $fullRepo --body $SUPABASE_URL
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ SUPABASE_URL adicionado" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Falha ao adicionar SUPABASE_URL" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "    ✗ Erro: $_" -ForegroundColor Red
    exit 1
}

# SUPABASE_SERVICE_KEY
Write-Host "  Adicionando SUPABASE_SERVICE_KEY..." -ForegroundColor Cyan
try {
    & gh secret set SUPABASE_SERVICE_KEY -R $fullRepo --body $SUPABASE_SERVICE_KEY
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    ✓ SUPABASE_SERVICE_KEY adicionado" -ForegroundColor Green
    } else {
        Write-Host "    ✗ Falha ao adicionar SUPABASE_SERVICE_KEY" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "    ✗ Erro: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# STEP 5: Verificar secrets adicionados
# ───────────────────────────────────────────────────────────────────────
Write-Host "[STEP 5] Verificando secrets..." -ForegroundColor Yellow

try {
    $secrets = & gh secret list -R $fullRepo 2>&1
    Write-Host $secrets -ForegroundColor Gray

    if ($secrets -match "SUPABASE_URL" -and $secrets -match "SUPABASE_SERVICE_KEY") {
        Write-Host ""
        Write-Host "  ✓ Todos os secrets adicionados com sucesso" -ForegroundColor Green
    } else {
        Write-Host "  ⚠ Nem todos os secrets estão visíveis" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ⚠ Não conseguiu listar secrets: $_" -ForegroundColor Yellow
}

Write-Host ""

# ───────────────────────────────────────────────────────────────────────
# SUMMARY
# ───────────────────────────────────────────────────────────────────────
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  ✓ GITHUB SECRETS CONFIGURADOS COM SUCESSO               ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Status:" -ForegroundColor Green
Write-Host "  ✓ SUPABASE_URL: $SUPABASE_URL" -ForegroundColor Gray
Write-Host "  ✓ SUPABASE_SERVICE_KEY: Configurado" -ForegroundColor Gray
Write-Host ""

Write-Host "Próximo passo:" -ForegroundColor Yellow
Write-Host "  GitHub Actions ativará automaticamente" -ForegroundColor Gray
Write-Host "  Acesse: https://github.com/$fullRepo/actions" -ForegroundColor Gray
Write-Host "  Workflow: Hourly Auto-Calibration" -ForegroundColor Gray
Write-Host "  Cron: 0 * * * * (toda hora)" -ForegroundColor Gray
Write-Host ""

Write-Host "Sistema rodando 24/7 em cloud (sem máquina local)." -ForegroundColor Green
Write-Host ""

exit 0
