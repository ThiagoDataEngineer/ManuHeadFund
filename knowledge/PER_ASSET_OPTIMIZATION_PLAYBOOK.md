# PER_ASSET_OPTIMIZATION_PLAYBOOK.md — Framework Cross-Asset Validado

> Bíblia operacional do framework Tier 2 entregue em 2026-05-17.
> Cada ativo é uma asset-class diferente — whitelist única é fantasia.
> Este doc cristaliza a metodologia que separa edge real de overfit.
>
> Cruza com `LOPEZ_DE_PRADO.md` (PBO, triple barrier, WF), `SIMONS_RENTECH.md`
> (filosofia Renaissance), `COINEX_REFERENCE.md` (limites API).

---

## 1. Filosofia

### 1.1 Por que per-asset, não whitelist única

Crypto NÃO é uma asset-class única. Cada ativo tem:
- Estrutura de volatilidade própria
- Trend secular (BTC tem; XRP não tem; DOGE não tem)
- Microestrutura própria (volume distribuído ≠ concentrado)
- Resposta a regimes diferente

Whitelist única que funciona em todos = ilusão estatística. Insight ficou claro em 2026-05-17:
- **BTC**: trend secular ascendente (halving cycles). LONG-only daily funciona. SHORT **piora**.
- **XRP**: sem trend secular. LONG+SHORT v3 funciona. LONG-only fica tail-driven.
- **ZEC**: privacy-cap pequena. Sharpe 5.31 com R:R 1:1 (não 7:1 como BTC).

### 1.2 Renaissance approach aplicado

| Dimensão Renaissance | Aplicação cripto |
|---|---|
| Múltiplos modelos descorrelacionados | Múltiplas whitelists por asset |
| Ensemble de sinais | Cascade V6 (Triagem + Mesa + Mentor) |
| Validação científica rigorosa | Triple barrier + WF + PBO/CSCV |
| Falsificação antes de capital | Pipeline gate A/B/C tier |
| Adaptação a regime change | Per-asset taxonomy + cycle awareness |

### 1.3 Princípio diretor

**"Cada moeda tem que provar o próprio edge."** Não extrapolamos. Não generalizamos prematuramente. Cross-asset rigor > anedota.

---

## 2. Stack de código atual

Arquivos entregues 2026-05-17 (Tier 2 completo, 96/96 TDD GREEN agregado):

### 2.1 `backtest/coinex_collector.py`

Coleta candles 1day para top 20 pares CoinEx por volume USD 24h.

```python
# Top 20 markets via /v2/spot/ticker
# Para cada market: GET /v2/spot/kline?market=X&period=1day&limit=1000
# Salva: journal/candles_coinex/<MARKET>_1day.json
```

**Limitação honesta**: API pública CoinEx retorna max 1000 candles = ~2.7 anos histórico. Para majors com 10+ anos histórico, **Bitstamp** continua sendo a fonte primária (BTCUSD 2011+, XRPUSD 2017+, etc).

### 2.2 `backtest/run_cross_asset_matrix.py`

Para cada market coletado, roda matriz completa:

```
para cada market:
  carrega candles 1day
  gera entries (classify_regime + apply_regime_filter strict_v2)
  para cada (stop_atr, target_atr) ∈ [0.5, 1, 2, 3] × [1, 2, 3, 5]:
    triple_barrier_simulator → trades
    metrics_pct_returns(trades)
    walk_forward_purged(k=5) → OOS folds
    pbo_cscv(N_combinations=16) → PBO score
  salva best config + métricas
```

**Output**: `journal/cross_asset_matrix_<DATE>.json` com Sharpe, DSR, PBO, WF OOS, eq final por par.

### 2.3 `backtest/build_per_asset_whitelist.py`

Aplica decision tree pra classificar cada par em 3 tiers:

