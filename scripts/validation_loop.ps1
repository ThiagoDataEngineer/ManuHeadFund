# validation_loop.ps1 - Loop leve para validacao Opcao 2
# Roda apenas: Update-TrailingStopsAdaptive + Update-MentorReview + Update-Layer4Review + Write-ValidationSnapshot
# Sem orchestrator, sem gem scan, sem trade abertura. Apenas observa e loga.
#
# Uso:
#   .\scripts\validation_loop.ps1                      # roda continuo (15min)
#   .\scripts\validation_loop.ps1 -IntervalMin 5       # custom interval
#   .\scripts\validation_loop.ps1 -Once                # uma vez e sai

param(
    [int]    $IntervalMin = 15,
    [switch] $Once
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"

# Carregar dependencias minimas
. (Join-Path $agentsDir "constants_loader.ps1")
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_coinex.ps1")
. (Join-Path $agentsDir "lib_macro.ps1")
. (Join-Path $agentsDir "lib_indicators.ps1")
. (Join-Path $agentsDir "lib_trailing.ps1")
. (Join-Path $agentsDir "lib_trailing_adaptive.ps1")
. (Join-Path $agentsDir "lib_mentor_reflection.ps1")
. (Join-Path $agentsDir "lib_layer4_tori_timestop.ps1")
. (Join-Path $agentsDir "lib_validation_logger.ps1")

# Lock idempotente (evita 2 loops simultaneos)
$myPid = $PID
try {
    $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like "*validation_loop*" -and $_.ProcessId -ne $myPid })
    $aliveOthers = @($others | Where-Object {
        $null -ne (Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue)
    })
    if ($aliveOthers.Count -gt 0) {
        Write-Host "[SKIP] Outro validation_loop ja rodando (PID=$($aliveOthers[0].ProcessId)); este PID=$myPid exit." -ForegroundColor Yellow
        exit 0
    }
} catch {}

Write-Host "[ValidationLoop] Iniciado - intervalo=${IntervalMin}min" -ForegroundColor Cyan

do {
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host ""
    Write-Host "[$ts] === Validation Cycle ===" -ForegroundColor DarkCyan

    try { Update-TrailingStopsAdaptive } catch { Write-Host "  [WARN] trailing: $_" -ForegroundColor Yellow }
    try { Update-MentorReview }          catch { Write-Host "  [WARN] mentor: $_"   -ForegroundColor Yellow }
    try { Update-Layer4Review }          catch { Write-Host "  [WARN] layer4: $_"   -ForegroundColor Yellow }
    try { Write-ValidationSnapshot }     catch { Write-Host "  [WARN] snapshot: $_" -ForegroundColor Yellow }

    # Verifica se a run foi finalizada
    $stateFile = Join-Path $agentsDir "..\journal\validation_run.json"
    if (Test-Path $stateFile) {
        try {
            $st = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($st.closed) {
                Write-Host "[ValidationLoop] Run encerrada (1a posicao fechou: $($st.firstClosedMarket)). Saindo." -ForegroundColor Magenta
                break
            }
        } catch { }
    }

    if ($Once) { break }

    Write-Host "[$ts] Dormindo ${IntervalMin}min ate proximo ciclo..." -ForegroundColor DarkGray
    Start-Sleep -Seconds ($IntervalMin * 60)

} while ($true)

Write-Host "[ValidationLoop] Finalizado." -ForegroundColor Cyan
