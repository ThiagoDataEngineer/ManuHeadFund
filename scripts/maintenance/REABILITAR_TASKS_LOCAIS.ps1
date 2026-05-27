# REABILITAR_TASKS_LOCAIS.ps1
# Reabilita tasks locais (usar quando GitHub Actions estiver com problema)
# Use quando quiser voltar a rodar localmente

$ErrorActionPreference = "Stop"

$tasks = @(
    "CoinEx_TrailingStop_Monitor",
    "CoinEx_PositionRisk",
    "CoinEx_Update_Dashboard_HTML"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   REABILITAR TASKS LOCAIS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nMaquina local assumira controle" -ForegroundColor Yellow
Write-Host "Use DESABILITAR_TASKS_LOCAIS.ps1 para reverter`n" -ForegroundColor Gray

$enabled = 0
$notFound = 0
$errors = 0

foreach ($task in $tasks) {
    try {
        $taskObj = Get-ScheduledTask -TaskName $task -ErrorAction Stop
        
        if ($taskObj.State -eq "Ready") {
            Write-Host "[SKIP] $task - ja habilitada" -ForegroundColor DarkGray
        } else {
            Enable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
            Write-Host "[OK]   $task - habilitada" -ForegroundColor Green
            $enabled++
        }
    } catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
        Write-Host "[AVISO] $task - nao encontrada" -ForegroundColor DarkYellow
        $notFound++
    } catch {
        Write-Host "[ERRO] $task - $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   RESULTADO" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Habilitadas: " -NoNewline
Write-Host $enabled -ForegroundColor Green
Write-Host "Nao encontradas: " -NoNewline
Write-Host $notFound -ForegroundColor Yellow
Write-Host "Erros: " -NoNewline
Write-Host $errors -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })

if ($enabled -gt 0) {
    Write-Host "`n[OK] Tasks locais habilitadas com sucesso!" -ForegroundColor Green
    Write-Host "Sistema agora roda localmente" -ForegroundColor Cyan
    Write-Host "`n[AVISO] Lembre-se de desabilitar quando desligar a maquina!" -ForegroundColor Yellow
} elseif ($notFound -eq $tasks.Count) {
    Write-Host "`n[AVISO] Nenhuma task encontrada" -ForegroundColor Yellow
    Write-Host "Talvez as tasks nao estejam configuradas?" -ForegroundColor Gray
} else {
    Write-Host "`n[INFO] Nenhuma mudanca necessaria" -ForegroundColor Cyan
}

Write-Host "`n"
