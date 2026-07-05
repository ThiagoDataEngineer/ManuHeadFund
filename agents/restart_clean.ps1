# restart_clean.ps1 — Restart limpo dos daemons com validação
# Propósito: Remove jobs/locks antigos, carrega código novo, inicia frota
# Uso: .\restart_clean.ps1

param(
    [switch] $DryRun,           # Mostra ações sem executar
    [switch] $Force,            # Força stop de daemons sem graceful shutdown
    [int] $TimeoutSeconds = 30  # Timeout pra graceful shutdown
)

$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "╔════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RESTART CLEAN — $(Get-Date -Format 'HH:mm:ss')                         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ─────────────────────────────────────────────────────────────────────────────
# FASE 1: Kill gracefully ou forcefully
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[1/5] Parando daemons..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "      (DRY RUN: sem ações)" -ForegroundColor Yellow
} else {
    # Stop gracefully primeiro
    $daemon_names = @("gem_loop", "scan_master", "tg_listener", "watchdog", "faro_scheduler")
    foreach ($name in $daemon_names) {
        $procs = Get-Process | Where-Object { $_.ProcessName -like "*$name*" -or $_.CommandLine -like "*$name*" }
        if ($procs) {
            Write-Host "   → Parando $name..." -ForegroundColor Gray
            $procs | Stop-Process -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2

    # Force kill se ainda rodar
    if ($Force) {
        Write-Host "   → Forcefully killing any remaining PowerShell..." -ForegroundColor Yellow
        Get-Process pwsh, powershell -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -ne $PID } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 2: Remove lock files
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[2/5] Limpando lock files..." -ForegroundColor Cyan

$journal_dir = "c:\Users\thiag\Coinex_AI_USER_API\journal"
$lock_patterns = @("*.lock", "*_daemon_*.state")

foreach ($pattern in $lock_patterns) {
    $locks = Get-ChildItem "$journal_dir\$pattern" -ErrorAction SilentlyContinue
    if ($locks) {
        foreach ($lock in $locks) {
            Write-Host "   → Removendo $($lock.Name)..." -ForegroundColor Gray
            if (-not $DryRun) {
                Remove-Item $lock.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 3: Limpar jobs PowerShell
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] Limpando jobs PowerShell..." -ForegroundColor Cyan

$jobs = Get-Job -ErrorAction SilentlyContinue
if ($jobs) {
    Write-Host "   → Encontrados $($jobs.Count) job(s), removendo..." -ForegroundColor Gray
    if (-not $DryRun) {
        $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "   → Nenhum job pra limpar" -ForegroundColor Gray
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 4: Validar código
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[4/5] Validando código..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "      (DRY RUN: validação pulada)" -ForegroundColor Yellow
} else {
    $agents_dir = "c:\Users\thiag\Coinex_AI_USER_API\agents"
    cd $agents_dir

    # Verificar gem_agent
    try {
        . ".\gem_agent.ps1" -ErrorAction Stop 2>$null
        if (Get-Command Get-PumpPhase -ErrorAction SilentlyContinue) {
            Write-Host "   ✓ gem_agent.ps1 OK (Get-PumpPhase loaded)" -ForegroundColor Green
        } else {
            Write-Host "   ⚠️  gem_agent.ps1 loaded but Get-PumpPhase missing" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   ✗ ERRO ao carregar gem_agent.ps1" -ForegroundColor Red
        Write-Host "      $_" -ForegroundColor Red
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FASE 5: Start fleet
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] Iniciando frota..." -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "      (DRY RUN: sem start)" -ForegroundColor Yellow
    Write-Host "`n→ Para executar de verdade, rode sem -DryRun" -ForegroundColor Yellow
} else {
    $start_script = "c:\Users\thiag\Coinex_AI_USER_API\scripts\start_fleet.ps1"
    if (Test-Path $start_script) {
        Write-Host "   → Executando start_fleet.ps1..." -ForegroundColor Gray
        & $start_script
        Write-Host "   ✓ Frota iniciada" -ForegroundColor Green
    } else {
        Write-Host "   ✗ start_fleet.ps1 não encontrado!" -ForegroundColor Red
        exit 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "✓ DRY RUN COMPLETO — nenhuma ação executada" -ForegroundColor Green
} else {
    Write-Host "✓ RESTART LIMPO COMPLETO" -ForegroundColor Green
}
Write-Host "════════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`nProximos passos:" -ForegroundColor Gray
Write-Host "  1. Verificar logs: Get-Content journal/master_*.log -Tail 20" -ForegroundColor Gray
Write-Host "  2. Monitorar reversal: Get-Content journal/reversal_watch_log.jsonl | tail" -ForegroundColor Gray
Write-Host "  3. Conferir pings: Invoke-RestMethod http://localhost:8080/health" -ForegroundColor Gray
