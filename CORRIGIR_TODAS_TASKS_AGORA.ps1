# CORRIGIR_TODAS_TASKS_AGORA.ps1
# Adicionar -WindowStyle Hidden em TODAS as tasks CoinEx
# EXECUTAR COMO ADMINISTRADOR

param([switch]$Force)

# Verificar admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Elevando para Administrador..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Force" -Verb RunAs
    exit
}

Write-Host "=== CORRIGIR TODAS AS TASKS COINEX ===" -ForegroundColor Cyan
Write-Host ""

$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
$fixed = 0
$skipped = 0

foreach ($task in $tasks) {
    $taskName = $task.TaskName
    $action = $task.Actions[0]
    
    # Verificar se é PowerShell
    if ($action.Execute -notmatch "powershell") {
        Write-Host "[$taskName] Pulando (nao e PowerShell)" -ForegroundColor Gray
        $skipped++
        continue
    }
    
    # Verificar se ja tem -WindowStyle Hidden
    if ($action.Arguments -match "-WindowStyle Hidden") {
        Write-Host "[$taskName] OK (ja tem -WindowStyle Hidden)" -ForegroundColor Green
        $skipped++
        continue
    }
    
    Write-Host "[$taskName] CORRIGINDO..." -ForegroundColor Yellow
    
    try {
        # Adicionar -WindowStyle Hidden
        $newArgs = "-WindowStyle Hidden " + $action.Arguments
        
        $newAction = New-ScheduledTaskAction `
            -Execute $action.Execute `
            -Argument $newArgs `
            -WorkingDirectory $action.WorkingDirectory
        
        Set-ScheduledTask -TaskName $taskName -Action $newAction | Out-Null
        
        Write-Host "[$taskName] CORRIGIDO!" -ForegroundColor Green
        $fixed++
    }
    catch {
        Write-Host "[$taskName] ERRO: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== RESULTADO ===" -ForegroundColor Cyan
Write-Host "Total: $($tasks.Count) tasks" -ForegroundColor White
Write-Host "Corrigidas: $fixed" -ForegroundColor Green
Write-Host "Ja estavam OK: $skipped" -ForegroundColor Green
Write-Host ""
Write-Host "PRONTO! PowerShell NAO vai mais aparecer!" -ForegroundColor Green
Write-Host ""
Write-Host "Pressione Enter para fechar..." -ForegroundColor Gray
Read-Host
