# activate_short_and_evolution.ps1 — Ativa SHORT + Evolution Engine
# 2026-07-05

param([switch]$DryRun)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$agentsDir = Join-Path $projectRoot "agents"
$journalDir = Join-Path $projectRoot "journal"

Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ ATIVAÇÃO: SHORT Scanner + Evolution Engine Auto-Rebalance ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

# ════════════════════════════════════════════════════════════════════════════
# PARTE A: Ativar SHORT Scanner daemon
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n🔴 PARTE A: SHORT Scanner Daemon" -ForegroundColor Yellow

$shortObsFlag = Join-Path $journalDir "SHORT_OBSERVATORY_ENABLED.flag"
if (-not (Test-Path $shortObsFlag)) {
    if (-not $DryRun) {
        "" | Out-File $shortObsFlag -Encoding UTF8
        Write-Host "✅ Flag SHORT_OBSERVATORY_ENABLED criada" -ForegroundColor Green
    }
}

Write-Host "`n🚀 Iniciando short_scanner.ps1 em background..." -ForegroundColor Cyan
if (-not $DryRun) {
    $shortScannerScript = Join-Path $PSScriptRoot "short_scanner.ps1"
    if (Test-Path $shortScannerScript) {
        Start-Process -FilePath "powershell" -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-File", $shortScannerScript -ErrorAction SilentlyContinue
        Write-Host "✅ short_scanner.ps1 iniciado" -ForegroundColor Green
    }
}

# ════════════════════════════════════════════════════════════════════════════
# PARTE B: Evolution Engine Auto-Rebalance
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n🧬 PARTE B: Evolution Engine Auto-Rebalance" -ForegroundColor Yellow

. (Join-Path $agentsDir "lib_evolution_autonomous_rebalance.ps1")

Write-Host "`n▶️  Invocando Invoke-EvolutionAutoRebalance..." -ForegroundColor Cyan

if (-not $DryRun) {
    $evoResult = Invoke-EvolutionAutoRebalance
    if ($evoResult) {
        Write-Host "`n✅ Evolution Engine: REBALANCEAMENTO EXECUTADO" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Evolution Engine: Métricas OK, nenhum rebalanceamento necessário" -ForegroundColor Yellow
    }
}

# ════════════════════════════════════════════════════════════════════════════
# RESUMO
# ════════════════════════════════════════════════════════════════════════════

Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ RESUMO                                                   ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`n✅ Ativações:" -ForegroundColor Green
Write-Host "   • SHORT Scanner: Procura vol_climax 2.5x + RSI overbought" -ForegroundColor Gray
Write-Host "   • Evolution Engine: Consulta 4 mentores se frequência baixa" -ForegroundColor Gray
Write-Host "   • Efeito: Mais SHORT entries em BEAR_WEAK + auto-gates relaxados" -ForegroundColor Gray

Write-Host "`n📊 Monitorar:" -ForegroundColor Yellow
Write-Host "   journal/short_alerts.jsonl" -ForegroundColor Gray
Write-Host "   journal/decisions_text.jsonl" -ForegroundColor Gray
Write-Host "   journal/evolution_rebalances.jsonl" -ForegroundColor Gray

Write-Host "`n✅ PRONTO!" -ForegroundColor Green
