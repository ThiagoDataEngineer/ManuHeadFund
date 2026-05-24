# DASHBOARD.ps1
# Dashboard visual para monitorar sistema de trading
# 2026-05-24

. "$PSScriptRoot\agents\config.ps1"
. "$PSScriptRoot\agents\lib_coinex.ps1"
. "$PSScriptRoot\agents\lib_order_validation.ps1"

function Show-Header {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           COINEX TRADING SYSTEM - DASHBOARD                        ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Atualizado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host ""
}

function Show-Tasks {
    Write-Host "═══ TASKS AGENDADAS ═══" -ForegroundColor Yellow
    Write-Host ""
    
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" -or $_.TaskName -like "*Trading*" }
    
    if ($tasks.Count -eq 0) {
        Write-Host "  Nenhuma task encontrada" -ForegroundColor Gray
    } else {
        foreach ($task in $tasks) {
            $info = Get-ScheduledTaskInfo -TaskName $task.TaskName
            $status = $task.State
            $lastRun = $info.LastRunTime
            $nextRun = $info.NextRunTime
            $lastResult = $info.LastTaskResult
            
            $statusColor = switch ($status) {
                "Ready" { "Green" }
                "Running" { "Cyan" }
                "Disabled" { "Yellow" }
                default { "Red" }
            }
            
            $resultColor = if ($lastResult -eq 0) { "Green" } else { "Red" }
            $resultText = if ($lastResult -eq 0) { "OK" } else { "ERRO ($lastResult)" }
            
            Write-Host "  📋 $($task.TaskName)" -ForegroundColor White
            Write-Host "     Status: " -NoNewline -ForegroundColor Gray
            Write-Host $status -ForegroundColor $statusColor
            Write-Host "     Última execução: $lastRun" -ForegroundColor Gray
            Write-Host "     Próxima execução: $nextRun" -ForegroundColor Gray
            Write-Host "     Resultado: " -NoNewline -ForegroundColor Gray
            Write-Host $resultText -ForegroundColor $resultColor
            Write-Host ""
        }
    }
}

function Show-Positions {
    Write-Host "═══ POSIÇÕES ABERTAS ═══" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $positions = CoinEx-GetPendingPositions
        
        if (-not $positions -or $positions.Count -eq 0) {
            Write-Host "  Nenhuma posição aberta" -ForegroundColor Gray
            return
        }
        
        $totalPnl = 0
        
        foreach ($pos in $positions) {
            $market = $pos.market
            $side = $pos.side
            $entry = [double]$pos.avg_entry_price
            $current = [double]$pos.latest_price
            $pnl = [double]$pos.unrealized_pnl
            $pnlRate = [double]$pos.unrealized_pnl_rate
            $leverage = $pos.leverage
            $stopLoss = [double]$pos.stop_loss_price
            $takeProfit = [double]$pos.take_profit_price
            
            $totalPnl += $pnl
            
            $pnlColor = if ($pnl -gt 0) { "Green" } elseif ($pnl -lt 0) { "Red" } else { "Gray" }
            $sideIcon = if ($side -eq "long") { "📈" } else { "📉" }
            $stopIcon = if ($stopLoss -gt 0) { "✅" } else { "❌" }
            $tpIcon = if ($takeProfit -gt 0) { "✅" } else { "⚠️" }
            
            Write-Host "  $sideIcon $market ($leverage`x)" -ForegroundColor White
            Write-Host "     Entry: `$$entry | Current: `$$current" -ForegroundColor Gray
            Write-Host "     PNL: " -NoNewline -ForegroundColor Gray
            Write-Host "`$$([Math]::Round($pnl, 2)) ($([Math]::Round($pnlRate, 2))%)" -ForegroundColor $pnlColor
            Write-Host "     Stop Loss: $stopIcon " -NoNewline
            if ($stopLoss -gt 0) {
                Write-Host "`$$stopLoss" -ForegroundColor Green
            } else {
                Write-Host "NÃO CONFIGURADO" -ForegroundColor Red
            }
            Write-Host "     Take Profit: $tpIcon " -NoNewline
            if ($takeProfit -gt 0) {
                Write-Host "`$$takeProfit" -ForegroundColor Green
            } else {
                Write-Host "Não configurado" -ForegroundColor Yellow
            }
            Write-Host ""
        }
        
        Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray
        $totalColor = if ($totalPnl -gt 0) { "Green" } elseif ($totalPnl -lt 0) { "Red" } else { "Gray" }
        Write-Host "  PNL Total: " -NoNewline -ForegroundColor White
        Write-Host "`$$([Math]::Round($totalPnl, 2))" -ForegroundColor $totalColor
        Write-Host ""
    }
    catch {
        Write-Host "  ERRO ao buscar posições: $_" -ForegroundColor Red
        Write-Host ""
    }
}

