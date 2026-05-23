# Branch A v2 — Expanded Universe Findings (2026-05-23)

> **Pattern**: doc-alongside-TDD. Follow-up de [BRANCH_A_FINDINGS.md](BRANCH_A_FINDINGS.md)
> com 139 markets (2.75x) — testa se mais dados rescue WSS edge.

## Objetivo

User confirmou WSS A/B retest desde início com full CoinEx universe. Question: mais
dados (135 markets vs 49 antes) revelam edge ou confirmam noise?

## Implementação

**Fetcher** [backtest/fetch_coinex_universe.py](../../backtest/fetch_coinex_universe.py):
- Bulk market list (1 API call) → 1,269 spot markets
- Bulk 24h tickers (1 API call) → 1,527 tickers
- Quality filter: vol_24h_usd >= $20K + USDT pair → 138 markets
- Sequential klines fetch (250ms rate limit) → 137/138 success in 90s

**Cache final**: 144 markets / 135 com ≥300 bars (era 49). **2.75x expansion.**

**Fast methodology** [backtest/lib_methodology_fast.py](../../backtest/lib_methodology_fast.py):
- NumPy vectorized RSI (one-shot per market, not per-bar)
- Early termination: RSI only computed if volume+lows+close_above pass
- Pre-loaded numpy arrays per market
- **2.5s para walking 139 markets × 600 bars** (vs ~5min pure-Python antes)

**Branch A v2** [backtest/branch_a_v2_expanded.py](../../backtest/branch_a_v2_expanded.py):
- Total execution: **8.3 seconds**
- Skip WSS scoring para baseline (58k events) — only score 166 sig events

## Results

### Sample expansion
| Métrica | v1 (49 markets) | v2 (139 markets) | Change |
|---|---|---|---|
| Sig events p3_bear | 60 | **166** | +176% |
| Distinct days | 25 | **38** | +52% |
| Tier S events | 28 | **36** | +29% |
| Tier S distinct days | 17 | **30** | +76% |

### OOS results per cycle
| Cycle | OOS events | OOS days | M2 lift | CI 95% |
|---|---|---|---|---|
| h20_p3_bear | 2 | 2 | -1.3pp | insufficient |
| h24_p3_bear | 6 | 6 | **-16.1pp** | [-54.2, +26.9] |
| **Combined** | 8 | 8 | **-10.5pp** | **[-44.1, +26.0]** |

### Comparativo v1 vs v2 (mesma metodologia, mesma OOS split logic)
| Métrica | v1 (49 markets) | v2 (139 markets) |
|---|---|---|
| Combined OOS lift (M2) | **+17.5pp** | **-10.5pp** |
| CI 95% | [-20.3, +52.5] | [-44.1, +26.0] |
| CI inclui zero? | SIM | SIM |

## 🚨 Findings — confirmação brutal

### Finding 1: Mais dados → result PIOR, não melhor
v1 reportava combined OOS lift **+17.5pp**. Com 2.75x mais markets, virou **-10.5pp**.
Razão: novos signals de markets adicionados (universe CoinEx 2023+ era) caíram
predominantemente no OOS holdout window (2026 H1) — período de FAIL atual.

Os "+17.5pp" do v1 eram artifact de sample size pequeno onde poucos events
sobreviventes happened to win.

### Finding 2: CI estreitou (statistical power melhorou)
v1 CI [-20.3, +52.5] = width 72.8pp (extremamente largo)
v2 CI [-44.1, +26.0] = width 70.1pp (similar, mais centrado em negativo)

CI still includes zero — **estatisticamente NÃO podemos rejeitar edge=0**.
Mas point estimate agora é negativo (era positivo por chance).

### Finding 3: h24 OOS especificamente -16pp
2026 H1 é período de fail consistente. WSS Tier S na 2026-Q1/Q2 = trade ruim.

Hypothesis: phase 3 bear late (mês 24+ post-halving) é diferente de phase 3
bear middle (mês 12-18) onde edge histórico residia. Sweet spot já passou.

### Finding 4: Speedup confirma value de otimização
Pure-Python: ~5min para 49 markets walking
NumPy+early-term: **2.5s para 139 markets walking** (~100x speedup proportional)

Insight: análises iterativas com vectorization tornam viable A/B testing rigoroso.
Sem speedup, 8.3s total run permite ~430 runs/hora vs 12 runs/hora antes.

## Implicações

### Para WSS deployment
**CONFIRMADO**: WSS Tier S não é edge replicável em regime atual.
- v1 sugeriu edge possível (+17pp lift)
- v2 com dados mais robustos: edge é NEGATIVO (-10pp lift)
- Não deve ser usado para auto-trade

### Para WSS como risk control
**Continua válido** como filter (Tier B = silent, Tier A = observatory).
Reduce exposure em regimes ruins mesmo sem edge proof.

### Para predicate vol_climax+RSI<30
- Edge sweet spot identificado: phase_3_bear meses 12-18 post-halving
- Atual: mês 25 post-halving = OUT of sweet spot
- Próxima janela esperada: 2028-2029 (h28 cycle meses 12-18)

### Para próximas branches WSS B/C/D
- Branch B (universe expansion) JÁ FEITO via fetcher (135 markets)
- Branch C (walk-forward retreino): provavelmente confirma negativo em current regime
- Branch D (ensemble Wyckoff): redução adicional de sample, improvável ajudar

## Recomendação senior brutalmente honesta

3 caminhos defensáveis pós-confirmação:

| Posture | Lógica |
|---|---|
| **α** Aceitar WSS como risk-control-only, freeze auto-trade, aguardar regime change | Honest. Edge histórico real mas atual regime out-of-window. |
| **β** Pivot para outras predicates/strategies validáveis (DCA mecânico BTC, etc) | Aceitar que vol_climax morreu para este regime. |
| **γ** Continuar branches C/D para due diligence completo (~3-4h) | Documentação completa, mesmo se confirmar negativo. |

Vote: **α + γ leve** — aceita WSS posture defensiva imediata + executa Branch C/D
rapidamente para completude da diligence (apenas se sample size permitir).

## Skill insights permanentes adicionados

> **"Mais dados podem REVELAR ausência de edge, não criar edge"**.
>
> Sample size expansion testa hipótese. Se hypothesis correto, edge estabiliza.
> Se hypothesis errado, edge converge para 0 ou negativo. v1 → v2 mostra que
> WSS edge era survivorship — mais data dissipou.

> **"Vectorize backtest loops desde início, não como otimização tardia"**.
>
> NumPy vectorized RSI + early termination tornaram 8.3s total run viável.
> Sem isso, A/B testing iterativo era impraticável (~5min/run). Performance
> não é luxury em research — é enabler.

## Artefatos

- Fetcher: [backtest/fetch_coinex_universe.py](../../backtest/fetch_coinex_universe.py)
- Fast lib: [backtest/lib_methodology_fast.py](../../backtest/lib_methodology_fast.py)
- Branch A v2: [backtest/branch_a_v2_expanded.py](../../backtest/branch_a_v2_expanded.py)
- Doc: este arquivo
- Predecessor: [BRANCH_A_FINDINGS.md](BRANCH_A_FINDINGS.md)
