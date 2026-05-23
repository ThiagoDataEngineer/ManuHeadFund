# Backtest Redo — Relatório Final (2026-05-16)

## Sumário Executivo

Refizemos todo o backtest com:
1. **% returns daily** (não R-multiples — Bailey & LdP 2014 padrão)
2. **Triple barrier path-dependent** (LdP AFML cap 3 — substitui simulação binária)
3. **Fees CoinEx + slippage** (round-trip 0.2%)

**Resultado:** o edge "validado" em backtests anteriores **não sobrevive** ao rigor metodológico — exceto XRP, que apresenta edge marginal.

## Comparação Cross-Metodologia

| Asset | Metodologia | Sharpe | PSR | DSR (n=50) | Decision | Final equity |
|-------|-------------|--------|-----|------------|----------|--------------|
| BTC | R-multiples binário (Wave 2) | 2.19 | 1.00 | 1.00 | PASS | — |
| BTC | % returns + binário (Fase C) | 1.60 | 0.95 | 0.50 | FAIL marginal | 2.95x |
| **BTC** | **% returns + triple barrier (Fase D-v2)** | **-2.47** | **0.03** | **0.001** | **FAIL** | **0.0004x** |
| XRP | R-multiples binário (Wave 1) | 41.60 | 1.00 | 1.00 | PASS | — |
| XRP | % returns + binário (Fase D-v1) | 17.09 | 1.00 | 1.00 | PASS bug | 10²⁸x ⚠️ |
| **XRP** | **% returns + triple barrier (Fase D-v2)** | **3.16** | **1.00** | **0.97** | **PASS condicional** | **594x** |

## Diagnóstico

### BTC FAIL — por quê?

- **Win rate 14%** com R:R 1:5 → expectancy = 0.14·5 + 0.86·(-1) = **-0.16R** (negativa)
- Triple barrier mostra: apenas 14% das entradas batem target 5·ATR em ≤ 7d
- Stops batidos: 85.5% (1757/2055 trades)
- **Whitelist v2 calibrada em simulação binária superestima**: assumir que qualquer subida = +5R não reflete realidade onde stops são tocados ANTES do target

### XRP PASS condicional

- **Win rate 22.8%** com R:R 1:5 → expectancy = 0.228·5 + 0.772·(-1) = **+0.37R** (positiva)
- DSR robusto até n_trials=50, FAIL acima (n=100: 0.95→0.949 borderline)
- XRP tem volatilidade superior — movimentos grandes mais frequentes batem target 5·ATR
- 594x em 9y = ~94% CAGR — plausível dado histórico XRP, mas concentrado em poucos eventos

## Implicação Operacional

### O que NÃO fazer
- Confiar em backtests com simulação binária (+5R/-1R) que ignoram stops reais
- Comparar Sharpe cross-asset sem padronizar metodologia (annualizer, returns scale)
- Usar `RR_DEFAULT=5.0` como suposição de payoff garantido

### O que fazer
- **Whitelist v2 NÃO é go-live para BTC** sob este rigor metodológico
- **XRP edge é marginal**: paper trade obrigatório, não opcional
- **Triple barrier deve ser padrão** em todo backtest novo
- Considerar **otimização ATR multipliers**: talvez BTC precise 2·ATR stop / 3·ATR target (R:R 1:1.5) em vez de 1·ATR / 5·ATR
- **Maker fees vs taker**: 0.05% taker assumido; live com maker reduziria custos

### Sistema atual em produção (paper trade)

Paper trade V6 cascade NÃO usa whitelist v2 diretamente — usa LLMs (Triagem → Mesa → Mentor) + whitelist v3 como filtro adicional. **Este finding não invalida o paper trade**, mas indica que o backtest histórico inflava expectativas. Manter paper rodando para coletar dados reais 14-30d antes de qualquer decisão GO live.

## Artefatos

- `backtest/triple_barrier_simulator.py` — 10/10 TDD GREEN
- `backtest/generate_trades_realistic.py` — gerador path-dependent + fees
- `backtest/run_pct_returns_realistic.py` — runner BTC/XRP
- `journal/simons_gate_realistic_btc_2026_05_16.json` — BTC métricas
- `journal/simons_gate_realistic_xrp_2026_05_16.json` — XRP métricas
- `journal/btc_trades_realistic_2026_05_16.json` — 2055 trades BTC
- `journal/xrp_trades_realistic_2026_05_16.json` — 3312 trades XRP

## Próximos passos sugeridos

1. **Tuning ATR mult em BTC**: grid search stop_atr ∈ {1, 2, 3}, target_atr ∈ {2, 3, 5} para encontrar combinação com expectancy positiva
2. **Walk-forward CPCV** (LdP cap 7): evitar overfit do tuning
3. **Re-validar whitelist v3** com nova metodologia (não v2 — v3 inclui SHORT)
4. **Maker-only execution**: revalidar com fee 0.02% vs taker 0.05% (CoinEx fee tiers)
