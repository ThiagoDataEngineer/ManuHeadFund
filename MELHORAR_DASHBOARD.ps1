# MELHORAR_DASHBOARD.ps1
# Adicionar informacoes importantes ao dashboard
# 2026-05-24

Write-Host "=== MELHORIAS PARA O DASHBOARD ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "INFORMACOES FALTANDO NO DASHBOARD ATUAL:" -ForegroundColor Yellow
Write-Host ""

Write-Host "1. METRICAS DE TRADING (24h/7d/30d):" -ForegroundColor White
Write-Host "   • Numero de trades executados" -ForegroundColor Gray
Write-Host "   • Taxa de acerto (win rate)" -ForegroundColor Gray
Write-Host "   • Profit factor" -ForegroundColor Gray
Write-Host "   • Sharpe ratio" -ForegroundColor Gray
Write-Host "   • Max drawdown" -ForegroundColor Gray
Write-Host "   • Melhor/pior trade" -ForegroundColor Gray
Write-Host ""

Write-Host "2. DECISOES DO MENTOR:" -ForegroundColor White
Write-Host "   • Total de analises (24h)" -ForegroundColor Gray
Write-Host "   • Taxa de aprovacao vs veto" -ForegroundColor Gray
Write-Host "   • Principais razoes de veto" -ForegroundColor Gray
Write-Host "   • Ultimas 10 decisoes" -ForegroundColor Gray
Write-Host ""

Write-Host "3. MESA (3 DRONES):" -ForegroundColor White
Write-Host "   • Consensus atual (FORTE/MEDIO/CAOS)" -ForegroundColor Gray
Write-Host "   • Score medio dos drones" -ForegroundColor Gray
Write-Host "   • Drones degraded (timeouts)" -ForegroundColor Gray
Write-Host "   • Ultimas analises" -ForegroundColor Gray
Write-Host ""

Write-Host "4. REGIME DE MERCADO:" -ForegroundColor White
Write-Host "   • Regime atual (BULL_STRONG/BULL_WEAK/BEAR/SIDEWAYS)" -ForegroundColor Gray
Write-Host "   • Ciclo (EARLY/MID/LATE)" -ForegroundColor Gray
Write-Host "   • MCE score (contexto favoravel/desfavoravel)" -ForegroundColor Gray
Write-Host "   • Tori proximity (distancia do topo)" -ForegroundColor Gray
Write-Host ""

Write-Host "5. PIPELINE DE PROMOCAO:" -ForegroundColor White
Write-Host "   • Ativos em DISCOVERY" -ForegroundColor Gray
Write-Host "   • Ativos em TIER_A/B/C" -ForegroundColor Gray
Write-Host "   • Ativos em GEM track" -ForegroundColor Gray
Write-Host "   • Ultimas promocoes/demotes" -ForegroundColor Gray
Write-Host ""

Write-Host "6. FQS (FUNDAMENTAL QUALITY SCORE):" -ForegroundColor White
Write-Host "   • Distribuicao de scores (BLUE_CHIP/QUALITY/SPECULATIVE/AVOID)" -ForegroundColor Gray
Write-Host "   • Ativos sem FQS (registry incompleto)" -ForegroundColor Gray
Write-Host "   • Ultimos enrichments" -ForegroundColor Gray
Write-Host ""

Write-Host "7. CUSTOS LLM:" -ForegroundColor White
Write-Host "   • Custo total (24h/7d/30d)" -ForegroundColor Gray
Write-Host "   • Custo por provider (Anthropic/Groq)" -ForegroundColor Gray
Write-Host "   • Tokens consumidos" -ForegroundColor Gray
Write-Host "   • Custo por decisao" -ForegroundColor Gray
Write-Host ""

Write-Host "8. FEEDBACK LOOP:" -ForegroundColor White
Write-Host "   • Vetos pendentes" -ForegroundColor Gray
Write-Host "   • Acoes corretivas executadas" -ForegroundColor Gray
Write-Host "   • Taxa de resubmissao bem-sucedida" -ForegroundColor Gray
Write-Host ""

Write-Host "9. TRAILING STOP ADAPTATIVO:" -ForegroundColor White
Write-Host "   • Threshold atual por posicao" -ForegroundColor Gray
Write-Host "   • Volatilidade (ATR%) por ativo" -ForegroundColor Gray
Write-Host "   • Momentum (RSI) por ativo" -ForegroundColor Gray
Write-Host "   • Distancia adaptativa" -ForegroundColor Gray
Write-Host ""

Write-Host "10. ALERTAS E EVENTOS:" -ForegroundColor White
Write-Host "   • Alertas criticos (ultimas 24h)" -ForegroundColor Gray
Write-Host "   • Posicoes sem stop loss" -ForegroundColor Gray
Write-Host "   • Beta cap violations" -ForegroundColor Gray
Write-Host "   • Concentration limit breaches" -ForegroundColor Gray
Write-Host ""

Write-Host "11. PORTFOLIO METRICS:" -ForegroundColor White
Write-Host "   • Beta portfolio atual" -ForegroundColor Gray
Write-Host "   • Concentracao por ativo (%)" -ForegroundColor Gray
Write-Host "   • Exposicao total (margin used)" -ForegroundColor Gray
Write-Host "   • Diversificacao (numero de ativos)" -ForegroundColor Gray
Write-Host ""

Write-Host "12. WHALE WATCHER:" -ForegroundColor White
Write-Host "   • Ultimos whale movements detectados" -ForegroundColor Gray
Write-Host "   • Volume anomalo" -ForegroundColor Gray
Write-Host "   • Impacto no portfolio" -ForegroundColor Gray
Write-Host ""

Write-Host ""
Write-Host "DESEJA CRIAR DASHBOARD COMPLETO COM TODAS ESSAS INFORMACOES? (S/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "S" -or $response -eq "s") {
    Write-Host ""
    Write-Host "Criando dashboard completo..." -ForegroundColor Green
    Write-Host "Isso vai levar alguns minutos..." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Pressione qualquer tecla para continuar..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} else {
    Write-Host ""
    Write-Host "Operacao cancelada." -ForegroundColor Gray
}
