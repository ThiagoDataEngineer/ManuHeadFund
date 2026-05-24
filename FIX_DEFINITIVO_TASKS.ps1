# FIX_DEFINITIVO_TASKS.ps1
# Corrigir DEFINITIVAMENTE todas as tasks CoinEx
# EXECUTAR COMO ADMINISTRADOR

param([switch]$Force)

# Auto-elevar para admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Elevando para Administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Force" -Verb RunAs
    exit
}

Write-Host "=== FIX DEFINITIVO - TODAS AS TASKS COINEX ===" -ForegroundColor Cyan
Write-Host ""

$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
$fixed = 0
$alreadyOk = 0
$errors = 0

foreach ($task in $tasks) {
    $taskName = $task.TaskName
    $action = $task.Actions[0]
    $principal = $task.Principal
    $trigger = $task.Triggers[0]
    $settings = $task.Settings
    
    # Verificar se precisa corrigir
    $hasHidden = $action.Arguments -match "-WindowStyle Hidden"
    $isS4U = $principal.LogonType -eq "S4U"
    $isHiddenSetting = $settings.Hidden
    
    if ($hasHidden -and $isS4U -and $isHiddenSetting) {
        Write-Host "[$taskName] OK" -ForegroundColor Green
        $alreadyOk++
        continue
    }
    
    Write-Host "[$taskName] CORRIGINDO..." -ForegroundColor Yellow
    Write-Host "  Hidden=$hasHidden, LogonType=$($principal.LogonType), SettingHidden=$isHiddenSetting" -ForegroundColor Gray
    
    try {
        # 1. Corrigir Arguments (adicionar -WindowStyle Hidden)
        $newArgs = $action.Arguments
        if (-not $hasHidden -and $action.Execute -match "powershell") {
            $newArgs = "-WindowStyle Hidden " + $action.Arguments
        }
        
        # 2. Criar nova action (WorkingDirectory pode ser vazio)
        $workDir = $action.WorkingDirectory
        if ([string]::IsNullOrEmpty($workDir)) {
            $workDir = "C:\Users\thiag\Coinex_AI_USER_API"
        }
        
        $newAction = New-ScheduledTaskAction `
            -Execute $action.Execute `
            -Argument $newArgs `
            -WorkingDirectory $workDir
        
        # 3. Criar novo principal (S4U = sem janela)
        $newPrincipal = New-ScheduledTaskPrincipal `
            -UserId $principal.UserId `
            -LogonType S4U `
            -RunLevel $principal.RunLevel
        
        # 4. Criar novos settings (Hidden = true)
        $newSettings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -MultipleInstances IgnoreNew `
            -Hidden
        
        # 5. Remover task antiga
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        
        # 6. Registrar task nova (completamente oculta)
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $newAction `
            -Trigger $trigger `
            -Settings $newSettings `
            -Principal $newPrincipal `
            -Description $task.Description `
            -ErrorAction Stop | Out-Null
        
        Write-Host "  CORRIGIDO!" -ForegroundColor Green
        $fixed++
    }
    catch {
        Write-Host "  ERRO: $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "=== RESULTADO FINAL ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total de tasks: $($tasks.Count)" -ForegroundColor White
Write-Host "Ja estavam OK: $alreadyOk" -ForegroundColor Green
Write-Host "Corrigidas agora: $fixed" -ForegroundColor Green
Write-Host "Erros: $errors" -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($fixed -gt 0) {
    Write-Host "SUCESSO! $fixed task(s) corrigida(s)!" -ForegroundColor Green
    Write-Host "PowerShell NAO vai mais aparecer!" -ForegroundColor Green
} elseif ($alreadyOk -eq $tasks.Count) {
    Write-Host "Todas as tasks ja estavam configuradas corretamente!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Verificacao:" -ForegroundColor Yellow
Write-Host ""

# Verificar novamente
foreach ($task in (Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" })) {
    $action = $task.Actions[0]
    $hasHidden = $action.Arguments -match "-WindowStyle Hidden"
    $logonType = $task.Principal.LogonType
    $settingHidden = $task.Settings.Hidden
    
    $status = if ($hasHidden -and $logonType -eq 'S4U' -and $settingHidden) { 
        "OK" 
    } else { 
        "PROBLEMA" 
    }
    
    $color = if ($status -eq "OK") { "Green" } else { "Red" }
    
    Write-Host "  $($task.TaskName): $status (Hidden=$hasHidden, LogonType=$logonType, Setting=$settingHidden)" -ForegroundColor $color
}

Write-Host ""
Write-Host "Pressione Enter para fechar..." -ForegroundColor Gray
Read-Host
