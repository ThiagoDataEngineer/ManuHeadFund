# ORGANIZE_PROJECT.ps1
# Organizar projeto - mover arquivos para estrutura limpa
# 2026-05-24

Write-Host "=== ORGANIZANDO PROJETO ===" -ForegroundColor Cyan
Write-Host ""

# Criar estrutura de pastas
$folders = @(
    "docs\archive",
    "docs\guides",
    "docs\status",
    "docs\current"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "[OK] Criado: $folder" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== MOVENDO ARQUIVOS ===" -ForegroundColor Cyan
Write-Host ""

# Guias importantes (docs\guides)
$guideFiles = @(
    "QUICK_START_VALIDACAO.md",
    "TASK_OCULTA_GUIA.md",
    "TELEGRAM_SETUP_GUIDE.md",
    "SETUP_RAPIDO_GITHUB.md"
)

# Status/Resumos recentes (docs\current)
$statusFiles = @(
    "RESUMO_VALIDACAO_COMPLETO_2026_05_24.md",
    "VALIDACAO_POS_EXECUCAO_2026_05_24.md",
    "ORDER_VALIDATION_SYSTEM_COMPLETE.md",
    "RESUMO_FINAL_2026_05_24.md",
    "EXECUCAO_TRAILING_STOP_2026_05_24.md",
    "TRAILING_STOP_INTELLIGENT_COMPLETE.md",
    "NEAR_EXECUTADO_2026_05_24.md",
    "NEAR_LONG_SETUP.md",
    "RESUMO_TRAILING_STOP_2026_05_24.md"
)

# Arquivos antigos (docs\archive)
$archivePatterns = @(
    "*2026_05_23*.md",
    "ANALISE_*.md",
    "AVALIACAO_*.md",
    "BUGFIX_*.md",
    "CANCEL_ORDER_*.md",
    "COINEX_API_*.md",
    "COMPLETO_*.md",
    "CONFIGURAR_*.md",
    "CORRECAO_*.md",
    "CRON_*.md",
    "DASHBOARD_*_COMPLETE*.md",
    "DIAGNOSTICO_*.md",
    "ELITE_*.md",
    "ENTREGA_*.md",
    "GEM_SCAN_*.md",
    "GITHUB_ACTIONS_*.md",
    "IMPLEMENTATION_*.md",
    "INTEGRATION_*.md",
    "MODO_*.md",
    "POR_QUE_*.md",
    "POSITION_MANAGEMENT_*.md",
    "PREVISAO_*.md",
    "PROTECAO_*.md",
    "PROXIMOS_PASSOS_*.md",
    "PUSH_TO_*.md",
    "RATE_LIMIT_*.md",
    "README_VOLTE_*.md",
    "RENAME_*.md",
    "RESUMO_*_2026_05_23.md",
    "RISK_*.md",
    "SISTEMA_*.md",
    "STATUS_*_2026_05_23*.md",
    "TDD_*.md",
    "TELEGRAM_*_2026_05_23.md",
    "TESTE_*.md",
    "VALIDACAO_*_2026_05_23.md",
    "VERIFICAR_*.md",
    "WHALE_*.md"
)

# Mover guias
Write-Host "Movendo guias..." -ForegroundColor Yellow
foreach ($file in $guideFiles) {
    if (Test-Path $file) {
        Move-Item -Path $file -Destination "docs\guides\" -Force
        Write-Host "  [OK] $file -> docs\guides\" -ForegroundColor Green
    }
}

# Mover status atuais
Write-Host ""
Write-Host "Movendo status atuais..." -ForegroundColor Yellow
foreach ($file in $statusFiles) {
    if (Test-Path $file) {
        Move-Item -Path $file -Destination "docs\current\" -Force
        Write-Host "  [OK] $file -> docs\current\" -ForegroundColor Green
    }
}

# Mover arquivos antigos para archive
Write-Host ""
Write-Host "Movendo arquivos antigos para archive..." -ForegroundColor Yellow
$movedCount = 0
foreach ($pattern in $archivePatterns) {
    $files = Get-ChildItem -Path . -Filter $pattern -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($statusFiles -contains $file.Name) {
            continue
        }
        Move-Item -Path $file.FullName -Destination "docs\archive\" -Force
        Write-Host "  [OK] $($file.Name) -> docs\archive\" -ForegroundColor Green
        $movedCount++
    }
}

Write-Host ""
Write-Host "Movidos $movedCount arquivos para archive" -ForegroundColor Cyan

# Mover scripts de execucao antigos
Write-Host ""
Write-Host "Movendo scripts antigos..." -ForegroundColor Yellow
$oldScripts = @(
    "EXECUTE_UNI_LONG.ps1",
    "FIND_OPPORTUNITY.ps1",
    "SCAN_OPORTUNIDADES.ps1",
    "MOVE_BNB_STOP_TO_BREAKEVEN.ps1",
    "TEST_TRAILING_STOP_DRY_RUN.ps1",
    "ANALISE_PROFUNDA_POSICOES.ps1",
    "fix_risk_manager.py"
)

foreach ($script in $oldScripts) {
    if (Test-Path $script) {
        Move-Item -Path $script -Destination "docs\archive\" -Force
        Write-Host "  [OK] $script -> docs\archive\" -ForegroundColor Green
    }
}

# Mover CSVs antigos
Write-Host ""
Write-Host "Movendo CSVs antigos..." -ForegroundColor Yellow
$csvFiles = Get-ChildItem -Path . -Filter "*.csv" -File -ErrorAction SilentlyContinue
foreach ($csv in $csvFiles) {
    Move-Item -Path $csv.FullName -Destination "docs\archive\" -Force
    Write-Host "  [OK] $($csv.Name) -> docs\archive\" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== LIMPEZA CONCLUIDA ===" -ForegroundColor Green
Write-Host ""
Write-Host "Estrutura organizada:" -ForegroundColor Cyan
Write-Host "  [ROOT] Scripts principais (DASHBOARD.ps1, PROTECT_NEAR_NOW.ps1, etc.)" -ForegroundColor White
Write-Host "  [docs\current] Documentacao atual (2026-05-24)" -ForegroundColor White
Write-Host "  [docs\guides] Guias de uso" -ForegroundColor White
Write-Host "  [docs\archive] Arquivos antigos (2026-05-23 e anteriores)" -ForegroundColor White
Write-Host ""
