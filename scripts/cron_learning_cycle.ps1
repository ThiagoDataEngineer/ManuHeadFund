# cron_learning_cycle.ps1 — Ciclo de Aprendizado Noturno
# Executa: 23:00 BRT diariamente (via Task Scheduler)
# Função: Analisar trades do dia, calibrar parametros, registrar evolução

param(
    [switch]$DryRun,    # Apenas relata propostas sem aplicar
    [int]$Hours = 24    # Quantas horas de histórico analisar
)

$ErrorActionPreference = "Continue"

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$agentsDir = Join-Path $scriptDir "..\agents"
$journalDir = Join-Path $scriptDir "..\journal"

# Carrega engines
. (Join-Path $agentsDir "config.ps1")
. (Join-Path $agentsDir "lib_learning_engine.ps1")
. (Join-Path $agentsDir "lib_evolution_engine.ps1")
. (Join-Path $agentsDir "lib_learning_integration.ps1")
. (Join-Path $agentsDir "lib_telegram.ps1")

$global:JOURNAL_DIR = $journalDir

Write-Host "
╔════════════════════════════════════════════════════════════════╗
║ CRON: CICLO DE APRENDIZADO NOTURNO                            ║
║ Timestamp: $(Get-Date -Format 'u')                  ║
╚════════════════════════════════════════════════════════════════╝
" -ForegroundColor Cyan

# ────────────────────────────────────────────────────────────────
# 1. ANÁLISE DE TRADES DO DIA
# ────────────────────────────────────────────────────────────────

Write-Host "`n[1] Analisando trades do dia..." -ForegroundColor Yellow

$learningPath = Join-Path $journalDir "learning_evolution.jsonl"
if (Test-Path $learningPath) {
    $all = @(Get-Content $learningPath | ConvertFrom-Json -ErrorAction SilentlyContinue)

    $today = (Get-Date).Date
    $todayRecords = @($all | Where-Object {
        try { [datetime]$_.timestamp -ge $today } catch { $false }
    })

    $entries = @($todayRecords | Where-Object { $_.type -eq "entry" })
    $exits = @($todayRecords | Where-Object { $_.type -eq "exit" })

    Write-Host "    Entries: $($entries.Count) | Exits: $($exits.Count)" -ForegroundColor Cyan

    if ($exits.Count -gt 0) {
        $winCount = @($exits | Where-Object { $_.outcome -eq "win" }).Count
        $lossCount = @($exits | Where-Object { $_.outcome -eq "loss" }).Count
        $winRate = [math]::Round($winCount / $exits.Count * 100, 1)

        Write-Host "    Win rate: $winRate% ($winCount W / $lossCount L)" -ForegroundColor $(if ($winRate -ge 50) { "Green" } else { "Red" })

        # Detecção de padrões de loss
        if ($lossCount -ge 3) {
            Write-Host "    ⚠️  Sequência de 3+ losses detectada — ajustar parametros" -ForegroundColor Yellow
        }

        # PnL do dia
        $dailyPnL = ($exits | Measure-Object -Property pnl_usd -Sum).Sum
        Write-Host "    PnL do dia: `$$([math]::Round($dailyPnL, 2))" -ForegroundColor $(if ($dailyPnL -ge 0) { "Green" } else { "Red" })
    }
} else {
    Write-Host "    ❌ learning_evolution.jsonl não encontrado" -ForegroundColor Red
}

# ────────────────────────────────────────────────────────────────
# 2. ANÁLISE DE ERROS NOS LOGS
# ────────────────────────────────────────────────────────────────

Write-Host "`n[2] Analisando erros/bloqueios..." -ForegroundColor Yellow

$gemLoopPath = Join-Path $journalDir "..\logs\gem_loop.log"
if (Test-Path $gemLoopPath) {
    $errorAnalysis = Read-CloudErrorLog -LogPath $gemLoopPath -Hours $Hours

    Write-Host "    Error rate: $($errorAnalysis.error_rate)%" -ForegroundColor $(if ($errorAnalysis.error_rate -le 5) { "Green" } else { "Red" })

    if ($errorAnalysis.errors.Count -gt 0) {
        # Agrupar por categoria
        $byReason = $errorAnalysis.errors | Group-Object -Property reason | Sort-Object -Property Count -Descending | Select-Object -First 5

        Write-Host "    Top erros:" -ForegroundColor Yellow
        $byReason | ForEach-Object {
            Write-Host "      • $($_.Name): $($_.Count)x" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "    ⚠️  gem_loop.log não encontrado (OK em primeiro run)" -ForegroundColor Gray
}

# ────────────────────────────────────────────────────────────────
# 3. PROPOSTAS DE EVOLUÇÃO
# ────────────────────────────────────────────────────────────────

Write-Host "`n[3] Calculando propostas de evolução..." -ForegroundColor Yellow

$current = Get-EvolutionParams
Write-Host "    Parametros atuais:" -ForegroundColor Cyan
$current.PSObject.Properties | ForEach-Object {
    Write-Host "      • $($_.Name) = $($_.Value)" -ForegroundColor Gray
}

# TODO: Integrar com Get-EvolutionProposals quando fixtures forem reais
Write-Host "    (Propostas ATIVAS em 2026-07-08)" -ForegroundColor Yellow

# ────────────────────────────────────────────────────────────────
# 4. SNAPSHOT DIÁRIO
# ────────────────────────────────────────────────────────────────

Write-Host "`n[4] Registrando snapshot diário..." -ForegroundColor Yellow

$snapshotPath = Join-Path $journalDir "learning_daily_snapshots.jsonl"
$snapshot = @{
    date = (Get-Date).ToString("yyyy-MM-dd")
    timestamp = (Get-Date).ToString("u")
    trades_count = $exits.Count
    win_count = $winCount
    loss_count = $lossCount
    win_rate = $winRate
    daily_pnl = $dailyPnL
    error_rate = $errorAnalysis.error_rate
} | ConvertTo-Json -Compress

try {
    Add-Content -Path $snapshotPath -Value $snapshot -Encoding UTF8 -ErrorAction Stop
    Write-Host "    ✅ Snapshot registrado" -ForegroundColor Green
} catch {
    Write-Host "    ❌ Falha ao registrar snapshot: $($_.Exception.Message)" -ForegroundColor Red
}

# ────────────────────────────────────────────────────────────────
# 5. ALERTAS TELEGRAM (resumo diário)
# ────────────────────────────────────────────────────────────────

Write-Host "`n[5] Enviando resumo para Telegram..." -ForegroundColor Yellow

$tgMsg = @"
📊 **RESUMO APRENDIZADO NOTURNO**
Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm')

**Trades:**
  • Entradas: $($entries.Count)
  • Saídas: $($exits.Count)
  • Win rate: $winRate%

**Performance:**
  • PnL: `$$([math]::Round($dailyPnL, 2))
  • Error rate: $($errorAnalysis.error_rate)%

**Próximo ciclo:** 23:00 BRT
"@

try {
    Send-TelegramAlert -Message $tgMsg -ParseMode "Markdown"
    Write-Host "    ✅ Alerta enviado" -ForegroundColor Green
} catch {
    Write-Host "    ⚠️  Falha ao enviar alerta (OK): $($_.Exception.Message)" -ForegroundColor Gray
}

# ────────────────────────────────────────────────────────────────
# FINALIZAÇÃO
# ────────────────────────────────────────────────────────────────

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║ CICLO DE APRENDIZADO CONCLUÍDO                                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

exit 0
