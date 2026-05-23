# setup_all_cron_jobs.ps1 - Configura TODOS os cron jobs do sistema
# Rodar como Administrador: .\scripts\setup_all_cron_jobs.ps1
#
# CRON JOBS:
# 1. Position Risk Manager (15 minutos)
# 2. Dashboard Generator (5 minutos)
# 3. Tori Monitoring (30 minutos)

$ErrorActionPreference = "Stop"

# Verificar se está rodando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "❌ ERRO: Este script precisa ser executado como Administrador" -ForegroundColor Red
    Write-Host ""
    Write-Host "Como executar:" -ForegroundColor Yellow
    Write-Host "1. Abra PowerShell como Administrador (botão direito → Executar como administrador)" -ForegroundColor White
    Write-Host "2. Navegue até o diretório: cd C:\Users\thiag\Coinex_AI_USER_API" -ForegroundColor White
    Write-Host "3. Execute: .\scripts\setup_all_cron_jobs.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host @"

╔════════════════════════════════════════════════════════╗
║          SETUP DE CRON JOBS - COINEX AI               ║
╚════════════════════════════════════════════════════════╝

Este script irá configurar 3 cron jobs:

1. 📊 Position Risk Manager (a cada 15 minutos)
   - Trailing stops automáticos
   - Ajuste de leverage por volatilidade
   - Proteção contra liquidação
   - Monitoramento de ladder exits

2. 📈 Dashboard Generator (a cada 5 minutos)
   - Atualiza métricas de performance
   - Gera HTML com auto-refresh
   - Monitora posições abertas

3. 🎯 Tori Monitoring (a cada 30 minutos)
   - Monitora proximidade de trendlines
   - Alertas de setup ripening
   - Análise de oportunidades

"@ -ForegroundColor Cyan

$confirm = Read-Host "Deseja continuar? (S/N)"
if ($confirm -ne "S" -and $confirm -ne "s") {
    Write-Host "Operação cancelada." -ForegroundColor Yellow
    exit 0
}

$projectRoot = "C:\Users\thiag\Coinex_AI_USER_API"

# ============================================================================
# FUNÇÃO: Criar Tarefa Agendada
# ============================================================================

