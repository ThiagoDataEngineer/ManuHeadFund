# Simons Gate Refinement — BTC OHLC Real vs Sintético
**Data:** 2026-05-15 | **Regime:** TRANSITION_UP+LONG | **N raw:** 1073 | **N alinhados:** 1073

---

## Resumo Executivo

Simons Gate com BTC OHLC real: **PASS** (4/4 critérios verdes).
N=1073 trades alinhados (100.0%) de 1073 raw (0 descartados por gap de candle).
DSR=1.0, PSR=1.0, Sharpe-BTC=2.18519, Ergodicity=0.00085747.
Edge validado com BTC real — não mais dependente de proxy sintético.

---

## Tabela A: Sintético vs Real (4 Métricas)

| Métrica | Sintético (Wave 1) | Real (BTC OHLC) | Delta |
|---------|-------------------|-----------------|-------|
| DSR | 1.0000 | 1.0 | +0.0000 |
| PSR | 1.0000 | 1.0000 | +0.0000 |
| Sharpe-BTC | 1.3967 | 2.1852 | +0.7884 |
| Ergodicity | 0.000857 | 0.000857 | +0.0000 |


**Fonte BTC:** supabase/coinex_real | **Candle:** BTCUSD 1hour | **Annualizer:** sqrt(365*8)=54.037

---

## Tabela B: Sensitivity n_trials (DSR com BTC real)

| n_trials | DSR | PSR | Decision |
|----------|-----|-----|----------|
| 20 | 1.0000 | 1.0000 | PASS |
| 50 | 1.0000 | 1.0000 | PASS |
| 100 | 1.0000 | 1.0000 | PASS |
| 200 | 1.0000 | 1.0000 | PASS |
| 500 | 1.0000 | 1.0000 | PASS |

**Primeiro n_trials onde DSR < 0.95:** Nenhum (robusto em todos os valores testados)

---

## Veredito

**GO — edge confirmado com dados reais; prosseguir para paper trade com whitelist v2.**



---

## Limitações Remanescentes

- Nenhuma limitação crítica identificada além das documentadas no MEMORY.

---

*Gerado por backtest/run_simons_gate_real.py em 2026-05-15*