```
para cada market em cross_asset_matrix:
  if grid_PASS_count >= 12/16 AND PBO < 0.30 AND WF_OOS_positive >= 3/5:
    tier = "A_LIVE"
  elif grid_PASS_count >= 4/16 AND PBO < 0.50 AND WF_OOS_positive >= 2/5:
    tier = "B_PAPER"
  else:
    tier = "C_SKIP"
```

Output: `agents/lib_operational_whitelist.ps1` atualizado com per-asset whitelist.

### 2.4 `backtest/quant_scanner.py` (9/9 TDD GREEN)

Substitui scanner heurístico (volume × log × spread) por priorização quant:

```
priority(market) = expected_sharpe × momentum_score × tier_weight
where:
  tier_weight = { A: 1.0, B: 0.4, C: 0.0 }
  expected_sharpe = best Sharpe do market no cross_asset_matrix
  momentum_score = z-score do retorno 7d vs vol 30d
```

Modes:
- `LIVE`: apenas Tier A
- `PAPER`: A + B
- `ALL`: A + B + C (debug)

### 2.5 `agents/lib_seasonality.ps1` — DAILY_CYCLE_MODE

```powershell
if ($global:DAILY_CYCLE_MODE) {
    # 1 cycle/dia após 00:05 UTC (close daily + buffer)
    return @{ window = "DAILY"; minutes = 1440 }
}
```

Opt-in via `config.local.ps1`. Quando ativo: custo LLM ÷ 24, trade frequency ÷ 24.

### 2.6 Pipeline end-to-end

```
1. coinex_collector → coleta 20 markets daily
2. run_cross_asset_matrix → grid 16 × 20 markets + PBO + WF
3. build_per_asset_whitelist → tier A/B/C
4. quant_scanner → ranking dinâmico
5. DAILY_CYCLE_MODE on → 1 ciclo/dia
6. Cascade V6 (orchestrator_v6) → Triagem → Mesa → Mentor → decisão
7. gem_executor → ordem (paper ou live)
```

---

## 3. Critérios de tiering

### 3.1 Tier A — LIVE-READY

**Promove se**:
- Grid PASS ≥ 12/16 (75% das combinações stop/target funcionam)
- PBO < 0.30 (probabilidade overfit baixa)
- WF OOS positive ≥ 3/5 (consistência cross-period)
- Sample size ≥ 1000 candles confiáveis
- DSR ≥ 0.95 no best config
- Liquidez ≥ $5M USD 24h (executável sem slippage abusivo)

**Permite**: capital seed real ($100-500 inicial). Risk 1% padrão.

### 3.2 Tier B — PAPER

**Promove se**:
- Grid PASS ≥ 4/16 (algum edge marginal)
- PBO < 0.50 (não-claro overfit)
- WF OOS positive ≥ 2/5
- Sample ≥ 500 candles
- Liquidez ≥ $1M USD 24h

**Permite**: paper trade 30+ dias. NÃO live ainda.

**Promove para A** se em 30 dias paper:
- N trades ≥ 10
- Win rate ≥ backtest expectation × 0.85
- DD máximo ≤ backtest expectation × 1.3

### 3.3 Tier C — SKIP

**Razões pra cair em C**:
- Grid PASS < 4/16
- PBO ≥ 0.50 (overfit provável)
- WF OOS positive < 2/5
- Sample < 500 candles
- Liquidez < $1M USD 24h

**Ação**: ignore. NÃO operar, nem paper. Pode reentrar análise se asset evoluir (volume cresce, history acumula).

### 3.4 Demote A → B

Em qualquer momento, se em 30 dias live:
- DD ≥ backtest expectation × 1.5
- N trades positivos / total < backtest WR × 0.7

→ rebaixa para B, capital congelado, paper validation 30d.

---

## 4. Asset taxonomy observada (2026-05-17)

### 4.1 Trend-secular ascendente

**Exemplos**: BTC, ETH (provavelmente)
**Característica**: halving cycles, network effect, store-of-value narrative
**Whitelist ótima**: v2 LONG-only daily
**Stop/Target**: 1×ATR / 7×ATR (R:R 7:1)
**Por que SHORT piora**: trend secular faz CAPITULATION ser temporária; stop em retracement antes do bottom real

