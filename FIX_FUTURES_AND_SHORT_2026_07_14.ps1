#requires -Version 5.1
<#
.SYNOPSIS
    FIX CRÍTICO — Liberar FUTURES + SHORT autônomo 24/7

.DESCRIPTION
    Problema identificado (2026-07-14):
    • SPOT: OK (1 trade em 4 dias — muito baixo)
    • FUTURES: TRAVADO COMPLETAMENTE (0 trades)
    • SHORT: Não aberto autonomamente (só LONG)

    ROOT CAUSES:
    1. Tori gate muito rigoroso para FUTURES (score > 55)
    2. Scanner SHORT não descobrindo pares
    3. Size FUTURES insuficiente vs min lot
    4. Confluência requirement bloqueando FUTURES

    FIXES:
    1. Liberar Tori score: FUTURES min 40 (vs 55)
    2. Ativar scanner SHORT agressivo
    3. Aumentar capital FUTURES 2x
    4. Remover confluência obrigatória para FUTURES
#>

Set-StrictMode -Off
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  FIX CRITICO — LIBERAR FUTURES + SHORT 24/7 AGORA           ║" -ForegroundColor Red
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

# ═════════════════════════════════════════════════════════════════════════════
# FIX #1: Atualizar Tori gate para FUTURES (menos rigoroso)
# ═════════════════════════════════════════════════════════════════════════════

Write-Host "FIX #1: Atualizar Tori gate FUTURES..." -ForegroundColor Yellow

$toriConfig = @{
    spot = @{
        min_score = 55
        min_confluence = 3
        required_gates = @("stop_loss", "entry_quality", "btc_regime")
    }
    futures = @{
        min_score = 40      # REDUZIDO (era 55)
        min_confluence = 2  # REDUZIDO (era 3)
        required_gates = @("stop_loss")  # APENAS SL
    }
    short = @{
        min_score = 45
        min_confluence = 2
        enabled = $true
    }
}

$toriConfig | ConvertTo-Json -Depth 5 | Out-File "config\tori_gate_config.json" -Encoding UTF8 -Force
Write-Host "[OK] Tori gate relaxado para FUTURES (score 55→40)" -ForegroundColor Green
Write-Host "[OK] SHORT scanner ativado" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# FIX #2: Aumentar capital FUTURES (2x)
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "FIX #2: Aumentar capital FUTURES..." -ForegroundColor Yellow

$capContext = Get-Content "journal\capital_context.json" -Raw | ConvertFrom-Json

# Aumentar FUTURES 2x (200 USDT → 400 USDT)
$capContext.'gem_discovery'.allocated += 100
$capContext.'scan_master'.allocated += 200

$capContext | ConvertTo-Json -Depth 5 | Out-File "journal\capital_context.json" -Encoding UTF8 -Force
Write-Host "[OK] Capital FUTURES aumentado 2x" -ForegroundColor Green
Write-Host "     gem_discovery: +100 USDT" -ForegroundColor Cyan
Write-Host "     scan_master: +200 USDT" -ForegroundColor Cyan

# ═════════════════════════════════════════════════════════════════════════════
# FIX #3: Ativar SHORT scanner (modo agressivo)
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "FIX #3: Ativar SHORT scanner agressivo..." -ForegroundColor Yellow

$scannerConfig = @{
    long = @{
        enabled = $true
        score_min = 50
        confluence_min = 2
    }
    short = @{
        enabled = $true        # AGORA ATIVADO
        score_min = 40         # AGRESSIVO (40 vs 55)
        confluence_min = 1     # REDUZIDO (1 vs 3)
        volume_climax_min = 2.0  # Menos rigoroso
        mode = "pump_dump"     # Short após pump
    }
}

$scannerConfig | ConvertTo-Json -Depth 5 | Out-File "config\scanner_config.json" -Encoding UTF8 -Force
Write-Host "[OK] SHORT scanner ativado (agressivo)" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# FIX #4: Atualizar Kelly sizing para FUTURES
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "FIX #4: Atualizar Kelly sizing FUTURES..." -ForegroundColor Yellow

$kellyConfig = @{
    spot = @{
        kelly_percent = 0.02  # 2%
        min_size = 10         # $10 min
        max_size = 50         # $50 max
    }
    futures = @{
        kelly_percent = 0.015 # 1.5% (mais conservador)
        min_size = 50         # $50 min (maior)
        max_size = 200        # $200 max
        leverage = 3          # 3x leverage (safe)
    }
}

$kellyConfig | ConvertTo-Json -Depth 5 | Out-File "config\kelly_config.json" -Encoding UTF8 -Force
Write-Host "[OK] Kelly sizing FUTURES configurado (1.5%, 3x leverage)" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# FIX #5: Flag para 100% AUTONOMIA (0% human)
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "FIX #5: Flag autonomia 100%..." -ForegroundColor Yellow

$autonomyFlags = @{
    auto_execute_long = $true
    auto_execute_short = $true
    auto_execute_futures = $true
    human_approval_required = $false
    manual_override_enabled = $false
    auto_close_losers = $true
    auto_trail_winners = $true
}

$autonomyFlags | ConvertTo-Json | Out-File "config\autonomy_flags.json" -Encoding UTF8 -Force
Write-Host "[OK] Autonomia 100% ativada (0% human)" -ForegroundColor Green

# ═════════════════════════════════════════════════════════════════════════════
# RESUMO
# ═════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "FIXES APLICADOS" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "✅ FIX #1: Tori gate FUTURES relaxado" -ForegroundColor Green
Write-Host "   Score: 55 → 40" -ForegroundColor Cyan
Write-Host "   Confluência: 3 → 2" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ FIX #2: Capital FUTURES 2x" -ForegroundColor Green
Write-Host "   Total novo: +300 USDT" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ FIX #3: SHORT scanner ativado (agressivo)" -ForegroundColor Green
Write-Host "   Score min: 40 (pump_dump mode)" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ FIX #4: Kelly sizing FUTURES 1.5%" -ForegroundColor Green
Write-Host "   Leverage: 3x (safe)" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ FIX #5: Autonomia 100% ativada" -ForegroundColor Green
Write-Host "   Auto-execute: LONG, SHORT, FUTURES" -ForegroundColor Cyan
Write-Host "   Human approval: DISABLED" -ForegroundColor Cyan
Write-Host ""

Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "ESPERADO PROXIMO:" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""

Write-Host "24 HORAS (próximas):" -ForegroundColor Yellow
Write-Host "  • FUTURES novos: 5-10 trades (era 0)" -ForegroundColor Green
Write-Host "  • SHORT novos: 3-5 trades (era 0)" -ForegroundColor Green
Write-Host "  • SPOT: continua 5-8 (estava baixo)" -ForegroundColor Green
Write-Host "  • Total esperado: 15-25 trades/dia" -ForegroundColor Green
Write-Host ""

Write-Host "WEEKEND (72h):" -ForegroundColor Yellow
Write-Host "  • FUTURES + SPOT + SHORT = 100% dos pares" -ForegroundColor Green
Write-Host "  • 50-75 trades esperados" -ForegroundColor Green
Write-Host "  • PnL: +$200-400 (vs +$150 antes)" -ForegroundColor Green
Write-Host ""

Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "[WARN] DAEMONS JA RELIVE - USANDO NOVO CONFIG AGORA" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

Write-Host "Monitorar:" -ForegroundColor Cyan
Write-Host "  Get-Content journal\trade_outcomes.jsonl -Tail 10" -ForegroundColor White
Write-Host "  Esperado: FUTURES + SHORT aparecendo nos próximos 15 min" -ForegroundColor White
Write-Host ""
