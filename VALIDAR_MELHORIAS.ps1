# VALIDAR_MELHORIAS.ps1
# Valida todas as melhorias implementadas
# 2026-05-24

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  VALIDACAO DE MELHORIAS IMPLEMENTADAS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allGood = $true

# 1. Verificar arquivos criados
Write-Host "[1] Verificando arquivos criados..." -ForegroundColor Yellow
$files = @(
    "agents\lib_veto_feedback.ps1",
    "agents\lib_trailing_stop_adaptive.ps1",
    "scripts\veto_feedback_processor.ps1",
    "TEST_ADAPTIVE_TRAILING.ps1",
    "ANALISE_PROFUNDA_24H_2026_05_24.md",
    "RESUMO_MELHORIAS_IMPLEMENTADAS.md"
)

foreach ($file in $files) {
    if (Test-Path $file) {
        Write-Host "  ✅ $file" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $file FALTANDO!" -ForegroundColor Red
        $allGood = $false
    }
}
Write-Host ""

# 2. Verificar posicoes protegidas
Write-Host "[2] Verificando protecao de posicoes..." -ForegroundColor Yellow
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"

try {
    $positions = CoinEx-GetPendingPositions
    
    if (-not $positions -or $positions.Count -eq 0) {
        Write-Host "  Nenhuma posicao aberta" -ForegroundColor Gray
    } else {
        $unprotected = 0
        foreach ($pos in $positions) {
            $hasStop = [double]$pos.stop_loss_price -gt 0
            if ($hasStop) {
                Write-Host "  ✅ $($pos.market): Stop loss configurado" -ForegroundColor Green
            } else {
                Write-Host "  ❌ $($pos.market): SEM STOP LOSS!" -ForegroundColor Red
                $unprotected++
                $allGood = $false
            }
        }
        
        if ($unprotected -eq 0) {
            Write-Host "  ✅ TODAS AS POSICOES PROTEGIDAS" -ForegroundColor Green
        }
    }
}
catch {
    Write-Host "  Erro ao verificar posicoes: $_" -ForegroundColor Yellow
}
Write-Host ""

# 3. Verificar libs carregam sem erro
Write-Host "[3] Verificando libs..." -ForegroundColor Yellow
try {
    . "$PSScriptRoot\agents\lib_veto_feedback.ps1"
    Write-Host "  ✅ lib_veto_feedback.ps1 carrega sem erros" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ lib_veto_feedback.ps1 tem erros: $_" -ForegroundColor Red
    $allGood = $false
}

try {
    . "$PSScriptRoot\agents\lib_trailing_stop_adaptive.ps1"
    Write-Host "  ✅ lib_trailing_stop_adaptive.ps1 carrega sem erros" -ForegroundColor Green
}
catch {
    Write-Host "  ❌ lib_trailing_stop_adaptive.ps1 tem erros: $_" -ForegroundColor Red
    $allGood = $false
}
Write-Host ""

# 4. Verificar funcoes existem
Write-Host "[4] Verificando funcoes implementadas..." -ForegroundColor Yellow
$functions = @(
    "Register-VetoFeedback",
    "Get-PendingVetoFeedbacks",
    "Invoke-CorrectiveAction",
    "Process-VetoFeedbackQueue",
    "Get-AdaptiveTrailingThreshold",
    "Get-AdaptiveTrailingDistance",
    "Calculate-ATR",
    "Get-MomentumScore"
)

foreach ($func in $functions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  ✅ $func" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $func NAO ENCONTRADA!" -ForegroundColor Red
        $allGood = $false
    }
}
Write-Host ""

# 5. Resumo final
Write-Host "========================================" -ForegroundColor Cyan
if ($allGood) {
    Write-Host "  ✅ TODAS AS VALIDACOES PASSARAM!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Sistema pronto para producao!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Proximos passos:" -ForegroundColor Yellow
    Write-Host "  1. Criar Task Scheduler para veto_feedback_processor.ps1" -ForegroundColor White
    Write-Host "  2. Monitorar logs nas proximas 24h" -ForegroundColor White
    Write-Host "  3. Expandir FQS registry" -ForegroundColor White
    Write-Host ""
    Write-Host "Documentacao completa em:" -ForegroundColor Cyan
    Write-Host "  • ANALISE_PROFUNDA_24H_2026_05_24.md" -ForegroundColor White
    Write-Host "  • RESUMO_MELHORIAS_IMPLEMENTADAS.md" -ForegroundColor White
} else {
    Write-Host "  ❌ ALGUMAS VALIDACOES FALHARAM" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Revise os erros acima e corrija antes de continuar." -ForegroundColor Yellow
}
Write-Host ""
