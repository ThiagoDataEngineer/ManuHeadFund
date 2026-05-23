# Summary Long-History Validation

> Gerado: `2026-05-14T13:15:50Z` — consolidacao dos 4 chats de benchmarking V2.

## Tabela consolidada

| Chat | Benchmark | Status | Insight |
|---|---|---|---|
| chat1 | Chat 1 — Short / Bear stress | ❌ failed | Criterio falha em: bear_2018, bear_2022. SHORT nao demonstra edge robusto. |
| chat2 | Chat 2 — Long 14y OOS | ❌ failed | positive_years_pct >= 70.0 AND total_pf >= 1.5 | total_pf=1.3534, positive_years_pct=66.7 |
| chat3 | Chat 3 — Monte Carlo DD | ✅ passed | Em 95% das simulacoes, DD fica abaixo de 20R. |
| chat4 | Chat 4 — Walk-forward 14y | ✅ passed | 77.27% windows positivas; streak max negativo 1; ergodicity 0.6119. |

## Veredito agregado

**REVISIT**

Mais de 1 benchmark falhou. Revisitar sistema antes de qualquer escalada.

## Achados-chave por benchmark

- **Chat 1 — Short / Bear stress:** Criterio falha em: bear_2018, bear_2022. SHORT nao demonstra edge robusto.
- **Chat 2 — Long 14y OOS:** positive_years_pct >= 70.0 AND total_pf >= 1.5 | total_pf=1.3534, positive_years_pct=66.7
- **Chat 3 — Monte Carlo DD:** `max_p95=10.0R` em 10,000 sims; `max_p99=13.0R`; robustness=1.0.
- **Chat 4 — Walk-forward 14y:** 22 janelas; positive%=77.27; streak max negativo=1; ergodicity=0.6119; pior janela: `2015-07-01 -> 2016-07-01` exp=-0.1129.

## Riscos identificados

- **Chat 1 — Short / Bear stress** falhou o criterio go-live.
- **Chat 2 — Long 14y OOS** falhou o criterio go-live.
- Resultados sinteticos demo no Chat 3/4 quando os inputs reais (baseline_v2) nao estao presentes.

## Próximos passos sugeridos

- Nao liberar live. Revisar pesos do orquestrador e thresholds.
- Re-rodar os 4 benchmarks apos cada ajuste material.
- Considerar reduzir universe (so BTC/ETH) ate consistencia voltar.

## Comparação vs baseline original (5 benchmarks 2026-05-14)

Baseline original (2026-05-14): 5 benchmarks puramente IN-SAMPLE com expectativa +1.2R medio, win rate 55%. Esta validacao long-history adiciona OOS + stress + MC + walk-forward e endurece o criterio de go-live.
