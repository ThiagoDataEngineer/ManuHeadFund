# PROJECT_MAP.md — Mapa estrutural

> **Propósito:** ponto único pra responder "onde fica X?" sem `grep`.
> **Última atualização:** 2026-05-19 (pós-saneamento estrutural).
> **Atualizar:** quando mover arquivo importante OU criar novo módulo/lib.

---

## Root limpo (4 arquivos + dirs)

```
README.md                       entry point + quick start
CLAUDE.md                       persona p/ Claude Code (root convention)
.gitignore                      patterns protegidos
PSScriptAnalyzerSettings.psd1   PSScriptAnalyzer config (root convention)
```

**Tudo o resto está em `docs/`, `scripts/`, `agents/`, `backtest/`, `tests/`, `knowledge/`, `journal/`, `logs/`.**

---

## Convenções

| Sigla / pattern | O que significa |
|---|---|
| `lib_*.ps1` | Módulo PowerShell sem entry point (importável via dot-source) |
| `*_agent.ps1` | Agente LLM (Claude/Groq/Gemini) |
| `benchmark_*.py` | Backtest histórico, output em `journal/` |
| `scan_*.py`, `scan_*.ps1` | Scanner ativo (não-histórico) |
| `*.Tests.ps1` | Pester test file |
| `test_*.py` | pytest test file |
| `_legacy/` | Arquivos arquivados, não rodados em produção |

---

## Mapa por pasta

### `agents/` — 60 módulos (motor LIVE)
Tudo que é importado pelo `orchestrator_v6.ps1` ou pelo cron.

**Tipos:**
- **`lib_*.ps1`** (~40 módulos) — biblioteca pura, sem I/O direto a APIs externas (exceto wrappers explícitos)
- **`*_agent.ps1`** (~10) — agentes LLM
- **Orquestradores:** `orchestrator_v6.ps1` (atual), `orchestrator.ps1` (legacy)
- **Executores:** `gem_executor.ps1`, `scanner.ps1`, `scan_master.ps1`

**Principais libs (alfabético):**

| Módulo | Função |
|---|---|
| `lib_atr_stop.ps1` | ATR stop calculation (Soros guardrail) |
| `lib_coinex.ps1` | Wrapper API CoinEx (auth, orders, candles) |
| `lib_coinex_news.ps1` | Feed CoinEx news triage |
| `lib_csv_utils.ps1` | RFC4180 quoting helper (`ConvertTo-CsvField`) — DRY SSoT pra escape de campos texto |
| `lib_cycle_indicators.ps1` | Pi Cycle, 200WMA, NUPL, ATH DD |
| `lib_dsr_global.ps1` | DSR multi-test counter (Bailey-LdP) — **B15**: append-only JSONL race-safe |
| `lib_gem_decision_cache.ps1` | TTL cache pra evitar GEM re-veto loop (B9) |
| `lib_halving_phase_alert.ps1` | Detect+alert halving phase change |
| `lib_idea_triggers.ps1` | Price alerts via Telegram |
| `lib_idempotency.ps1` | Callback idempotency key (B14) — duplicate trade impossível |
| `lib_order_idempotency.ps1` | **B19b** PlaceOrder client_id UUID — exchange dedup, retry safe em POST /order |
| `lib_kelly_sizing.ps1` | Kelly fracionário (Simons/Berlekamp) |
| `lib_living_whitelist.ps1` | Auto-add BULL_STRONG → OBSERVATION |
| `lib_market_context_engine.ps1` | MCE: 6 fatores × score (DoW, season, halving, session, macro, regime) |
| `lib_mentor_invariants.ps1` | Pre-mentor payload validation (4-mode ortogonal) — reject sem LLM call |
| `lib_meta_label_short.ps1` | (não existe em PS; ver `backtest/meta_label_short.py`) |
| `lib_price_freshness.ps1` | Stale price detection (B18) — `Test-PriceFresh` fail-closed |
| `lib_promotion_ladder.ps1` | State machine OBSERVATION→PAPER→LIVE |
| `lib_retry.ps1` | `Invoke-WithRetry` + `Test-CoinExRetriable` (B19 — backoff transient) |
| `lib_runspace_audit.ps1` | `Test-RunspaceLibsComplete` — preventivo runspace child gap |
| `lib_seasonality.ps1` | DoW + month adjustments |
| `lib_telegram.ps1` | Send/format Telegram messages |
| `lib_trailing.ps1` | Trailing stop logic |
| `lib_trendline_filter.ps1` | Tori A+ trendline (paridade com `backtest/trendline_filter.py`) |
| `lib_watchdog_backoff.ps1` | Watchdog backoff exponencial + kill switch (B16) — anti respawn-loop |

**Agentes LLM:**

