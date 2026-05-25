# setup_cron_manual.ps1 - Setup manual de cron jobs (sem precisar de admin)
# Rodar: .\scripts\setup_cron_manual.ps1
#
# ALTERNATIVA: Se nÃ£o conseguir rodar como admin, use este script
# Ele cria os cron jobs para o usuÃ¡rio atual

$ErrorActionPreference = "Stop"
$projectRoot = "C:\Users\thiag\Coinex_AI_USER_API"

Write-Host @"

â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
â•‘       SETUP MANUAL DE CRON JOBS - COINEX AI           â•‘
â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

Este script cria cron jobs SEM precisar de privilÃ©gios de admin.
Os jobs rodarÃ£o apenas quando vocÃª estiver logado.

"@ -ForegroundColor Cyan

# ============================================================================
# CRIAR TAREFAS
# ============================================================================

Write-Host "Criando tarefas..." -ForegroundColor Yellow

try {
    # 1. Position Risk Manager (15 minutos)
    Write-Host "`n1. Position Risk Manager (15 minutos)..." -ForegroundColor Cyan
    
    $action1 = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `(Join-Path (Join-Path $projectRoot "scripts") "position_risk_cron.ps1`")" `
        -WorkingDirectory $projectRoot
    
    $trigger1 = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 15) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $settings1 = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable
    
    # Remover se jÃ¡ existe
    $existing1 = Get-ScheduledTask -TaskName "CoinEx_PositionRisk" -ErrorAction SilentlyContinue
    if ($existing1) {
        Unregister-ScheduledTask -TaskName "CoinEx_PositionRisk" -Confirm:$false
    }
    
    Register-ScheduledTask `
        -TaskName "CoinEx_PositionRisk" `
        -Action $action1 `
        -Trigger $trigger1 `
        -Settings $settings1 `
        -Description "Position Risk Manager - Trailing stops, leverage adjustment" | Out-Null
    
    Write-Host "   âœ… CoinEx_PositionRisk criado" -ForegroundColor Green
    
    # 2. Dashboard Generator (5 minutos)
    Write-Host "`n2. Dashboard Generator (5 minutos)..." -ForegroundColor Cyan
    
    $action2 = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `(Join-Path (Join-Path $projectRoot "scripts") "generate_position_dashboard.ps1`")" `
        -WorkingDirectory $projectRoot
    
    $trigger2 = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $settings2 = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable
    
    # Remover se jÃ¡ existe
    $existing2 = Get-ScheduledTask -TaskName "CoinEx_Dashboard" -ErrorAction SilentlyContinue
    if ($existing2) {
        Unregister-ScheduledTask -TaskName "CoinEx_Dashboard" -Confirm:$false
    }
    
    Register-ScheduledTask `
        -TaskName "CoinEx_Dashboard" `
        -Action $action2 `
        -Trigger $trigger2 `
        -Settings $settings2 `
        -Description "Dashboard Generator - Atualiza mÃ©tricas a cada 5 minutos" | Out-Null
    
    Write-Host "   âœ… CoinEx_Dashboard criado" -ForegroundColor Green
    
    # 3. Tori Monitoring (30 minutos)
    Write-Host "`n3. Tori Monitoring (30 minutos)..." -ForegroundColor Cyan
    
    $action3 = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `(Join-Path (Join-Path $projectRoot "scripts") "tori_monitoring_cron.ps1`")" `
        -WorkingDirectory $projectRoot
    
    $trigger3 = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $settings3 = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable
    
    # Remover se jÃ¡ existe
    $existing3 = Get-ScheduledTask -TaskName "CoinEx_ToriMonitoring" -ErrorAction SilentlyContinue
    if ($existing3) {
        Unregister-ScheduledTask -TaskName "CoinEx_ToriMonitoring" -Confirm:$false
    }
    
    Register-ScheduledTask `
        -TaskName "CoinEx_ToriMonitoring" `
        -Action $action3 `
        -Trigger $trigger3 `
        -Settings $settings3 `
        -Description "Tori Monitoring - Monitora proximidade de trendlines" | Out-Null
    
    Write-Host "   âœ… CoinEx_ToriMonitoring criado" -ForegroundColor Green
    
    Write-Host @"

â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
â•‘                  âœ… SETUP COMPLETO                     â•‘
â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

Tarefas criadas com sucesso!

ðŸ“‹ TAREFAS AGENDADAS:
   â€¢ CoinEx_PositionRisk (15 minutos)
   â€¢ CoinEx_Dashboard (5 minutos)
   â€¢ CoinEx_ToriMonitoring (30 minutos)

ðŸ“Š VERIFICAR TAREFAS:
   Get-ScheduledTask | Where-Object { `$_.TaskName -like "CoinEx_*" }

â–¶ï¸  INICIAR MANUALMENTE:
   Start-ScheduledTask -TaskName "CoinEx_PositionRisk"
   Start-ScheduledTask -TaskName "CoinEx_Dashboard"
   Start-ScheduledTask -TaskName "CoinEx_ToriMonitoring"

ðŸ“‚ ABRIR TASK SCHEDULER:
   taskschd.msc

"@ -ForegroundColor Green
    
    # Listar tarefas criadas
    Write-Host "Tarefas criadas:" -ForegroundColor Cyan
    Get-ScheduledTask | Where-Object { $_.TaskName -like "CoinEx_*" } | ForEach-Object {
        Write-Host "  â€¢ $($_.TaskName) - Estado: $($_.State)" -ForegroundColor White
    }
    
    # Perguntar se quer testar
    Write-Host ""
    $test = Read-Host "Deseja executar um teste agora? (S/N)"
    
    if ($test -eq "S" -or $test -eq "s") {
        Write-Host "`nTestando Dashboard Generator..." -ForegroundColor Yellow
        Start-ScheduledTask -TaskName "CoinEx_Dashboard"
        
        Write-Host "Aguardando 15 segundos..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
        
        $dashboardPath = Join-Path $projectRoot "dashboard\position_metrics.html"
        if (Test-Path $dashboardPath) {
            Write-Host "âœ… Dashboard gerado com sucesso!" -ForegroundColor Green
            
            $open = Read-Host "Deseja abrir o dashboard? (S/N)"
            if ($open -eq "S" -or $open -eq "s") {
                Start-Process $dashboardPath
            }
        } else {
            Write-Host "âš ï¸  Dashboard ainda nÃ£o foi gerado (pode levar alguns segundos)" -ForegroundColor Yellow
        }
    }
    
}
catch {
    Write-Host "`nâŒ ERRO: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "PossÃ­veis soluÃ§Ãµes:" -ForegroundColor Yellow
    Write-Host "1. Execute como Administrador" -ForegroundColor White
    Write-Host "2. Verifique se os scripts existem em:" -ForegroundColor White
    Write-Host "   $projectRoot\scripts\" -ForegroundColor Gray
    Write-Host "3. Verifique permissÃµes de execuÃ§Ã£o:" -ForegroundColor White
    Write-Host "   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Gray
}

Write-Host "`nPressione ENTER para sair..." -ForegroundColor DarkGray
Read-Host
