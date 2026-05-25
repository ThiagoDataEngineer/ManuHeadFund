# setup_cron_jobs.ps1 - Configura cron jobs no Windows Task Scheduler
# Rodar como Administrador: .\scripts\setup_cron_jobs.ps1
#
# CRON JOBS CRIADOS:
# 1. Position Risk Manager (a cada 15 minutos)
# 2. Dashboard Generator (a cada 5 minutos)
# 3. Ladder Exit Monitor (a cada 10 minutos)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$baseDir = Split-Path $PSScriptRoot -Parent
$scriptsDir = Join-Path $baseDir "scripts"

Write-Host @"

â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
â•‘        SETUP CRON JOBS - TASK SCHEDULER                â•‘
â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

Este script criarÃ¡ 3 tarefas agendadas:
1. Position Risk Manager (15min)
2. Dashboard Generator (5min)
3. Ladder Exit Monitor (10min)

"@ -ForegroundColor Cyan

# ============================================================================
# FunÃ§Ã£o auxiliar para criar tarefa
# ============================================================================

function New-CronTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [int]$IntervalMinutes,
        [string]$Description
    )
    
    try {
        # Verificar se tarefa jÃ¡ existe
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Host "  âš ï¸  Tarefa '$TaskName' jÃ¡ existe. Removendo..." -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Criar aÃ§Ã£o
        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
            -WorkingDirectory $baseDir
        
        # Criar trigger (repetir a cada X minutos)
        $trigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date).AddMinutes(1) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
        
        # ConfiguraÃ§Ãµes
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew
        
        # Registrar tarefa
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description $Description `
            -User $env:USERNAME `
            -RunLevel Limited | Out-Null
        
        Write-Host "  âœ“ Tarefa '$TaskName' criada (intervalo: ${IntervalMinutes}min)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  âœ— Erro ao criar tarefa '$TaskName': $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# TAREFA 1: Position Risk Manager (15min)
# ============================================================================

Write-Host "`n=== TAREFA 1: Position Risk Manager ===" -ForegroundColor Yellow

$task1Path = Join-Path $scriptsDir "position_risk_cron.ps1"
if (-not (Test-Path $task1Path)) {
    Write-Host "  âœ— Arquivo nÃ£o encontrado: $task1Path" -ForegroundColor Red
} else {
    $success1 = New-CronTask `
        -TaskName "CoinEx_PositionRiskManager" `
        -ScriptPath $task1Path `
        -IntervalMinutes 15 `
        -Description "Monitora posiÃ§Ãµes e aplica trailing stops, ajuste de leverage e proteÃ§Ã£o de liquidaÃ§Ã£o"
}

# ============================================================================
# TAREFA 2: Dashboard Generator (5min)
# ============================================================================

Write-Host "`n=== TAREFA 2: Dashboard Generator ===" -ForegroundColor Yellow

$task2Path = Join-Path $scriptsDir "generate_position_dashboard.ps1"
if (-not (Test-Path $task2Path)) {
    Write-Host "  âœ— Arquivo nÃ£o encontrado: $task2Path" -ForegroundColor Red
} else {
    $success2 = New-CronTask `
        -TaskName "CoinEx_DashboardGenerator" `
        -ScriptPath $task2Path `
        -IntervalMinutes 5 `
        -Description "Gera dashboard HTML com mÃ©tricas de posiÃ§Ãµes e performance"
}

# ============================================================================
# TAREFA 3: Ladder Exit Monitor (10min)
# ============================================================================

Write-Host "`n=== TAREFA 3: Ladder Exit Monitor ===" -ForegroundColor Yellow

# Criar script de monitoramento de ladder exits
$task3Path = Join-Path $scriptsDir "ladder_exit_monitor_cron.ps1"
$task3Content = @'
# ladder_exit_monitor_cron.ps1 - Monitora execuÃ§Ã£o de ladder exits
# Rodar automaticamente a cada 10 minutos

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_coinex_position_management.ps1"
. ".\agents\lib_multi_tp_ladder.ps1"
. ".\agents\lib_telegram.ps1"

