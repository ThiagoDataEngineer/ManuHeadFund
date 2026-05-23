# CONSTANTS.md — Single Source of Truth

> **Criado 2026-05-16. Atualizado 2026-05-20** com constants das ondas 2/3.1.
> Catalogação de TODOS os valores hardcoded do projeto categorizados por tipo.
> Objetivo: eliminar drift entre arquivos.

## ⚡ ATUALIZACOES 2026-05-19/20

| Constante | Antes | Agora | Lib |
|---|---|---|---|
| `$CAPITAL_SPOT` bootstrap | 100 | **100** (mantido conservador, ver feedback_bootstrap_conservador.md) | config.ps1 |
| `$CAPITAL_FUTURES` bootstrap | 718 | **100** (revisado: bootstrap NUNCA reflete real; user feedback) | config.ps1 |
| `$CAPITAL_TOTAL` bootstrap | 818 | **200** (sub-real intencional pra fail-safe) | config.ps1 |
| Daily Loss threshold | -5% fixo | **CAPITAL-SCALED 2%/3%/5%** | `Get-CapitalScaledDailyLossThreshold` |
| MaxTierA concentration | 5 | **17** (expandido) | `Test-ConcentrationLimit` |
| Beta avg cap | 1.0 | **1.2 BLOCK / 1.0 WARN** (V1.6: data-driven 45 markets) | `Test-BetaConcentration` |
| FQS BLUE_CHIP threshold | – | **6/7** | `lib_fundamental_quality.ps1` V1.6 |
| FQS cycle resilience paths | 2 (explicit + young<2y) | **3** (+ partial >=50% ATH) | V1.6 partial recovery |
| FQS manual override | – | preserva `recovered_2021_ath_source='manual_override_*'` | batch merge respeita |
| Mesa cascade fallback | Groq→Gemini→Haiku 4.5 | inalterado | `lib_claude.ps1:239` |
| **Mentor cascade fallback** | Sonnet→Groq→Gemini | **Sonnet→Groq→Gemini→Haiku 4.5** | `lib_claude.ps1:287` |
| **Triagem cascade fallback** | Gemini→Groq | **Gemini→Groq→Haiku 4.5** | `lib_claude.ps1:331` |
| Mentor prompt Mesa-skip | "Mesa: pulada (Tier A direto...)" | **"Mesa: NAO_APLICAVEL (Tier A pre-validado...)"** | hallucination fix |
| Mentor prompt confluencias=0 | "[ALERTA: Mesa nao documentou]" | **"N/A (drone silent, peso reduzido)"** | hallucination fix |
| Mentor KNOWLEDGE: header | sempre injetado | **só se context não-vazio** | hallucination fix |
| Mesa.degraded no Mentor prompt | invisível | **`[DEGRADED: 1+ drone falhou]`** quando aplicável | bug invisível corrigido |
| V6 PlaceOrder flag | inexistente | **`journal/V6_LIVE_ENABLED.flag`** (opt-in adicional) | `Invoke-V6PostMentorExecution` |
| EnforceGates flag | inexistente | **`journal/ENFORCE_GATES_ENABLED.flag`** (opt-in p/ 13 gates pré-promote) | `Invoke-PromotionCycle -EnforceGates` |
| FQS prompt format | `fqs=N/7 X` (lowercase) | **`FQS=N/7 X`** (uppercase, proeminente) | anti-hallucination secundária |
| FQS missing market | omitido do prompt | **`FQS=N/A_no_registry`** explícito + enqueue | `Build-MentorFullContext` |
| FQS enrichment queue | inexistente | **`journal/fqs_enrichment_queue.jsonl`** auto-populated | `process_fqs_queue.ps1` |
| Mentor system prompt rule | sem | **`ANTI-HALLUCINATION: se CONTEXTO tem 'FQS=N/7' NUNCA escreva 'FQS nao declarado'`** | `$MENTOR_DEBATE_SYSTEM` |
| Registry size | 31 markets | **36 markets** (+XCH/LIT/RON/BU/ARB) | `coin_registry.json` |
| decisions.csv schema | 12 colunas | **13 colunas** (+ `provider_used`) | `lib_observation_logger.ps1` |
| Parallel runspace libs dot-sourced | 20 | **26** (+ fundamental_quality/pump_buy/market_router/market_router_wire/order_routed/entry_score_boost/news_entry_boost) | `lib_orchestrator_parallel.ps1` |
| Crons registered | 4 | **5** (+ `CoinExHourlyHeartbeat`) | `register_hourly_heartbeat.ps1` |
| Heartbeat behavior | só durante cycle (1440min daily sleep = silencioso 24h) | **hourly independente** via `watch_status.ps1 -Telegram` | `CoinExHourlyHeartbeat` task |
| GEM_CAPITAL_DISCOVERY | 0.002 (0.2%) | **0.005 (0.5%)** | `agents/config.ps1:135` PM4 |
| GEM_CAPITAL_MOMENTUM | 0.004 (0.4%) | **0.008 (0.8%)** | `agents/config.ps1:136` PM4 |
| Watchdog gem_loop logic | AND-logic (process dead AND log stale) | **process primary** com CIM retry 3x; log = warning secundário | `watchdog_paper.ps1:322` PM4 |
| Daemon hot-reload | inexistente | **Cron diário 03:00 BRT** `CoinExDaemonRestart` rolling kill+respawn | `daily_daemon_restart.ps1` |
| Drift detection | inexistente | watch_status mostra `[DRIFT: Xh pre-config]` por daemon | PM4 |
| **Watchdog backoff (B16)** | respawn imediato infinito | **`2^N`s exponencial + kill switch após 5 falhas consecutivas** | `lib_watchdog_backoff.ps1` PM6+390min |
| **DSR storage (B15)** | `dsr_global.json` overwrite (race) | **append-only `dsr_trials.jsonl` race-safe** (Add-Content atomic NTFS) | `lib_dsr_global.ps1` PM6+380min |
| **Daily Loss CB corruption (B17)** | silent fail-open em corrupt JSON | **fail-closed via `.corrupt` flag + `-StateCorrupt` switch** | `lib_promotion_gates.ps1:42-72` PM6+400min |
| **Price freshness (B18)** | sem validação | **`New-FreshTicker` + `Test-PriceFresh -MaxAgeSeconds 60`** | `lib_price_freshness.ps1` PM6+410min |
| **CoinEx retry (B19)** | Invoke-RestMethod throw em 429/503 | **`Invoke-WithRetry` em GET + POST não-/order** (skip /order pra evitar duplicate sem client_id) | `lib_retry.ps1` PM6+420min |
| **PlaceOrder idempotency (B19b)** | sem client_id (orphan order risk em retry) | **UUID v4 prefix `c` por PlaceOrder + persist `order_client_ids.jsonl`** — exchange dedup → retry agora safe | `lib_order_idempotency.ps1` PM6+450min |
| **Stale price gate wire (B18-wire)** | lib `lib_price_freshness.ps1` sem caller | **`CoinEx-GetTickerFresh` + gate em orchestrator_v6:573 ABORTAR se idade >60s** | `lib_coinex.ps1` + `orchestrator_v6.ps1` PM6+460min |
| **Callback idempotency (B14)** | inexistente | **`Test-CallbackIdempotent` antes do ACK** + rolling 1000 store | `lib_idempotency.ps1` PM6+350min |
| GEM_AUTO_APPROVE.flag | inexistente | **opt-in strict** (score≥90 + FQS≥QUALITY + registry + sizing≤1% + cap 3/dia) | `lib_gem_auto_approve.ps1` |
| GEM_AUTO_APPROVE STATE | OFF | **✅ ATIVO desde 2026-05-20 14:28 BRT** | `journal/GEM_AUTO_APPROVE.flag` |
| MARKET_TO_CG entries | 31 | **40** (+9 PM5: TAO/PENGU/KITE/RIVER/ARB/XCH/LIT/RON/BU) | `backtest/coingecko_enrichment.py:34` |
| Registry size | 36 markets | **40** (CoinGecko-enriched 9 PM5) | `journal/coin_registry.json` |
| GEM auto-approve elegíveis novos | RENDER/BTC/INJ/XMR + DASH/ZEC/CFG/PENDLE/etc | **+ TAO/ARB/LIT/RON QUALITY** | dependendo score≥90 |
| CoinGecko raw numbers persisted | só booleans (supply_capped, recovered_2021_ath) | **+ max_supply, circulating_supply, current_price_usd, ath_all_time_usd** | `coingecko_enrichment.py:107-128` PM5 fix |
| FQS V1.6 partial path | cego (sem dados) | **funcional** (raw current/ath now persisted) | `lib_fundamental_quality.ps1:95-100` |
| BTC prod validation 15:12 | inexistente | **Triagem tier=A score=92, Mentor VETAR conf=78 anthropic_sonnet, 0 halluc FQS** | `Invoke-OrchestratorV6` end-to-end |
| Mentor modes | 3 (TIER_A_LIVE / TIER_B_PAPER / GEM) | **4** (+ TIER_A_PAPER) | system prompt + orchestrator_v6:211-225 |
| Mode mapping orchestrator | `wl.tier='observe' → TIER_B_PAPER` cego | **Combina triagem.tier × wl.tier ortogonal** | PM6 bug semântico fix |
| BTC prod validation 15:22 (pós-fix PM6) | Mentor VETAR "CONFLITO CRÍTICO" | **Mentor APROVAR conf=82** "TIER_A_PAPER legítimo sem conflito" | ABORTAR final por MCE_BLOCK 0.1215 (defesa estrutural OK) |
| Crons registered | 5 | **8** (+ DailyDigest + WeeklyCostReport + DaemonRestart) | PM3+PM4 |
| Asymmetric demote streak | 4 sem Sharpe<0 | **3 dias FLAG consecutivos** (auto-fired) | `Test-AsymmetricDemoteCondition` |
| Kelly fraction default | – | **0.25** (quarter Kelly) | `lib_kelly_adaptive.ps1` |
| Kelly cap por mode | – | BLUE_CHIP 2%, TIER_A 1%, GEM 0.5% | `$script:MODE_CAPS` |
| Trend boost STRONG/MODERATE/NOISE | – | **+10 / +5 / -5** | `Get-EntryScoreBoost` |
| CoinGecko batch endpoint | – | `/coins/markets` 300x speedup | `coingecko_batch.py` |
| Hot wallet ratio alert | – | **0.80 default** (alerta withdraw cold) | `Test-HotWalletRatio` |

