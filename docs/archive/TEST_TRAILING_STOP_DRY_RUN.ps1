# TEST_TRAILING_STOP_DRY_RUN.ps1
# Testar trailing stop inteligente SEM executar (dry run)
# 2026-05-24

# Carregar libs
. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_coinex_position_management.ps1"
. "$PSScriptRoot\agents\lib_trailing_stop_intelligent.ps1"

Write-Host "=== TESTE TRAILING STOP (DRY RUN) ===" -ForegroundColor Cyan
Write-Host "Este script NAO executa nenhuma modificacao real" -ForegroundColor Yellow
Write-Host ""

try {
    # Verificar credenciais
    if (-not $COINEX_ACCESS_ID -or -not $COINEX_SECRET_KEY) {
        Write-Host "ERROR: Credenciais nao configuradas" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Buscando posicoes abertas..." -ForegroundColor Cyan
    
    # Executar dry run
    $result = Update-AllTrailingStops -DryRun $true
    
    if (-not $result.success) {
        Write-Host "ERROR: $($result.error)" -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "=== RESUMO ===" -ForegroundColor Green
    Write-Host "Total positions: $($result.total_positions)"
    Write-Host "Would update: $($result.simulated)"
    Write-Host "No update needed: $($result.no_update)"
    Write-Host "Errors: $($result.errors)"
    Write-Host ""
    
    # Detalhes por posicao
    Write-Host "=== DETALHES POR POSICAO ===" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($posResult in $result.results) {
        Write-Host "Market: $($posResult.market)" -ForegroundColor Yellow
        
        if ($posResult.success) {
            if ($posResult.action -eq "simulated") {
                Write-Host "  Action: WOULD UPDATE" -ForegroundColor Green
                Write-Host "  Current Stop: `$$($posResult.old_stop)"
                Write-Host "  New Stop: `$$($posResult.new_stop)"
                Write-Host "  Trailing %: $($posResult.trailing_pct)%"
                Write-Host "  PNL: $($posResult.pnl_pct)%"
                Write-Host "  ATR %: $($posResult.atr_pct)%"
                if ($posResult.nearest_support) {
                    Write-Host "  Nearest Support: `$$($posResult.nearest_support)"
                }
                Write-Host "  Reason: $($posResult.reason)"
            }
            elseif ($posResult.action -eq "no_update") {
                Write-Host "  Action: NO UPDATE NEEDED" -ForegroundColor Gray
                Write-Host "  Current Stop: `$$($posResult.current_stop)"
                Write-Host "  PNL: $($posResult.pnl_pct)%"
                Write-Host "  Reason: $($posResult.reason)"
            }
        }
        else {
            Write-Host "  Action: ERROR" -ForegroundColor Red
            Write-Host "  Error: $($posResult.error)"
        }
        
        Write-Host ""
    }
    
    Write-Host "=== TESTE COMPLETO ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Para executar de verdade:" -ForegroundColor Yellow
    Write-Host "1. Revise os resultados acima"
    Write-Host "2. Execute: .\scripts\trailing_stop_monitor.ps1"
    Write-Host "3. Ou configure Task Scheduler: .\scripts\setup_trailing_stop_task.ps1"
}
catch {
    Write-Host ""
    Write-Host "=== ERRO CRITICO ===" -ForegroundColor Red
    Write-Host "$_"
    Write-Host $_.ScriptStackTrace
    exit 1
}
