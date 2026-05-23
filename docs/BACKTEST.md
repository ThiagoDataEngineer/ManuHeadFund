# BACKTEST — Arquitetura do Sistema de Backtesting

> Documento interno. Não commitar. Ver .gitignore.

---

## Objetivo

Validar com dados reais se os sinais do TechAgent têm edge estatístico.
Sem backtest = sem evidência = não é institucional.

---

## Decisões de Design

### Por que Python e não PowerShell?
- PowerShell: ~17.000 candles × 100 indicadores = horas
- Python/pandas vectorizado: segundos
- pytest é o padrão de TDD em data science
- Bibliotecas prontas: pandas, numpy, supabase-py

### Por que Supabase e não arquivos locais?
- Candles coletados uma vez, reutilizados em múltiplos runs
- Queries SQL por range de data, par, timeframe
- Histórico permanente de cada backtest run
- Compartilhado com outros projetos (l402-kit, Diagram Forge) no mesmo projeto
- Free tier: 500MB — nosso uso estimado: ~61MB

### Por que abstração db.py?
- Trocar Supabase por DuckDB/PostgreSQL/TimescaleDB sem tocar nos módulos
- DuckDB seria ideal para análise local pura (mais rápido para séries temporais grandes)
- Por ora: Supabase é suficiente e já existe

### Resolução dos dados Binance (data.binance.vision)

| Granularidade | Endpoint | Formato ZIP | Disponível de graça |
|--------------|----------|-------------|---------------------|
| ≥ 1 minuto (1m, 1h, 4h, 1d…) | `monthly/klines/{symbol}/{interval}/` | 1 ZIP/mês | ✅ Implementado |
| **1 segundo** (`1s`) | `daily/klines/{symbol}/1s/` | 1 ZIP/dia | ✅ Implementado (`--period 1sec`) |
| Tick (aggTrades) | `daily/aggTrades/{symbol}/` | 1 ZIP/dia | Disponível; não implementado |

> A Binance é a única fonte **gratuita** com granularidade de 1 segundo em dados históricos.
> Use `--source binance --period 1sec` para backtests de micro-estrutura (scalp/HFT).

### ⚠️ Limitação de cobertura histórica — data.binance.vision vs CoinEx

**Validado em 2026-05-12:**

| Par | Binance UM Futures (data.binance.vision) | CoinEx API |
|-----|------------------------------------------|------------|
| BTCUSDT | Jan/2024 em diante ✅ | Histórico mais longo disponível |
| PAXGUSDT | **Só desde mar/2025** (listagem recente no Binance futures) | Pode ter histórico anterior (spot) |
| Pares spot/altcoins | Depende da listagem no Binance UM Futures | Depende da listagem na CoinEx |

**Regra prática:**
- `--source binance`: cobre bem BTC/ETH/SOL/pares líquidos com futuros antigos
- `--source coinex`: usa para pares listados na CoinEx antes da listagem na Binance
- `--source auto` (padrão): tenta CoinEx primeiro, cai para Binance se < 100 candles

> Para pares como PAXGUSDT que não têm histórico longo na Binance UM Futures,
> usar `--source coinex` ou `--source auto` para máximo de histórico disponível.

---

## Arquitetura

```
CoinEx API (público)  /  data.binance.vision (mensal ≥1m  |  diário 1s)
    ↓
data_collector.py
    ↓  upsert (evita duplicatas)
Supabase: tabela candles
    ↓  SELECT por market/period/range
signal_generator.py
    ├── indicators.py (EMA, RSI, ATR, MACD, Bollinger, ADX, etc.)
    └── bar-a-bar sem lookahead bias
    ↓  INSERT
Supabase: tabela backtest_signals
    ↓
backtest_runner.py          ← NOVO — orquestra o loop completo
    ├── simulate_trade (trade_simulator.py)
    │     ├── sizing: 1% rule do capital
    │     ├── fees: 0.05% taker (CoinEx futures)
    │     └── slippage: 0.05% (conservador)
    ├── classify_regime (metrics.py)
    │     └── SMA200 dos candles anteriores → bull/bear/sideways
    ↓  INSERT (com campo regime)
Supabase: tabela backtest_trades
    ↓
calc_metrics_by_regime (metrics.py)
    ├── métricas combinadas
    └── métricas por regime (bull / bear / sideways)
    ↓  INSERT (com campo regime_breakdown JSONB)
Supabase: tabela backtest_runs
    ↓
relatório terminal (win_rate, expectancy, Sharpe por regime)
```

---

## Schema Supabase

Ver: [backtest/supabase_schema.sql](backtest/supabase_schema.sql)

### Tabelas

| Tabela | Linhas estimadas | Tamanho |
|--------|-----------------|---------|
| `candles` | ~315.000 (5 pares × 3 TFs × 2 anos) | ~50 MB |
| `backtest_signals` | ~31.500 (~10% das candles) | ~8 MB |
| `backtest_trades` | ~5.000 | ~2 MB |
| `backtest_runs` | <100 | <1 MB |
| **Total** | | **~61 MB** |

---

## Estrutura de Arquivos

