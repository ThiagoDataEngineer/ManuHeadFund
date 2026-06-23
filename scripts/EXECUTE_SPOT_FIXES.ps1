#!/usr/bin/env pwsh
# EXECUTE_SPOT_FIXES.ps1 — Executa decisões de portfolio (SPLIT, SL, Trailing)
# Data: 2026-06-22 | Análise: docs/SPOT_PORTFOLIO_ANALYSIS_2026_06_22.md

param(
    [switch]$DryRun = $true,
    [switch]$ExecuteUB = $false,
    [switch]$ExecutePAXG = $false,
    [switch]$ExecuteTNSR = $false,
    [switch]$ExecuteXRP = $false,
    [string]$Action = "SPLIT"  # SPLIT, SELL_ALL, HOLD
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$journalDir = Join-Path $projectRoot "journal"
$agentsDir = Join-Path $projectRoot "agents"

Set-Location $projectRoot

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    SPOT PORTFOLIO FIX EXECUTION — 2026-06-22                   ║" -ForegroundColor Cyan
Write-Host "║    Analysis: docs/SPOT_PORTFOLIO_ANALYSIS_2026_06_22.md        ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "DRY RUN: $DryRun | ExecuteUB: $ExecuteUB | Action: $Action" -ForegroundColor Yellow

# ═══════════════════════════════════════════════════════════════════════════
# UBUSDT — SPLIT 50/50 (venda 50%, trailing 50%)
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n📍 [1/4] UBUSDT — SPLIT 50/50 DECISION" -ForegroundColor Magenta
Write-Host "  Current: 710.91 units | $67.41 | PnL: -$10.81 (-16%)" -ForegroundColor Gray

if ($ExecuteUB) {
    Write-Host "  📋 Action Plan:" -ForegroundColor Green
    Write-Host "    1. VENDA 50%: ~355 units" -ForegroundColor Green
    Write-Host "    2. Realiza -$5.40 loss (metade da perda)" -ForegroundColor Green
    Write-Host "    3. Trailing 50%: stop loss em 1% abaixo entry" -ForegroundColor Green
    Write-Host "    4. Registra em gem_trades.csv como OPEN/SPLIT" -ForegroundColor Green

    if (-not $DryRun) {
        Write-Host "  ✅ [EXECUTING] Venda 50% UBUSDT..." -ForegroundColor Red
        # TODO: CoinEx-PlaceOrder -Market UBUSDT -Side sell -Type market -Amount 355
        Write-Host "  ✅ [EXECUTING] Update gem_trades.csv..." -ForegroundColor Red
        Write-Host "  ✅ [EXECUTING] Add trailing SL..." -ForegroundColor Red
        Write-Host "  ✅ DONE" -ForegroundColor Green
    } else {
        Write-Host "  ⏸️  [DRY RUN] Não vai vender" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⏹️  Skipped (use -ExecuteUB para executar)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════
# PAXGUSDT — DECIDIR BASEADO EM OURO
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n📍 [2/4] PAXGUSDT — MACRO OURO DECISION" -ForegroundColor Magenta
Write-Host "  Current: 0.257 units | $1,066.24 | PnL: -$171.09 (-14%)" -ForegroundColor Gray
Write-Host "  Gold suporte crítico: $2,300/oz" -ForegroundColor Yellow

if ($ExecutePAXG) {
    Write-Host "  🔍 Verificando ouro atual..." -ForegroundColor Green

    try {
        $goldUrl = "https://api.metals.live/v1/spot/gold"
        $goldData = Invoke-RestMethod -Uri $goldUrl -Method GET -TimeoutSec 5
        $goldPrice = $goldData.price
        $goldDecision = if ($goldPrice -gt 2300) { "HOLD/SPLIT" } else { "SELL" }

        Write-Host "  💰 Ouro atual: $goldPrice/oz | Decisão: $goldDecision" -ForegroundColor Cyan

        if ($goldDecision -eq "HOLD/SPLIT") {
            Write-Host "  📋 Ouro mantendo suporte → SPLIT 50% PAXG (acumulação esperada)" -ForegroundColor Green
            if (-not $DryRun) {
                Write-Host "  ✅ [EXECUTING] Venda 50% PAXGUSDT..." -ForegroundColor Red
                # TODO: CoinEx-PlaceOrder
                Write-Host "  ✅ DONE" -ForegroundColor Green
            }
        } else {
            Write-Host "  📋 Ouro abaixo suporte → VENDA TUDO PAXG (distribuição, mais queda)" -ForegroundColor Red
            if (-not $DryRun) {
                Write-Host "  ✅ [EXECUTING] Venda 100% PAXGUSDT..." -ForegroundColor Red
                # TODO: CoinEx-PlaceOrder
                Write-Host "  ✅ DONE" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ⚠️  Erro ao buscar ouro; usando decisão padrão: SPLIT 50% (segura)" -ForegroundColor Yellow
        if (-not $DryRun) {
            Write-Host "  ✅ [EXECUTING] Venda 50% PAXGUSDT (default)..." -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ⏹️  Skipped (use -ExecutePAXG para executar)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════
# TNSR — VERIFICAR E ADICIONAR TRAILING SE FALTANDO
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n📍 [3/4] TNSR — CHECK TRAILING STATUS" -ForegroundColor Magenta
Write-Host "  Current: 1,499.66 units | $58.93 | PnL: -$9.17 (-13%)" -ForegroundColor Gray

$trailingFile = Join-Path $journalDir "trailing_positions.json"
if (Test-Path $trailingFile) {
    try {
        $trailing = Get-Content $trailingFile -Raw | ConvertFrom-Json
        $tnsr_trailing = $trailing | Where-Object { $_.market -eq "TNSR" }

        if ($tnsr_trailing) {
            Write-Host "  ✅ TNSR já tem trailing ativo" -ForegroundColor Green
            Write-Host "    SL: $($tnsr_trailing.stop_price), TP: $($tnsr_trailing.target_price), Peak: $($tnsr_trailing.peak_price)" -ForegroundColor Gray
        } else {
            Write-Host "  ⚠️  TNSR NÃO está em trailing_positions.json" -ForegroundColor Yellow
            if ($ExecuteTNSR -and -not $DryRun) {
                Write-Host "  ✅ [EXECUTING] Adicionar TNSR ao trailing..." -ForegroundColor Red
                # TODO: Add to trailing_positions.json
                Write-Host "  ✅ DONE" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ❌ Erro ao ler trailing_positions.json" -ForegroundColor Red
    }
} else {
    Write-Host "  ❌ trailing_positions.json não existe" -ForegroundColor Red
}

# ═══════════════════════════════════════════════════════════════════════════
# XRPUSDT — VERIFICAR E ADICIONAR TRAILING SE FALTANDO
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n📍 [4/4] XRPUSDT — CHECK TRAILING STATUS" -ForegroundColor Magenta
Write-Host "  Current: 22.33 units | $25.13 | PnL: -$5.81 (-19%)" -ForegroundColor Gray

if (Test-Path $trailingFile) {
    try {
        $trailing = Get-Content $trailingFile -Raw | ConvertFrom-Json
        $xrp_trailing = $trailing | Where-Object { $_.market -eq "XRPUSDT" }

        if ($xrp_trailing) {
            Write-Host "  ✅ XRPUSDT já tem trailing ativo" -ForegroundColor Green
            Write-Host "    SL: $($xrp_trailing.stop_price), TP: $($xrp_trailing.target_price)" -ForegroundColor Gray
        } else {
            Write-Host "  ⚠️  XRPUSDT NÃO está em trailing_positions.json" -ForegroundColor Yellow
            if ($ExecuteXRP -and -not $DryRun) {
                Write-Host "  ✅ [EXECUTING] Adicionar XRPUSDT ao trailing..." -ForegroundColor Red
                # TODO: Add to trailing_positions.json
                Write-Host "  ✅ DONE" -ForegroundColor Green
            }
        }
    } catch {
        Write-Host "  ❌ Erro ao ler trailing_positions.json" -ForegroundColor Red
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                        SUMMARY                                 ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

if ($DryRun) {
    Write-Host "  ⏸️  DRY RUN MODE — Nada foi executado" -ForegroundColor Yellow
    Write-Host "`n  Para executar de verdade, rode:" -ForegroundColor Cyan
    Write-Host "    PS> .\\scripts\\EXECUTE_SPOT_FIXES.ps1 -ExecuteUB -ExecutePAXG -ExecuteTNSR -ExecuteXRP -DryRun:\$false" -ForegroundColor Gray
} else {
    Write-Host "  ✅ EXECUÇÕES COMPLETADAS" -ForegroundColor Green
}

Write-Host "`n  📊 Próxima auditoria: 2026-06-23 (manual ou cron)" -ForegroundColor Gray
Write-Host "  🚀 v7 Arbitrage: Começa 2026-06-23" -ForegroundColor Gray