## Categorias

- 🔴 **STATE** — NÃO é constante, deve vir live (capital, fees, prices)
- 🌍 **WORLD_FACT** — Imutável (halving date, constantes matemáticas)
- 🎯 **BUSINESS_RULE** — Calibração de negócio (risk %, RR mínimo, score threshold)
- ⚙️ **RUNTIME_CONFIG** — Endpoint, paths, modelos LLM
- 🔐 **ENV_SECRET** — API keys
- 🤖 **LLM_TUNING** — Temperature, max tokens
- 💎 **GEM_HEURISTIC** — Gem detection (todos heurísticas a calibrar)
- 🔬 **BACKTEST** — Walk-forward, metrics, gate thresholds
- 📊 **REGIME** — Classifier params
- 🌐 **SCANNER** — Universe sweep params
- ⚠️ **OVERRIDE** — Opt-in override em config.local.ps1
- 🐛 **DRIFT** — Mesma constante valor diferente em arquivos distintos
- ❓ **DEAD** — Definida mas não usada no pipeline live

---

## 🔴 STATE (DEVE vir live, fallback em config)

| Variável | Bootstrap | Onde | Fonte real |
|---|---|---|---|
| `$CAPITAL_SPOT` | 100.0 | config.ps1:31 | `CoinEx-GetSpotCapitalUSDT` ✅ |
| `$CAPITAL_FUTURES` | 718.0 | config.ps1:32 | `CoinEx-GetFuturesCapitalUSDT` ✅ |
| `$CAPITAL_TOTAL` | derivado | config.ps1:33 | soma live ✅ |
| `$COINEX_FEE_MAKER_FALLBACK` | 0.0003 | config.ps1:68 | `/v2/account/trade-fee-rate` ⚠️ não pull live |
| `$COINEX_FEE_TAKER_FALLBACK` | 0.0005 | config.ps1:69 | idem ⚠️ |
| `$COINEX_FEE_ROUNDTRIP_FALLBACK` | 0.0008 | config.ps1:70 | maker+taker live ⚠️ |

