# STATUS_TASKS.ps1
# Mostra status atual das tasks (habilitadas/desabilitadas)

$ErrorActionPreference = "Continue"

$tasks = @(
    "CoinEx_TrailingStop_Monitor",
    "CoinEx_PositionRisk",
    "CoinEx_Update_Dashboard_HTML"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "   STATUS DAS TASKS" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Cyan

$enabled = 0
$disabled = 0
$notFound = 0

foreach ($task in $tasks) {
    try {
        $taskObj = Get-ScheduledTask -TaskName $task -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName $task -ErrorAction Stop
        
        $status = $taskObj.State
        $color = switch ($status) {
            "Ready" { "Green"; $enabled++ }
            "Disabled" { "Yellow"; $disabled++ }
            default { "Gray" }
        }
        
        Write-Host "$task" -ForegroundColor White
        Write-Host "  Status: " -NoNewline
        Write-Host $status -ForegroundColor $color
        
        if ($info.LastRunTime) {
            Write-Host "  Ultima execucao: $($info.LastRunTime)" -ForegroundColor Gray
        }
        
        if ($info.NextRunTime) {
            Write-Host "  Proxima execucao: $($info.NextRunTime)" -ForegroundColor Gray
        }
        
        Write-Host ""
        
    } catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
        Write-Host "$task" -ForegroundColor White
        Write-Host "  Status: " -NoNewline
        Write-Host "NAO ENCONTRADA" -ForegroundColor Red
        Write-Host ""
        $notFound++
    } catch {
        Write-Host "$task" -ForegroundColor White
        Write-Host "  Status: " -NoNewline
        Write-Host "ERRO - $_" -ForegroundColor Red
        Write-Host ""
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   RESUMO" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Habilitadas: " -NoNewline
Write-Host $enabled -ForegroundColor Green
Write-Host "Desabilitadas: " -NoNewline
Write-Host $disabled -ForegroundColor Yellow
Write-Host "Nao encontradas: " -NoNewline
Write-Host $notFound -ForegroundColor Red

Write-Host "`n"

if ($enabled -gt 0 -and $disabled -eq 0) {
    Write-Host "[INFO] Sistema rodando LOCALMENTE" -ForegroundColor Cyan
    Write-Host "Use DESABILITAR_TASKS_LOCAIS.ps1 para passar controle ao GitHub Actions" -ForegroundColor Gray
} elseif ($disabled -gt 0 -and $enabled -eq 0) {
    Write-Host "[INFO] Sistema rodando no GITHUB ACTIONS" -ForegroundColor Cyan
    Write-Host "Use REABILITAR_TASKS_LOCAIS.ps1 para voltar ao controle local" -ForegroundColor Gray
} elseif ($enabled -gt 0 -and $disabled -gt 0) {
    Write-Host "[AVISO] Sistema HIBRIDO (algumas tasks locais, outras no GitHub)" -ForegroundColor Yellow
    Write-Host "Recomendado: escolher um modo (local ou GitHub Actions)" -ForegroundColor Gray
}

Write-Host "`n"