### 4.2 Bidirectional volatility

**Exemplos**: XRP, possivelmente SOL, AVAX
**Característica**: sem trend secular claro; eventos idiossincráticos (regulação, partnerships); volatilidade alta cross-period
**Whitelist ótima**: v3 LONG+SHORT (BULL_STRONG LONG + TRANSITION_UP+Mon LONG + BEAR_STRONG SHORT + CAPITULATION SHORT)
**Stop/Target**: 1×ATR / 3-5×ATR (R:R 3-5:1)
**Por que SHORT funciona**: bear runs são reais e sustentados

### 4.3 Privacy-cap pequena

**Exemplo**: ZEC (validado Tier A 2026-05-17, Sharpe 5.31)
**Característica**: small-cap niche, menos atacado por MMs, volatilidade controlada
**Whitelist ótima**: v2 LONG-only daily
**Stop/Target**: 3×ATR / 3×ATR (R:R 1:1)
**Insight surpresa**: privacy coin pequena passou onde large caps falham — provavelmente porque MMs ignoram (não vale latency arb), retail edge sobrevive

### 4.4 Hipóteses para outros perfis (a validar)

| Asset | Perfil esperado | Whitelist hipotética | Confirmar via |
|---|---|---|---|
| ETH | Trend-secular | v2 LONG-only daily | Cross-asset matrix |
| LTC | Halving cycle próprio (defasado vs BTC) | v2 LONG-only daily | Idem |
| BCH | "Zombie fork" | C SKIP provável | Idem |
| DOGE | Sentiment-driven | C SKIP provável | Idem |
| SOL | High-beta L1 | v3 LONG+SHORT | Idem |
| ADA | Slow trend | TBD | Idem |
| LINK | Utility token | TBD | Idem |
| ATOM, DOT, MATIC | L1/L2 mid-cap | TBD | Idem |

**Princípio**: nunca operar antes de cross-asset matrix passar.

---

## 5. Sample size — insight crítico

### 5.1 BTC: dois datasets, dois veredictos

| Dataset | Sample | Tier |
|---|---|---|
| CoinEx 1day (2.7y) | ~1000 candles | **C** (Sharpe 2.86, marginal) |
| Bitstamp 1day (11y) | ~4000 candles | **A** (Sharpe 5.04, PBO 0.20) |

**Conclusão**: para majors (BTC, ETH, LTC, XRP), **Bitstamp é fonte primária** (10+ anos histórico). CoinEx é fonte secundária pra ativos nativos (ZEC, KAS, etc) sem Bitstamp.

### 5.2 Mínimo viável

- < 500 candles: descarta (HYPE/TON do Tier 2 falharam aqui — PBO 0.33-1.0)
- 500-1000 candles: Tier B máximo
- 1000-2000 candles: Tier A possível com PBO rigoroso
- 2000+ candles: Tier A com confiança alta

### 5.3 Regra prática

Quando coletar histórico:
1. **Bitstamp primeiro** (majors): ETH, LTC, XRP, BCH têm 5-10y
2. **CoinEx fallback** (nativos): ZEC, KAS, GST, MEME
3. **Binance Vision**: apenas se Bitstamp/CoinEx falharem (formato CSV gratuito mas só pós-listing UM Futures)

---

## 6. Extensões propostas (não implementadas)

### 6.1 Sub-amostragem temporal

Treinar em fold A (anos 1-4), testar em fold C (anos 9-12), depois treinar em B (anos 5-8), testar em D (anos 13+). Bootstrap regime cycles.

Esforço: ~3h
Valor: detecta degradação edge entre cycles (importante pós-halving)

### 6.2 Regime stress test

Simular forced bear (e.g., 2018 sustained), forced blow-off (2017Q4, 2021Q1), sideways longo (2019). Ver se whitelist quebra em cenários específicos.

