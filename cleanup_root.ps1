# cleanup_root.ps1 -- Remove arquivos temporários da raiz
# Seguro: apenas remove documentação/dados temporários, nenhum código

param(
    [switch]$DryRun = $true,  # Por padrão, apenas mostra o que seria removido
    [switch]$Force = $false   # Remover sem confirmação
)

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Lista de arquivos a remover (relatórios temporários)
$filesToRemove = @(
    # 20260529 (43 arquivos)
    "ANALYSIS_THRESHOLDS_20260529.md",
    "CHANGES_2026_05_29.md",
    "CHANGES_2026_05_29_FQS_AUDIT.md",
    "CONTEXT_TRANSFER_SESSION_20260529.md",
    "DASHBOARD_ANALYSIS_20260529.txt",
    "EXAMPLES_BEFORE_AFTER_20260529.md",
    "FINAL_CONSOLIDATED_REPORT_20260529.md",
    "FINAL_EXECUTION_REPORT_20260529.md",
    "FINAL_REPORT_COINGECKO_ENRICH_20260529.md",
    "FINAL_SUMMARY_20260529.txt",
    "FQS_COINGECKO_ENRICH_PLAN_20260529.md",
    "FQS_REGISTRY_ACTION_PLAN_20260529.md",
    "FQS_REGISTRY_AUDIT_20260529.md",
    "FQS_REGISTRY_DOCUMENTATION_INDEX.md",
    "FQS_REGISTRY_EXECUTIVE_SUMMARY.txt",
    "FQS_REGISTRY_VALIDATION_20260529_140623.json",
    "IMPLEMENTATION_GUIDE_20260529.md",
    "IMPLEMENTATION_MUDANCAS_1_2_20260529.md",
    "INDEX_ANALYSIS_20260529.md",
    "INDEX_COINGECKO_PROJECT_20260529.md",
    "INTEGRATION_TEST_REPORT_20260529.md",
    "NEW_DOCUMENTATION_20260529.md",
    "PROJECT_FINAL_SUMMARY_20260529.txt",
    "PROJECT_STATUS_FINAL_20260529.md",
    "SUMMARY_FINDINGS_20260529.md",
    "TDD_COINGECKO_ENRICH_20260529.md",
    "TDD_COINGECKO_ENRICH_COMPLETE_20260529.md",
    "TDD_COINGECKO_ENRICH_REFACTOR_20260529.md",
    "TDD_SUMMARY_20260529.txt",
    "TIER_D_ENRICH_EVALUATION_20260529.md",
    "TOTAL_DELIVERABLES_20260529.md",
    "VERIFICATION_CHECKLIST_20260529.md",
    "coingecko_enrich_complete_20260529.json",
    "coingecko_enrich_integration_test_20260529.json",
    "coingecko_enrich_real_20260529.json",
    "coingecko_ids_validation_20260529.json",
    "fqs_enriched_data_real_20260529.json",
    "fqs_enriched_data_real_v3_20260529.json",
    "COMMIT_MESSAGE_20260529.txt",
    "coingecko_enrich_retry_20260529.log",
    
    # 20260528
    "CHANGES_2026_05_28.md",
    
    # 20260527
    "CHANGES_2026_05_27.md",
    
    # 20260526
    "CHANGES_2026_05_26.md",
    
    # Outros antigos
    "IMPLICACOES_SISTEMICAS.md",
    "PROJECT_COMPLETION_SUMMARY.md"
)

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                         CLEANUP ROOT - DRY RUN MODE                           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "🔍 DRY RUN MODE - Nenhum arquivo será removido" -ForegroundColor Yellow
    Write-Host ""
}

$found = 0
$notFound = 0
$totalSize = 0

foreach ($file in $filesToRemove) {
    $path = Join-Path $projectRoot $file
    if (Test-Path $path) {
        $item = Get-Item $path
        $size = [math]::Round($item.Length / 1KB, 1)
        $totalSize += $item.Length
        Write-Host "  ✓ $file ($size KB)" -ForegroundColor Green
        $found++
        
        if (-not $DryRun) {
            Remove-Item $path -Force -ErrorAction SilentlyContinue
            Write-Host "    → Removido" -ForegroundColor DarkGreen
        }
    } else {
        Write-Host "  ✗ $file (não encontrado)" -ForegroundColor DarkGray
        $notFound++
    }
}

Write-Host ""
Write-Host "📊 RESUMO" -ForegroundColor Cyan
Write-Host "  Arquivos encontrados: $found"
Write-Host "  Arquivos não encontrados: $notFound"
Write-Host "  Tamanho total: $([math]::Round($totalSize / 1KB, 1)) KB"
Write-Host ""

if ($DryRun) {
    Write-Host "✅ Para executar a limpeza, use:" -ForegroundColor Yellow
    Write-Host "   .\cleanup_root.ps1 -DryRun:`$false" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "✅ Limpeza concluída!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📝 Próximo passo: fazer commit" -ForegroundColor Yellow
    Write-Host "   git add -A" -ForegroundColor Cyan
    Write-Host "   git commit -m 'Cleanup: remove temporary reports from 20260526-20260529'" -ForegroundColor Cyan
    Write-Host ""
}
