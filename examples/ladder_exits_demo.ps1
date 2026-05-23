# ladder_exits_demo.ps1 - Demonstração de Multi-TP Escalonado
# Rodar: .\examples\ladder_exits_demo.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\..

. ".\agents\config.ps1"
. ".\agents\lib_coinex.ps1"
. ".\agents\lib_multi_tp_ladder.ps1"

Write-Host @"

╔════════════════════════════════════════════════════════╗
║          MULTI-TP LADDER EXITS - DEMO                  ║
╚════════════════════════════════════════════════════════╝

ESTRATÉGIA:
- TP1 (25%): 2x ATR - Recupera capital
- TP2 (35%): 4x ATR - Lucro moderado
- TP3 (25%): 6x ATR - Lucro alto
- TP4 (15%): 10x ATR - Runner (deixa correr)

STOP LOSS DINÂMICO:
- TP1 hit → SL para breakeven
- TP2 hit → SL para TP1
- TP3 hit → SL para TP2

"@ -ForegroundColor Cyan

# ============================================================================
# EXEMPLO 1: Calcular Níveis de TP
# ============================================================================

Write-Host "`n=== EXEMPLO 1: Calcular Níveis de TP ===" -ForegroundColor Yellow

$entryPrice = 100000
$atr = 800
$totalQty = 0.01

Write-Host "Entrada: $$entryPrice" -ForegroundColor White
Write-Host "ATR: $$atr" -ForegroundColor White
Write-Host "Quantidade: $totalQty BTC" -ForegroundColor White

$ladder = Get-LadderExitLevels -EntryPrice $entryPrice -Side "long" `
    -AtrValue $atr -TotalQty $totalQty

Write-Host "`nNíveis Calculados:" -ForegroundColor Cyan
Write-Host "  TP1: $$($ladder.tp1.price) ($($ladder.tp1.qty) BTC = 25%)" -ForegroundColor Green
Write-Host "  TP2: $$($ladder.tp2.price) ($($ladder.tp2.qty) BTC = 35%)" -ForegroundColor Green
Write-Host "  TP3: $$($ladder.tp3.price) ($($ladder.tp3.qty) BTC = 25%)" -ForegroundColor Green
Write-Host "  TP4: $$($ladder.tp4.price) ($($ladder.tp4.qty) BTC = 15%)" -ForegroundColor Green

# ============================================================================
# EXEMPLO 2: Simular Estratégia Completa (Dry Run)
# ============================================================================

Write-Host "`n=== EXEMPLO 2: Estratégia Completa (Dry Run) ===" -ForegroundColor Yellow

$result = Invoke-LadderExitStrategy `
    -Market "BTCUSDT" `
    -EntryPrice 100000 `
    -Side "long" `
    -TotalQty 0.01 `
    -AtrValue 800 `
    -DryRun

if ($result.success) {
    Write-Host "`n✓ Estratégia configurada com sucesso (simulação)" -ForegroundColor Green
} else {
    Write-Host "`n✗ Erro: $($result.error)" -ForegroundColor Red
}

# ============================================================================
# EXEMPLO 3: Monitorar Execução
# ============================================================================

Write-Host "`n=== EXEMPLO 3: Monitorar Execução ===" -ForegroundColor Yellow

Write-Host "Simulando cenários de execução..." -ForegroundColor White

# Cenário 1: Preço atinge TP1
Write-Host "`nCenário 1: Preço @ $$($ladder.tp1.price) (TP1 hit)" -ForegroundColor Cyan
Write-Host "  → SL move para breakeven ($$entryPrice)" -ForegroundColor Yellow

# Cenário 2: Preço atinge TP2
Write-Host "`nCenário 2: Preço @ $$($ladder.tp2.price) (TP2 hit)" -ForegroundColor Cyan
Write-Host "  → SL move para TP1 ($$($ladder.tp1.price))" -ForegroundColor Yellow
Write-Host "  → Lucro protegido: +$([math]::Round((($ladder.tp1.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green

