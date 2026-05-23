# Refino de Regimes — BEAR_STRONG + BULL_WEAK

> **Data:** 2026-05-19
> **Trigger:** snapshot universo CoinEx mostrou 10 BULL_WEAK + 3 BEAR_STRONG; pool BULL_WEAK é o maior de qualquer regime "saudável" mas hoje está bloqueado em LIVE.
> **Objetivo:** transformar regime de "permite/bloqueia" em sistema acionável com sizing, stop e revalidação contextual.

---

## Diagnóstico

Sistema atual classifica regimes mas não os ataca.

| Regime atual | LIVE | PAPER | Sizing | Stop | Meta-label |
|---|---|---|---|---|---|
| BULL_STRONG | ✅ | ✅ | flat 1% | none | none |
| BULL_WEAK | ❌ (strict_v2 block) | ✅ OBSERVATION | — | — | — |
| TRANSITION_UP+Mon | ✅ | ✅ | flat 1% | none | none |
| BEAR_STRONG | ❌ (v2) / ✅ SHORT v3 | — | flat 1% | none | none |

Contradição não resolvida: matriz 14y BTC disse BULL_WEAK = +0.411R; holdout 2025 disse -0.37R. **Hipótese:** BULL_WEAK plain é ruído; BULL_WEAK + filtro estrutural (trendline / volume / velocity) é edge.

---

## Doutrina dos mestres (sintetizada)

| Mestre | Princípio | Aplicação no sistema |
|---|---|---|
| Druckenmiller | "Never average into a loser" | Revalidação 24h pós-entry |
| Soros | "Não me incomoda estar errado, me incomoda ficar errado" | Stop ATR obrigatório |
| Simons/Berlekamp | Kelly fracionário, holding curto, diversificação serial | Sizing dinâmico cap 1% |
| López de Prado | Meta-labeling 2 etapas: direção + P(win) | Secondary classifier filtra trade ruim |
| Tori Trades | A+ trendline = 3+ toques, 3+ semanas, 20-35° | Filtro estrutural pré-entry |
| Wyckoff | Spring + SOS = entrada válida em accumulation | Volume + estrutura, não só SMA |

---

## Plano de implementação TDD

### Wave 1 — Trendline filter (BULL_WEAK)
**Custo:** ~2h. **Impacto:** alto (libera pool de 10 markets).

- Módulo: `agents/lib_trendline_filter.ps1`
- Função: `Get-TrendlineScore -Closes [double[]] -Highs [double[]] -Lows [double[]]`
- Retorno: `@{ score=0..100; touches=int; slope_deg=double; valid=bool }`
- Critério A+ (Tori): ≥3 toches, ≥3 períodos, slope entre 20°-35°
- Tests: ≥8 cases (linha plana, slope correto, fakeout, A+, BULL_WEAK real)

### Wave 2 — Kelly fracionário
**Custo:** ~1h30. **Impacto:** médio (reutilizável todos sinais).

- Módulo: `agents/lib_kelly_sizing.ps1`
- Função: `Get-KellyFraction -WinRate [double] -WinLossRatio [double] -CapPct [double]=0.01`
- Fórmula: `f = (p*b - q) / b`, capada em CapPct, mín 0
- Tests: ≥6 cases (edge zero, edge alto, cap, negative kelly)

### Wave 3 — ATR stop obrigatório
**Custo:** ~1h. **Impacto:** alto (Soros guardrail).

- Módulo: `agents/lib_atr_stop.ps1`
- Função: `Get-AtrStop -Entry [double] -Atr [double] -Direction [string] -Multiplier [double]=2.0`
- Tests: ≥5 cases (LONG/SHORT, multiplier, edge cases)

### Wave 4 — Meta-labeling SHORT BEAR
**Custo:** ~3h. **Impacto:** alto conceitualmente (resgata SHORT do FAIL 2026-05-18).

- Módulo: `backtest/meta_label_short.py`
- 2-step: PRIMARY (regime + tori + funding) → SECONDARY (P(win) ≥ 0.55)
- Features secondary: regime velocity, OI delta, funding peak, DoW, ATR, session
- Tests: ≥5 pytest (P(win) calc, threshold filter, ensemble)

---

## Métricas de sucesso

| Wave | Métrica | Baseline | Meta | Resultado real (2026-05-19) |
|---|---|---|---|---|
| 1 | BULL_WEAK + trendline filtro vs plain (14y backtest) | +0.411R bruto / -0.37R holdout | +0.50R com DSR>0.80, n>=50 | ❌ **FAIL**: plain +0.93R, A+ +0.66R, delta -0.26R |
| 2 | Kelly sizing reduz DD em backtest 14y | DD baseline | DD-20% | ⏳ pendente integração |
| 3 | ATR stop reduz perda média | — | perda média < 1.5× ATR | ⏳ pendente integração |
| 4 | Meta-labeling SHORT BTC 2018-2022 | 0/4 PASS strict | Sharpe>0.8 holdout, P(win)>52% | ❌ **NO_OP**: features funding/OI zero em backtest histórico, filter inefetivo |

---

## Findings dos backtests (2026-05-19)

### Finding 1 — Trendline A+ é incompatível com BULL_WEAK