**TODO:** fees não estão sendo pulled live. VIP tier do user pode ter fee menor → RR cálculo otimista vs real.

---

## 🌍 WORLD_FACT (imutáveis)

| Variável | Valor | Onde |
|---|---|---|
| `$HALVING_DATE` | 2024-04-19 | config.ps1:50 |
| `EULER_MASCHERONI` | 0.5772156649 | metrics_simons.py:18 |
| `LUNAR_CYCLE_DAYS` | 29.530588853 | calendar_effects_btc.py:191 |
| `SECONDS_PER_HOUR` | 3600 | (implícito vários lugares) |

---

## 🎯 BUSINESS_RULE (regras de negócio calibradas)

### Risk & Sizing

| Constante | Valor | Onde | Pedigree | Action |
|---|---|---|---|---|
| `$RISCO_MAXIMO_PCT` | 0.01 | config.ps1:36 | 🟡 Heurística (LdP prescreve Half-Kelly) | Refinar com Kelly dinâmico |
| `$RR_MINIMO` | 5.0 | config.ps1:37 | 🟢 Validado (derivado fee 0.08%) | OK |
| `$RR_PREFERIDO` | 5.0 | config.ps1:38 | 🟢 Igual ao mínimo | Duplicação útil |
| `$SCORE_MINIMO` | 65.0 | config.ps1:39 | 🟢 Validado 14y cross-period | 🐛 DRIFT — ver abaixo |
| `$MAX_TRADES_DIA` | 5 | config.ps1:40 | 🟡 Heurística | Calibrar com dados |
| `$MAX_RISCO_ABERTO` | 0.03 | config.ps1:41 | 🟡 Heurística (3 trades × 1%) | OK derivado |
| `$ALAVANCAGEM_MAX` | 5.0 | config.ps1:42 | 🟡 Heurística | OK |