```
backtest/
├── supabase_schema.sql     # DDL das 4 tabelas + ALTER para regime columns
├── requirements.txt        # dependências Python
├── pytest.ini              # configuração do pytest
├── db.py                   # abstração Supabase: candles/signals/trades/runs
├── data_collector.py       # CoinEx + Binance (mensal ≥1m, diário 1s) → candles
├── indicators.py           # port dos indicadores do TechAgent
├── signal_generator.py     # TechAgent bar-a-bar sobre histórico → signals
├── trade_simulator.py      # simula execução com 1% rule + fees
├── metrics.py              # win rate, expectancy, Sharpe, drawdown + benchmarking por regime
├── backtest_runner.py      # orquestra: signals → trades + runs + HTML (regime labels)
├── report.py               # gera HTML com métricas por regime + badges Tier 3
├── journal_analytics.py    # analytics sobre gem_signals.csv + gem_trades.csv (gate pass rate, D/M ratio, PnL)
├── optimizer.py            # Optuna walk-forward refatorado — API testável, ergodicity_objective, detect_overfitting
├── optimize_walkforward.py # módulo original (mantido para compatibilidade)
├── signal_generator_v2.py  # score refinado: MTF +25, ADX ±20, Volume +20, EMA/RSI/MACD reduzidos
├── compare_v1_v2.py        # benchmark v1 vs v2 in-memory (mesmo dataset, HTF para MTF)
├── param_sweep.py          # varredura SCORE_THRESHOLD / RR_DEFAULT (in-memory)
├── risk_adjusted_metrics.py        # Sharpe/Sortino/Calmar universais + classification + go-live discount
├── benchmark_long_14y.py            # baseline LONG 11 anos BTCUSD por ano (4 ciclos)
├── regime_8state_classifier.py     # 8 regimes ADX-aware: BULL_STRONG/WEAK, TRANSITION_UP/DOWN, SIDEWAYS, BEAR_STRONG/WEAK, CAPITULATION (precompute O(N), thresholds parametrizáveis)
├── regime_direction_matrix.py      # matriz Regime × Direção: edge_strength, confidence, go_criterion
├── recalibrate_regime_classifier.py # grid search dos thresholds com train (2014-2022) / holdout (2023-2025) split — sem overfit
├── transition_up_drilldown.py      # drill-down em TRANSITION_UP por sub-condições: ADX, RSI, hora BRT, DoW, volume relativo
└── tests/
    ├── test_indicators.py
    ├── test_trade_simulator.py
    ├── test_metrics.py
    ├── test_data_collector.py
    ├── test_signal_generator.py
    ├── test_backtest_runner.py
    ├── test_report.py
    ├── test_db.py
    ├── test_journal_analytics.py        # 9 testes
    ├── test_optimizer.py                # 10 testes
    ├── test_signal_v2.py                # 6 testes — refino score v2 + MTF alignment
    ├── test_param_sweep.py              # 6 testes — sweep parâmetros
    ├── test_risk_adjusted_metrics.py    # 16 testes — Sharpe/Sortino/Calmar + classification
    ├── test_benchmark_long_14y.py       # 13 testes — baseline LONG ano-a-ano
    ├── test_regime_8state_classifier.py # 10 testes — 8 regimes ADX-aware + precompute
    ├── test_regime_direction_matrix.py  # 9 testes — matriz Regime × Direção
    ├── test_recalibrate_regime_classifier.py # 10 testes — grid search train/holdout, decisão PASS/FAIL_OVERFIT/FAIL_NO_EDGE
    └── test_transition_up_drilldown.py  # 14 testes — drill-down TRANSITION_UP em 5 dimensões
```

---

## TDD — Filosofia

```
RED   → escrever teste que falha (define o contrato)
GREEN → implementar o mínimo para passar
REFACTOR → limpar sem quebrar testes
```

Indicadores são matemática pura — devem ser testados com valores conhecidos
calculados à mão ou pelo TradingView para garantir que o port do PowerShell
está correto. Um EMA errado invalida todos os sinais.

---

## Benchmarking por Regime de Mercado

Um edge real sobrevive ao bear market. Um backtest sem segmentação de regime esconde beta disfarçado de alpha.

### classify_regime (SMA200 rule)

```python
classify_regime(close, sma200, threshold=0.02)
# bull     → close > sma200 * 1.02
# bear     → close < sma200 * 0.98
# sideways → dentro da banda
```

Critério objetivo, derivável dos próprios candles coletados. Threshold de 2% evita flip constante em faixas laterais.

### calc_metrics_by_regime

```python
result = calc_metrics_by_regime(r_series, regimes)

# result.bull.win_rate      → win rate só em períodos bull
# result.bear.win_rate      → win rate só em períodos bear
# result.sideways           → None se nenhum trade neste regime
# result.combined           → métricas do backtest inteiro
# result.regime_counts      → {"bull": 73, "bear": 31, "sideways": 12}
```

### O que procurar no relatório

| Diagnóstico | Indicador |
|-------------|-----------|
| Edge real | `bear.expectancy_r > 0.3R` — estratégia funciona mesmo em queda |
| Beta disfarçado | `bull.win_rate >> bear.win_rate` (ex: 68% vs 22%) — é só long bias |
| Estratégia curta robusta | `bear.sharpe > 1.0` — lucra com quedas |
| Sideways edge | `sideways.profit_factor > 1.5` — scalp/range funciona |

### Integração com o pipeline