function Show-Capital {
    Write-Host "═══ CAPITAL DISPONÍVEL ═══" -ForegroundColor Yellow
    Write-Host ""
    
    try {
        $futures = CoinEx-GetFuturesCapitalUSDT
        $spot = CoinEx-GetSpotCapitalUSDT
        $total = $futures + $spot
        
        Write-Host "  💰 Futures: `$$([Math]::Round($futures, 2)) USDT" -ForegroundColor Green
        Write-Host "  💰 Spot: `$$([Math]::Round($spot, 2)) USDT" -ForegroundColor Green
        Write-Host "  ─────────────────────────────────────" -ForegroundColor Gray
        Write-Host "  💰 Total: `$$([Math]::Round($total, 2)) USDT" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Host "  ERRO ao buscar capital: $_" -ForegroundColor Red
        Write-Host ""
    }
}

function Show-RecentLogs {
    param([int]$Lines = 10)
    
    Write-Host "═══ LOGS RECENTES (últimas $Lines linhas) ═══" -ForegroundColor Yellow
    Write-Host ""
    
    $logFile = "$PSScriptRoot\logs\trailing_stop_monitor.log"
    
    if (-not (Test-Path $logFile)) {
        Write-Host "  Nenhum log encontrado" -ForegroundColor Gray
        return
    }
    
    $logs = Get-Content $logFile -Tail $Lines -ErrorAction SilentlyContinue
    
    if (-not $logs) {
        Write-Host "  Log vazio" -ForegroundColor Gray
        return
    }
    
    foreach ($line in $logs) {
        if ($line -match "ERROR|CRITICAL|ALERT") {
            Write-Host "  $line" -ForegroundColor Red
        }
        elseif ($line -match "WARNING|WARN") {
            Write-Host "  $line" -ForegroundColor Yellow
        }
        elseif ($line -match "SUCCESS|UPDATED") {
            Write-Host "  $line" -ForegroundColor Green
        }
        else {
            Write-Host "  $line" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

function Show-Menu {
    Write-Host "═══ AÇÕES ═══" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [R] Atualizar dashboard" -ForegroundColor Cyan
    Write-Host "  [L] Ver logs completos" -ForegroundColor Cyan
    Write-Host "  [T] Ver todas as tasks" -ForegroundColor Cyan
    Write-Host "  [P] Proteger NEAR agora" -ForegroundColor Cyan
    Write-Host "  [F] Verificar posições sem stop" -ForegroundColor Cyan
    Write-Host "  [H] Reconfigurar tasks para oculto" -ForegroundColor Cyan
    Write-Host "  [Q] Sair" -ForegroundColor Cyan
    Write-Host ""
}

# Main loop
while ($true) {
    Show-Header
    Show-Tasks
    Show-Positions
    Show-Capital
    Show-RecentLogs -Lines 10
    Show-Menu
    
    $choice = Read-Host "Escolha uma opção"
    
    switch ($choice.ToUpper()) {
        "R" {
            # Refresh - loop continua
            continue
        }
        "L" {
            Clear-Host
            Write-Host "═══ LOGS COMPLETOS ═══" -ForegroundColor Yellow
            Write-Host ""
            $logFile = "$PSScriptRoot\logs\trailing_stop_monitor.log"
            if (Test-Path $logFile) {
                Get-Content $logFile | ForEach-Object {
                    if ($_ -match "ERROR|CRITICAL|ALERT") {
                        Write-Host $_ -ForegroundColor Red
                    }
                    elseif ($_ -match "WARNING|WARN") {
                        Write-Host $_ -ForegroundColor Yellow
                    }
                    elseif ($_ -match "SUCCESS|UPDATED") {
                        Write-Host $_ -ForegroundColor Green
                    }
                    else {
                        Write-Host $_ -ForegroundColor Gray
                    }
                }
            } else {
                Write-Host "Nenhum log encontrado" -ForegroundColor Gray
            }
            Write-Host ""
            Read-Host "Pressione Enter para voltar"
        }
        "T" {
            Clear-Host
            Write-Host "═══ TODAS AS TASKS AGENDADAS ═══" -ForegroundColor Yellow
            Write-Host ""
            Get-ScheduledTask | Where-Object { $_.State -ne "Disabled" } | Format-Table TaskName, State, @{Label="LastRun";Expression={(Get-ScheduledTaskInfo -TaskName $_.TaskName).LastRunTime}} -AutoSize
            Write-Host ""
            Read-Host "Pressione Enter para voltar"
        }
        "P" {
            Clear-Host
            Write-Host "═══ PROTEGER NEAR ═══" -ForegroundColor Yellow
            Write-Host ""
            & "$PSScriptRoot\PROTECT_NEAR_NOW.ps1"
            Write-Host ""
            Read-Host "Pressione Enter para voltar"
        }
        "F" {
            Clear-Host
            Write-Host "═══ VERIFICAR POSIÇÕES SEM STOP ═══" -ForegroundColor Yellow
            Write-Host ""
            & "$PSScriptRoot\FIX_MISSING_STOPS.ps1"
            Write-Host ""
            Read-Host "Pressione Enter para voltar"
        }
        "H" {
            Clear-Host
            Write-Host "═══ RECONFIGURAR TASKS PARA OCULTO ═══" -ForegroundColor Yellow
            Write-Host ""
            & "$PSScriptRoot\RECONFIGURAR_TASK_OCULTA.ps1"
            Write-Host ""
            Read-Host "Pressione Enter para voltar"
        }
        "Q" {
            Write-Host ""
            Write-Host "Saindo..." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "Opção inválida!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