# Cenário 3: Preço atinge TP3
Write-Host "`nCenário 3: Preço @ $$($ladder.tp3.price) (TP3 hit)" -ForegroundColor Cyan
Write-Host "  → SL move para TP2 ($$($ladder.tp2.price))" -ForegroundColor Yellow
Write-Host "  → Lucro protegido: +$([math]::Round((($ladder.tp2.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green

# Cenário 4: Runner continua
Write-Host "`nCenário 4: Preço @ $$($ladder.tp4.price) (TP4 hit)" -ForegroundColor Cyan
Write-Host "  → 15% da posição ainda aberta (runner)" -ForegroundColor Yellow
Write-Host "  → Lucro total: +$([math]::Round((($ladder.tp4.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green

# ============================================================================
# EXEMPLO 4: Comparação com TP Único
# ============================================================================

Write-Host "`n=== EXEMPLO 4: Comparação com TP Único ===" -ForegroundColor Yellow

$singleTpPrice = $entryPrice + ($atr * 4)  # 4x ATR (equivalente a TP2)
$singleTpProfit = (($singleTpPrice - $entryPrice) / $entryPrice) * 100

Write-Host "`nTP Único @ $$singleTpPrice (4x ATR):" -ForegroundColor White
Write-Host "  Lucro: +$([math]::Round($singleTpProfit, 2))%" -ForegroundColor Gray
Write-Host "  Problema: Deixa dinheiro na mesa se preço continua" -ForegroundColor Red

Write-Host "`nLadder Exits:" -ForegroundColor White
Write-Host "  TP1 (25%): +$([math]::Round((($ladder.tp1.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green
Write-Host "  TP2 (35%): +$([math]::Round((($ladder.tp2.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green
Write-Host "  TP3 (25%): +$([math]::Round((($ladder.tp3.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green
Write-Host "  TP4 (15%): +$([math]::Round((($ladder.tp4.price - $entryPrice) / $entryPrice) * 100, 2))%" -ForegroundColor Green
Write-Host "  Vantagem: Protege lucros + deixa runner" -ForegroundColor Green

# Calcular lucro médio ponderado
$avgProfit = (
    ($ladder.tp1.pct * (($ladder.tp1.price - $entryPrice) / $entryPrice)) +
    ($ladder.tp2.pct * (($ladder.tp2.price - $entryPrice) / $entryPrice)) +
    ($ladder.tp3.pct * (($ladder.tp3.price - $entryPrice) / $entryPrice)) +
    ($ladder.tp4.pct * (($ladder.tp4.price - $entryPrice) / $entryPrice))
) * 100

Write-Host "`nLucro Médio Ponderado: +$([math]::Round($avgProfit, 2))%" -ForegroundColor Cyan

# ============================================================================
# RESUMO
# ============================================================================

Write-Host @"

╔════════════════════════════════════════════════════════╗
║                      RESUMO                            ║
╚════════════════════════════════════════════════════════╝

✅ VANTAGENS DO LADDER EXITS:
  • Protege lucros progressivamente
  • Deixa runner para capturar movimentos grandes
  • SL dinâmico (breakeven → TP1 → TP2)
  • Reduz risco de "deixar dinheiro na mesa"
  • Melhor R:R médio que TP único

📊 QUANDO USAR:
  • Trades com alta convicção
  • Mercados com tendência forte
  • Setups com R:R > 3:1
  • GEMs com score > 75

⚠️ QUANDO NÃO USAR:
  • Mercados laterais (range-bound)
  • Baixa liquidez
  • Setups com R:R < 2:1
  • Scalping (timeframes curtos)

🚀 PRÓXIMOS PASSOS:
  1. Testar em paper trading
  2. Ajustar distribuição de % por perfil
  3. Integrar com gem_executor
  4. Backtesting de performance

"@ -ForegroundColor Cyan

Write-Host "Pressione ENTER para sair..." -ForegroundColor DarkGray
Read-Host
