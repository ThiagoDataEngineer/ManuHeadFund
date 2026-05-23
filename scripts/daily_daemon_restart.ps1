# daily_daemon_restart.ps1 -- Restart rolling de daemons 03:00 BRT
#
# Resolve drift: daemons que rodam 24h+ nao recarregam config.ps1/libs alteradas.
# Audit 2026-05-20: gem_loop PID 5400 rodou 46h sem restart, perdeu config update
# (sizing 0.2 -> 0.5) e patch path do tech_agent_ai. Score 95 GEM perdido.
#
# Solucao: kill rolling diario. Cada daemon respawna em <60s via watchdog OR
# spawn manual.
#
# Ordem:
#   1. gem_loop (menos critico, mais frequente)
#   2. scan_master (defensivo, vai pra DAILY sleep)
#   3. tg_listener (precisa pra receber commands)
#   4. watchdog_paper (POR ULTIMO, pra nao auto-respawn os outros)
#
# Cron: 03:00 BRT (entre PromotionCron 02:00 e KellyGraduation 02:35)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logDir = Join-Path $projectRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("daemon_restart_" + (Get-Date -Format "yyyyMMdd_HHmm") + ".log")
function Log { param($M) "[$((Get-Date).ToString('HH:mm:ss'))] $M" | Tee-Object -FilePath $logFile -Append }

Log "=== Daily daemon restart START ==="

# FASE 2 fix D (2026-05-21): warmup LLM endpoints ANTES de respawn pra evitar
# cold-start no primeiro cycle (LIDAR null em HYPE/USELESS/ZEC manha 08:32 BRT).
# Async fire-forget: nao bloqueia restart se travar.
$warmupPath = Join-Path $scriptDir "warmup_llm_endpoints.ps1"
if (Test-Path $warmupPath) {
    try {
        Log "Warmup LLM endpoints (async pre-restart)"
        Start-Process powershell.exe -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$warmupPath) `
            -WorkingDirectory $projectRoot -WindowStyle Hidden | Out-Null
    } catch {
        Log "  warmup spawn falhou: $_"
    }
}

$daemons = @(
    @{ name = "gem_loop";       pattern = "*gem_loop.ps1*";       script = "scripts\gem_loop.ps1" },
    @{ name = "scan_master";    pattern = "*scan_master.ps1*";    script = "scripts\scan_master.ps1" },
    @{ name = "tg_listener";    pattern = "*telegram_listener.ps1*"; script = "scripts\telegram_listener.ps1" },
    @{ name = "watchdog_paper"; pattern = "*watchdog_paper.ps1*"; script = "scripts\watchdog_paper.ps1" }
)

foreach ($d in $daemons) {
    Log "[$($d.name)] checking..."
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -like $d.pattern -and $_.CommandLine -notlike "*Get-CimInstance*" })
    foreach ($p in $procs) {
        try {
            $pp = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
            if (-not $pp) { continue }
            $age = [math]::Round(((Get-Date) - $pp.StartTime).TotalHours, 1)
            Log "  Killing PID=$($p.ProcessId) age=${age}h"
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            Log "  Kill PID=$($p.ProcessId) erro: $_"
        }
    }
    Start-Sleep -Seconds 2

    # Respawn with -Force (bypass idempotent guards)
    $scriptPath = Join-Path $projectRoot $d.script
    if (-not (Test-Path $scriptPath)) { Log "  script ausente: $scriptPath"; continue }
    $psArgs = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$scriptPath)
    # gem_loop + watchdog aceitam -Force (idempotent bypass). tg_listener + scan_master nao.
    if ($d.name -eq "gem_loop" -or $d.name -eq "watchdog_paper") { $psArgs += "-Force" }
    try {
        $new = Start-Process powershell.exe -ArgumentList $psArgs -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 5
        $alive = Get-Process -Id $new.Id -ErrorAction SilentlyContinue
        if ($alive) {
            Log "  RESPAWN OK PID=$($new.Id)"
        } else {
            Log "  RESPAWN FAILED (process died)"
        }
    } catch {
        Log "  Spawn erro: $_"
    }
    Start-Sleep -Seconds 3
}

Log "=== Daily daemon restart DONE ==="