### Agent Weights

| Constante | Valor | Pedigree |
|---|---|---|
| `$AGENT_WEIGHT_TECH/SENT/CHAIN/FUND` | 0.40/0.20/0.25/0.15 | 🟡 Soma 1.0; sem ablation |
| `$WEIGHTS_BULL` | Tech=0.40 Chain=0.30 Sent=0.20 Fund=0.10 | 🟡 Sem ablation |
| `$WEIGHTS_BEAR` | Tech=0.35 Chain=0.20 Sent=0.25 Fund=0.20 | 🟡 |
| `$WEIGHTS_NEUTRAL` | Tech=0.40 Chain=0.25 Sent=0.20 Fund=0.15 | 🟡 |

### Ciclo Halving-aware

| Constante | Valor | Onde | Pedigree |
|---|---|---|---|
| `$CYCLE_CONSOLIDATION_MONTHS` | 6 | config.ps1:51 | 🟡 Folclore crypto |
| `$CYCLE_BULL_MONTHS` | 18 | config.ps1:52 | 🟡 Folclore |
| `$CYCLE_DISTRIBUTION_MONTHS` | 24 | config.ps1:53 | 🟡 Folclore |

### Sentimento / Funding / On-chain

| Constante | Valor | Onde | Pedigree |
|---|---|---|---|
| `$FUNDING_NEUTRAL_MAX` | 0.0001 | config.ps1:57 | 🟡 Heurística |
| `$FUNDING_EXTREME` | 0.0005 | config.ps1:58 | 🟡 Heurística |
| `$LSR_LONG_EXTREME` | 0.65 | config.ps1:59 | 🟡 Heurística |
| `$LSR_SHORT_EXTREME` | 0.35 | config.ps1:60 | 🟡 Heurística |
| `$NUPL_EUFORIA` | 0.75 | config.ps1:61 | 🟡 Heurística (literatura on-chain) |

---

## ⚙️ RUNTIME_CONFIG

| Variável | Valor | Onde |
|---|---|---|
| `$COINEX_BASE_URL` | https://api.coinex.com | config.ps1:88 |
| `$COINEX_MARKET_TYPE` | FUTURES | config.ps1:89 |
| `$CLAUDE_MODEL` | claude-sonnet-4-6 | config.ps1:80 |
| `$CLAUDE_MODEL_CHEAP` | claude-haiku-4-5-20251001 | config.ps1:81 |
| `$JOURNAL_DIR` | `..\journal` | config.ps1:99 |
| `$JOURNAL_FILE` | `..\journal\trades.csv` | config.ps1:100 |
| `$LOG_DIR` | `..\logs` | config.ps1:101 |
| `$TF_HTF` | 4hour | config.ps1:93 |
| `$TF_MTF` | 1hour | config.ps1:94 |
| `$TF_LTF` | 15min | config.ps1:95 |

---

## 🔐 ENV_SECRET (em config.local.ps1, gitignored)

