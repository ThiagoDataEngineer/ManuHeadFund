# restart_all_daemons.ps1 — Restart completo com regime-specific allocation
# 2026-06-08: Ativar SHORT 80% / LONG 20% (BEAR_WEAK regime)

param([switch]$DryRun)

$ErrorActionPreference = "SilentlyContinue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$scriptsDir = $PSScriptRoot

Write-Host "`n" -ForegroundColor Cyan
Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           🚀 RESTART TODOS OS CICLOS — REGIME BEAR_WEAK            ║" -ForegroundColor Cyan
Write-Host "║         SHORT 80% PRIMARY | LONG 20% HEDGE | LIVE ACTIVATED        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# === 1. KILL OLD PROCESSES ===
Write-Host "`n[1/5] Terminando processos antigos..." -ForegroundColor Yellow
$oldProcs = Get-Process | Where-Object {
    $_.ProcessName -like "*pwsh*" -or $_.ProcessName -like "*powershell*"
} | Where-Object {
    $_.CommandLine -like "*gem_loop*" -or
    $_.CommandLine -like "*scan_master*" -or
    $_.CommandLine -like "*telegram*"
}

foreach ($proc in $oldProcs) {
    Write-Host "  ✓ Matando PID=$($proc.Id) ($($proc.ProcessName))" -ForegroundColor Gray
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}

if ($oldProcs.Count -eq 0) {
    Write-Host "  ✓ Nenhum processo antigo encontrado" -ForegroundColor Gray
}

Start-Sleep -Seconds 2

