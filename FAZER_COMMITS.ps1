# FAZER_COMMITS.ps1
# Script para fazer commits organizados da migração

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   COMMITS ORGANIZADOS" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

# ============================================================================
# COMMIT 1: Core - GitHub Actions e Scripts Cross-Platform
# ============================================================================

Write-Host "COMMIT 1: Core System..." -ForegroundColor Yellow

git add .gitignore
git add .github/workflows/trading-pipeline.yml
git add scripts/short_scanner.ps1
git add scripts/trailing_stop_monitor.ps1
git add scripts/position_risk_cron.ps1
git add scripts/collect_dashboard_data.ps1
git add agents/lib_cross_platform.ps1

git commit -m "feat: Sistema 100% na nuvem com GitHub Actions

- Refatorado short_scanner.ps1 para cross-platform
- Workflow completo com 6 jobs (trailing stop, risk, dashboard, deploy, short scanner, health)
- Deploy automatico para GitHub Pages
- Scripts funcionam em Windows e Linux
- Atualização a cada 5 minutos
- Zero dependencia da maquina local"

Write-Host "[OK] Commit 1 feito`n" -ForegroundColor Green

# ============================================================================
# COMMIT 2: Scripts de Controle
# ============================================================================

Write-Host "COMMIT 2: Scripts de Controle..." -ForegroundColor Yellow

git add DESABILITAR_TASKS_LOCAIS.ps1
git add REABILITAR_TASKS_LOCAIS.ps1
git add STATUS_TASKS.ps1

git commit -m "feat: Scripts de controle para tasks locais

- DESABILITAR_TASKS_LOCAIS.ps1: Desabilita tasks do Windows
- REABILITAR_TASKS_LOCAIS.ps1: Reabilita tasks se necessario
- STATUS_TASKS.ps1: Mostra status atual das tasks
- Evita conflitos entre Windows e GitHub Actions"

Write-Host "[OK] Commit 2 feito`n" -ForegroundColor Green

# ============================================================================
# COMMIT 3: Documentação Principal
# ============================================================================

Write-Host "COMMIT 3: Documentacao Principal..." -ForegroundColor Yellow

git add README_SISTEMA_COMPLETO.md
git add MIGRACAO_COMPLETA_GITHUB_ACTIONS.md
git add CONFIGURAR_GITHUB_PAGES.md
git add COMO_ACESSAR_DASHBOARD.md

git commit -m "docs: Documentacao completa do sistema na nuvem

- README_SISTEMA_COMPLETO.md: Guia principal
- MIGRACAO_COMPLETA_GITHUB_ACTIONS.md: Processo de migracao
- CONFIGURAR_GITHUB_PAGES.md: Setup GitHub Pages
- COMO_ACESSAR_DASHBOARD.md: Opcoes de acesso ao dashboard"

Write-Host "[OK] Commit 3 feito`n" -ForegroundColor Green

# ============================================================================
# COMMIT 4: Documentação Técnica
# ============================================================================

Write-Host "COMMIT 4: Documentacao Tecnica..." -ForegroundColor Yellow

git add COMPARACAO_WINDOWS_VS_GITHUB_ACTIONS.md
git add ANALISE_CONFLITOS_WINDOWS_GITHUB.md
git add AVALIACAO_FUNCIONAMENTO_COMPLETA.md
git add ANALISE_PROFUNDA_24H_2026_05_24.md
git add SISTEMA_CROSS_PLATFORM_COMPLETO.md
git add AVALIACAO_FINAL_COMPLETA.md

git commit -m "docs: Documentacao tecnica e analises

- Comparacao Windows vs GitHub Actions
- Analise de conflitos e solucoes
- Avaliacao completa de funcionamento
- Analise profunda do sistema
- Arquitetura cross-platform"

Write-Host "[OK] Commit 4 feito`n" -ForegroundColor Green

# ============================================================================
# COMMIT 5: Dashboard (apenas index.html)
# ============================================================================

Write-Host "COMMIT 5: Dashboard..." -ForegroundColor Yellow

git add dashboard/index.html

git commit -m "feat: Dashboard moderno e responsivo

- Design moderno com gradientes
- Grid responsivo
- Auto-refresh a cada 5 minutos
- Metricas: Posicoes, PNL, PNL%, Margin
- Cores dinamicas (verde/vermelho)
- Mobile-friendly"

Write-Host "[OK] Commit 5 feito`n" -ForegroundColor Green

# ============================================================================
# RESUMO
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   COMMITS CONCLUIDOS!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Total de commits: " -NoNewline
Write-Host "5" -ForegroundColor Green

Write-Host "`nProximo passo:" -ForegroundColor Yellow
Write-Host "  git push`n" -ForegroundColor Cyan

Write-Host "Depois:" -ForegroundColor Yellow
Write-Host "  1. Habilitar GitHub Pages" -ForegroundColor Gray
Write-Host "  2. Acessar: https://thiagodataengineer.github.io/ManuHeadFund/`n" -ForegroundColor Gray