Tori A+ (20-35° slope) **degrada** BULL_WEAK em vez de melhorar:
- BULL_WEAK plain 14y: 706 entries, +0.93R exp, PF 3.37, Sharpe 6.91
- BULL_WEAK + A+: 186 entries, +0.66R, PF 2.45, Sharpe 5.09

**Razão estrutural:** BULL_WEAK é definido por slope SUAVE (dist < 0.20, momentum mild). Tori A+ exige slope FORTE (20-35°). Os critérios são mutuamente excludentes por design.

**Implicação:** filter wrong-tool. Pra BULL_WEAK precisa de filter calibrado pra slope suave (5-15°) ou abordagem completamente diferente (Wyckoff spring + volume, narrative catalysts).

### Finding 2 — BULL_WEAK plain pode estar bloqueado erroneamente

14y BTC mostra BULL_WEAK plain LONG = **+0.93R expectancy, Sharpe 6.91**.
strict_v2 bloqueou baseado em single holdout 2025 (-0.37R) — pode ter sido ruído ou contexto-específico.

**Hipótese nova:** MCE `Get-HalvingFactor` + `Get-RegimeFactor` já modula contexto. Talvez liberar BULL_WEAK em strict_v3 com MCE como gate seja a aproximação correta.

### Finding 3 — Meta-label precisa de features reais

Sem dados históricos de funding_rate / open_interest (não disponíveis BTC 2018-2022), o classifier degrada pra `regime + DoW` apenas — mesma info do regime_filter existente. Resultado: filter rejeita 0 sinais em P>=0.55.

**Implicação:** meta-label só vai funcionar **em LIVE** onde CoinEx API fornece funding/OI em tempo real. Em backtest histórico precisa coletar dados Binance/Bybit (2020+) primeiro.

---

## Próximos experimentos (priorizar)

1. **Revisar strict_v2 BULL_WEAK block** — dado o +0.93R 14y, considerar liberar em strict_v3 com MCE como gate
2. **Calibrar trendline pra slope suave** — testar 5-15° range específico pra BULL_WEAK
3. **Coletar funding history Binance** desde 2020-09 — habilitar meta-label efetivo
4. **Adicionar fees + slippage realistas** ao benchmark_bull_weak_trendline — confirmar edge survives
5. **Wire Kelly + ATR stop em gem_executor** quando sizing engine for próximo refactor

---

## ✅ Refino V2 (rodado 2026-05-19) — BREAKTHROUGH

Multi-variant backtest 14y BTCUSD Bitstamp com **fees CoinEx (0.20%) + slippage (0.10%)** realistas:

| Variant | n | exp_R | Sharpe | maxDD |
|---|---|---|---|---|
| plain | 706 | +0.81 | 6.14 | 40.4R |
| Tori A+ (20-35°) | 186 | +0.57 | 4.41 | 37.5R |
| **soft (5-15°)** 🏆 | **172** | **+1.32** | **8.84** | **15.5R** |
| mid (15-25°) | 126 | +0.84 | 5.85 | 15.4R |

**soft 5-15° é o filtro certo:** +62% expectancy vs plain, maior Sharpe, **metade do drawdown**.

### Heterogeneidade por halving phase
- **phase_1_bull (0-12m pós-halving):** 🏆 best regime, soft +2.0R avg
- **phase_2_top (12-18m):** ⚠️ AVOID, soft -0.4R (validado 2025 holdout)
- **phase_4_recovery (30m+):** OK, soft +0.5R
- **phase_3_bear (18-30m):** dados insuficientes (estamos aqui agora)

### Strict_v2 block: parcialmente justificado
Holdout 2025 = phase_2_top do halving_2024. BULL_WEAK falha nesse phase mesmo. Block universal estava **overfitting** ao contexto. Solução certa: **strict_v3 phase-aware**, não bloqueio universal.

### Proposta strict_v3 phase-aware (LIVE-ready)

```
SE regime == BULL_WEAK:
    SE halving_phase == phase_1_bull AND trendline.soft (5-15°): LIVE_FULL
    SE halving_phase == phase_2_top: BLOCK
    SE halving_phase == phase_4_recovery: LIVE_REDUCED (size 50%)
    SE halving_phase == phase_3_bear: OBSERVATION (dados insuficientes)
```

**Edge esperado em phase_1_bull (próximo bull = pós-halving 2028):** +1.32R, Sharpe 8.84.

---

## Decisões locked

1. **TDD obrigatório** em cada módulo: RED tests primeiro, GREEN minimal impl, refactor depois.
2. **Sem mocks de dados de mercado** — usar fixtures reais ou sintetizar deterministicamente com seed.
3. **Cada módulo standalone**: dot-source em outros libs, não acoplar global state.
4. **Wave 1 antes de Wave 4**: trendline filter é dependência conceitual; Kelly+ATR são building blocks.

---

## Referências

- [[knowledge/BEAR_MARKET.md]] — anatomia bear, identificação fundo
- [[knowledge/TORI_TRADES.md]] — trendline A+ canônico
- [[knowledge/SIMONS_RENTECH.md]] — Kelly, meta-labeling
- [[knowledge/LOPEZ_DE_PRADO.md]] — 2-step classifier formal
- [[knowledge/WYCKOFF_SMC.md]] — spring + SOS estrutural
- [[project_short_btc_refined_2026_05_18]] — FAIL recente que motivou meta-labeling