O caller (signal_generator / backtest runner) é responsável por:
1. Calcular SMA200 dos candles históricos
2. Classificar o regime de cada trade no momento da entrada
3. Passar `regimes` para `calc_metrics_by_regime`

---

## Métricas Alvo (Tier 3 Institucional)

| Métrica | Mínimo aceitável | Excelente |
|---------|-----------------|-----------|
| Win Rate | >45% (com R:R 1:3) | >55% |
| Expectancy | >0.3R por trade | >0.5R |
| Profit Factor | >1.5 | >2.0 |
| Max Drawdown | <20% | <10% |
| Sharpe Ratio | >1.0 | >1.5 |
| Calmar Ratio | >0.5 | >1.0 |
| Trades/mês | >10 (significância) | >30 |

---

## Pares Prioritários

| Par | Timeframes | Período |
|-----|-----------|---------|
| BTCUSDT | 1h, 4h, 1d | 2023-2025 |
| ETHUSDT | 1h, 4h, 1d | 2023-2025 |
| TONUSDT | 1h, 4h | 2023-2025 |

---

## Status Atual — FASE 1 COMPLETA + GemAgent Analytics ✅ (2026-05-12)

| Componente | Status | Testes |
|-----------|--------|--------|
| `db.py` | ✅ — requests direto (sem supabase-py) | 13 |
| `indicators.py` | ✅ — port fiel do TechAgent | 31 |
| `trade_simulator.py` | ✅ — 1% rule, R:R, fees, LONG/SHORT | 16 |
| `metrics.py` | ✅ — win rate, expectancy, Sharpe, **Sortino**, Calmar + classify_regime (SMA200) + calc_metrics_by_regime + **ergodicity_score** | 45 |
| Schema Supabase | ✅ — 4 tabelas em produção | — |
| `data_collector.py` | ✅ — CoinEx + Binance (ZIPs mensais ≥1m + ZIPs diários 1s) — **4.345 candles BTCUSDT 1h (Nov/24–Mai/25)** | 44 |
| `signal_generator.py` | ✅ — TechAgent bar-a-bar, zero lookahead bias — **134 sinais gerados** | 27 |
| `backtest_runner.py` | ✅ — pipeline completo: simulate_trade + classify_regime + INSERT trades/run + HTML — **134 trades, win=33.6%, E=+0.090R, PF=1.14, Sharpe=0.055** | 19 |
| `report.py` | ✅ — HTML com métricas por regime (bull/bear/sideways) + badges Tier 3 institucional | 17 |
| `journal_analytics.py` | ✅ — gate pass rate, top blocked gate, D/M ratio, spike ratio, PnL summary | 9 |
| `optimizer.py` | ✅ — Optuna walk-forward refatorado: `build_splits`, `ergodicity_objective`, `detect_overfitting`, API 100% testável | 10 |

**Total Python: 265 testes passando ✅** (231 base + 19 stablecoin_regime + 15 funding_peak)
**Total geral (Python + PowerShell): 527 testes passando ✅** (231 + 296)

| Arquivo de teste | Testes |
|-----------------|--------|
| `tests/test_db.py` | 13 (requests direto, sem supabase-py) |
| `tests/test_indicators.py` | 31 |
| `tests/test_metrics.py` | 45 (23 base + 4 Sortino + 7 `classify_regime` + 8 `calc_metrics_by_regime` + 5 ergodicity) |
| `tests/test_trade_simulator.py` | 16 |
| `tests/test_data_collector.py` | 44 (14 CoinEx + 19 Binance mensal + 11 Binance 1s diário) |
| `tests/test_signal_generator.py` | 27 |
| `tests/test_backtest_runner.py` | 19 (pipeline completo + regime) |
| `tests/test_report.py` | 17 (HTML estrutura + conteúdo + thresholds + arquivo) |
| `tests/test_journal_analytics.py` | 9 (load, gate_pass_rate, top_blocked, D/M ratio, pnl_summary) |
| `tests/test_optimizer.py` | 10 (build_splits, ergodicity_objective, Optuna trial, detect_overfitting) |

## Resultado BTCUSDT 1h — Nov/2024 a Mai/2025

> Primeiro run real com dados coletados via CoinEx API (4.345 candles, 134 sinais, 2026-05-12)

| Métrica | Valor | Tier 3 (mínimo) | Status |
|---------|-------|----------------|--------|
| Total Trades | 134 | — | — |
| Win Rate | 33.6% | >45% | Abaixo (R:R compensa parcialmente) |
| Expectancy | +0.090R | >0.3R | Abaixo — edge marginal |
| Profit Factor | 1.14 | >1.5 | Abaixo |
| Max Drawdown | 26.43R | <20% | Acima do limite |
| Sharpe Ratio | 0.055 | >1.0 | Muito abaixo |

**Breakdown por regime:**

| Regime | Win Rate | Expectancy | Trades | Edge? |
|--------|---------|------------|--------|-------|
| **BULL** | 44% | +0.578R | 34 | **Sim [OK]** |
| BEAR | 33% | -0.035R | 15 | Não |
| SIDEWAYS | 29% | -0.084R | 85 | Não |

