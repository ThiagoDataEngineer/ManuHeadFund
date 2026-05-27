# DESABILITAR_TASKS_LOCAIS.ps1
# Desabilita tasks locais para evitar conflito com GitHub Actions
# Use quando quiser que GitHub Actions assuma 100% do controle

$ErrorActionPreference = "Stop"

$tasks = @(
    "CoinEx_TrailingStop_Monitor",
    "CoinEx_PositionRisk",
    "CoinEx_Update_Dashboard_HTML"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   DESABILITAR TASKS LOCAIS" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`nGitHub Actions assumira controle total" -ForegroundColor Yellow
Write-Host "Use REABILITAR_TASKS_LOCAIS.ps1 para reverter`n" -ForegroundColor Gray

$disabled = 0
$notFound = 0
$errors = 0

foreach ($task in $tasks) {
    try {
        $taskObj = Get-ScheduledTask -TaskName $task -ErrorAction Stop
        
        if ($taskObj.State -eq "Disabled") {
            Write-Host "[SKIP] $task - ja desabilitada" -ForegroundColor DarkGray
        } else {
            Disable-ScheduledTask -TaskName $task -ErrorAction Stop | Out-Null
            Write-Host "[OK]   $task - desabilitada" -ForegroundColor Green
            $disabled++
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
Write-Host "Desabilitadas: " -NoNewline
Write-Host $disabled -ForegroundColor Green
Write-Host "Nao encontradas: " -NoNewline
Write-Host $notFound -ForegroundColor Yellow
Write-Host "Erros: " -NoNewline
Write-Host $errors -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Green" })

if ($disabled -gt 0) {
    Write-Host "`n[OK] Tasks locais desabilitadas com sucesso!" -ForegroundColor Green
    Write-Host "Sistema agora roda 100% no GitHub Actions" -ForegroundColor Cyan
} elseif ($notFound -eq $tasks.Count) {
    Write-Host "`n[AVISO] Nenhuma task encontrada" -ForegroundColor Yellow
    Write-Host "Talvez as tasks nao estejam configuradas?" -ForegroundColor Gray
} else {
    Write-Host "`n[INFO] Nenhuma mudanca necessaria" -ForegroundColor Cyan
}

Write-Host "`n"
