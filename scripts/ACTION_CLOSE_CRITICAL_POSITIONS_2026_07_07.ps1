# ACTION: Close Critical Positions — 2026-07-07 17:45
# Intenção: Liberar capital + reduzir drawdown crítico
# Posições: CRCLXUSDT + PYTHUSDT (ambas >14% drawdown)

Write-Host "╔═══════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  ⚠️  AÇÃO CRÍTICA: FECHAR 2 POSIÇÕES             ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""

Write-Host "POSIÇÕES A FECHAR:" -ForegroundColor Red
Write-Host ""
Write-Host "1. CRCLXUSDT" -ForegroundColor Red
Write-Host "   Entry: 69.10 | Current: 65.49 | PnL: -16.42% (-$7.38)" -ForegroundColor Yellow
Write-Host "   Ação: MARKET SELL" -ForegroundColor Red
Write-Host "   Razão: Sem recuperação clara em BEAR_WEAK + leverage 3x = risco" -ForegroundColor Gray
Write-Host ""

Write-Host "2. PYTHUSDT" -ForegroundColor Red
Write-Host "   Entry: 0.0456 | Current: 0.0434 | PnL: -14.81% (-$6.76)" -ForegroundColor Yellow
Write-Host "   Ação: MARKET SELL" -ForegroundColor Red
Write-Host "   Razão: AI token memecoin + severe dump + leverage 3x = parar loss" -ForegroundColor Gray
Write-Host ""

Write-Host "IMPACTO:" -ForegroundColor Green
Write-Host "  • Capital liberado: ~$40 USD (margin freed)"
Write-Host "  • PnL preservado: $14.14 (ambas positions realizado perda)"
Write-Host "  • Positions restantes: 5 (BTCUSDT, AAVEUSDT, LDOUSDT, WAVESUSDT, WLDUSDT)"
Write-Host "  • Drawdown máximo: -16.42% → -0% (CRCLXUSDT eliminated)"
Write-Host ""

Write-Host "⏰ TIMING CRÍTICO:" -ForegroundColor Cyan
Write-Host "  Próximo 15min — antes de qualquer volatilidade maior" -ForegroundColor Yellow
Write-Host ""

Write-Host "CONFIRMAÇÃO MANUAL:" -ForegroundColor Green
Write-Host "  1. Abrir app CoinEx"
Write-Host "  2. Ir em Futures → CRCLXUSDT"
Write-Host "  3. Click 'Close' → Market Order"
Write-Host "  4. Confirmar (fecha posição inteira 127.39 USDT)"
Write-Host "  5. Repetir para PYTHUSDT (130.23 USDT)"
Write-Host ""

Write-Host "STATUS: ⏳ AGUARDANDO CONFIRMAÇÃO" -ForegroundColor Yellow