**Diagnóstico:**
- Edge real existe apenas em regime **bull** (expectancy +0.578R > 0.3R)
- 63% dos trades ocorreram em sideways (regime mais fraco) — strategy sobrescaneia lateralização
- Melhorias prioritárias: (1) filtro de regime ao vivo (só operar quando bull), (2) reduzir score threshold para sideways, (3) coletar dados em múltiplos timeframes (4h, 1d) para confirmar

---

## Resultado BTCUSD 2w — 14 anos (2011-2026) — Macro

> Backtest macro standalone via `backtest_2w_14y.py` (2026-05-13)
> Fonte: Bitstamp 5.383 candles 1d resampleados para 385 candles 2w
> Cobre 3 halvings completos (2012/2016/2020/2024) + bears 2014/2018/2022

| Métrica | Valor |
|---------|-------|
| Período | 2011-08-18 → 2026-05-07 (14.7 anos) |
| Candles 2w | 385 |
| Total Trades | 159 (87 wins) |
| Win Rate | **54.7%** |
| Expectancy | **+1.088R** |
| Profit Factor | **4.92** |
| Max Drawdown | 17.23R |
| Sharpe | 0.502 |

**Breakdown por regime (SMA50 sobre 2w ≈ 2 anos de tendência macro):**

| Regime | Trades | Win Rate | Expectancy | Edge? |
|--------|--------|----------|------------|-------|
| **BULL** | 90 | 65.6% | **+1.676R** | ✅ |
| BEAR | 55 | 30.9% | -0.244R | Não |
| **SIDEWAYS** | 14 | 78.6% | **+2.535R** | ✅ |

**Breakdown por ciclo macro:**

| Ciclo | Trades | Win | Expectancy | PF | Edge |
|-------|--------|-----|------------|-----|------|
| Bull 2013 | 22 | 72.7% | +2.861R | 12.99 | ✅ |
| Bear 2014 | 23 | 39.1% | +0.001R | 1.01 | — |
| Bull 2016-17 | 34 | 91.2% | +2.677R | 31.34 | ✅ |
| Bear 2018 | 8 | 12.5% | -0.487R | 0.06 | ❌ |
| Bull 2019-21 | 31 | 45.2% | +0.793R | 2.83 | ✅ |
| Bear 2022 | 18 | 38.9% | -0.217R | 0.44 | ❌ |
| Bull 2023-24 | 10 | 50.0% | +0.420R | 2.16 | ✅ |
| 2025+ | 13 | 30.8% | -0.156R | 0.49 | ❌ |

**Diagnóstico macro:**
- Edge **estatisticamente consistente em todos os 4 bull markets** (PF 2.16–31.34) — assinatura do TechAgent confirmada em 14 anos
- Bears são consistentemente negativos ou flat — confirma necessidade de **macro filter** (já implementado via `lib_macro.macro_bias` nos pesos adaptativos do orchestrator)
- Resultado valida a tese: estratégia long-bias em bull macro, redução de exposição em bear
- 159 trades em 14 anos = ~11 trades/ano em 2w → frequência baixa, próprio do timeframe macro

**Comparação com 1h/6m (BTCUSDT Nov/2024–Mai/2025):**

| Métrica | 1h/6m | 2w/14anos |
|---------|-------|-----------|
| Win Rate overall | 33.6% | **54.7%** |
| Expectancy overall | +0.090R | **+1.088R** |
| Edge em BULL | +0.578R | **+1.676R** |
| Edge em BEAR | -0.035R | -0.244R |

O timeframe maior **limpa o ruído de scalp** e revela a edge estrutural do TechAgent em swing macro.

**Arquivo HTML:** `backtest/backtest_report_BTCUSD_2w_14y.html`

---

## Pesquisa Shorts BTC — Validação em 14 anos (2026-05-13)

Investigação se TechAgent pode shortar BTC com edge usando dados free tier.

### Resumo das tentativas

| Tentativa | Approach | Resultado | Veredito |
|-----------|----------|-----------|----------|
| Short_bias TA pura (RSI extremo, divergências, parabólico) | Stack TA com gates exaustão | n=7 shorts em 14y, 1/4 topos | Insuficiente |
| Short v2 com F&G + funding parcial | Gates sentimentais + TA | n=135 shorts, exp +0.575R vs +1.812R LONG-only, DD 10x maior | Destrutivo |
| Stablecoin supply regime (USDT/DeFiLlama) | Macro gate por contração supply | Sinal fraco: 2.1pp dd_60d entre regimes | Modulador secundário apenas |

### Conclusão estrutural

**Topos macro do BTC não são preditiveis com TA + sentimento free tier.** O sinal que distingue "blowoff intermediário" de "topo real" vive em métricas on-chain (MVRV-Z, LTH SOPR, exchange whale inflows) — paid tier (Glassnode/CryptoQuant $30-50/mês).

### Estratégia adotada

1. **BTC = LONG-only no TechAgent** (decisão arquitetural validada empiricamente)
2. **Stablecoin regime** = modulador suave de LONG sizing (não gate hard de SHORT)
3. **Shorts continuam viáveis em altcoins** (Cenário 1 pendente de validação)
4. **Próximas iterações**: Funding rate sequence + Volume divergence + (futuramente) on-chain pago

### Módulo `stablecoin_regime.py`