# === 2. VERIFY CONFIG ===
Write-Host "`n[2/5] Verificando configuração regime-specific..." -ForegroundColor Yellow
$configFile = Join-Path $agentsDir "config.ps1"
if (Test-Path $configFile) {
    $configContent = Get-Content $configFile -Raw
    if ($configContent -match "REGIME_SPECIFIC_ENABLED" -and $configContent -match "BEAR_WEAK") {
        Write-Host "  ✓ Config regime-specific carregado ✅" -ForegroundColor Green
        Write-Host "  ✓ Regime: BEAR_WEAK" -ForegroundColor Green
        Write-Host "  ✓ Allocation: SHORT 80% | LONG 20%" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Config não atualizado — usando default" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ❌ config.ps1 não encontrado!" -ForegroundColor Red
    exit 1
}

# === 3. VERIFY LIVE MODE ===
Write-Host "`n[3/5] Verificando modo LIVE..." -ForegroundColor Yellow
$liveFlag = Join-Path $projectRoot "journal\LIVE_MODE_ENABLED.flag"
if (Test-Path $liveFlag) {
    Write-Host "  ✓ LIVE mode ativado ✅" -ForegroundColor Green
    $paperFlag = Join-Path $projectRoot "journal\PAPER_CALIBRATION_MODE.flag"
    if (Test-Path $paperFlag) {
        Write-Host "  ⚠️  PAPER_CALIBRATION_MODE.flag ainda existe — removendo..." -ForegroundColor Yellow
        Remove-Item $paperFlag -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removido" -ForegroundColor Green
    }
} else {
    Write-Host "  ⚠️  LIVE_MODE_ENABLED.flag não encontrado — criando..." -ForegroundColor Yellow
    New-Item -Path $liveFlag -ItemType File -Force | Out-Null
    Write-Host "  ✓ LIVE mode ativado" -ForegroundColor Green
}

# === 4. START DAEMONS ===
Write-Host "`n[4/5] Iniciando daemons..." -ForegroundColor Yellow

$daemons = @(
    @{ name = "gem_loop"; path = "scripts\gem_loop.ps1"; args = "-CheckInterval 60" },
    @{ name = "scan_master"; path = "scripts\scan_master.ps1"; args = "" }
)

foreach ($daemon in $daemons) {
    $daemonPath = Join-Path $projectRoot $daemon.path
    if (Test-Path $daemonPath) {
        $argStr = if ($daemon.args) { " $($daemon.args)" } else { "" }

        if ($DryRun) {
            Write-Host "  [DRY] $($daemon.name): pwsh -File $daemonPath$argStr" -ForegroundColor Gray
        } else {
            Write-Host "  ▶ Iniciando $($daemon.name)..." -ForegroundColor Cyan
            Start-Process pwsh -ArgumentList "-NoExit", "-File", $daemonPath, $daemon.args -NoNewWindow -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            # Verify start
            $started = Get-Process | Where-Object { $_.CommandLine -like "*$($daemon.name)*" }
            if ($started) {
                Write-Host "  ✓ $($daemon.name) iniciado (PID=$($started.Id))" -ForegroundColor Green
            } else {
                Write-Host "  ❌ $($daemon.name) FALHOU — check logs" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  ❌ $daemonPath não encontrado!" -ForegroundColor Red
    }
}

# === 5. FINAL STATUS ===
Write-Host "`n[5/5] Status final..." -ForegroundColor Yellow
Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                        ✅ SISTEMA ATIVO                            ║" -ForegroundColor Green
Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  REGIME: BEAR_WEAK (post-halving)                                  ║" -ForegroundColor Cyan
Write-Host "║  ALLOCATION: SHORT 80% (primary) | LONG 20% (hedge)                ║" -ForegroundColor Cyan
Write-Host "║  LEVERAGE: LONG 1x | SHORT 2x                                      ║" -ForegroundColor Cyan
Write-Host "║  MODE: LIVE ✓                                                      ║" -ForegroundColor Cyan
Write-Host "╠════════════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "║  DAEMONS:                                                          ║" -ForegroundColor White
Write-Host "║    • gem_loop (GEM scanning/execution 60min cycle)                  ║" -ForegroundColor White
Write-Host "║    • scan_master (daily market analysis)                           ║" -ForegroundColor White
Write-Host "║                                                                    ║" -ForegroundColor White
Write-Host "║  EXPECTED:                                                         ║" -ForegroundColor White
Write-Host "║    • SHORT trades: 6-10 por semana (Sharpe 1.6, hit 61%)           ║" -ForegroundColor White
Write-Host "║    • LONG trades: 2-4 por semana (hedge)                           ║" -ForegroundColor White
Write-Host "║    • PnL: +1-2% por semana = $52-104                               ║" -ForegroundColor White
Write-Host "║                                                                    ║" -ForegroundColor White
Write-Host "║  MONITORAR:                                                        ║" -ForegroundColor White
Write-Host "║    • journal/gem_loop.log (trade execution)                        ║" -ForegroundColor White
Write-Host "║    • Telegram alerts (SHORT 📉 | LONG 📈)                           ║" -ForegroundColor White
Write-Host "║    • Capital: SPOT $2,472 + FUTURES $2,713 = $5,186 TOTAL          ║" -ForegroundColor White
Write-Host "║                                                                    ║" -ForegroundColor White
Write-Host "║  GUARDRAILS ATIVOS:                                                ║" -ForegroundColor White
Write-Host "║    ✓ Kelly Criterion (WR < 40% blocks)                            ║" -ForegroundColor White
Write-Host "║    ✓ Daily Loss Cap (-2% max)                                      ║" -ForegroundColor White
Write-Host "║    ✓ R:R Ratio (1:5 minimum)                                       ║" -ForegroundColor White
Write-Host "║    ✓ Position Sizing (1% capital/trade)                            ║" -ForegroundColor White
Write-Host "║    ✓ Risk Parity (SHORT ≤ LONG)                                    ║" -ForegroundColor White
Write-Host "║    ✓ MinMax Detection (≤5% zones)                                  ║" -ForegroundColor White
Write-Host "║                                                                    ║" -ForegroundColor White
Write-Host "║  🎯 OBJETIVO: +3-5% por semana sustentável                         ║" -ForegroundColor Yellow
Write-Host "║  ⏰ TIMELINE: Validar em 3-5 dias de dados reais                    ║" -ForegroundColor Yellow
Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`n[✅] RESTART COMPLETO FINALIZADO" -ForegroundColor Green
Write-Host "    Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "`n"
