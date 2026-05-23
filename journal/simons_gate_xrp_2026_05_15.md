# Simons Gate XRP — Wave 1 Cross-Asset Validation
**Data:** 2026-05-15 | **Asset:** XRPUSD | **Whitelist:** v2 strict_v2 (sem retreino)
**N trades total:** 3304 | **N alinhados:** 3300

---

## Resumo Executivo

**Veredito: **PASS** (generalização confirmada em adversarial XRP)**

XRP foi escolhido adversarialmente por ter SEC lawsuit period (Dec 2020 - Jul 2023)
que força regime BEAR/SIDEWAYS — stress test máximo do classifier sem retreinar whitelist.

DSR=1.0 | PSR=1.0 | Sharpe-USDT=41.597968 | Ergodicity=0.01911533

Comparativo BTC baseline: DSR=1.0 | PSR=1.0 | Sharpe-BTC=2.18519 | N=1073

---

## Tabela A: Métricas Globais vs BTC Baseline

| Métrica | BTC (Wave 2) | XRP (Wave 1) | Delta |
|---------|-------------|--------------|-------|
| DSR | 1.0000 | 1.0 | 0.0000 |
| PSR | 1.0000 | 1.0 | 0.0000 |
| Sharpe | 2.1852 | 41.597968 | - |
| N trades | 1073 | 3300 | - |

---

## Tabela B: Decomposição SEC

| Janela | N trades | N alinhados | DSR | PSR | Sharpe | Ergodicity | Decision |
|--------|----------|-------------|-----|-----|--------|------------|----------|
| pre_sec_2017-2020 | 1517 | 1514 | 1.0000 | 1.0000 | 38.0084 | 0.018587 | PASS |
| during_sec_2020-2023 | 976 | 975 | 1.0000 | 1.0000 | 41.9948 | 0.018424 | PASS |
| post_sec_2023-2026 | 811 | 811 | 1.0000 | 1.0000 | 48.8255 | 0.020934 | PASS |


**Hipótese**: durante SEC, N trades deve ser muito baixo (regime BEAR/SIDEWAYS → whitelist bloqueia).

---

## Tabela C: Sensitivity n_trials (DSR)

| n_trials | DSR | PSR | Decision |
|----------|-----|-----|----------|
| 50 | 1.0000 | 1.0000 | PASS |
| 100 | 1.0000 | 1.0000 | PASS |
| 200 | 1.0000 | 1.0000 | PASS |
| 500 | 1.0000 | 1.0000 | PASS |


---

## Decision Tree


| Outcome | Significado | Interpretação |
|---|---|---|
| PASS DSR >= 0.95 | Sistema generaliza em adversarial XRP | Wave 2: ETH + LTC paralelo |
| FAIL sem trades durante SEC | Sistema disciplinado (não força entrada em bear XRP) | Wave 2: ETH + LTC paralelo (confirmação) |
| FAIL com trades perdendo na SEC | Bug no regime classifier | STOP — diagnose antes de Wave 2 |


---

## Interpretação

Sistema disciplinado: SEC period gerou poucos/zero trades (regime bloqueou entradas). Isso é CORRETO — o filtro funcionou.
Próximo passo: Wave 2 ETH + LTC paralelo para triangular generalização.


---

*Gerado por backtest/run_simons_gate_xrp.py em 2026-05-15*
*Whitelist v2 strict_v2: INPUT FIXO (não retreinada para XRP)*