- 19 testes passando (TDD)
- 5 regimes: EXPANSION ≥ +3% / NEUTRAL ≥ -0.5% / WARNING ≥ -2% / CONTRACTION ≥ -5% / CRISIS < -5%
- Multiplicadores de sizing: 1.2/1.0/0.7/0.4/0.0
- Validação 9 anos: WARNING+ avg dd_60d -15.86% vs EXPANSION/NEUTRAL -13.74% (diferença marginal)
- Uso recomendado: reduzir LONG sizing em WARNING+, bloquear LONG em CRISIS

### Módulo `funding_peak.py`

- 15 testes passando (TDD)
- API: `rolling_mean`, `is_overheated`, `detect_peak`, `detect_drop`, `scan_signals`
- Lógica: detectar pico de funding ≥ 0.05%/8h (rolling 5d), trigger short na queda ≥ 30% confirmada por 2+ dias
- Validação 6.5 anos (Binance BTCUSDT 2019-09 → 2026-05, 7313 samples):
  - **13 triggers detectados**
  - Win rate 38.5%, expectancy +0.178R, profit factor ~1.4
  - **3 wins de +3R cada** capturaram crashes reais (COVID Mar/2020 -45%, Jan/2021 -17%, Mai/2021 -30%)
  - 8 stops em bulls grinding onde funding sustentou após queda parcial
  - **Limitação conhecida:** trigger é coincidente/tardio, não preditivo (Mar/2024 disparou pós-topo)
- Uso recomendado: combinar com stablecoin_regime + macro_bias como confluência, não signal isolado
- Bug crítico corrigido: paginação Binance API requer FORWARD via startTime (endTime retorna oldest 1000 — comportamento da API)

#### Validação com fonte primária CoinEx (atualização)

Re-validado em CoinEx (fonte primária do projeto) via `/v2/futures/funding-rate-history`:
- Cobertura CoinEx: 2021-01-27 → 2026-05-13 (5.3y, 5796 samples)
- **15 triggers, win 26.7%, exp -0.193R** — SEM edge
- Sinal Binance (+0.178R) vinha 100% do COVID crash Mar/2020 — outlier que CoinEx não capturou (dado começa em 2021)
- **CoinEx capturou o topo 2021-11-14** com +2.54R (Binance não capturou)
- Funding CoinEx ~2x mais alto que Binance (menor liquidez)
- **Decisão final:** funding peak NÃO é trigger isolado válido. Apenas como confluência com outros sinais.

### Status total das pesquisas de Short

| Módulo | Testes | Edge | Status |
|---|---|---|---|
| stablecoin_regime | 19 | Fraco (2.1pp dd_60d) | Modulador secundário |
| funding_peak | 15 | Fraco (+0.178R) | Confluência apenas |
| **Total novos testes** | **34** | — | — |

**Total geral pytest**: 231 + 34 = **265 testes Python**.

---

## Efeitos Calendário/Cíclicos — BTC 14 anos (2026-05-13)

Testados 4 efeitos sazonais em 5382 dias BTC (`backtest/calendar_effects_btc.py`):

| Efeito | p-value | Veredito |
|---|---|---|
| **Dia da semana** | **0.0068** | ✅ SIG (Mon vs Thu) |
| Última semana do mês | 0.6426 | ns (sem efeito) |
| Janela FOMC ±2d | 0.93/0.83 | ns |
| Lua nova/cheia (Yuan 2006) | 0.71/0.63 | ns (não replicou em crypto) |

### Dia da semana — calibração empírica

**Returns médios em 14 anos:**

| Dia | mean% | Comportamento |
|---|---|---|
| Segunda | **+0.551%** | MELHOR (institucional retorna, lift-off) |
| Quarta | +0.337% | Segundo melhor |
| Terça | +0.214% | Positivo |
| Sexta | +0.212% | Positivo |
| Domingo | +0.041% | Neutro |
| Sábado | -0.034% | Levemente negativo |
| **Quinta** | **-0.164%** | PIOR (settlement Deribit, vol front-running) |

**Cross-regime (mecanismo):**
- BULL: Mon +1.056% / Thu +0.210%
- BEAR: Mon -0.068% / Thu **-0.645%** (catastrófico)
- Sideways: caótico, sample pequeno

### Estratégias de timing — 14 anos cumulative return

| Estratégia | Tempo% | CumRet | Sharpe |
|---|---|---|---|
| Buy & Hold | 100% | +731,175% | 0.73 |
| **Skip Thursday** | 86% | **+2,583,188%** | 1.03 |
| Mon-Wed only | 43% | +481,290% | **1.57** |
| Mon+Wed | 29% | +92,492% | 1.85 |
| Mon only | 14% | +6,845% | **2.29** |

**Insight chave:** "Skip Thursday" = 3.5× retorno vs Buy & Hold em 14 anos (compounding negativo da quinta-feira é catastrófico).

### Robustez subperíodos

| Período | Mon | Thu | p-value | Status |
|---|---|---|---|---|
| 2011-2014 | +0.924% | -0.516% | 0.082 | marginal |
| 2015-2018 | +0.500% | +0.550% | 0.906 | quebra |
| 2019-2022 | +0.409% | -0.378% | 0.096 | marginal |
| 2023-2026 | +0.409% | -0.411% | 0.006 | SIG |

Efeito sobrevive 3/4 subperíodos (2015-2018 quebra). Recente mais robusto.

### Implementação no agente