| Módulo | Provider | Função |
|---|---|---|
| `mesa_agent.ps1` | Groq (llama+qwen+gemma) | Esquadrão V6: 3 drones consenso |
| `mentor_agent.ps1` (agents/) | Claude | Persona Livermore/Tudor/Druckenmiller |
| `tech_agent_ai.ps1` | Claude | Análise técnica IA |
| `tech_agent.ps1` (**root**) | — | Indicadores HARDCODED (RSI/BB/EMA/ADX/ATR/Stoch). Usado por `lib_indicators.ps1`. |

---

### `backtest/` — 131 módulos (validação histórica)
Tudo que processa candles históricos, gera trades, calcula métricas.

**Subgrupos lógicos:**

| Tipo | Pattern | Exemplos |
|---|---|---|
| **Benchmarks** | `benchmark_*.py` | `benchmark_long_14y.py`, `benchmark_short_v6_btc.py`, `benchmark_bull_weak_trendline.py` |
| **Scanners ativos** | `scan_*.py`, `snapshot_*.py` | `snapshot_all_coinex.py`, `scan_top_movers.py`, `scan_new_listings.py` |
| **Validadores** | `validate_*.py` | `validate_strict_v3_phase.py` |
| **Monitores cron** | `*_monitor.py` | `tier_a_drawdown_monitor.py`, `regime_change_monitor.py` |
| **Lib core** | módulos sem prefixo | `signal_generator.py`, `metrics.py`, `regime_8state_classifier.py`, `trendline_filter.py`, `meta_label_short.py` |
| **Pipelines** | `weekly_discovery.py`, `run_cross_asset_matrix.py`, `build_per_asset_whitelist.py` | Cron weekly |

---

### `scripts/` — 18 scripts (runners + manuais)
Entry points executáveis. Não importados, só executados.

| Script | Função | Frequência |
|---|---|---|
| `promotion_weekly_cron.ps1` | **Cron diário 02h BRT** — orquestra todos os daily checks | Diário |
| `telegram_listener.ps1` | Bot interativo (poll getUpdates) | Sempre rodando |
| `watchdog_paper.ps1` | Supervisiona gem_loop + scan_master | Sempre rodando |
| `register_promotion_cron.ps1` | Cadastra task no Task Scheduler | One-shot |
| `gem_loop.ps1` | Loop scanner gem coins | Sempre rodando |

`scripts/_legacy/` — dryruns antigos (`_run_orchestrator.ps1`, `_trendline_dryrun.ps1`).

---

### `tests/` — 83 Pester (.Tests.ps1)
Convenção:
- `lib_X.Tests.ps1` testa `agents/lib_X.ps1`
- Helpers no topo do arquivo, fixtures inline
- Pester 3.x sintaxe (Should Not BeNullOrEmpty, sem colon)

### `backtest/tests/` — ~30 pytest
- `test_X.py` testa `backtest/X.py`
- Classes `TestY` agrupam casos relacionados

---

### `knowledge/` — 28 docs trading (referência canônica)

Categorias:

| Categoria | Docs |
|---|---|
| **Análise técnica** | TECHNICAL_ANALYSIS, INDICATORS_REFERENCE, SCALP_DAYTRADING |
| **Smart Money / institucional** | WYCKOFF_SMC, MANIPULATION, CRYPTO_MARKET_MICROSTRUCTURE |
| **Especialização** | BEAR_MARKET, GEM_COINS, MICRO_LIQUIDITY, NARRATIVE_CATALYSTS, PUMP_FINGERPRINTS |
| **Macro/Ciclos** | MARKET_CYCLES, MACRO_CONTEXT, ONCHAIN_ANALYSIS, MARKET_TIMING_BRT |
| **Risco** | RISK_MANAGEMENT |
| **Mestres/Personas** | MENTOR, MENTOR_PROMPT, TORI_TRADES, MELAO_SATURNO, SIMONS_RENTECH, LOPEZ_DE_PRADO, REFERENCES_LIBRARY |
| **CoinEx** | COINEX_REFERENCE |
| **Path** | PATH_TO_1PCT |
| **Acadêmicos** | CRYPTO_ACADEMIC_FOUNDATIONS, PER_ASSET_OPTIMIZATION_PLAYBOOK |

---

### `docs/` — schemas + arquitetura + refinos

| Doc | Propósito |
|---|---|
| `PROJECT_MAP.md` | **Este arquivo** |
| `ARCHITECTURE_TATICA.md` | Pipeline militar 24 codinomes, ASCII + Mermaid |
| `CONSTANTS.md` | Single Source of Truth (PS + Python loaders, em construção) |
| `PARITY_CONTRACTS.md` | 12 contratos cross-language PS↔Python |
| `PROMOTION_LADDER_SCHEMA.md` | Schema do state machine DESCOBERTA→LIVE |
| `REFINO_REGIMES_2026_05_19.md` | Plano de refino regimes + findings + validação |
| `_legacy/` | FIX_SUMMARY, README_FIX, backtest_report.html (arquivado) |

---

### `journal/` — outputs persistentes

