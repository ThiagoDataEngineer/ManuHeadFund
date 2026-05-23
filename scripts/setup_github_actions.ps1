# setup_github_actions.ps1 - Preparar projeto para GitHub Actions
# Uso: .\scripts\setup_github_actions.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SETUP GITHUB ACTIONS - MANUHEADFUND  ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

# Verificar se git está instalado
try {
    $gitVersion = git --version
    Write-Host "`n✓ Git instalado: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "`n✗ Git não encontrado!" -ForegroundColor Red
    Write-Host "Instale: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Verificar se já é um repositório git
if (Test-Path ".git") {
    Write-Host "✓ Repositório git já inicializado" -ForegroundColor Green
} else {
    Write-Host "`n[1/5] Inicializando repositório git..." -ForegroundColor Yellow
    git init
    git branch -M main
    Write-Host "✓ Git inicializado" -ForegroundColor Green
}

# Criar .gitignore se não existir
if (-not (Test-Path ".gitignore")) {
    Write-Host "`n[2/5] Criando .gitignore..." -ForegroundColor Yellow
    
    $gitignore = @"
# Secrets e configs locais
agents/config.local.ps1
config/telegram.json
*.env
*.key

# Logs e cache
*.log
.cache/
journal/

# PowerShell
*.ps1xml

# Python
__pycache__/
*.pyc
.pytest_cache/

# Node
node_modules/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db

# Backups
*.bak
*.backup
"@
    
    $gitignore | Out-File -FilePath ".gitignore" -Encoding UTF8 -Force
    Write-Host "✓ .gitignore criado" -ForegroundColor Green
}

# Verificar se workflow existe
if (Test-Path ".github/workflows/trading-pipeline.yml") {
    Write-Host "`n✓ Workflow GitHub Actions já existe" -ForegroundColor Green
} else {
    Write-Host "`n✗ Workflow não encontrado!" -ForegroundColor Red
    Write-Host "Execute primeiro: git pull origin main" -ForegroundColor Yellow
}

# Adicionar arquivos
Write-Host "`n[3/5] Adicionando arquivos ao git..." -ForegroundColor Yellow
git add .
Write-Host "✓ Arquivos adicionados" -ForegroundColor Green

# Commit
Write-Host "`n[4/5] Criando commit..." -ForegroundColor Yellow
try {
    git commit -m "Setup GitHub Actions - ManuHeadFund Trading System"
    Write-Host "✓ Commit criado" -ForegroundColor Green
} catch {
    Write-Host "! Nenhuma mudança para commitar" -ForegroundColor Yellow
}

# Instruções para push
Write-Host "`n[5/5] Próximos passos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Criar repositório no GitHub:" -ForegroundColor White
Write-Host "   https://github.com/new" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Conectar repositório:" -ForegroundColor White
Write-Host "   git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Fazer push:" -ForegroundColor White
Write-Host "   git push -u origin main" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Configurar Secrets no GitHub:" -ForegroundColor White
Write-Host "   Settings → Secrets and variables → Actions" -ForegroundColor Gray
Write-Host ""
Write-Host "   Adicionar 4 secrets:" -ForegroundColor Gray
Write-Host "   - COINEX_ACCESS_ID" -ForegroundColor Gray
Write-Host "   - COINEX_SECRET_KEY" -ForegroundColor Gray
Write-Host "   - TELEGRAM_BOT_TOKEN" -ForegroundColor Gray
Write-Host "   - TELEGRAM_CHAT_ID" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Ativar GitHub Actions:" -ForegroundColor White
Write-Host "   Actions → Enable workflows" -ForegroundColor Gray
Write-Host ""
Write-Host "6. Ativar GitHub Pages (opcional):" -ForegroundColor White
Write-Host "   Settings → Pages → Source: gh-pages" -ForegroundColor Gray
Write-Host ""

Write-Host "╔════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║         PREPARAÇÃO COMPLETA ✓          ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nDocumentação completa:" -ForegroundColor Cyan
Write-Host "  - SETUP_RAPIDO_GITHUB.md" -ForegroundColor Gray
Write-Host "  - GITHUB_ACTIONS_SETUP.md" -ForegroundColor Gray
Write-Host ""