Atualizado `agents/lib_seasonality.ps1` com calibração empírica:

```
Mon  +8  Tue +2  Wed +5  Thu -8  Fri -2  Sat -5  Sun -3
```

vs originais antes da calibração:
```
Mon  +5  Tue  0  Wed  0  Thu  0  Fri -5  Sat -8  Sun -8
```

Principais mudanças:
- **Thursday: 0 → -8** (NOVO, baseado em -0.164% médio / -0.645% em bear)
- **Friday: -5 → -2** (estava penalizado errado, dado é +0.212%)
- **Wednesday: 0 → +5** (segundo melhor dia)
- **Monday: +5 → +8** (reforçar o melhor dia)

### Testes adicionados

- `tests/lib_seasonality.Tests.ps1` — 14 testes Pester
- Cobre: campos obrigatórios, ordem DoW empírica, classificação de window, scan interval, score adjustment

**Total geral Pester: 322 + 14 = 336 testes PowerShell.**

**Total geral combinado: 265 pytest + 336 Pester = 601 testes ✅**

### Validação no universo CoinEx (942 markets USDT)

Rodado `backtest/dow_universe_coinex.py` em **TODOS os 1017 pares USDT da CoinEx** (942 com ≥200 dias de histórico):

| Métrica | Resultado |
|---|---|
| Mon > Thu em | **711/942 markets (75.5%)** |
| Significativo (p<0.05) | 70/942 |
| Mon - Thu diff médio | **+0.7222pp/dia** |

**Efeito CONFIRMADO no universo inteiro.** Calibração DoW válida em escala.

### Insight crítico — Quinta-feira em altcoins é catastrófica

| Dia | Alts (avg) | BTC (ref) | % markets positivos |
|---|---|---|---|
| Mon | -0.31%/d | +0.55% | 34% |
| **Thu** | **-1.03%/d** | -0.16% | **9% (!!)** |

**Apenas 9% dos altcoins têm quinta positiva.** Quinta em alts é **6.4× pior** que quinta em BTC.

### Top 5 markets com efeito mais acentuado (todos SIG p<0.05)

| Market | Mon | Thu | Diff |
|---|---|---|---|
| MYXUSDT | +3.88% | -4.23% | **+8.10pp/d** |
| REIUSDT | +2.54% | -5.21% | +7.75pp/d |
| CARDSUSDT | +1.44% | -5.83% | +7.27pp/d |
| OPUSUSDT | +1.16% | -5.76% | +6.92pp/d |
| MLGUSDT | +2.33% | -4.52% | +6.85pp/d |

Padrão: small/meme cap com baixa liquidez têm efeito mais forte.

### `lib_seasonality.ps1` v2 — MarketTier implementado (TDD)

Parâmetro `MarketTier` adicionado com calibração diferenciada:

| Tier | Thursday penalty | Justificativa empírica |
|---|---|---|
| btc (default) | -8 | Thu -0.164%/d |
| eth | -10 | Top10 proxy intermediário |
| alt | **-15** | Thu -1.03%/d, 9% positivos em 942 markets |

**Backward compat:** sem param = `btc`. Tier inválido = fallback seguro pra `btc`.

**Testes Pester:** 14 → 22 (+8 novos cobrindo MarketTier). Total: 322 + 22 = **344 testes Pester**.

**Total geral atualizado: 265 pytest + 344 Pester = 609 testes ✅**

### Uso recomendado

```powershell
$ctx = Get-SeasonalityContext -MarketTier "alt"   # para GemAgent/scanner em altcoins
$ctx = Get-SeasonalityContext -MarketTier "btc"   # para TechAgent em BTC
$ctx = Get-SeasonalityContext                     # default = btc (backward compat)
```

**Integração completa:**

- `agents/lib_seasonality.ps1` — função helper `Get-MarketTier -Market <name>` retorna btc / eth / alt
- `agents/orchestrator.ps1` linha 140 — agora chama `Get-SeasonalityContext -MarketTier (Get-MarketTier -Market $Market)`
- `scanner.ps1` e `gem_agent.ps1` não chamam seasonality direto (não necessário)
- `scan_master.ps1` — mantém default `btc` (global pacing, sem market específico)

**Classificação:**
- `btc`: BTCUSDT
- `eth`: ETHUSDT, BNBUSDT, SOLUSDT, XRPUSDT (top5 mcap)
- `alt`: todos os outros

**Testes finais Pester `lib_seasonality.Tests.ps1`: 32 passando** (era 22, +10 cobrindo `Get-MarketTier`).

**Total geral combinado: 265 pytest + 354 Pester = 619 testes ✅**

---

## Matriz Regime × Direção — 14 anos BTCUSD (2026-05-14)

**Dataset:** 18.710 trades / 99.313 candles 1h Bitstamp 2014-2025 (4 ciclos, 2 bears severos).
Reclassificação 8-state ADX-aware via `regime_8state_classifier.py` (precompute O(N), ~30s total).

