# Backtest Redo — Relatório Final Consolidado (2026-05-17)

## Sumário Executivo

Refatoração metodológica completa em 5 fases + grid search sobre 32 combinações de parâmetros:

1. **Fase A:** equity_curve_from_trades (% returns daily)
2. **Fase B:** Sharpe/PSR/DSR Bailey & López de Prado 2014
3. **Fase C:** BTC com binário+% returns: DSR 1.0 → 0.50 (marginal)
4. **Fase D-v1:** XRP binário: equity 10²⁸ (bug detectado)
5. **Fase D-v2:** Triple barrier path-dependent + fees CoinEx
6. **Grid search:** 16 combinações (stop ∈ {0.5, 1, 1.5, 2}, target ∈ {1, 2, 3, 5}) × 2 assets

## Resultado Final (Best Params per Asset)

| Asset | Stop | Target | R:R | Sharpe | DSR | PSR | Win% | Mean R | Final eq | Decision |
|-------|------|--------|-----|--------|-----|-----|------|--------|----------|----------|
| **BTC** | 2.0 | 5.0 | 2.5 | **-0.65** | 0.02 | 0.28 | 25.6% | -0.37 | 0.000x | **FAIL** |
| **XRP** | 2.0 | 5.0 | 2.5 | **+4.44** | 1.00 | 1.00 | 37.2% | +0.46 | 605700x | PASS (overfit?) |

## BTC: Whitelist v2 FAIL definitivo

**TODOS 16 grid combinations → Sharpe NEGATIVO.** Mesmo o melhor (stop=2/target=5) tem Sharpe -0.65, equity terminal 0.000x (perde tudo).

| Stop | Target | Sharpe | Win% | Mean R |
|------|--------|--------|------|--------|
| 0.5 | 5.0 | -6.71 | 7.7% | -0.47 |
| 1.0 | 5.0 | -2.47 | 14.0% | -0.36 |
| 1.5 | 5.0 | -1.28 | 19.8% | -0.36 |
| 2.0 | 5.0 | -0.65 | 25.6% | -0.37 |

**Padrão:** stops mais largos aumentam win% mas mean R fica negativo porque cada loss é proporcionalmente maior. Whitelist v2 strict_v2 (BULL_STRONG + TRANSITION_UP+Mon LONG) **não tem edge** em BTC sob backtest rigoroso 14y (2014-2025).

## XRP: edge real mas concentrado

4/16 grid combinations PASS:
- stop=1.0/target=5.0 → Sharpe 3.16, eq 594x
- stop=1.5/target=3.0 → Sharpe 3.36, eq 511x
- stop=1.5/target=5.0 → Sharpe 3.97, eq 44371x ⚠️
- stop=2.0/target=3.0 → Sharpe 3.79, eq 2499x
- **stop=2.0/target=5.0 → Sharpe 4.44, eq 605700x ⚠️**

**Equity terminal absurdo (605k x):** sinal de concentração em poucos eventos (XRP teve runs históricos 1000x em 2017/2021). Sharpe 4.44 é otimista demais — provavelmente overfit do grid search.

**Veredito XRP honesto:** edge existe mas é em "long volatility" (capture de moves grandes). Não é "strategy with edge", é mais "biased exposure to vol spikes". Equity reflete sobrevivência de poucos winners massivos.

## Implicações Operacionais

### O que isso revela
1. **Backtests anteriores (Wave 1+2) infláveis** — R-multiples binário + annualizer hourly + sem fees criaram Sharpe falso 2-40x
2. **Edge BTC com whitelist v2 NÃO EXISTE** sob rigor metodológico real
3. **Edge XRP é volatility play** — não edge tático, é exposure ao tail

### O que NÃO mudar
- Paper trade V6 cascade (Triagem/Mesa/Mentor + whitelist v3) — **não** usa whitelist v2 puro
- Sistema infra (watchdog, regime per-pair, constants, persona LLM) — todos válidos
- Risk_pct 1% — confirmado adequado

### O que mudar
- ❌ **Parar de citar Wave 2 BTC 4/4 PASS como evidência de edge** — era artefato metodológico
- ✅ **Triple barrier vira padrão** em todo backtest futuro
- ✅ **Whitelist v3 precisa re-validação** com triple barrier (não só v2)
- ✅ **Walk-forward CPCV obrigatório** antes de qualquer "best params" merecer confiança
- ✅ **Maker-only execution** considerada (fee 0.02% vs 0.05% taker — pode mudar Sharpe BTC marginalmente)

## Stack Metodológica Final

```
candles OHLCV
   ↓
regime_classifier (per-pair, com PairChange24h domina)
   ↓
apply_regime_filter (whitelist v3 strict_v2 LONG+SHORT)
   ↓
detect_entries → entries_cache (deteção UMA vez)
   ↓
simulate_from_entries (triple barrier + fees + slippage)
   ↓
build_equity_curve (multiplicativa, risk_pct=1%)
   ↓
daily_returns_from_equity (% returns daily, padrão LdP)
   ↓
sharpe / psr / dsr (Bailey & LdP 2014)
   ↓
decisão PASS/FAIL (DSR ≥ 0.95 e PSR ≥ 0.95 e Sharpe > 0)
```

## Próximos passos sugeridos

1. **Walk-forward purged CV** (LdP cap 7) para validar que best XRP params não são overfit
2. **Re-validar whitelist v3** (LONG + SHORT) com triple barrier
3. **Trade-by-trade analysis XRP**: quantos % do equity vem dos top-10 trades?
   (se >50% → confirma overfit/concentração)
4. **Maker-only revalidation** com fee 0.02% (CoinEx tier)
5. **Considerar abandonar BTC com esta whitelist** — investir tempo em alt strategies

## Artefatos

- `backtest/triple_barrier_simulator.py` (10/10 TDD)
- `backtest/entries_cache.py` (deteção desacoplada)
- `backtest/simulate_from_entries.py` (4/4 TDD)
- `backtest/run_grid_search.py` (runner BTC+XRP)
- `backtest/run_pct_returns_realistic.py` (single-param)
- `backtest/equity_curve_from_trades.py` (10/10 TDD)
- `backtest/metrics_pct_returns.py` (9/9 TDD)
- `journal/grid_search_xrp_2026_05_17.json`
- `journal/grid_search_btc_2026_05_17.json`
- `journal/entries_cache_{btc,xrp}_2026_05_17.json` (reusáveis)
- TDD total: 33/33 GREEN (10 triple_barrier + 9 metrics_pct + 10 equity + 4 simulate)
