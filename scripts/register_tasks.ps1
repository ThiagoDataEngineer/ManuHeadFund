# register_tasks.ps1 -- Registra tarefas no Windows Task Scheduler
# Uso: powershell -File scripts\register_tasks.ps1
# Requer: executar como Administrador (ou usuario com permissao de agendamento)

$scriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$masterScript = Join-Path $scriptRoot "scan_master.ps1"
$psExe = "powershell.exe"

# ── Tarefa DryRun (teste -- nao executa ordens reais) ────────────────────────
$taskNameDry = "CoinexScanMaster_DryRun"
$argsDry = "-NonInteractive -File `"$masterScript`" -DryRun -GemTopN 3 -OrchestratorTopN 2"

$actionDry   = New-ScheduledTaskAction -Execute $psExe -Argument $argsDry
$triggerDry  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settingsDry = New-ScheduledTaskSettingsSet `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 10) `
    -ExecutionTimeLimit (New-TimeSpan -Days 30) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

try {
    Unregister-ScheduledTask -TaskName $taskNameDry -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask `
        -TaskName    $taskNameDry `
        -Action      $actionDry `
        -Trigger     $triggerDry `
        -Settings    $settingsDry `
        -RunLevel    Highest `
        -Description "CoinEx ScanMaster - DryRun (sem ordens reais). Auto-pacing via sazonalidade." `
        -Force | Out-Null
    Write-Host "[OK] Tarefa registrada: $taskNameDry" -ForegroundColor Green
    Write-Host "     Trigger: ao fazer login como $env:USERNAME" -ForegroundColor DarkGray
    Write-Host "     Modo: DryRun (sem ordens reais)" -ForegroundColor DarkGray
} catch {
    Write-Host "[ERRO] Falha ao registrar $taskNameDry`: $_" -ForegroundColor Red
}

# ── Tarefa Live (producao -- executa ordens reais) ───────────────────────────
$taskNameLive = "CoinexScanMaster_Live"
$argsLive = "-NonInteractive -File `"$masterScript`" -GemTopN 5 -OrchestratorTopN 3"

$actionLive   = New-ScheduledTaskAction -Execute $psExe -Argument $argsLive
$triggerLive  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settingsLive = New-ScheduledTaskSettingsSet `
    -RestartCount 5 `
    -RestartInterval (New-TimeSpan -Minutes 10) `
    -ExecutionTimeLimit (New-TimeSpan -Days 30) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable

try {
    Unregister-ScheduledTask -TaskName $taskNameLive -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask `
        -TaskName    $taskNameLive `
        -Action      $actionLive `
        -Trigger     $triggerLive `
        -Settings    $settingsLive `
        -RunLevel    Highest `
        -Description "CoinEx ScanMaster - LIVE (ordens reais). Ativar apenas apos validacao DryRun." `
        -Force | Out-Null
    Write-Host "[OK] Tarefa registrada: $taskNameLive" -ForegroundColor Green
    Write-Host "     Trigger: ao fazer login (DESABILITADA por padrao)" -ForegroundColor DarkGray
    Write-Host "     Modo: LIVE -- habilitar manualmente quando pronto" -ForegroundColor DarkYellow

    # Desabilita a Live por seguranca -- habilitar manualmente quando quiser producao
    Disable-ScheduledTask -TaskName $taskNameLive | Out-Null
    Write-Host "     [DESABILITADA] Habilite manualmente: Enable-ScheduledTask -TaskName '$taskNameLive'" -ForegroundColor DarkYellow
} catch {
    Write-Host "[ERRO] Falha ao registrar $taskNameLive`: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  TAREFAS REGISTRADAS" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Get-ScheduledTask | Where-Object { $_.TaskName -like "CoinexScan*" } | ForEach-Object {
    $state = if ($_.State -eq "Disabled") { "DESABILITADA" } else { $_.State }
    Write-Host ("  {0,-35} [{1}]" -f $_.TaskName, $state) -ForegroundColor White
}
Write-Host ""
Write-Host "Para iniciar o DryRun agora:" -ForegroundColor Cyan
Write-Host "  Start-ScheduledTask -TaskName '$taskNameDry'" -ForegroundColor Yellow
Write-Host ""
Write-Host "Para ativar o Live quando pronto:" -ForegroundColor Cyan
Write-Host "  Enable-ScheduledTask -TaskName '$taskNameLive'" -ForegroundColor Yellow
Write-Host "  Start-ScheduledTask  -TaskName '$taskNameLive'" -ForegroundColor Yellow
Write-Host ""
Write-Host "Para parar:" -ForegroundColor Cyan
Write-Host "  Stop-ScheduledTask -TaskName '$taskNameDry'" -ForegroundColor Yellow