try {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "`n=== LADDER EXIT MONITOR - $timestamp ===" -ForegroundColor Cyan
    
    # Buscar posiÃ§Ãµes abertas
    $positions = CoinEx-GetPendingPositions
    if (-not $positions -or $positions.Count -eq 0) {
        Write-Host "Nenhuma posiÃ§Ã£o aberta" -ForegroundColor DarkGray
        exit 0
    }
    
    Write-Host "PosiÃ§Ãµes abertas: $($positions.Count)" -ForegroundColor White
    
    # Verificar se hÃ¡ ladder exits ativos (arquivo de estado)
    $ladderStatePath = Join-Path $global:JOURNAL_DIR "ladder_exits_state.json"
    if (-not (Test-Path $ladderStatePath)) {
        Write-Host "Nenhum ladder exit ativo" -ForegroundColor DarkGray
        exit 0
    }
    
    $ladderStates = Get-Content $ladderStatePath | ConvertFrom-Json
    $updates = 0
    
    foreach ($state in $ladderStates) {
        $market = $state.market
        
        # Verificar se posiÃ§Ã£o ainda existe
        $pos = $positions | Where-Object { $_.market -eq $market } | Select-Object -First 1
        if (-not $pos) {
            Write-Host "  $market: posiÃ§Ã£o fechada (remover do estado)" -ForegroundColor DarkGray
            continue
        }
        
        Write-Host "`n  --- $market ---" -ForegroundColor Yellow
        
        # Monitorar execuÃ§Ã£o
        $result = Monitor-LadderExecution `
            -Market $market `
            -EntryPrice $state.entry_price `
            -Ladder $state.ladder `
            -Side $state.side
        
        if ($result.success) {
            Write-Host "  âœ“ SL atualizado: $($result.old_sl) â†’ $($result.new_sl)" -ForegroundColor Green
            Write-Host "    Motivo: $($result.reason)" -ForegroundColor Gray
            $updates++
            
            # Enviar alerta
            $msg = "ðŸ“Š Ladder Exit Update: $market`n`n" +
                   "$($result.reason)`n" +
                   "SL: $($result.old_sl) â†’ $($result.new_sl)"
            Send-TelegramAlert -Message $msg | Out-Null
        }
    }
    
    if ($updates -gt 0) {
        Write-Host "`nâœ“ $updates SLs atualizados" -ForegroundColor Green
    } else {
        Write-Host "`nâœ“ Nenhuma atualizaÃ§Ã£o necessÃ¡ria" -ForegroundColor DarkGray
    }
    
} catch {
    Write-Host "`nâœ— ERRO: $_" -ForegroundColor Red
    
    if (Get-Command Send-TelegramAlert -ErrorAction SilentlyContinue) {
        Send-TelegramAlert -Message "ðŸš¨ ERRO Ladder Exit Monitor:`n$_" | Out-Null
    }
    
    exit 1
}
'@

$task3Content | Out-File -FilePath $task3Path -Encoding UTF8 -Force

$success3 = New-CronTask `
    -TaskName "CoinEx_LadderExitMonitor" `
    -ScriptPath $task3Path `
    -IntervalMinutes 10 `
    -Description "Monitora execuÃ§Ã£o de ladder exits e ajusta stop loss dinamicamente"

# ============================================================================
# RESUMO
# ============================================================================

Write-Host @"

â•”â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—
â•‘                      RESUMO                            â•‘
â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

"@ -ForegroundColor Cyan

$totalSuccess = 0
if ($success1) { $totalSuccess++ }
if ($success2) { $totalSuccess++ }
if ($success3) { $totalSuccess++ }

Write-Host "Tarefas criadas: $totalSuccess/3" -ForegroundColor $(if($totalSuccess -eq 3){"Green"}else{"Yellow"})

if ($totalSuccess -eq 3) {
    Write-Host @"

âœ… TODAS AS TAREFAS CONFIGURADAS COM SUCESSO!

PrÃ³ximos passos:
1. Verificar tarefas: Get-ScheduledTask | Where-Object { `$_.TaskName -like "CoinEx_*" }
2. Testar manualmente: Start-ScheduledTask -TaskName "CoinEx_PositionRiskManager"
3. Ver logs: Get-ScheduledTaskInfo -TaskName "CoinEx_PositionRiskManager"

As tarefas comeÃ§arÃ£o a rodar automaticamente em:
- Position Risk Manager: 15 minutos
- Dashboard Generator: 5 minutos
- Ladder Exit Monitor: 10 minutos

Para desabilitar: Disable-ScheduledTask -TaskName "CoinEx_*"
Para remover: Unregister-ScheduledTask -TaskName "CoinEx_*" -Confirm:`$false

"@ -ForegroundColor Green
} else {
    Write-Host "`nâš ï¸  Algumas tarefas falharam. Verifique os erros acima." -ForegroundColor Yellow
}

Write-Host "Pressione ENTER para sair..." -ForegroundColor DarkGray
Read-Host
