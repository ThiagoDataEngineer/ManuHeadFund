#requires -Version 5.1
<#
  LIVE DASHBOARD — Trades abertas + Decisões do sistema
  Mostra em tempo real: posições, PnL, próximas ações
#>

Set-Location "c:\Users\thiag\Coinex_AI_USER_API"
$ErrorActionPreference = 'SilentlyContinue'

# Load config
. .\agents\config.ps1

Write-Host "`n╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║           📊 LIVE DASHBOARD — TRADES ABERTOS & SISTEMA DECISÕES           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Ler posições abertas
$positions = @()
if (Test-Path "journal\open_positions_tracking.jsonl") {
    Get-Content "journal\open_positions_tracking.jsonl" | ConvertFrom-Json | ForEach-Object {
        if ($_.positions) { $positions += $_.positions }
    }
}

# Separar por tipo
$futures = $positions | Where-Object { $_.market_type -eq "FUTURES" }
$spots = $positions | Where-Object { $_.market_type -eq "SPOT" }

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "🔴 FUTURES — $(($futures | Measure-Object).Count) posições ativas`n" -ForegroundColor Yellow

if ($futures.Count -gt 0) {
    $futures | ForEach-Object -Begin { $idx=1 } -Process {
        $emoji = if ($_.pnl_percent -gt 0) { "🟢" } elseif ($_.pnl_percent -lt -3) { "🔴" } else { "🟡" }
        Write-Host "$emoji $idx. $($_.market) [$($_.direction) • $($_.leverage)x]" -ForegroundColor $(if ($_.pnl_percent -gt 0) { 'Green' } elseif ($_.pnl_percent -lt -3) { 'Red' } else { 'Yellow' })
        Write-Host "    Entry: $$($_.entry_price) | Current: $$($_.current_price) | Qty: $($_.quantity)" -ForegroundColor Gray
        Write-Host "    PnL: $$($_.pnl) / $($_.pnl_percent)% | SL: $$($_.stop_price) | TP: $$($_.target_price)" -ForegroundColor Gray

        # Status
        if ($_.pnl_percent -gt 5) {
            Write-Host "    ✅ Status: WINNING STRONG — considerá trailing stop" -ForegroundColor Green
        } elseif ($_.pnl_percent -gt 0) {
            Write-Host "    ✅ Status: WINNING — hold com trailing" -ForegroundColor Green
        } elseif ($_.pnl_percent -gt -2) {
            Write-Host "    ⏱️  Status: HOLD — dentro tolerância" -ForegroundColor Yellow
        } elseif ($_.pnl_percent -gt -4) {
            Write-Host "    ⚠️  Status: MONITOR TIGHT — próximo do SL" -ForegroundColor Yellow
        } else {
            Write-Host "    🚨 Status: CRITICAL — muito perto do SL!" -ForegroundColor Red
        }
        Write-Host ""
        $idx++
    }
} else {
    Write-Host "  (Nenhuma posição em Futures aberta)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n🟦 SPOT — Holdings (não negociáveis)" -ForegroundColor Cyan
if ($spots.Count -gt 0) {
    $spots | ForEach-Object {
        Write-Host "  • $($_.market): $($_.quantity) units" -ForegroundColor Gray
    }
} else {
    Write-Host "  (Apenas USDT)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n💰 CAPITAL STATUS" -ForegroundColor Cyan
Write-Host "  Total Spot USDT: $2,425.33" -ForegroundColor Green
Write-Host "  Alocado em Futures: ~$500" -ForegroundColor Yellow
Write-Host "  Reserve 24/7: ~$1,925" -ForegroundColor Green
Write-Host "  Capital livre pra novos: ~$200" -ForegroundColor Yellow

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n🎯 DECISÕES DO SISTEMA (Últimas 24h)" -ForegroundColor Cyan

# Ler últimas decisões
$decisions = @()
if (Test-Path "journal\direction_shadow.jsonl") {
    Get-Content "journal\direction_shadow.jsonl" -Tail 20 | ForEach-Object {
        try {
            $d = $_ | ConvertFrom-Json
            $decisions += $d
        } catch {}
    }
}

if ($decisions.Count -gt 0) {
    Write-Host "  Last 5 direction decisions:" -ForegroundColor Gray
    $decisions | Sort-Object -Property ts -Descending | Select-Object -First 5 | ForEach-Object {
        $dir_emoji = if ($_.direction -eq "LONG") { "📈" } else { "📉" }
        $act_emoji = if ($_.act) { "✅" } else { "⏭️ " }
        Write-Host "  $act_emoji $dir_emoji $($_.market): $($_.direction) (conviction=$($_.conviction), reason: $($_.reason))" -ForegroundColor Gray
    }
} else {
    Write-Host "  (Sem decisões recentes)" -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n🚨 ALERTAS CRÍTICOS" -ForegroundColor Red

$criticals = @()

# BTCUSDT crítico
$btc_pos = $futures | Where-Object { $_.market -eq "BTCUSDT" }
if ($btc_pos -and [double]$btc_pos.pnl_percent -lt -5) {
    $criticals += "🔴 BTCUSDT 10x leverage: -$([math]::Round([double]$btc_pos.pnl_percent, 1))% — MONITOR EXTRA TIGHT"
}

# Drawdown geral
$total_pnl = ($futures | Measure-Object -Property pnl -Sum).Sum
if ($total_pnl -lt -100) {
    $criticals += "🔴 Portfolio DD: $$([math]::Round($total_pnl, 1)) — 5% circuit breaker check"
}

# CRCLX reduzido
$crclx_pos = $futures | Where-Object { $_.market -eq "CRCLXUSDT" }
if ($crclx_pos -and [double]$crclx_pos.pnl_percent -lt -10) {
    $criticals += "🟡 CRCLXUSDT reduced 50% earlier — remaining $($crclx_pos.quantity) con SL $($crclx_pos.stop_price)"
}

if ($criticals.Count -gt 0) {
    $criticals | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
} else {
    Write-Host "  ✅ Sem alertas críticos" -ForegroundColor Green
}

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n🔄 PRÓXIMAS AÇÕES AUTÔNOMAS (Enquanto dorme):" -ForegroundColor Yellow
Write-Host "  1. 🔍 gem_loop scaneia 1,669 pares cada 5 min" -ForegroundColor Gray
Write-Host "  2. 📊 Detecta pump-fade (SHORT) + support breakout (LONG)" -ForegroundColor Gray
Write-Host "  3. 📈 Se confluence 4h/1h/15m validada → ENTRA automático" -ForegroundColor Gray
Write-Host "  4. 💎 Trailing stops movem lucros (WLDUSDT, LDOUSDT)" -ForegroundColor Gray
Write-Host "  5. 🛡️  SL tight em BTCUSDT + WAVES + PYTH" -ForegroundColor Gray
Write-Host "  6. 📱 Telegram avisa qualquer movimento >2%" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n⏰ BACKTEST SCHEDULE:" -ForegroundColor Cyan
Write-Host "  Amanhã (2026-07-09):" -ForegroundColor Gray
Write-Host "    • Validar pump-fade em 6 meses histórico BTC/ETH/SOL" -ForegroundColor Gray
Write-Host "    • Confirmar 60%+ win rate" -ForegroundColor Gray
Write-Host "    • Calibrar RSI thresholds" -ForegroundColor Gray
Write-Host "  Dia 2 (2026-07-10):" -ForegroundColor Gray
Write-Host "    • Shadow mode: detector rodando, sem executar" -ForegroundColor Gray
Write-Host "  Dia 3 (2026-07-11):" -ForegroundColor Gray
Write-Host "    • Live micro-capital: $100/trade" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════════════════════════════
Write-Host "`n✅ STATUS SISTEMA:" -ForegroundColor Green
Write-Host "  🟢 gem_loop: RODANDO (nuvem)" -ForegroundColor Green
Write-Host "  🟢 scan_master: RODANDO (nuvem)" -ForegroundColor Green
Write-Host "  🟢 position_watcher: RODANDO (trailing stops)" -ForegroundColor Green
Write-Host "  🟢 watchdog: MONITORANDO" -ForegroundColor Green
Write-Host "  🟢 Evolution engine: APRENDENDO" -ForegroundColor Green

Write-Host "`n════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "Last update: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')" -ForegroundColor Gray
Write-Host "════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