function New-CronJob {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [int]$IntervalMinutes,
        [string]$Description
    )
    
    try {
        # Verificar se tarefa já existe
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        
        if ($existingTask) {
            Write-Host "  ⚠️  Tarefa '$TaskName' já existe. Removendo..." -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        
        # Criar ação
        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
            -WorkingDirectory $projectRoot
        
        # Criar trigger (repetir a cada X minutos, indefinidamente)
        $trigger = New-ScheduledTaskTrigger `
            -Once `
            -At (Get-Date) `
            -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
            -RepetitionDuration ([TimeSpan]::MaxValue)
        
        # Configurações
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
        
        Write-Host "  ✅ Tarefa '$TaskName' criada com sucesso" -ForegroundColor Green
        Write-Host "     Intervalo: $IntervalMinutes minutos" -ForegroundColor Gray
        Write-Host "     Script: $ScriptPath" -ForegroundColor Gray
        
        return $true
    }
    catch {
        Write-Host "  ❌ Erro ao criar tarefa '$TaskName': $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# CRIAR CRON JOBS
# ============================================================================

Write-Host "`n=== CRIANDO CRON JOBS ===" -ForegroundColor Cyan

$success = 0
$failed = 0

# 1. Position Risk Manager (15 minutos)
Write-Host "`n1. Position Risk Manager..." -ForegroundColor Yellow
$script1 = Join-Path $projectRoot "scripts\position_risk_cron.ps1"
if (Test-Path $script1) {
    if (New-CronJob `
        -TaskName "CoinEx_PositionRisk" `
        -ScriptPath $script1 `
        -IntervalMinutes 15 `
        -Description "Position Risk Manager - Trailing stops, leverage adjustment, liquidation protection") {
        $success++
    } else {
        $failed++
    }
} else {
    Write-Host "  ❌ Script não encontrado: $script1" -ForegroundColor Red
    $failed++
}

# 2. Dashboard Generator (5 minutos)
Write-Host "`n2. Dashboard Generator..." -ForegroundColor Yellow
$script2 = Join-Path $projectRoot "scripts\generate_position_dashboard.ps1"
if (Test-Path $script2) {
    if (New-CronJob `
        -TaskName "CoinEx_Dashboard" `
        -ScriptPath $script2 `
        -IntervalMinutes 5 `
        -Description "Dashboard Generator - Atualiza métricas de performance a cada 5 minutos") {
        $success++
    } else {
        $failed++
    }
} else {
    Write-Host "  ❌ Script não encontrado: $script2" -ForegroundColor Red
    $failed++
}

# 3. Tori Monitoring (30 minutos)
Write-Host "`n3. Tori Monitoring..." -ForegroundColor Yellow
$script3 = Join-Path $projectRoot "scripts\tori_monitoring_cron.ps1"
if (Test-Path $script3) {
    if (New-CronJob `
        -TaskName "CoinEx_ToriMonitoring" `
        -ScriptPath $script3 `
        -IntervalMinutes 30 `
        -Description "Tori Monitoring - Monitora proximidade de trendlines e alertas de setup") {
        $success++
    } else {
        $failed++
    }
} else {
    Write-Host "  ❌ Script não encontrado: $script3" -ForegroundColor Red
    $failed++
}

# ============================================================================
# RESUMO
# ============================================================================

Write-Host @"

╔════════════════════════════════════════════════════════╗
║                      RESUMO                            ║
╚════════════════════════════════════════════════════════╝

✅ Tarefas criadas: $success
❌ Tarefas falhadas: $failed

"@ -ForegroundColor Cyan

if ($success -gt 0) {
    Write-Host "📋 TAREFAS AGENDADAS:" -ForegroundColor Green
    Write-Host ""
    
    Get-ScheduledTask | Where-Object { $_.TaskName -like "CoinEx_*" } | ForEach-Object {
        $task = $_
        $trigger = $task.Triggers[0]
        $interval = if ($trigger.Repetition) { $trigger.Repetition.Interval } else { "N/A" }
        
        Write-Host "  • $($task.TaskName)" -ForegroundColor White
        Write-Host "    Estado: $($task.State)" -ForegroundColor Gray
        Write-Host "    Intervalo: $interval" -ForegroundColor Gray
        Write-Host "    Próxima execução: $($task.NextRunTime)" -ForegroundColor Gray
        Write-Host ""
    }
}

# ============================================================================
# COMANDOS ÚTEIS
# ============================================================================

Write-Host @"
╔════════════════════════════════════════════════════════╗
║                  COMANDOS ÚTEIS                        ║
╚════════════════════════════════════════════════════════╝

📊 LISTAR TAREFAS:
   Get-ScheduledTask | Where-Object { `$_.TaskName -like "CoinEx_*" }

▶️  INICIAR TAREFA MANUALMENTE:
   Start-ScheduledTask -TaskName "CoinEx_PositionRisk"
   Start-ScheduledTask -TaskName "CoinEx_Dashboard"
   Start-ScheduledTask -TaskName "CoinEx_ToriMonitoring"

⏸️  PAUSAR TAREFA:
   Disable-ScheduledTask -TaskName "CoinEx_PositionRisk"

▶️  RETOMAR TAREFA:
   Enable-ScheduledTask -TaskName "CoinEx_PositionRisk"

🗑️  REMOVER TAREFA:
   Unregister-ScheduledTask -TaskName "CoinEx_PositionRisk" -Confirm:`$false

📋 VER HISTÓRICO DE EXECUÇÃO:
   Get-ScheduledTask -TaskName "CoinEx_PositionRisk" | Get-ScheduledTaskInfo

📂 ABRIR TASK SCHEDULER (GUI):
   taskschd.msc

"@ -ForegroundColor Cyan

# ============================================================================
# TESTE INICIAL
# ============================================================================

Write-Host "╔════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║              TESTE INICIAL (OPCIONAL)                  ║" -ForegroundColor Yellow
Write-Host "╚════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

$runTest = Read-Host "Deseja executar um teste inicial agora? (S/N)"

if ($runTest -eq "S" -or $runTest -eq "s") {
    Write-Host "`nExecutando testes..." -ForegroundColor Yellow
    
    # Testar Position Risk Manager
    Write-Host "`n1. Testando Position Risk Manager..." -ForegroundColor Cyan
    try {
        Start-ScheduledTask -TaskName "CoinEx_PositionRisk"
        Write-Host "   ✅ Tarefa iniciada" -ForegroundColor Green
        Write-Host "   ⏳ Aguarde 10 segundos para verificar logs..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
        
        $taskInfo = Get-ScheduledTask -TaskName "CoinEx_PositionRisk" | Get-ScheduledTaskInfo
        Write-Host "   Última execução: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "   Resultado: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
    }
    catch {
        Write-Host "   ❌ Erro: $_" -ForegroundColor Red
    }
    
    # Testar Dashboard Generator
    Write-Host "`n2. Testando Dashboard Generator..." -ForegroundColor Cyan
    try {
        Start-ScheduledTask -TaskName "CoinEx_Dashboard"
        Write-Host "   ✅ Tarefa iniciada" -ForegroundColor Green
        Write-Host "   ⏳ Aguarde 10 segundos para verificar logs..." -ForegroundColor Gray
        Start-Sleep -Seconds 10
        
        $taskInfo = Get-ScheduledTask -TaskName "CoinEx_Dashboard" | Get-ScheduledTaskInfo
        Write-Host "   Última execução: $($taskInfo.LastRunTime)" -ForegroundColor Gray
        Write-Host "   Resultado: $($taskInfo.LastTaskResult)" -ForegroundColor Gray
        
        # Verificar se dashboard foi gerado
        $dashboardPath = Join-Path $projectRoot "dashboard\position_metrics.html"
        if (Test-Path $dashboardPath) {
            Write-Host "   ✅ Dashboard gerado: $dashboardPath" -ForegroundColor Green
            
            $openDashboard = Read-Host "   Deseja abrir o dashboard no navegador? (S/N)"
            if ($openDashboard -eq "S" -or $openDashboard -eq "s") {
                Start-Process $dashboardPath
            }
        } else {
            Write-Host "   ⚠️  Dashboard não encontrado (pode estar sendo gerado)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "   ❌ Erro: $_" -ForegroundColor Red
    }
}

# ============================================================================
# FINALIZAÇÃO
# ============================================================================

Write-Host @"

╔════════════════════════════════════════════════════════╗
║                    SETUP COMPLETO                      ║
╚════════════════════════════════════════════════════════╝

✅ Cron jobs configurados e rodando!

📊 MONITORAMENTO:
   • Dashboard: C:\Users\thiag\Coinex_AI_USER_API\dashboard\position_metrics.html
   • Logs: C:\Users\thiag\Coinex_AI_USER_API\journal\

🔔 ALERTAS:
   • Telegram configurado (se disponível)
   • Logs em journal/

⚙️  TASK SCHEDULER:
   • Abrir GUI: taskschd.msc
   • Pasta: Task Scheduler Library

🚀 PRÓXIMOS PASSOS:
   1. Monitorar dashboard (auto-refresh 5min)
   2. Verificar logs em journal/
   3. Ajustar parâmetros se necessário
   4. Testar em paper trading

"@ -ForegroundColor Green

Write-Host "Pressione ENTER para sair..." -ForegroundColor DarkGray
Read-Host