| Arquivo | Conteúdo |
|---|---|
| `per_asset_whitelist_*.json` | Whitelist atual por tier (A LIVE / B PAPER / C SKIP) |
| `tier_a_drawdown_<DATE>.json` | Snapshot diário pullbacks Tier A |
| `halving_phase_state.json` | Phase atual + timestamp (auto cron) |
| `regime_state.json` | Regime BTC atual + ultima transition |
| `promotion_pipeline.jsonl` | Append-only events do state machine |
| `dsr_trials.jsonl` | **NOVO B15** — append-only DSR trials (race-safe entre 9+ gates concurrent) |
| `dsr_global.legacy.json` | Legacy DSR aggregate (read-only, 90 trials migrados pro JSONL) |
| `decisions_text.jsonl` | **D3 sidecar** — texto livre Mentor (reason/alerta) sem corruption CSV |
| `telegram_callbacks_processed.json` | B14 idempotency store (rolling 1000) |
| `order_client_ids.jsonl` | **B19b** PlaceOrder client_id append-only (audit + recovery, status updates) |
| `watchdog_respawn_state.json` | B16 backoff state per-daemon (failures, last_failure, killed) |
| `gem_recent_decisions.json` | B9 TTL cache (60min) pra GEM same-(market,reason) skip |
| `equity_daily_YYYYMMDD.json` | Daily Loss CB baseline — fail-closed em corrupt (B17) |
| `idea_triggers.jsonl` | Price alerts user (/idea) |
| `observations.csv` | Trades log (paper + live) |
| `trades.csv` | Trades executados |
| `cost_tracker.jsonl` | Custo LLM por chamada |
| `candles_coinex/*.json` | Candles cached por market |
| `entries_coinex/entries_*.json` | Entries signal_generator |
| `entries_coinex/alldicts_*.json` | Candles + indicadores |

---

### `memory/` — DEPRECATED no root
Auto-memory do Claude Code vive em:
`C:\Users\thiag\.claude\projects\c--Users-thiag-Coinex-AI-USER-API\memory\`

Indice em `MEMORY.md` daquele dir. NÃO usar `memory/` no root.

---

## Scripts em `scripts/` (CLI tools + launchers + cron)

Pós-saneamento 2026-05-19. Tudo que **executa** vive aqui.

| Script | Função |
|---|---|
| `promotion_weekly_cron.ps1` | **Cron diário 02h BRT** — orquestra daily checks |
| `telegram_listener.ps1` | Bot interativo (sempre rodando) |
| `watchdog_paper.ps1` | Supervisiona gem_loop + scan_master |
| `gem_loop.ps1` | Loop scanner gem coins |
| `register_promotion_cron.ps1` | Cadastra task no Task Scheduler |
| `start_services.ps1` / `.bat` | Inicializa daemons |
| `QUICK_COMMANDS.bat` | Atalhos pra user |
| `mentor_agent_cli.ps1` | Standalone interativo Claude/Groq/Gemini (não confundir com `agents/mentor_agent.ps1`) |
| `tech_agent.ps1` | Indicadores hardcoded — chamado por `agents/lib_indicators.ps1`, `agents/scanner.ps1`, `agents/tech_agent_ai.ps1` via `$PSScriptRoot\..\scripts\tech_agent.ps1` |
| `trailing_long.ps1` / `trailing_short.ps1` / `trailing_stop.ps1` | Trailing stop CLI standalone |
| `update_knowledge.ps1` | Sync knowledge base |
| `_legacy/` | Dryruns arquivados (`_run_orchestrator.ps1`, `_trendline_dryrun.ps1`) |

---

## Dependency graph (alto nível)

```
                        ┌─────────────────┐
                        │ Task Scheduler  │
                        │ daily 02h BRT   │
                        └────────┬────────┘
                                 ▼
              ┌──────────────────────────────────────┐
              │ scripts/promotion_weekly_cron.ps1    │
              └─┬───┬───┬───┬───┬───┬───┬───┬───┬───┘
                │   │   │   │   │   │   │   │   │
                ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼   ▼
   Halving Phase Tier A Regime    Promotion  Weekly  Living
   Check         Drawdown Monitor Cycle      Disc.   Whitelist

         ┌────────────────┐
         │ orchestrator_v6│ ← chamado por scanner/gem_executor em LIVE
         └───────┬────────┘
                 │
                 ▼
   BATEDOR → PORTEIRO → ESQUADRÃO (3 drones) → GENERAL → APROVADOR HUMANO
   (Groq)    (lib)      (mesa_agent.ps1)        (Claude) (Telegram /ok)
```

Detalhes completos: [ARCHITECTURE_TATICA.md](ARCHITECTURE_TATICA.md).

---

## Como buscar contexto eficientemente

Quando o assistente precisa entender o sistema, ordem ideal de leitura:

1. **README.md** (root) — orientação geral
2. **PROJECT_MAP.md** (este) — onde fica X
3. **MEMORY.md** (.claude/.../memory/) — estado atual + decisões recentes
4. Arquivo específico só após localizar via PROJECT_MAP

Evitar `grep` cego em 131 arquivos `backtest/` — usar pattern + tipo nessa tabela primeiro.
