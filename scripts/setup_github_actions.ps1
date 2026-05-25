# setup_github_actions.ps1 - Preparar projeto para GitHub Actions
# Uso: .\scripts\setup_github_actions.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "`nâ•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Cyan
Write-Host "â•‘   SETUP GITHUB ACTIONS - MANUHEADFUND  â•‘" -ForegroundColor Cyan
Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Cyan

# Verificar se git estÃ¡ instalado
try {
    $gitVersion = git --version
    Write-Host "`nâœ“ Git instalado: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "`nâœ— Git nÃ£o encontrado!" -ForegroundColor Red
    Write-Host "Instale: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Verificar se jÃ¡ Ã© um repositÃ³rio git
if (Test-Path ".git") {
    Write-Host "âœ“ RepositÃ³rio git jÃ¡ inicializado" -ForegroundColor Green
} else {
    Write-Host "`n[1/5] Inicializando repositÃ³rio git..." -ForegroundColor Yellow
    git init
    git branch -M main
    Write-Host "âœ“ Git inicializado" -ForegroundColor Green
}

# Criar .gitignore se nÃ£o existir
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
    Write-Host "âœ“ .gitignore criado" -ForegroundColor Green
}

# Verificar se workflow existe
if (Test-Path ".github/workflows/trading-pipeline.yml") {
    Write-Host "`nâœ“ Workflow GitHub Actions jÃ¡ existe" -ForegroundColor Green
} else {
    Write-Host "`nâœ— Workflow nÃ£o encontrado!" -ForegroundColor Red
    Write-Host "Execute primeiro: git pull origin main" -ForegroundColor Yellow
}

# Adicionar arquivos
Write-Host "`n[3/5] Adicionando arquivos ao git..." -ForegroundColor Yellow
git add .
Write-Host "âœ“ Arquivos adicionados" -ForegroundColor Green

# Commit
Write-Host "`n[4/5] Criando commit..." -ForegroundColor Yellow
try {
    git commit -m "Setup GitHub Actions - ManuHeadFund Trading System"
    Write-Host "âœ“ Commit criado" -ForegroundColor Green
} catch {
    Write-Host "! Nenhuma mudanÃ§a para commitar" -ForegroundColor Yellow
}

# InstruÃ§Ãµes para push
Write-Host "`n[5/5] PrÃ³ximos passos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Criar repositÃ³rio no GitHub:" -ForegroundColor White
Write-Host "   https://github.com/new" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Conectar repositÃ³rio:" -ForegroundColor White
Write-Host "   git remote add origin https://github.com/SEU_USUARIO/Coinex_AI_USER_API.git" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Fazer push:" -ForegroundColor White
Write-Host "   git push -u origin main" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Configurar Secrets no GitHub:" -ForegroundColor White
Write-Host "   Settings â†’ Secrets and variables â†’ Actions" -ForegroundColor Gray
Write-Host ""
Write-Host "   Adicionar 4 secrets:" -ForegroundColor Gray
Write-Host "   - COINEX_ACCESS_ID" -ForegroundColor Gray
Write-Host "   - COINEX_SECRET_KEY" -ForegroundColor Gray
Write-Host "   - TELEGRAM_BOT_TOKEN" -ForegroundColor Gray
Write-Host "   - TELEGRAM_CHAT_ID" -ForegroundColor Gray
Write-Host ""
Write-Host "5. Ativar GitHub Actions:" -ForegroundColor White
Write-Host "   Actions â†’ Enable workflows" -ForegroundColor Gray
Write-Host ""
Write-Host "6. Ativar GitHub Pages (opcional):" -ForegroundColor White
Write-Host "   Settings â†’ Pages â†’ Source: gh-pages" -ForegroundColor Gray
Write-Host ""

Write-Host "â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—" -ForegroundColor Green
Write-Host "â•‘         PREPARAÃ‡ÃƒO COMPLETA âœ“          â•‘" -ForegroundColor Green
Write-Host "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•" -ForegroundColor Green

Write-Host "`nDocumentaÃ§Ã£o completa:" -ForegroundColor Cyan
Write-Host "  - SETUP_RAPIDO_GITHUB.md" -ForegroundColor Gray
Write-Host "  - GITHUB_ACTIONS_SETUP.md" -ForegroundColor Gray
Write-Host ""