| Variável | Onde set |
|---|---|
| `$env:ANTHROPIC_API_KEY` | config.local.ps1:5 |
| `$env:GROQ_API_KEY` | config.local.ps1:9 |
| `$env:GEMINI_API_KEY` | config.local.ps1:46 (NOVO 2026-05-16) |
| `$env:COINEX_ACCESS_ID` | config.local.ps1:24 |
| `$env:COINEX_SECRET_KEY` | config.local.ps1:25 |
| `$env:SUPABASE_URL` | config.local.ps1:28 |
| `$env:SUPABASE_SERVICE_KEY` | config.local.ps1:30 |
| `$env:TELEGRAM_BOT_TOKEN` | config.local.ps1:34 |
| `$env:TELEGRAM_CHAT_ID` | config.local.ps1:35 |
| `$env:FRED_API_KEY` | config.local.ps1:41 |

---

## 🤖 LLM_TUNING

| Constante | Valor | Onde |
|---|---|---|
| `$CLAUDE_MAX_TOKENS` | 2048 | config.ps1:82 |
| `$CLAUDE_TEMP_TRADE` | 0.3 | config.ps1:83 |
| `$CLAUDE_TEMP_STUDY` | 0.7 | config.ps1:84 |

---

## 💎 GEM_HEURISTIC (todos heurística, calibração pendente)

| Constante | Valor | Onde |
|---|---|---|
| `$GEM_VOL_SPIKE_MIN` | 2.0 | config.ps1:106 |
| `$GEM_MCAP_DISCOVERY` | $2M | config.ps1:109 |
| `$GEM_MCAP_MOMENTUM` | $20M | config.ps1:110 |
| `$GEM_LISTING_DAYS_MAX` | 10 | config.ps1:111 |
| `$GEM_CAPITAL_DISCOVERY` | 0.002 | config.ps1:114 |
| `$GEM_CAPITAL_MOMENTUM` | 0.004 | config.ps1:115 |
| `$GEM_STOP_DISCOVERY` | 0.50 | config.ps1:118 |
| `$GEM_STOP_MOMENTUM` | 0.30 | config.ps1:119 |
| `$GEM_TARGET_DISCOVERY` | 2.00 | config.ps1:120 (RR 1:4) |
| `$GEM_TARGET_MOMENTUM` | 0.90 | config.ps1:121 (RR 1:3) |
| `$GEM_MAX_DAYS_DISC` | 30 | config.ps1:124 |
| `$GEM_MAX_DAYS_MOM` | 21 | config.ps1:125 |
| `$GEM_TRAILING_PCT` | 0.30 | config.ps1:126 |
| `$GEM_SCORE_MIN_DISC` | 70 | config.ps1:129 |
| `$GEM_SCORE_MIN_MOM` | 60 | config.ps1:130 |
| `$GEM_CV_ORGANIC_MIN` | 0.5 | config.ps1:133 — 🟢 PUMP_FINGERPRINTS.md |
| `$GEM_WASH_MAX_PCT` | 0.40 | config.ps1:134 — 🟢 idem |
| `$GEM_GREEN_RATIO_MIN` | 0.65 | config.ps1:135 — 🟢 idem |
| `$GEM_WICK_RATIO_MAX` | 2.5 | config.ps1:136 — 🟢 idem |
| `$GEM_RANGE_MIN_PCT` | 0.15 | config.ps1:139 |

---

## ⚠️ OVERRIDE (config.local.ps1 — OPT-IN runtime)

| Constante | Valor | Onde | Status |
|---|---|---|---|
| `$global:SKIP_THURSDAY_ALTS` | $false | config.local.ps1:47 | 🟢 dow_seasonality validado |
| `$global:GEM_SAFETY.MaxExposurePct` | 15.0 | config.local.ps1:53 | 🟡 Heurística |
| `$global:GEM_SAFETY.MaxGemsPerDay` | 10 | config.local.ps1:54 | 🟡 |
| `$global:GEM_SAFETY.MaxGemsPerWeek` | 40 | config.local.ps1:55 | 🟡 |
| `$global:GEM_SAFETY.CircuitBreakerStops` | 5 | config.local.ps1:56 | 🟡 |
| `$global:GEM_SAFETY.DoubleConfirmThreshold` | 10.0 | config.local.ps1:57 | 🟡 |
| `$global:ORCHESTRATOR_TOPN_OVERRIDE` | 7 | config.local.ps1:66 | ⚠️ Sem expiry |
| `$global:SCANNER_SCORE_CLAMP_OVERRIDE` | 85 | config.local.ps1:74 | 🔴 Cosmético — não está no pipeline live |
| `$global:TRIAGEM_THRESHOLDS` | D=15 B=25 A=40 | config.local.ps1:89 | 🟢 Validado runtime |