| Regime | LONG (exp / n) | SHORT (exp / n) | best | edge | conf |
|---|---|---|---|---|---|
| BULL_STRONG | **+0.358R** / 2.648 | — | LONG | MEDIUM | HIGH |
| **BULL_WEAK** | **+0.411R** / 2.750 | -0.109R / 2.818 | LONG | MEDIUM | HIGH |
| TRANSITION_UP | +0.116R / 1.073 | -0.131R / 27 | AVOID | WEAK | HIGH |
| TRANSITION_DOWN | -0.100R / 4 | +0.151R / 1.184 | AVOID | WEAK | HIGH |
| SIDEWAYS | (filtrado via `--filter-sideways`) | | | | |
| BEAR_WEAK | -0.093R / 2.594 | +0.080R / 2.004 | AVOID | WEAK | HIGH |
| BEAR_STRONG | — | +0.062R / 3.499 | AVOID | WEAK | HIGH |
| **CAPITULATION** | — | **-0.734R** / 65 | AVOID | WEAK | MEDIUM |

**Achados:**

- **BULL_WEAK é o melhor setup do sistema** (+0.411R, PF 1.62) — refuta a hipótese "AVOID" levantada em testes curtos.
- **Sistema atual é LONG-only em bull** (55.95% do tempo tradeable). 2/8 regimes qualificam.
- **CAPITULATION SHORT é desastre** (-0.734R em 65 trades): nunca shortear preço já 25%+ abaixo SMA200.
- **SHORT é uniformemente WEAK** (+0.06 a +0.15R em todos os bears) — sistema SHORT precisa redesign.
- **TRANSITION states são tóxicos** em ambas direções — cruzamentos choppy.

**GO criterion:** falhou (precisa ≥ 4 regimes MEDIUM+ HIGH, qualifica 2).
**Output completo:** `journal/task2_regime_direction_matrix.json`.

---

## Recalibração com Train/Holdout (2026-05-14) — FAIL_OVERFIT

Grid search 108 combos de thresholds (ADX/transition_bars/sideways_band/capitulation) no train 2014-2022, validado no holdout 2023-2025 sem otimização.

**Melhor combo no train:** ADX=20, TB=10, SB=0.01, CAP=0.20 → 3 regimes MEDIUM+.
**Holdout com MESMOS thresholds:** apenas 1 regime MEDIUM+.

**Decisão: FAIL_OVERFIT.**

- BULL_STRONG e BULL_WEAK passam no train mas QUEBRAM no holdout (edge desaparece).
- Único regime estável cross-period: **TRANSITION_UP**.
- Confirma: validações 14y agregadas estavam parcialmente enviesadas pelos ciclos 2017/2020-2021.

**Output:** `journal/task2b_recalibrated_matrix.json`.

---

## Drill-down TRANSITION_UP (2026-05-14) — ACHADO MAIS VALIOSO

1.073 trades em TRANSITION_UP LONG (843 train / 230 holdout) analisados por 5 sub-dimensões.

| Dim | Best (train) | exp_train | n_tr | exp_holdout | n_ho | Decision |
|---|---|---|---|---|---|---|
| ADX | 15-20 | +0.282R | 79 | +0.154R | 12 | NO_EDGE |
| RSI | >60 | +0.154R | 699 | +0.013R | 176 | NO_EDGE |
| Hour | h08 BRT | +0.686R | 31 | **-0.670R** | 5 | NO_EDGE (overfit clássico) |
| **DoW** | **Mon** | **+1.085R** | **170** | **+0.981R** | **25** | **NEEDS_MORE_DATA** ⭐ |
| Volume | >1.2 | +0.175R | 549 | +0.101R | 145 | NO_EDGE |

**Único sub-setup com edge cross-period: TRANSITION_UP + Segunda-feira (BRT) + LONG.**

- Edge ~+1.0R por trade, replicado em duas amostras independentes.
- Falhou critério VIABLE somente por 5 trades a menos (25 vs 30 mínimo no holdout).
- Bate o achado de [`project_dow_seasonality.md`](knowledge/) (BTC Mon +0.55%, p=0.0068).

**Refutação importante:** Hour=h08 BRT parecia ótimo no train (+0.686R) mas REVERTEU completamente no holdout (-0.670R). Armadilha clássica de overfit horário.

**Setup operacional candidato (NÃO operar ainda):**
- Regime = TRANSITION_UP (cruzamento ascendente SMA200)
- DoW = Mon (segunda BRT)
- Direção = LONG

**Output:** `journal/task2a_transition_up_subsetups.json`.

---

## Próximos Passos — Extensão para GemAgent

O backtesting existente serve o pipeline principal (BTC, ETH, altcoins líquidas).
Para o GemAgent (micro-caps explosivos) precisaremos de extensões:

### 1. Tabela `pump_fingerprints` (Supabase)

```sql
CREATE TABLE pump_fingerprints (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,           -- "FP-001-PEPE", "FP-004-SKYAI"
    market          TEXT NOT NULL,
    period          TEXT NOT NULL,
    window_start    TIMESTAMPTZ,
    window_end      TIMESTAMPTZ,
    cv_volume       FLOAT,                   -- coeficiente de variação do volume
    green_ratio     FLOAT,                   -- % volume em candles verdes
    body_ratio      FLOAT,                   -- média body/range dos candles
    max_retraction  FLOAT,                   -- retração máxima intraday
    vol_accel       FLOAT,                   -- aceleração do volume nos últimos 3 candles
    outcome_pct     FLOAT,                   -- resultado do pump (ex: 4.41 = +441%)
    created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### 2. Script `compute_fingerprints.py` (a criar)

```bash
# Coleta 1s data dos grandes pumps históricos via Binance
python data_collector.py --market PEPEUSDT --period 1sec --source binance \
    --start 2023-04-14 --end 2023-04-21

