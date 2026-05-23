# analyze_performance.ps1 - Script de Analise de Performance
# Rodar: .\scripts\analyze_performance.ps1
# Output: Console + arquivo JSON

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_performance_analyzer.ps1"

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "ANALISE DE PERFORMANCE" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    # Gerar relatorio completo
    $report = Get-ComprehensivePerformanceReport -Limit 100
    
    if (-not $report.success) {
        Write-Host "ERRO: $($report.error)" -ForegroundColor Red
        exit 1
    }
    
    # Exibir metricas basicas
    Write-Host "=== METRICAS BASICAS ===" -ForegroundColor Yellow
    Write-Host "Trades Analisados: $($report.trades_analyzed)" -ForegroundColor White
    Write-Host "PnL Total: `$$($report.total_pnl)" -ForegroundColor $(if($report.total_pnl -gt 0){'Green'}else{'Red'})
    Write-Host "Wins: $($report.wins) | Losses: $($report.losses)" -ForegroundColor White
    Write-Host "Win Rate: $($report.win_rate)%" -ForegroundColor White
    
    # Exibir metricas avancadas
    Write-Host "`n=== METRICAS AVANCADAS ===" -ForegroundColor Yellow
    Write-Host "Sharpe Ratio: $($report.sharpe_ratio)" -ForegroundColor White
    Write-Host "Avg Return: `$$($report.avg_return)" -ForegroundColor White
    Write-Host "Std Dev: `$$($report.std_dev)" -ForegroundColor White
    Write-Host "Max Drawdown: $($report.max_drawdown_pct)% (`$$($report.max_drawdown_usd))" -ForegroundColor Red
    
    # Exibir streaks
    Write-Host "`n=== STREAKS ===" -ForegroundColor Yellow
    Write-Host "Max Win Streak: $($report.max_win_streak)" -ForegroundColor Green
    Write-Host "Max Loss Streak: $($report.max_loss_streak)" -ForegroundColor Red
    Write-Host "Current Streak: $($report.current_streak) ($($report.current_streak_type))" -ForegroundColor White
    
    # Exibir top 5 markets
    Write-Host "`n=== TOP 5 MARKETS ===" -ForegroundColor Yellow
    foreach ($m in $report.by_market | Select-Object -First 5) {
        $color = if ($m.total_pnl -gt 0) { 'Green' } else { 'Red' }
        Write-Host "$($m.market): $($m.trades) trades, $($m.win_rate)% WR, `$$($m.total_pnl) PnL" -ForegroundColor $color
    }
    
    # Exibir melhores horarios
    Write-Host "`n=== MELHORES HORARIOS ===" -ForegroundColor Yellow
    foreach ($h in $report.by_hour | Select-Object -First 5) {
        $color = if ($h.total_pnl -gt 0) { 'Green' } else { 'Red' }
        Write-Host "$($h.hour):00h: $($h.trades) trades, $($h.win_rate)% WR, `$$($h.total_pnl) PnL" -ForegroundColor $color
    }
    
    # Salvar relatorio em JSON
    $outputDir = Join-Path $PSScriptRoot "..\reports"
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $outputDir "performance_report_$timestamp.json"
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath -Encoding UTF8
    
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Relatorio salvo: $outputPath" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    
} catch {
    Write-Host "`nERRO CRITICO: $_" -ForegroundColor Red
    exit 1
}