---

## 🐛 DRIFT (mesma constante, valores ou nomes diferentes — BUGS)

### DRIFT-1: Score threshold

| Onde | Nome | Valor |
|---|---|---|
| config.ps1:39 | `$SCORE_MINIMO` | 65.0 |
| signal_generator.py:23 | `SCORE_THRESHOLD` | 65.0 |
| signal_generator_v2.py:23 | `SCORE_THRESHOLD_V2` | 65.0 |

**Mesmo valor hoje, mas 3 lugares pra editar.** Fix: 1 fonte só (CONSTANTS.md → loaders PS+Python).

### DRIFT-2: GO_CRITERION_POSITIVE_PCT (valores DIFERENTES)

| Onde | Valor |
|---|---|
| benchmark_long_14y.py:36 | 70.0 |
| benchmark_walkforward_14y.py:42 | **60.0** |

**MESMA constante, valores diferentes em arquivos rodando lado a lado.** Bug ativo.

### DRIFT-3: Fee (backtest vs live)

| Onde | Valor |
|---|---|
| backtest_runner.py:32 | `fee_pct=0.10` (assumido %) |
| config.ps1:91 | `$COINEX_FEE_ROUNDTRIP_FALLBACK = 0.0008` (decimal 0.08%) |

**Backtest pessimista 25%** em fees vs live. Live deveria outperform.

### DRIFT-4: SMA200_WINDOW

| Onde | Nome | Valor |
|---|---|---|
| regime_classifier.py:19 | `SMA200_WINDOW` | 200 |
| signal_generator.py:?, benchmark_long_14y.py:38 | `SMA200_PERIOD` | 200 |
| (+ 2 outros arquivos) | | |

Mesmo valor mas 4 cópias.

### DRIFT-5: DIST_SIDEWAYS / SIDEWAYS_BAND

| Onde | Nome | Valor |
|---|---|---|
| regime_classifier.py:27 | `DIST_SIDEWAYS` | 0.02 |
| regime_8state_classifier.py:28 | `SIDEWAYS_BAND` | 0.02 |

Mesmo conceito, 2 nomes, 2 arquivos.

### DRIFT-6: DEFAULT_BULL_THRESHOLD

| Onde | Valor |
|---|---|
| cycle_recalibrate.py:59 | 10.0 |
| current_cycle_analyzer.py:63 | 10.0 |

### DRIFT-7: RR (entre PS e Python)

| Onde | Nome | Valor |
|---|---|---|
| config.ps1:37 | `$RR_MINIMO` | 5.0 |
| signal_generator.py:22 | `RR_DEFAULT` | 5.0 |

Mesmo valor, 2 lugares.

---

## ❓ DEAD (declaradas mas não usadas no pipeline live)

A confirmar via grep. Pendente próxima iteração.

---

## 🔬 BACKTEST core

| Constante | Valor | Onde |
|---|---|---|
| `MAX_BARS_FORWARD` | 50 | backtest_runner.py:27 |
| `REGIME_LOOKBACK` | 200 | backtest_runner.py:28 |
| `MIN_CANDLES` | 35 | signal_generator.py:20 |
| `ATR_STOP_MULT` | 2.0 | signal_generator.py:21 |
| `FEE_PCT` | 0.10 | backtest_runner.py:32 (🐛 ver DRIFT-3) |
| `RESAMPLE_DAYS` | 14 | backtest_2w_14y.py:29 |

---

## 📊 REGIME classifier

| Constante | Valor | Onde |
|---|---|---|
| `SMA200_WINDOW / SMA200_PERIOD` | 200 | regime_classifier.py:19 + 3 outros (🐛 DRIFT-4) |
| `WMA200_BARS_DAILY` | 1400 | regime_classifier.py:20 |
| `TRANSITION_WINDOW` | 10 | regime_classifier.py:21 |
| `TRANSITION_BARS` | 20 | regime_8state_classifier.py:27 |
| `RETURN_60D_LOOKBACK` | 60 | regime_classifier.py:22 |
| `DIST_SIDEWAYS / SIDEWAYS_BAND` | 0.02 | regime_classifier.py:27 + regime_8state:28 (🐛 DRIFT-5) |
| `DIST_STRONG` | 0.15 | regime_classifier.py:28 |
| `RETURN_60D_STRONG` | 0.15 | regime_classifier.py:29 |
| `RETURN_60D_SIDEWAYS` | 0.10 | regime_classifier.py:30 |
| `ADX_PERIOD` | 14 | regime_8state_classifier.py:26 |
| `ADX_STRONG_THRESHOLD` | 25.0 | regime_8state_classifier.py:29 |
| `CAPITULATION_THRESHOLD` | 0.25 | regime_8state_classifier.py:30 |