# Computa fingerprints e salva na tabela pump_fingerprints
python compute_fingerprints.py --market PEPEUSDT --label FP-001-PEPE
```

### 3. Indicadores de micro-liquidez (extensão de `indicators.py`)

- `calc_volume_cv(candles, window)` — coeficiente de variação do volume
- `calc_organic_score(candles_5min, candles_1min)` — score 0-100 orgânico vs wash
- `calc_fingerprint_similarity(current, library)` — distância coseno vs biblioteca

Ver: [PUMP_FINGERPRINTS.md](../knowledge/PUMP_FINGERPRINTS.md), [MICRO_LIQUIDITY.md](../knowledge/MICRO_LIQUIDITY.md)

## Como Rodar

```bash
cd backtest

# instalar dependências
pip install -r requirements.txt

# rodar todos os testes
pytest -v

# coletar dados históricos (klines padrão)
python data_collector.py --market BTCUSDT --period 1hour --years 2

# coletar dados de 1 segundo para micro-estrutura (Binance daily ZIPs)
python data_collector.py --market BTCUSDT --period 1sec --source binance --start 2024-01-01 --end 2024-03-01

# rodar backtest completo (pipeline sequencial)
python signal_generator.py --market BTCUSDT --period 1hour --start 2023-01-01 --end 2025-01-01
python backtest_runner.py  --market BTCUSDT --period 1hour --start 2023-01-01 --end 2025-01-01
# → imprime relatório por regime no terminal
# → armazena backtest_trades + backtest_runs no Supabase
# → gera backtest_report.html (--html caminho/para/report.html para personalizar)
```

---

## Variáveis de Ambiente

```env
SUPABASE_URL=https://urcqtpklpfyvizcgcsia.supabase.co
SUPABASE_ANON_KEY=sb_publishable_v_dOX1JVgEm_vlT-Qr5lsw_EQHc-av-
COINEX_BACKTEST_CAPITAL=1000
```

---

## Integração com o Pipeline de Agentes

O banco de dados do backtesting não é isolado — ele **alimenta e valida todos os 7 agentes**.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SUPABASE (backtesting DB)                         │
│  candles │ backtest_signals │ backtest_trades │ backtest_runs        │
└──────┬───────────┬──────────────────┬──────────────────┬────────────┘
       │           │                  │                  │
  ┌────▼──────┐ ┌──▼──────────┐ ┌────▼──────┐ ┌────────▼──────────┐
  │ TechAgent │ │ Orchestrator│ │  Mentor   │ │ Todos os agentes  │
  │           │ │             │ │  Agent    │ │ (validação geral) │
  └───────────┘ └─────────────┘ └───────────┘ └───────────────────┘
```

### Por agente — como usa o banco

| Agente | Tabela lida | Para quê |
|--------|------------|---------|
| **TechAgent** | `candles` | Busca histórico para calcular indicadores em tempo real (contexto de ciclo) |
| **TechAgent** | `backtest_signals` | Compara sinal atual com sinais históricos similares — base histórica obrigatória (80% Pareto) |
| **OrchestratorAgent** | `backtest_runs` | Valida se estratégia tem edge antes de aprovar execução (win_rate, expectancy) |
| **MentorAgent** | `backtest_trades` | Cita padrões históricos reais: "47 setups similares, 68% resultaram em alta" |
| **MentorAgent** | `backtest_runs` | Bloqueia trade se Sharpe < 1.0 ou max_drawdown > 20% da estratégia em uso |
| **FundAgent** *(futuro)* | `candles` | Correlaciona preço com eventos fundamentais históricos |
| **SentAgent** *(futuro)* | `backtest_signals` | Valida se sentimento atual é consistente com sinais históricos vencedores |
| **ChainAgent** *(futuro)* | `candles` | Correlaciona on-chain metrics com movimentos históricos de preço |

### Fluxo de validação com dados históricos (Pareto 80%)

```
Trade proposto
    │
    ├─ OrchestratorAgent consulta backtest_runs
    │    └─ estratégia tem win_rate > 45% e expectancy > 0.3R?
    │         SE NÃO → AGUARDAR (dados insuficientes ou estratégia sem edge)
    │
    ├─ TechAgent consulta backtest_signals
    │    └─ quantos setups similares no histórico? qual o win rate deles?
    │         SE < 20 ocorrências → confiança baixa, sinal C
    │
    └─ MentorAgent consulta backtest_trades
         └─ "Setup A+ — 73 ocorrências, 71% hit target, avg +2.8R"
              SE aprovado → EXECUTAR com sizing calculado
```

---

## Limitações Conhecidas

1. **CoinEx kline limit**: verificar se API permite paginação histórica profunda.
   Fallback: usar Binance public API (mesmo OHLCV, sem autenticação).
2. **Lookahead bias**: signal_generator DEVE usar apenas candles[0..i] para bar[i].
3. **Slippage**: estimativa de 0.05% é conservadora — em altcoins pode ser maior.
4. **Sem dados de orderbook histórico**: stop loss simulado assume execução no preço exato.