Esforço: ~6h
Valor: identifica fragilidades antes de cycle change

### 6.3 Liquidity-aware filtering

Gate na coleta: volume_usd_24h ≥ threshold. Hoje coletor não filtra — pode pegar ativos ilíquidos demais para operar.

```python
if median_volume_usd_24h(market, days=30) < LIQUIDITY_GATE:
    skip
```

Esforço: ~30min
Valor: economiza compute em assets não-operáveis

### 6.4 Cross-asset correlation matrix

Precursor de HRP allocation. Calcular Σ retornos diários entre todos pares Tier A+B.

```python
returns_matrix = df_returns[['BTC', 'ZEC', 'ETH', ...]]
correlation_matrix = returns_matrix.corr()
```

Esforço: ~2h
Valor: prepara HRP allocation quando >5 ativos forem Tier A

---

## 7. Insights surpresa do Tier 2

### 7.1 ZEC Tier A único — por quê?

Privacy coin, mid-cap (~$300M-1B), sem narrativa forte 2024-25. Mas:
- Sharpe 5.31, PBO 0.00, WF 3/5 OOS+
- Hipótese: MMs **ignoram** ZEC (não vale latency arb), retail edge sobrevive
- Hipótese: privacy narrative gera moves estruturais (regulação, breach scares) que regime classifier captura
- Hipótese: liquidez controlada filtra stop-hunts hourly que matam BTC

Investigar mais antes de capital sério. Sample 2.7y é decente mas curto.

### 7.2 HYPE / TON Tier B — armadilha clássica

- HYPE: Sharpe 12.23 (absurdo) mas PBO 0.33 + WF 0/5 + sample 357 candles
- TON: Sharpe 7.06 mas PBO 1.00 (overfit total) + sample pequeno

**Lição**: Sharpe alto sem PBO baixo = artefato. Tier 2 corretamente classificou como B (não A), evitando capital em fantasia. **Sistema funcionou.**

### 7.3 BTC Tier C em CoinEx → A em Bitstamp

Mesma asset, mesma whitelist, mesma metodologia. **Apenas sample size diferente** mudou Tier C → A.

**Lição operacional**: sample size é variável estrutural, não detalhe. Para majors, sempre usar Bitstamp 10+ anos.

---

## 8. Configuração LIVE consolidada (2026-05-17)

### 8.1 BTC sistemático

```yaml
asset:           BTCUSD
source:          Bitstamp via Supabase (11y data)
timeframe:       1day
whitelist:       v2 strict_v2 LONG-only
  - BULL_STRONG + LONG (qualquer dia)
  - TRANSITION_UP + LONG (Monday BRT only)
stop_atr:        1.0 × ATR(14)
target_atr:      7.0 × ATR(14)
max_hold:        14 dias
risk_per_trade:  1% do capital_futures
fees:            0.05% taker (CoinEx)
slippage:        0.05%
DAILY_CYCLE_MODE: true
```

Expected stats: Sharpe 5.04, win rate 37%, mean R +0.72, eq 12y 7496×.

### 8.2 ZEC sistemático

```yaml
asset:           ZECUSDT
source:          CoinEx native
timeframe:       1day
whitelist:       v2 strict_v2 LONG-only
stop_atr:        3.0 × ATR(14)
target_atr:      3.0 × ATR(14)
max_hold:        14 dias
risk_per_trade:  1% do capital_futures
fees:            0.05% taker
slippage:        0.05%
```

Expected stats: Sharpe 5.31, PBO 0.00, eq 2.7y 3.97×.

### 8.3 Sequência operacional

```
00:05 UTC daily candle close
  ↓
quant_scanner.py rankeia Tier A + B markets
  ↓
para cada market priorizado:
  scan_master → classify_regime → apply_regime_filter (per-asset whitelist)
  ↓
  se sinal:
    Cascade V6:
      Triagem (Gemini/Groq) → tier A/B/C/D
      se ≥ B:
        Mesa drones (3 paralelos: Termal/Radar/Lidar)
        ↓
        se consensus FORTE_3 ou MEDIO_2:
          Mentor (Sonnet 4.6) → decisão final
          ↓
          se APROVAR:
            gem_executor → ordem (paper ou live)
```