---

## 🎯 GO-LIVE criteria (vários arquivos, alguns drift)

| Constante | Valor | Onde |
|---|---|---|
| `GO_CRITERION_POSITIVE_PCT` (long_14y) | **70.0** | benchmark_long_14y.py:36 |
| `GO_CRITERION_TOTAL_PF` | 1.5 | benchmark_long_14y.py:37 |
| `REGIME_BAND` | 0.02 | benchmark_long_14y.py:39 |
| `GO_CRITERION_POSITIVE_PCT` (WF) | **60.0** ← 🐛 DRIFT-2 | benchmark_walkforward_14y.py:42 |
| `GO_CRITERION_MAX_STREAK` | 4 | benchmark_walkforward_14y.py:43 |
| `GO_CRITERION_ERGODICITY` | 0.40 | benchmark_walkforward_14y.py:44 |
| `GO_LIVE_DD_THRESHOLD_R` | 20.0 | benchmark_monte_carlo.py:44 |
| `DEFAULT_N_SIMS` | 10000 | benchmark_monte_carlo.py:42 |
| `DEFAULT_SEED` | 42 | benchmark_monte_carlo.py:41 |
| `DEFAULT_DISCOUNT_FACTOR` | 0.5 | risk_adjusted_metrics.py:43 |
| `GO_LIVE_THRESHOLD` | 1.5 | risk_adjusted_metrics.py:44 |

---

## 🔬 Simons Gate

| Constante | Valor | Onde |
|---|---|---|
| `N_TRIALS_PRIMARY` | 50 | run_simons_gate_real.py:41 |
| `SAMPLE_VAR` | 0.5 | run_simons_gate_real.py:42 |
| `DSR_THRESH` | 0.95 | run_simons_gate_real.py:43 |
| `PSR_THRESH` | 0.95 | run_simons_gate_real.py:44 |

---

## 📊 Strata / Edges

| Constante | Valor | Onde |
|---|---|---|
| `EDGE_STRONG_MIN` | 0.50 | benchmark_regime_strata.py:15 |
| `EDGE_MEDIUM_MIN` | 0.30 | benchmark_regime_strata.py:16 |
| `EDGE_WEAK_MIN` | 0.10 | benchmark_regime_strata.py:17 |
| `DIRECTION_MIN_EDGE` | 0.30 | benchmark_regime_strata.py:20 |
| `GO_MIN_REGIMES_WITH_EDGE` | 3 | benchmark_regime_strata.py:23 |
| `MIN_TRADES_THRESHOLD` | 5 | optimizer.py:37 |
| `MIN_N_TRADES_PER_BUCKET` | 30 | transition_up_drilldown.py:35 |
| `TRAIN_THRESHOLD` | 0.40 | transition_up_drilldown.py:36 |
| `HOLDOUT_THRESHOLD` | 0.30 | transition_up_drilldown.py:37 |
| `MIN_HOLDOUT_N` | 30 | transition_up_drilldown.py:38 |

---

## 💸 Funding Peak

| Constante | Valor | Onde |
|---|---|---|
| `DEFAULT_HOT_THRESHOLD` | 0.05 | funding_peak.py:16 |
| `DEFAULT_EXTREME_THRESHOLD` | 0.08 | funding_peak.py:17 |
| `DEFAULT_DROP_PCT` | 0.30 | funding_peak.py:18 |
| `DEFAULT_LOOKBACK_DAYS` | 14 | funding_peak.py:19 |
| `DEFAULT_PEAK_MIN_DAYS` | 5 | funding_peak.py:20 |

---

## 🌐 Scanner / Universe Sweep

