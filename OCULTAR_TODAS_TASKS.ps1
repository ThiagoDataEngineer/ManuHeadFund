# OCULTAR_TODAS_TASKS.ps1
# Reconfigurar TODAS as tasks CoinEx para rodar OCULTAS
# 2026-05-24
# EXECUTAR COMO ADMINISTRADOR

Write-Host "=== OCULTAR TODAS AS TASKS COINEX ===" -ForegroundColor Cyan
Write-Host ""

# Verificar se esta rodando como admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script precisa ser executado como ADMINISTRADOR!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Clique direito no arquivo e escolha 'Executar como Administrador'" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Buscar todas as tasks CoinEx
$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }

Write-Host "Encontradas $($tasks.Count) tasks CoinEx" -ForegroundColor Yellow
Write-Host ""

$reconfigured = 0
$errors = 0

foreach ($task in $tasks) {
    $taskName = $task.TaskName
    Write-Host "Processando: $taskName" -ForegroundColor Cyan
    
    try {
        # Pegar configuracao atual
        $taskInfo = Get-ScheduledTask -TaskName $taskName
        $action = $taskInfo.Actions[0]
        $trigger = $taskInfo.Triggers[0]
        $settings = $taskInfo.Settings
        $principal = $taskInfo.Principal
        
        # Verificar se ja esta oculto
        $isHidden = $settings.Hidden -and $principal.LogonType -eq "S4U"
        
        if ($isHidden) {
            Write-Host "  [OK] Ja esta oculto" -ForegroundColor Green
            continue
        }
        
        Write-Host "  [FIX] Reconfigurando para oculto..." -ForegroundColor Yellow
        
        # Criar nova action com -WindowStyle Hidden
        $executable = $action.Execute
        $arguments = $action.Arguments
        $workingDir = $action.WorkingDirectory
        
        # Adicionar -WindowStyle Hidden se for PowerShell
        if ($executable -match "powershell") {
            if ($arguments -notmatch "-WindowStyle Hidden") {
                $arguments = "-WindowStyle Hidden " + $arguments
            }
        }
        
        $newAction = New-ScheduledTaskAction `
            -Execute $executable `
            -Argument $arguments `
            -WorkingDirectory $workingDir
        
        # Criar novo principal com S4U (sem janela)
        $newPrincipal = New-ScheduledTaskPrincipal `
            -UserId $principal.UserId `
            -LogonType S4U `
            -RunLevel $principal.RunLevel
        
        # Criar novos settings com Hidden
        $newSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew `
            -Hidden
        
        # Remover task antiga
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        
        # Registrar task nova (oculta)
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $newAction `
            -Trigger $trigger `
            -Settings $newSettings `
            -Principal $newPrincipal `
            -Description $taskInfo.Description `
            -ErrorAction Stop | Out-Null
        
        Write-Host "  [OK] Reconfigurado com sucesso!" -ForegroundColor Green
        $reconfigured++
    }
    catch {
        Write-Host "  [ERRO] Falha: $_" -ForegroundColor Red
        $errors++
    }
    
    Write-Host ""
}

Write-Host "=== RESULTADO ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total de tasks: $($tasks.Count)" -ForegroundColor White
Write-Host "Reconfiguradas: $reconfigured" -ForegroundColor Green
Write-Host "Erros: $errors" -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($reconfigured -gt 0) {
    Write-Host "SUCESSO! Todas as tasks agora rodam OCULTAS!" -ForegroundColor Green
    Write-Host "PowerShell NAO vai mais aparecer!" -ForegroundColor Green
} else {
    Write-Host "Todas as tasks ja estavam ocultas!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Pressione Enter para fechar..." -ForegroundColor Gray
Read-Host
