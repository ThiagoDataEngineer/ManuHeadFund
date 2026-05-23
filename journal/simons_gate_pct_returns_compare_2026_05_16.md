# Simons Gate — % Returns Daily (Fase C — Backtest Redo)
**Data:** 2026-05-16 | **Regime:** TRANSITION_UP+LONG | **Metodologia:** Bailey-López de Prado 2014

---

## Resumo Executivo

Simons Gate em % returns DAILY: **FAIL** — DSR 0.4973 < 0.95; PSR 0.9500 < 0.95.
Sharpe=1.6031, PSR=0.9500, DSR=0.4973.

---

## Métricas (% returns DAILY, padrão cripto)

| Métrica | Valor | Threshold | Status |
|---------|-------|-----------|--------|
| Sharpe (annualized) | 1.6031 | > 0 | ✅ |
| PSR | 0.9500 | ≥ 0.95 | ❌ |
| DSR (n_trials=50) | 0.4973 | ≥ 0.95 | ❌ |

**Annualizer:** sqrt(365) = 19.105 (cripto 24/7, daily returns)
**Risk per trade:** 1.0% do capital

---

## Comparação: % Returns vs R-multiples (Legacy)

| Métrica | R-multiples (Wave 2) | % Returns Daily (Fase C) | Δ |
|---------|----------------------|-------------------------|----|
| Sharpe | 2.1852 | 1.6031 | -0.5821 |
| PSR | 1.0000 | 0.9500 | -0.0500 |
| DSR | 1.0000 | 0.4973 | -0.5027 |
| Decision | PASS | FAIL | ⚠️ DIVERGÊNCIA |

**Nota:** Sharpe não é diretamente comparável (annualizers diferentes), mas decision binária deve ser consistente.

---

## Sensitivity n_trials

| n_trials | Sharpe | PSR | DSR | Decision |
|----------|--------|-----|-----|----------|
| 20 | 1.6031 | 0.9500 | 0.6048 | FAIL ← FRAGIL |
| 50 | 1.6031 | 0.9500 | 0.4973 | FAIL ← FRAGIL |
| 100 | 1.6031 | 0.9500 | 0.4242 | FAIL ← FRAGIL |
| 200 | 1.6031 | 0.9500 | 0.3588 | FAIL ← FRAGIL |
| 500 | 1.6031 | 0.9500 | 0.2844 | FAIL ← FRAGIL |


---

## Veredito

**HOLD — degradação ao mudar de R-multiples para % returns. Investigar concentração de PnL ou outliers diários.**

**Reasons:** DSR 0.4973 < 0.95; PSR 0.9500 < 0.95

---

## Dataset

- Trades raw: 1073
- Daily returns: 291
- Dias com atividade: 292
- Período: 2014-01-11 → 2025-04-12
- Risk per trade: 1.0%

---

*Gerado por backtest/run_simons_gate_pct_returns.py em 2026-05-16*
