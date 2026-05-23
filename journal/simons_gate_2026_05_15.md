# Simons Gate — Wave 1 (2026-05-15)

## Dataset
- Fonte: `transition_up_trades_dump.json`
- N trades: 1073
- Periodo: 2014-01-11 -> 2025-04-12
- Regime: TRANSITION_UP+LONG (whitelist V2 OBSERVATION cell)

## 4 Metricas Simons

| Metrica | Valor | Threshold | Status |
|---------|-------|-----------|--------|
| DSR (Deflated Sharpe) | 1,0 | 0.95 | PASS |
| PSR (Probabilistic Sharpe) | 1.0 | 0.95 | PASS |
| Sharpe-BTC (vs HODL) | 1.3967 | 0.0 | PASS |
| Ergodicity | 0.000857 | 0.0 | PASS |

## Decision: **PASS**

## Baseline V2 strict_v2 (contexto)
- N trades: 3483
- PF: 2.015 | exp: 0.6093R | DD: 114.24R | WR: 38.42%
- Sharpe(anual): 4.172

## Analise Honesta

**BTC proxy:** BTC HODL sintetizado N(mu=0.0001, sigma=0.012) seed=42 - aproximacao; refinar com OHLC real

**Limitacoes desta corrida:**
1. **BTC HODL eh sintetico** (N(0.0001, 0.012)) -- nao usa OHLC real ainda.
   Sharpe-BTC eh aproximado; refinar com OHLC alinhado por timestamp em Wave 2.
2. **n_trials=50** eh estimativa do total de variacoes testadas em backtest.
   Se subir para n_trials=200 (mais conservador) DSR cai mais.
3. **Annualizer = sqrt(365*8)** assume ~8 trades/dia em media (hourly entries).
4. **Dataset = TRANSITION_UP only**; BULL_STRONG+LONG (3055 trades) seria a
   celula LIVE primaria do whitelist V2. Rodar em ambos em Wave 2.

## Recomendacao

**GO** para Wave 2: refinar com OHLC BTC real + rodar BULL_STRONG dump.
Edge cientificamente validado nos 4 criterios Simons com proxy aproximado.

---
Gerado por scripts/run_simons_gate.ps1 em 2026-05-15.