| Constante | Valor | Onde |
|---|---|---|
| `MIN_MCAP_DEFAULT` | $50M | scan_top_movers.py:31 |
| `MIN_VOLUME_DEFAULT` | $10M | scan_top_movers.py:32 |
| `SIDEWAYS_BAND_PCT` | 1.0 | scan_top_movers.py:48 |
| `MIN_DAYS` | 200 | dow_universe_coinex.py:25 |
| `MAX_LIMIT` | 1000 | data_collector.py:33 |
| `RATE_LIMIT_SLEEP` | 0.4 | data_collector.py:34 |
| `MIN_AUTO_FALLBACK_CANDLES` | 100 | data_collector.py:54 |
| `BITSTAMP_MAX_LIMIT` | 1000 | data_collector.py:60 |
| `RATE_LIMIT_SEC` | 0.10 | dow_universe_coinex.py:26 |

---

## 🔄 Cycle / Drilldown

| Constante | Valor | Onde |
|---|---|---|
| `DEFAULT_BULL_THRESHOLD` | 10.0 | cycle_recalibrate.py:59 + current_cycle_analyzer.py:63 (🐛 DRIFT-6) |
| `DEFAULT_UNPRECEDENTED_THRESHOLD` | 0.3 | current_cycle_analyzer.py:65 |
| `THRESHOLD_TRAIN` | 0.70 | cycle_recalibrate.py:63 |
| `THRESHOLD_HOLDOUT` | 0.65 | cycle_recalibrate.py:64 |
| `MAX_GAP` | 0.15 | cycle_recalibrate.py:65 |
| `DEGRADATION_THRESHOLD` | 0.10 | drilldown_bull_by_year.py:18 |
| `MIN_REGIMES_MEDIUM_PLUS` | 3 | recalibrate_regime_classifier.py:36 |
| `MEDIUM_THRESHOLD` | 0.3 | recalibrate_regime_classifier.py:37 |

---

## 🧪 TEST_FIXTURES (mock values centralizados)

Valores mockados para tests devem usar essas constantes (não magic numbers):

| Constante PS | Constante Python | Valor | Uso |
|---|---|---|---|
| `$global:CONST_TEST_BTC_PRICE` | `TEST_BTC_PRICE` | 60000.0 | Mock BTC price em unit tests |
| `$global:CONST_TEST_ALT_PRICE_SUB_DOLLAR` | `TEST_ALT_PRICE_SUB_DOLLAR` | 0.5 | Mock altcoin sub-dollar (AIUSDT precision bug) |
| `$global:CONST_TEST_CAPITAL_USDT` | `TEST_CAPITAL_USDT` | 1000.0 | Mock capital padrão |
| `$global:CONST_TEST_RR_SCENARIO` | `TEST_RR_SCENARIO` | 5.0 | RR padrão pra setup tests |
| `$global:CONST_TEST_ATR_PCT` | `TEST_ATR_PCT` | 2.5 | ATR-proxy padrão |
| `$global:CONST_TEST_CHANGE_24H_BULLISH` | `TEST_CHANGE_24H_BULLISH` | 5.0 | mock bull scenario |
| `$global:CONST_TEST_CHANGE_24H_BEARISH` | `TEST_CHANGE_24H_BEARISH` | -5.0 | mock bear scenario |

**Regra:** tests novos devem importar dessas constantes. Magic numbers em testes existentes serão migrados gradualmente.

---

## 📋 Resumo executivo

**Total constantes catalogadas:** ~100+
**DRIFTs ativos identificados:** 7 (sendo 1 com VALORES DIFERENTES — DRIFT-2)
**State erroneamente como constante:** 6 (capital, fees)
**Heurísticas sem validação backtest:** ~20

## Plano de refactor (próximas fases)

### Fase 2A — Loader único
- Criar `lib/constants_loader.ps1` + `backtest/constants.py`
- Format: ler de TOML/JSON único `constants.toml`
- Funções: `Get-Constant -Name X -Category Y`

### Fase 2B — Fix DRIFT-2 imediato
- Decidir: walkforward_14y deve usar 70 ou 60?
- Provavelmente 60 é mais permissivo (walk-forward é mais conservador) — mas precisa fundamentar
- Atualizar arquivo e add test pra prevenir regress

### Fase 2C — Capital/fee live mandatory
- Refactor pra sempre tentar pull live primeiro, fallback só se API down + log WARN
- Critério: paper trade real deve usar capital REAL do usuário (não bootstrap)

### Fase 2D — Audit heurísticas
- Para cada 🟡 "Heurística sem validação":
  - Ou validar com dado real (mover para 🟢)
  - Ou marcar como "TBD calibração"

---

**Status documento:** Inicial. Próxima revisão: após Fase 2 (refactor + loaders).