---

## 9. Roadmap de extensão

### 9.1 Curto prazo (1-2 semanas)

1. **Coletar Bitstamp histórico** para ETH, LTC, XRP (10+ anos) → expande matrix com long-history
2. **Rodar cross_asset_matrix** com novos dados
3. **Identificar Tier A + B adicionais** para portfolio diversification
4. **Integrar quant_scanner** ao orchestrator_v6 (substituir scanner heurístico)
5. **Migrar paper V6 hourly → daily** (`$global:DAILY_CYCLE_MODE = $true`)

### 9.2 Médio prazo (1-2 meses)

6. **Capital seed real** após 7-14 dias paper daily validado
7. **Meta-labeling per-asset** (M1=whitelist, M2=LightGBM com P(win))
8. **Sigmoid bet sizing** substituindo 1% fixo
9. **Liquidity-aware filtering** no coletor

### 9.3 Longo prazo (3-6 meses)

10. **Cross-asset HRP allocation** quando ≥5 Tier A
11. **Carry trade BTC** (não-direcional, edge estrutural funding)
12. **Pairs trading** (ETH/BTC, BTC/ZEC se correlação for instável)
13. **Hedge layer** (delta neutral, basis arb)

---

## 10. Referências cruzadas

- [[LOPEZ_DE_PRADO]] — PBO/CSCV (§3.9), triple barrier (§3.3), walk-forward purged (§3.6), meta-labeling (§3.4), sigmoid sizing (§3.14)
- [[SIMONS_RENTECH]] — filosofia Renaissance, multi-model ensemble, falsification-first
- [[COINEX_REFERENCE]] — limites API v2 (1000 candles max, margin endpoints, fees por tier)
- [[CRYPTO_ACADEMIC_FOUNDATIONS]] — Makarov/Schoar cross-exchange, Liu/Tsyvinski factor analysis
- [[CRYPTO_MARKET_MICROSTRUCTURE]] — por que daily salvou BTC (microstructure noise filtering)
- [[MANIPULATION]] — stop hunts, Wyckoff Springs (background pra entender por que stops em hourly explodem)
- [[MARKET_CYCLES]] — halving, sazonalidade, Weinstein

Memórias críticas:
- `project_tier2_complete_2026_05_17` — entrega que originou este doc
- `project_btc_final_verdict_2026_05_17` — BTC v2 daily validado
- `project_btc_daily_edge_2026_05_17` — breakthrough hourly→daily

---

## 11. Sources

- AFML (López de Prado 2018) — Chapter 3 (Triple Barrier), 7 (Purged K-Fold), 11 (PBO/CSCV)
- Bailey, López de Prado, Borwein, Zhu (2014) — "The Probability of Backtest Overfitting", J. Computational Finance
- Bailey, López de Prado (2014) — "The Deflated Sharpe Ratio", JPM
- Bitstamp public API v2 — `https://www.bitstamp.net/api/v2/ohlc/<pair>/?step=86400`
- CoinEx public API v2 — `https://api.coinex.com/v2/spot/kline`
- Supabase project — BTC candles 1day 2014-2025
- Journal artefatos:
  - `journal/btc_daily_grid_2026_05_17.json`
  - `journal/cross_asset_matrix_2026_05_17.json`
  - `journal/pbo_validation_2026_05_17.json`
  - `journal/entries_btc_daily_2026_05_17.json`
- Memórias originadoras:
  - `project_tier2_complete_2026_05_17.md`
  - `project_btc_final_verdict_2026_05_17.md`
  - `project_btc_daily_edge_2026_05_17.md`
  - `project_grid_search_finding_2026_05_17.md`
  - `project_triple_barrier_finding_2026_05_16.md`
