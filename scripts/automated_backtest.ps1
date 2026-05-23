# automated_backtest.ps1 - Sistema de Backtesting Automatizado
# Integra com backtest/ existente e compara configuracoes
# Rodar: .\scripts\automated_backtest.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"

# ============================================================================
# Run-BacktestComparison - Compara performance antes/depois de ajustes
# ============================================================================

function Run-BacktestComparison {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigName,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$Parameters = @{}
    )
    
    Write-Host "`n=== BACKTEST: $ConfigName ===" -ForegroundColor Cyan
    
    try {
        # Verificar se Python esta disponivel
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            Write-Host "Python nao encontrado. Pulando backtest." -ForegroundColor Yellow
            return $null
        }
        
        # Verificar se arquivo de backtest existe
        $backtestScript = ".\backtest\backtest_runner.py"
        if (-not (Test-Path $backtestScript)) {
            Write-Host "Script de backtest nao encontrado: $backtestScript" -ForegroundColor Yellow
            return $null
        }
        
        # Executar backtest
        Write-Host "Executando backtest..." -ForegroundColor Yellow
        $output = & python $backtestScript 2>&1
        
        # Parsear resultados (simplificado)
        $result = [PSCustomObject]@{
            config_name = $ConfigName
            success = $LASTEXITCODE -eq 0
            output = $output -join "`n"
            timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        
        if ($result.success) {
            Write-Host "Backtest concluido com sucesso" -ForegroundColor Green
        } else {
            Write-Host "Backtest falhou" -ForegroundColor Red
        }
        
        return $result
        
    } catch {
        Write-Host "Erro ao executar backtest: $_" -ForegroundColor Red
        return $null
    }
}

# ============================================================================
# Compare-BacktestResults - Compara resultados de diferentes configuracoes
# ============================================================================

function Compare-BacktestResults {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results
    )
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "COMPARACAO DE RESULTADOS" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    foreach ($result in $Results) {
        if ($result) {
            Write-Host "Config: $($result.config_name)" -ForegroundColor White
            Write-Host "Status: $(if($result.success){'OK'}else{'FALHOU'})" -ForegroundColor $(if($result.success){'Green'}else{'Red'})
            Write-Host "Timestamp: $($result.timestamp)" -ForegroundColor Gray
            Write-Host ""
        }
    }
}

# ============================================================================
# Save-BacktestReport - Salva relatorio de backtest
# ============================================================================

function Save-BacktestReport {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Results
    )
    
    $reportDir = Join-Path $PSScriptRoot "..\reports\backtests"
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $reportDir "backtest_comparison_$timestamp.json"
    
    $report = [PSCustomObject]@{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        results = $Results
        summary = @{
            total_tests = $Results.Count
            successful = ($Results | Where-Object { $_.success }).Count
            failed = ($Results | Where-Object { -not $_.success }).Count
        }
    }
    
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-Host "Relatorio salvo: $reportPath" -ForegroundColor Green
    return $reportPath
}

# ============================================================================
# MAIN
# ============================================================================

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "SISTEMA DE BACKTESTING AUTOMATIZADO" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Configuracoes para testar
    $configs = @(
        @{ name = "Baseline"; params = @{ atr_mult = 2.0; min_profit = 2.0 } }
        @{ name = "Ajustado"; params = @{ atr_mult = 1.5; min_profit = 1.0 } }
    )
    
    $results = @()
    
    foreach ($config in $configs) {
        $result = Run-BacktestComparison -ConfigName $config.name -Parameters $config.params
        if ($result) {
            $results += $result
        }
    }
    
    # Comparar resultados
    if ($results.Count -gt 0) {
        Compare-BacktestResults -Results $results
        $reportPath = Save-BacktestReport -Results $results
        
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "BACKTEST COMPLETO" -ForegroundColor Green
        Write-Host "========================================`n" -ForegroundColor Cyan
    } else {
        Write-Host "`nNenhum backtest foi executado." -ForegroundColor Yellow
        Write-Host "Verifique se Python e os scripts de backtest estao disponiveis." -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "`nERRO CRITICO: $_" -ForegroundColor Red
    exit 1
}
