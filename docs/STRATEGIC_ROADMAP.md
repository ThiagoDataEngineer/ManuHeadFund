# Strategic Roadmap

Documento vivo. Estagio atual sessao 2026-05-19 PM.

## Filosofia
Toda evolucao deve ser: efetiva, barata, rapida, otima, retroalimentada
(ideias + correcoes). TDD-first. Docs sempre updated.

---

## ONDA 1 — Source-aware downstream (ENTREGUE 2026-05-19)

**Problema resolvido**: gap de visibilidade pos-GEM. Estagios downstream nao
sabiam diferenciar fonte (GEM vs TIER_A_LIVE vs STANDARD) e aplicavam mesma
logica pra todos.

**Entregue**:
- `lib_trailing.ps1` Add-TrailingPosition persiste `mode`, `max_days`, `dd_threshold_pct`
- `Update-TrailingStops` enforce `max_days` (GEM positions auto-close)
- `tier_a_drawdown_monitor.py` thresholds source-aware (GEM tolera ate -45% antes CRITICAL)
- `docs/PIPELINE_POST_DISCOVERY.md` mapeia o que cada estagio valida
- TDD: 9 PS Pester + 7 Python = **16 testes GREEN**

---

## ONDA 2 — Quick wins e trend optimization [TODAS CONCLUIDAS 2026-05-19 PM]

### 2.1 ✅ Trend persistence detection (ENTREGUE)
- `backtest/trend_persistence.py` (Hurst R/S + Kaufman Efficiency Ratio)
- ZEC + INJ identificados como MODERATE_TREND (KER 0.43+)
- Pronto pra wire como entry boost no orchestrator (proximo)

### 2.2 ✅ News-driven entry boost (ENTREGUE 2026-05-19 PM)
- `lib_news_entry_boost.ps1` (composite 4 fontes: ideas + news + trend + funding) + `lib_entry_score_boost.ps1` (trend direto)
- Wire em orchestrator_v6 post-Mentor-APROVAR (STRONG +10 / MODERATE +5 / NOISE -5)
- TDD: 12 + 9 = 21 GREEN

### 2.3 ✅ Spot routing no orchestrator_v6 (ENTREGUE 2026-05-19 PM)
- `lib_market_router.ps1` (pure) + `lib_market_router_wire.ps1` (live CoinEx probe)
- Add-MarketRouteToContext em orchestrator_v6 fase 0 + Get-GemRouteForMarket em gem_executor
- TDD: 14 GREEN. Decision wired; order execution path stays futures (rollout cauteloso).

### 2.4 ✅ Feedback loop pos-trade (ENTREGUE 2026-05-19 PM)
- `lib_feedback_loop.ps1` (Add-TradeOutcome + Get-OutcomeStats + Get-RegimeAdjustment)
- Wire em Close-TrailingPosition: emite R-multiple + exit_reason
- TDD: 10 GREEN
- Pending: weekly aggregation -> adjust score weights (require trade outcomes acumulando)

### 2.5 ✅ Kelly-fractional adaptive sizing (ENTREGUE 2026-05-19 PM)
- `lib_kelly_adaptive.ps1` (math) + `lib_kelly_wire.ps1` + `lib_executor_sizing.ps1`
- Wire em gem_executor + position_sizer com $global:USE_KELLY_SIZING flag (default OFF)
- TDD: 14 + 4 + 4 = 22 GREEN
- Auto-fallback fixed 1% ate 10+ trade outcomes

---

## ONDA 3 — Fundamental Quality + Adaptive Learning [3.1 CONCLUIDA 2026-05-19 PM]

### 3.1 ✅ Fundamental Quality Score MVP V1.5 (ENTREGUE)
- `lib_fundamental_quality.ps1` (Get-FundamentalScore + Test-FundamentalQualityGate)
- `journal/coin_registry.json` (32 markets curated)
- V1.5 refinos: young_NA_cycle bonus + burn_net_deflation + concentration_insider override
- Wire em `Invoke-AllGates` (opt-in via -TargetTier)
- Wire em `weekly_discovery.py` (fqs_gate_discovery.py)
- CoinGecko enrichment: per-coin (full) + batch (300x speedup) + --new-only auto-detect
- Cron weekly_data_refresh.ps1 inclui CoinGecko batch + new-only cascade
- TDD: 13 + 14 + 17 + 12 = 56 GREEN

### 3.1.1 ✅ Recalibragens 2026-05-20 (ENTREGUE)
**Trigger**: BTC FQS dropou 6→5 (CoinGecko ATH all-time $108K-2025 > current $77K), beta cap 1.0 muito restritivo, Bitstamp markets mislocated.

- **FQS V1.5 → V1.6** terceiro path cycle resilience: `current_price >= 0.5 * ath_all_time` (recovered_partial)
- **BTC manual override**: `recovered_2021_ath=true source=manual_override_semantic_match_2021_bear_2022_recovered` (FQS restaurado 6 BLUE_CHIP)
- **SOL manual override**: idem (note ja confirmava "Recover ATH 2021 sim")
- **Batch persist** `current_price_usd` + `ath_all_time_usd` no `coingecko_batch.py` (V1.6 partial path agora funcional)
- **merge_batch_into_registry** respeita `manual_override_*` (nao sobrescreve)
- **Beta threshold 1.0 → 1.2 BLOCK / 1.0 WARN** (V1.6 data-driven 45 markets: 49% diversifier negativos, median 0.00)
- **Bitstamp realocado**: ETHUSD/LTCUSD/BTCUSD-BITSTAMP de TIER_B_PAPER → TIER_REFERENCE (v3.10)
- **Telegram listener**: `/scan` reply clarifies "PromotionCron disparado"; `/promote` alias
- TDD: 17 PS Pester + 4 V1.6 = **21 GREEN adicional**

### 3.1.2 ✅ Mentor hallucination resolvido + cascade completo (ENTREGUE 2026-05-20 PM)

**Trigger**: audit profundo revelou Mentor vetando 11/13 (85%) com 81% hallucination ("Mesa pulou", "[ALERTA]", "knowledge empty"). Validado em prod 10:41 BRT.

**3 fixes cirurgicos** (zero arquitetura, so prompt engineering):
- Tipo A: `mentor_agent.ps1:466` Mesa-skip string "pulada" → "NAO_APLICAVEL"
- Tipo C: `mentor_agent.ps1:459` `[ALERTA]` → "N/A (drone silent)"
- Tipo B: `mentor_agent.ps1:506` KNOWLEDGE: header agora condicional

**+ Mesa.degraded sinalizado pro Mentor** (era invisivel)

**+ Cascade Haiku completo**:
- Mentor: 4 niveis (Sonnet → Groq → Gemini → **Haiku**)
- Triagem: 3 niveis (Gemini → Groq → **Haiku**)
- Mesa: 3 niveis (ja tinha — Groq → Gemini → Haiku)

**+ Provider trace**: `$script:LAST_CASCADE_PROVIDER` captura qual LLM respondeu cada decisao (anthropic_sonnet/groq_llama70b/gemini_2_flash/anthropic_haiku) — saber qual modelo erra mais.

**Resultado em prod**:
| Metric | Antes | Depois | Delta |
|---|---|---|---|
| VETAR rate | 11/13 (85%) | 4/7 (57%) | -28pts |
| APROVAR rate | 0/13 (0%) | 2/7 (29%) | +29pts |
| Hallucination "Mesa pulou" | 6/13 (46%) | 0/7 (0%) | **ELIMINADO** |
| VETARs legitimos | 1/13 (8%) | 4/4 (100%) | +92pts |

Cascade Haiku salvou em prod: `[mesa_lidar] Gemini 429 → Haiku raw_len=1363`. Sem Haiku seria fail-safe VETO.

**TDD**: 17 cascade + 28 Mentor (3 hallucination fixes + degraded + provider trace) = 45 GREEN incremental.

### 3.1.21 ✅ C6 JSON Contract — 3 camadas defesa + repair retroativo (ENTREGUE 2026-05-20 PM6 +700min)

**Trigger**: user notou em logs que **HYPE** tinha `failures` serializado char-by-char enquanto outros markets tinham array correto. Insight: bug write-time silent corruption.

**Root cause (2 bugs latentes PS 5.1):**
1. **Property assignment unwrap**: `$x = $obj.failures` quando array tem 1 elemento → `$x` vira `String`
2. **ConvertTo-Json -Compress scalar**: `@("a")` serializa como `"a"` (string) não `["a"]`

**Sintoma prod**: 8/102 entries (7.8%) em `promotion_pipeline.jsonl` corrompidas durante 5 dias, **todas HYPEUSDT**. Replay analyzer e daily_digest leram char-by-char sem detectar.

**Entregue 3 camadas (~120min, 53 TDD novos):**

**FASE H — Helper write-side `lib_json_contract.ps1`**:
- `ConvertTo-NormalizedJson -ArrayFields -NestedPaths`: força `@()` wrap antes de serializar
- `Get-NormalizedJsonArray`: re-wrap defensivo read-side
- `Test-JsonSchemaArray`: predicate validator
- Globais `$JSON_CONTRACT_COMMON_ARRAY_FIELDS` (10 fields) + `$JSON_CONTRACT_COMMON_NESTED_PATHS` (3)
- **CRITICAL**: helper usa `PSObject.Properties[name].Value` em vez de `$obj.field` pra preservar tipo

**FASE I — Schema validators `lib_schema_validators.ps1`**:
- `Test-PromotionEventSchema`: valida event shape (failures/reasons/blocked_by array)
- `Invoke-PromotionPipelineAudit`: audita arquivo, retorna report
- Wire em `daily_summary_digest.ps1` linha "Schema audit: N invalid (X%)"

**FASE J1 — round-trip TDD generalizado**:
- `tests/c6_round_trip_writers.Tests.ps1`: escreve 1-elemento + lê back + asserta array
- 4 PASS incluindo caso real "failure passada como STRING"

**FASE J2 — audit retroativo + repair in-place**:
- `scripts/repair_promotion_pipeline_schema.ps1`: re-normaliza linhas corruptas, backup automático, anota `_schema_repaired` timestamp
- **Resultado**: 8/8 HYPE entries reparadas. Pos-repair: 102/102 valid (0% corruption)

**Migrações aplicadas**:
- `Add-PromotionEvent` em `lib_promotion_ladder.ps1`: usa `ConvertTo-NormalizedJson`
- `lib_gem_auto_approve.ps1`, `lib_fundamental_quality.ps1`: `[string[]]@()` wrap em returns

**Skill 22 nova**: `feedback_ps51_json_array_contract.md` — 2 bugs documentados + anti-pattern + checklist.

**Validação retroativa em prod**:
```
Antes: 102 lines, 94 valid, 8 invalid (7.8%) → todos HYPE
Depois: 102 lines, 102 valid, 0 invalid (0%)
Backup: promotion_pipeline.jsonl.bak_schema_20260520_235355
```

**Daemons fresh**: gem_loop / scan_master 23304 / tg_listener 23388 / watchdog 21392.

### 3.1.20 ✅ Strategy edge audit — B23 Sharpe ceiling + B24 pump-after-discovery (ENTREGUE 2026-05-20 PM6 +520min)

**Contexto**: user recomendou mudar foco de bugs de código pra risco **metodológico**. Caso PENDLE -19% dia 1 vs Sharpe 8.75 backtest = bug metodológico, não bug de código.

**Pattern estatístico confirmado em prod**:

| Sharpe | Markets | Outcome |
|--------|---------|---------|
| > 5 | PENDLE 8.75, CFG 8.48 | **2/2 desastre** (demoted) |
| 2-4 | RENDER 3.63, INJ 3.88, ZEC 2.86, SKY 2.57 | 4/4 OK |

**3 vieses metodológicos identificados:**
- **V1 — Pump-after-discovery**: PENDLE promovido com mom_20d=+33%. Backtest valida edge histórica mas janela de descoberta era exatamente o pico realizado. Buy-the-top latente.
- **V2 — Sharpe outlier overfit**: > 5 = red flag (lookahead, regime concentration, sample pequeno, triple-barrier missing)
- **V3 — Regime-blind**: backtest 4.5y mistura bull/bear, phase atual phase_3_bear

**Entregue (~50min, 12 TDD novos, 0 regressions):**

**B23 — `lib_methodology_gates.ps1:Test-SharpeCeilingGate`**:
- Sharpe > 5 → BLOCK `overfit_red_flag`
- Sharpe 4-5 → PASS warn `suspect`
- Sharpe 2-4 → PASS `robust`
- Sharpe 1.5-2 → PASS `marginal`
- Sharpe ≤ 0 → BLOCK `no_edge`

**B24 — `Test-PumpAfterDiscoveryGate`**:
- mom_20d > 25% → BLOCK `chase_trap` (PENDLE +33% caso real)
- mom_20d 15-25% → WARN
- < 15% (incluindo negativo) → OK

**Wire em `Invoke-AllGates`** (lib_promotion_gates.ps1:679-684): opt-in via params `-Sharpe` + `-Mom20dPct`.

**Validação retroativa**: B23+B24 ativos em 2026-05-18 teriam BLOCKED PENDLE em 2 dimensões + CFG em Sharpe. EV salvo: ~$280 (drawdown -19% × sizing).

**B25 deferred — Regime-conditioned Sharpe**:
- Requer re-rodar backtests split por halving_phase (4 phases)
- Custo: ~4h dev + re-runs + 30+ TDD
- Defer próxima sessão com bandwidth Python
- Por hora: B23+B24 cobrem 100% dos desastres observados

**Skill nova permanente**: `feedback_sharpe_outlier_red_flag.md` — regra empírica + mecanismos + custo aceito

### 3.1.19 ✅ B20 spot client_id parity + B21 dead code + B22 dedup assumption docs (ENTREGUE 2026-05-20 PM6 +490min)

**Contexto**: meta-audit user PM6+ identificou 3 gaps residuais pós-3.1.18:
- **B20** — `CoinEx-PlaceSpotOrder` + `CoinEx-PlaceSpotStopOrder` SEM client_id (spot wallet $800 exposto sem proteção idempotency)
- **B21** — Dead code embaraçoso em `_Order-GenerateClientId` (gera GUID, descarta com Out-Null, gera OUTRO)
- **B22** — Comment afirma "exchange dedup via client_id" sem citar docs nem smoke test (assumption não-validada)

**Entregue (~25min, 5 TDD anti-regression, 0 regressions):**

**B21 — Dead code removed**:
- `lib_order_idempotency.ps1:15-19`: 1 linha em vez de 5. Apenas 1 `[guid]::NewGuid()` call.
- Anti-regression test: grep conta exatly 1 `[guid]::NewGuid()` no scope da função.

**B20 — Spot paridade com futures B19b**:
- `CoinEx-PlaceSpotOrder` (lib_coinex.ps1:344+): gera client_id ANTES do body, adiciona ao body, atualiza status confirmed/failed no try/catch (mesmo padrão futures)
- `CoinEx-PlaceSpotStopOrder` (lib_coinex.ps1:424+): idem; side="$Side-stop" pra diferenciar nas entries
- Retry agora habilitado em POST `/spot/order` quando client_id presente (via `CoinEx-Post` lógica)
- 5/5 TDD GREEN (b20_spot_client_id_parity) — grep no source verifica `New-OrderClientId`, `client_id`, `Update-OrderClientIdStatus` em ambas funções

**B22 — Dedup assumption documented**:
- `lib_coinex.ps1:196-207`: comentário expandido cita `knowledge/COINEX_REFERENCE.md:352` (client_id no body) + linha 450 (`cancel-order-by-client-id` confirma uso como identifier)
- **3 cenários explicitamente listados** (a/b/c) com mitigação se cenário (c) confirmar
- TODO smoke test em testnet documentado inline
- Decisão consciente: assumption mantida (comportamento exchange padrão), mas explicitada não documentada

**Restart daemons**: 4 fresh (gem_loop 19684, scan_master 20592, tg_listener 14184, watchdog 21020).

### 3.1.18 ✅ B19b PlaceOrder client_id + B18-wire stale-price gate (ENTREGUE 2026-05-20 PM6 +460min)

**Contexto**: 2 gaps operacionais latentes pós-3.1.17:
- **B19b**: PlaceOrder ainda sem retry (orphan order risk) — gap deferred explicitamente. Trade real em 503 = perdido (EV=0, mas dinheiro na mesa).
- **B18-wire**: lib `lib_price_freshness.ps1` existia mas zero callers. Stop ATR calculado com preço 30min cached ainda passível.

**Entregue (~30min, 5 TDD novos, 0 regressions):**

**B19b — PlaceOrder client_id idempotency**:
- CoinEx v2 `/futures/order` aceita `client_id` field (confirmado em `knowledge/COINEX_REFERENCE.md:352`). Mesmo ID em request duplicada → exchange retorna ordem existente, não cria nova.
- Nova `agents/lib_order_idempotency.ps1`: `New-OrderClientId` (UUID v4 sem hifens, prefix `c`), `Update-OrderClientIdStatus`, `Get-OrderClientIdEntries`.
- Persistência em `journal/order_client_ids.jsonl` (append-only schema `{ts, client_id, market, side, amount, status}` + status updates).
- Wire em `lib_coinex.ps1:CoinEx-PlaceOrder`: gera client_id ANTES do POST; passa no body; try/catch atualiza status (`confirmed`/`failed`).
- Retry agora HABILITADO em POST `/order` quando body contém `client_id` (line 184: `$retrySafe = -not $isOrderCreate -or $hasClientId`).
- 5/5 TDD GREEN (b19b_placeorder_client_id).

**B18-wire — Stale price gate fail-closed**:
- Nova função `CoinEx-GetTickerFresh` em `lib_coinex.ps1`: envolve raw ticker em `New-FreshTicker` wrapper (registra `fetched_at` local).
- `CoinEx-GetTicker` original mantido pra back-compat (callers legacy).
- Wire crítico em `orchestrator_v6.ps1:573-602` ANTES do Get-SetupForCascade:
  ```
  $tkFresh = CoinEx-GetTickerFresh $Market
  $fr = Test-PriceFresh -FetchedAt $tkFresh.fetched_at -MaxAgeSeconds 60
  if (-not $fr.is_fresh) { return ABORTAR STALE_PRICE }
  ```
- Fail-closed: stop ATR / sizing nunca calculados com preço >60s velho.

**Daemons dot-source atualizado**:
- `scan_master.ps1`: lib_retry + lib_order_idempotency + lib_price_freshness
- `gem_loop.ps1`: idem com `-ErrorAction SilentlyContinue` back-compat

**Restart daemons**: 4 daemons fresh (gem_loop 14192, scan_master 9572, tg_listener 12752, watchdog 14032).

**Gaps fechados completamente** (não mais "deferred"):
- ✅ B14 callback idempotency
- ✅ B19 transient retry
- ✅ B19b PlaceOrder client_id (era deferred — fechado agora)
- ✅ B18 freshness lib + wire (era latente — fechado agora)

### 3.1.17 ✅ Capital safety stress test — B15/B16/B17/B18/B19 + B13 re-smoke (ENTREGUE 2026-05-20 PM6 +430min)

**Contexto**: 5o audit user identificou riscos críticos pra LIVE Mode 2 (capital $2762.93 exposto):
- **B15** — DSR race condition (9 gates concurrent writes em `Out-File` não-atômico)
- **B16** — Watchdog respawn loop sem backoff (potential 1000x/h)
- **B17** — Daily Loss CB fail-open silencioso em corrupt `equity_daily_*.json`
- **B18** — Stale price detection ausente (decisão com cotação 30min cached)
- **B19** — CoinEx 429/503 sem retry + risk de orphan order

**Entregue (~110min, 30 TDD novos, 0 regressions):**

**B15 — DSR append-only JSONL** (race-safe):
- `lib_dsr_global.ps1` refactor: novo path `dsr_trials.jsonl` (Add-Content atomic em NTFS pra writes <512 bytes)
- `Get-DsrTrials` agora computa agregação on-read (count linhas; filtra por `.gate`)
- Back-compat: legacy `.json` path ainda funciona (read-only)
- Migrado 90 trials existentes pro JSONL (zero perda); legacy renamed `.legacy.json`
- `promotion_weekly_cron.ps1` + `mentor_agent.ps1` apontam pro JSONL agora
- 6/6 TDD GREEN (b15_dsr_atomic_jsonl) + 5 regression legacy

**B16 — Watchdog backoff + kill switch**:
- Nova `agents/lib_watchdog_backoff.ps1`: `Test-RespawnAllowed`, `Add-RespawnFailure`, `Reset-RespawnState`
- Backoff exponencial `2^N` segundos (cap 600s), state em `journal/watchdog_respawn_state.json`
- Kill switch após 5 falhas consecutivas → intervenção manual obrigatória (delete state file)
- Wire em `watchdog_paper.ps1` pra scan_master + gem_loop, Reset on success
- 6/6 TDD GREEN

**B17 — Daily Loss CB fail-closed**:
- `Get-DailyEquityDelta` retorna `.corrupt = true` quando JSON parse falha (antes: silent fail-open)
- `Test-DailyLossCircuit -StateCorrupt` → BLOCK explícito independente do equity_pct
- Wire em `scan_master.ps1:542`: caller passa flag corrupt
- Anti-vulnerability: corrupt mid-day não silencia CB permitindo -10% loss
- 6/6 TDD GREEN

**B18 — Stale price freshness gate**:
- Nova `agents/lib_price_freshness.ps1`: `New-FreshTicker` (registra fetched_at local), `Test-PriceFresh -MaxAgeSeconds N`
- Null/missing fetched_at = fail-closed (`is_fresh=false`)
- Pattern: caller envolve ticker em wrapper; downstream valida antes de usar
- 5/5 TDD GREEN

**B19 — Retry transient + idempotency gap doc**:
- Nova `agents/lib_retry.ps1`: `Invoke-WithRetry` (backoff exponencial), `Test-CoinExRetriable` (regex 429/503/502/504/timeout/dns)
- Wire em `CoinEx-Get` (sempre safe — idempotente) e `CoinEx-Post` (skip path `/order$` pra evitar duplicate)
- **Gap documentado deferred**: PlaceOrder sem retry pra prevenir orphan order; solução real requer `client_id` field como idempotency key (CoinEx aceita) — task pra próxima sessão
- 5/5 TDD GREEN

**B13 re-smoke**: 2o spawn scan_master auto-exit 13s com `[SKIP] Outro scan_master VIVO ja rodando (PID=11796)`. Lock confirmado pós-restart.

**Restart daemons**: 4 daemons fresh (gem_loop 18968, scan_master 18456, tg_listener 20372, watchdog 19144) carregaram B15-B19.

**TDD acumulado 3.1.17**: 28 PASS (B15 6 + B16 6 + B17 6 + B18 5 + B19 5) + regressions intactas.

### 3.1.16 ✅ B14 Callback idempotency (ENTREGUE 2026-05-20 PM6 +350min)

**Contexto crítico**: Sistema LIVE Mode 2 desde 18/05 (~48h ativo). Capital exposto $2762.93. Worst case duplicate callback = 2× sizing 1% = +$55 exposição inesperada por trade + daily_loss CB violado silenciosamente (calcula com 1 trade, executa 2).

**Surface real identificada**: `$global:TG_UPDATE_OFFSET` compartilhado entre `tg_listener.ps1` e `Wait-TgCallbackApproval` (em `lib_telegram.ps1:473`). Race condition latente: ambos polling Telegram, mesmo callback poderia processar 2x se ordem de leitura/offset save falhar.

**Entregue (~30min, 8 TDD novos, 0 regressions):**

**Nova `agents/lib_idempotency.ps1`**:
- `Test-CallbackIdempotent -Path $journalDir/telegram_callbacks_processed.json -CallbackId $cbId` retorna `$true` apenas na primeira chamada
- Schema: `{callbacks:[{id,ts}], max_entries:1000, updated_at}` — rolling window
- Fail-open em arquivo corrompido (cria novo, log warn) — escolha consciente vs lock-out total
- Race-safe via file write atômico

**Wire em `lib_telegram.ps1:Wait-TgCallbackApproval`**:
```powershell
if (-not $isNew) {
    Confirm-TgCallback -CallbackId $cbId | Out-Null  # ACK pra remover spinner
    continue  # skip trade, segue polling
}
```
Posicionado **antes** do ACK + decision return = duplicate jamais dispara trade downstream.

**TDD 8 PASS** (b14_callback_idempotency.Tests.ps1):
- primeiro callback retorna true
- duplicate retorna false (poupa trade)
- callback ID diferente após primeiro retorna true
- persistência sobrevive reload (file-based)
- rolling window cap 1000
- arquivo corrompido fail-open
- race condition simulada (2 calls = 1 true)
- **integration**: 3 chamadas mesmo ID = 1 trade único

**Wire em daemons**:
- `scripts/scan_master.ps1`: dot-source `lib_idempotency.ps1`
- `scripts/gem_loop.ps1`: dot-source com `-ErrorAction SilentlyContinue` (back-compat)
- `scripts/telegram_listener.ps1`: já carrega via lib_telegram

**Restart daemons**: 4 daemons restarted (PIDs 5100/19748/26932/21812). Smoke test prod: lib carrega + 3 chamadas geram (True/False/True) = comportamento correto em scope real.

### 3.1.15 ✅ Patch cirúrgico final — pre-mentor invariant + DSR decorator + anti-regressão (ENTREGUE 2026-05-20 PM6 +320min)

**Contexto**: user propôs "patch único 35min" cobrindo B4/B7/B10/B11 + 4 anti-regressões + B12+B13. Avaliei item-por-item; #1 (DRY) e #4 (rotation) já estavam feitos no round 3; #2, #3, #5, B12, B13 eram genuinamente novos/úteis.

**Entregue (~30min, 12 TDD novos PASS, 0 regressions):**

**Item 2 — Pre-mentor invariant** (defesa em profundidade pre-LLM):
- Nova `agents/lib_mentor_invariants.ps1`: `Test-MentorPayloadInvariant` 
- Matriz coerente (A+LIVE/A+PAPER/B+B_PAPER/B+A_PAPER ✓; A+B_PAPER/B→A_LIVE/C+*/D+* ✗); GEM bypass; payload incompleto reject
- Wire em `orchestrator_v6.ps1:230+` ANTES de `Invoke-MentorDebate` → corrompido = ABORTAR INVARIANT_VIOLATION sem queimar LLM ($0.006/evento poupado)
- 7/7 TDD GREEN (b4_mode_invariant_premento)
- `scan_master.ps1` ganha dot-source da lib

**Item 3 — DSR decorator em ladder gates** (consistency):
- `Test-GateObservationToC/CToB/BToLive` ganharam params opt-in `-DsrPath` + `-Market`
- Quando providos, registram próprio gate_name em DSR internamente
- Lib_promotion_cycle.ps1 continua compatível (não passa → registração externa existente preserva)
- Caller futuro pode bypassar lib_promotion_cycle e ainda ter DSR consistente
- 99 PASS regression (promotion_ladder + promotion_cycle + lib_promotion_gates + dsr_global)

**Item 5 — Anti-regression suite** (lockdown):
- `tests/anti_regression_round3.Tests.ps1`: 5 PASS cobrindo:
  - B4 invariant: tier=A + mode=TIER_B_PAPER reject
  - B7 multi-gate: Invoke-AllGates → by_gate > 1 chave
  - B10 rotation: 7 backups → 5 mantidos
  - B11 single helper: ConvertTo-CsvField definido em 1 arquivo apenas (lib_csv_utils.ps1)
  - B11 zero hacks: nenhum `-replace ',', ';'` em agents/

**B12 — `.env` cleanup**:
- `backtest/.env`: removido comentário órfão "Service role key" deixado pelo round 1 fix
- Agora só SUPABASE_URL, SUPABASE_ANON_KEY, COINEX_BACKTEST_CAPITAL

**B13 — scan_master lock smoke test em prod**:
- Spawn 1 scan_master (PID 20068)
- Spawn 2o em <5s (PID 412) → exit imediato com log `[SKIP] Outro scan_master VIVO ja rodando (PID=19144)`
- Race condition (14:29 case) prevenida em prod confirmado

**TDD acumulado 3.1.15**: 12 novos (7 invariant + 5 anti-regression) + 99 regression suite. Total sessão 2026-05-20 PM6+: **~150 TDD novos**, 0 regressions.

### 3.1.14 ✅ Round 3 — DRY + prevention + prod validation + anti-bias skill (ENTREGUE 2026-05-20 PM6 +260min)

**Contexto**: user fez 3o audit (apos 3.1.13). Listou 4 anti-padroes:
- B7 marcado completo mas DSR ainda single-gate (nao exercitei em prod)
- B4 meia-resolvido (detector sem prevencao)
- **B11 NOVO**: 3 copias do RFC4180 escape (DRY violado)
- **Vies geral**: "completo onde toca, conservador em escopo"

**Entregue (~80min, 29 PASS, 0 regressions):**

**B11 DRY** — helper unico:
- Novo `agents/lib_csv_utils.ps1`: `ConvertTo-CsvField`
- `lib_observation_logger.ps1` removeu copia + dot-source
- `lib_ladder_tracker.ps1` `_LadderTracker-CsvField` virou thin wrapper
- `lib_journal.ps1` inline RFC4180 -> `ConvertTo-CsvField` via dot-source
- 25 PASS regression

**B4 prevention** (nao so detector):
- `scripts/watchdog_paper.ps1`: nova `Test-DaemonDrift`
- Wire em loop: `needsRespawn = dead || stale_log || drift` (threshold 1h)
- Mesma logica gem_loop
- 4 PASS (b4_drift_detection)
- Drift auto-respawna entre crons (nao espera 03:00 BRT)

**B7 validation em prod**:
- Manual `Invoke-AllGates -DsrPath`: `by_gate` foi de `[obs_to_c]` -> 9 gates (obs_to_c, funding, phase_boundary, min_volume, concentration, sector, beta_concentration, cooldown, daily_loss)
- Bonferroni multi-test agora dimensionalmente correto

**Audit ampliado**: grep `.bak`, `-replace ',', ';'`, mentor prompt "use ;" — zero outros. B10/B3 ja completos.

**Skill nova**: `feedback_scope_expansion_anti_bias.md` — 5 checklists pos-fix obrigatorios.

### 3.1.13 ✅ Re-audit profundo + JSONL sidecar + 3 bugs novos (ENTREGUE 2026-05-20 PM6 +180min)

**Contexto**: user fez segundo audit (mais profundo que 3.1.12). Achados:
- Os fixes anteriores eram **band-aids** (RFC4180 só no logger, não upstream)
- Schema CSV é fundamentalmente errado pra texto livre (Mentor reason com vírgulas, aspas, newlines)
- 3 bugs novos descobertos (B8/B9/B10)
- DAEMONS rodando código antigo (orchestrator_v6.ps1 modificado 16:02 BRT mas daemons subiram 14:21/14:40)

**Entregue (~180min, 0 regressions):**

**B3 upstream** (3 fontes corrompiam ANTES do logger):
- `lib_ladder_tracker.ps1:73,117`: novo helper `_LadderTracker-CsvField` (RFC4180)
- `lib_journal.ps1:85`: inline RFC4180 (antes hack `,→;`)
- Logger já com `ConvertTo-CsvField` desde 3.1.12

**D3 JSONL sidecar** (design correto):
- Novo `Add-DecisionText` em `lib_observation_logger.ps1` — escreve `journal/decisions_text.jsonl`
- Schema: `{ts, market, reason, alerta?, notes?, mesa_consensus?, mentor_decision?}` linkado por (ts, market)
- `Add-Decision` ganhou param `-TextSidecarFile` (default = pasta do CSV) — escreve CSV + JSONL em paralelo
- CSV continua SSoT tabular; JSONL guarda texto livre sem ginástica de escape
- 7/7 TDD GREEN

**B7 callers restantes**:
- `lib_promotion_ladder.ps1:466` (Invoke-PromotionPropose): wire `-DsrPath` via `$gateArgs`
- `promotion_weekly_cron.ps1`: já chamava `Invoke-PromotionCycle` que passa DsrPath (path completo)

**B1 refino** (veto-early ≠ trade-zerado):
- Heurística: se `entry+stop+target+atr` **todos = 0** → veto-early → escreve `""`
- Trade real com setup não toca (entry>0 sempre num trade legítimo)
- 3/3 TDD GREEN

**B8 NOVO — scan_master lock idempotent**:
- Replicado pattern `gem_loop.ps1:39-51` (Get-CimInstance + skip-if-alive) no `scan_master.ps1:24`
- Race condition 2x ciclos quase simultâneos (14:29:01 / 14:29:49) resolvida

**B9 NOVO — GEM TTL cache** (lib nova `lib_gem_decision_cache.ps1`):
- `Add-GemRejection` + `Test-GemRecentlyRejected` (TTL 60min default)
- Normaliza floats em reason (`MCE_BLOCK 0.1823` ≡ `MCE_BLOCK 0.1824`) — evita re-veto loop
- Wire em `gem_executor.ps1:204+` (skip silencioso se cache hit)
- Dot-source em `gem_loop.ps1:88+`
- DASH 5x rejection hoje (~$0.03 desperdício LLM) não acontece mais
- 6/6 TDD GREEN

**B10 NOVO — backup rotation**:
- `coingecko_enrichment.py:253+` e `coingecko_batch.py:172+`: keep last N=5 backups (glob + sort + unlink stale)
- Aplicado retention now: 6→5 (1 removido)

**B2 — .gitignore verify + doc warning**:
- `*.env` cobre `backtest/.env` via glob — mas projeto **NÃO é git repo** (gitignore inerte)
- Surface real = OneDrive/Dropbox/Windows backup
- `docs/SECURITY.md`: nova seção "Surface de filesystem (alem do git)" com matriz de vetores + mitigações
- Não refatorei `config.local.ps1` (system policy: NEVER read)

**B4 — Force restart daemons**:
- gem_loop PID 27340→21812, scan_master 24236→19144, tg_listener 21236→19684, watchdog 27208→16752
- Todos 4 daemons agora fresh com **TODOS** os fixes da sessão (PM6 4-mode + 3.1.12 + 3.1.13)

**B5 — CoinExLogRotation cron registered**:
- `pwsh -File scripts\register_log_rotation_cron.ps1` executado
- Cron `CoinExLogRotation` Ready, daily 03:30 BRT
- **Total crons: 9** (era 8)

**TDD acumulado 3.1.13**:
- B3: 7 PASS (b3_csv_upstream_no_corruption)
- D3: 7 PASS (decision_text_jsonl_sidecar)
- B7: 69 PASS (lib_promotion_gates + lib_promotion_ladder regression)
- B1: 3 PASS (b1_observations_veto_early) + 8 PASS legacy = 11
- B9: 6 PASS (b9_gem_recent_decision_cache)
- Total novo: ~30 GREEN, 0 regressions

**Skills permanentes adicionadas** (será no MEMORY):
- `feedback_audit_raw_artifacts_periodically.md` (já em 3.1.12)
- Nova: `feedback_csv_jsonl_split_for_freetext.md` (CSV tabular + JSONL texto livre)

### 3.1.12 ✅ 6 bugs operacionais auditados pelo user (ENTREGUE 2026-05-20 PM6 +90min)

**Contexto**: user auditou sistema fora das memories e listou 7 bugs reais. Validei cada um e corrigi 6 (B4 já estava fixed pre-PM6).

**B2 — Secrets duplicate (5min, 🔴)**: `SUPABASE_SERVICE_KEY` (RLS bypass) duplicada em `agents/config.local.ps1` + `backtest/.env`. Removida de `backtest/.env`. `backtest/db.py:15` já tinha fallback `ANON_KEY` (privilege menor, backtest não precisa bypass RLS). `config.local.ps1` permanece SSoT.

**B1 — observations.csv numerics zerados (30min, 🔴)**: `orchestrator_v6.ps1:320` mapeava `setup` só de `mesa.setup`/`triagem.setup` — em Tier A (mesa skipped) cai em `@{entry=0;...}`. Fix: hierarchy `$Setup param → mesa.setup → triagem.setup → 0` + atrPct computado de Setup quando ausente. Mesma fix no CAOS path (161-185). 8/8 TDD PASS.

**B7 — DSR single-gate Bonferroni torta (30min, 🟡)**: `dsr_global.json` registrava só ladder gates (obs_to_c/c_to_b/b_to_a). Outros 9 gates (concentration/daily_loss/sector/cooldown/min_vol/phase_boundary/funding/beta_concentration/pump_buy/time_of_week/slippage/cross_corr/fundamental_quality) ficavam fora. Fix: `lib_promotion_gates.ps1:Invoke-AllGates` ganhou param `-DsrPath`; loop `Add-DsrTrial` sobre todas gates. `lib_promotion_cycle.ps1:117` wire. 74/74 TDD PASS.

**B3 — CSV escape RFC4180 (15min, 🟡)**: `Add-Observation` + `Add-Decision` substituíam `,` por `;` silenciosamente. Texto desfigurado (Druckenmiller; preserve...). Fix: nova função `ConvertTo-CsvField` envolve em aspas duplas + duplica aspas internas (RFC4180 padrão). 8/8 TDD PASS.

**B5 — Log rotation (15min, 🟡)**: `journal/watchdog.log` 721KB sem rotação. Novos scripts: `scripts/rotate_logs.ps1` (5MB threshold, archive `journal/archive/<name>.YYYY-MM-DD.log`, prune 30d) + `scripts/register_log_rotation_cron.ps1` (daily 03:30 BRT). **Pendente**: registrar cron manualmente (requer admin).

**B6 — Test dirs leak (5min, 🟢)**: 8 dirs `journal_new_test__*` na raiz. Root cause: `tests/override_expiry.Tests.ps1:143` usava `$$` (não expande PID em PS — vira `__` duplo). Fix: `$PID` + `$env:TEMP` + try/finally. 8 dirs leaked deletados. 16/16 TDD PASS, 0 leaks.

**B4 — Mode conflict (já fixed PM6)**: timestamp `2026-05-20T18:13:04Z` = 15:13 BRT, 9min antes da PM6 fix. Verificado `orchestrator_v6.ps1:215-222` (4 ortogonal modes). Próxima BTC validation 18:22:31Z post-fix mostrou VETAR_MCE (sem conflito). Causa-raiz resolvida; 18:13 é artefato histórico pre-fix.

**Skill nova**: PM6 não criou skill — bugs operacionais sem padrão único pra abstrair.

**TDD acumulado**: 98 PASS (8 observation + 74 gates/DSR + 8 csv escape + 16 override = sample). 0 regressions.

**Pendente operacional**:
1. `pwsh -File scripts\register_log_rotation_cron.ps1` (admin) — registra CoinExLogRotation 03:30 BRT
2. Daemons reload automático via CoinExDaemonRestart 03:00 BRT (drift detector pega B1+B3+B7 fixes)

### 3.1.11 ✅ Retratação mid-cap gap + skill "check existing design" (ENTREGUE 2026-05-20 PM6 final +30min)

**Contexto**: gem cycle manual 15:48 BRT retornou 0 gems com DASH +15.86% / ZEC +13.96% (privacy rally). Inicialmente propus "mid-cap pump detector" como backlog feature.

**Correção do user**: ler `per_asset_whitelist_2026_05_20_v3_10.json:96` antes de propor feature.
```json
"promoted_reason": "swap_replacement_for_ZEC_beta_0.95_AAA+_privacy"
```
`demote_history.jsonl:3` registra swap ZEC→XMR explícito 2026-05-20T02:29:47Z. XMR é vehicle privacy ativo desde então (beta 0.95 AAA+ vs ZEC 1.57 amplifier).

**Retratação**: não havia gap. Sistema já cobre narrativa privacy via swap-replacement curado. Backlog "mid-cap detector" **REJEITADO** (duplicaria V6 daily existente).

**Estado correto validado**:
- ZEC TIER_B_PAPER por beta cap (estructural)
- DASH rejeitado por Sharpe baixo (merit-only)
- XMR TIER_A_LIVE como vehicle privacy ativo

**Skill nova permanente**: `feedback_check_existing_design_before_proposing_feature.md` — protocolo obrigatório antes de propor feature:
1. Grep whitelist por `promoted_reason` e `swap_replacement`
2. Ler `demote_history.jsonl` recente
3. Ler `sector_map.json`
4. Mapear narrativa → vehicle ativo
5. Se vehicle moveu = sistema funcionou; se NÃO moveu durante setor pump = gap real

**Memory entries**:
- `project_midcap_pump_gap_2026_05_20.md` reescrito como RETRATAÇÃO
- `feedback_check_existing_design_before_proposing_feature.md` salvo como skill

Nenhum código novo. 0 TDD adicional (não havia feature pra testar — só retração).

### 3.1.10 ✅ Métricas honestas + ZEC decision (ENTREGUE 2026-05-20 PM6 final)

**Métricas LLM desenviesadas**: V6_LIVE_ACTIVATION_CRITERIA contava hallucination/conflito/fail-safe como "VETAR sem causa actionable", causando bias. Now exclui 3 patterns explicitos:
- Hallucination (pre-PM1): `mesa pulou`, `fqs indisponivel`, `[ALERTA]`, `caixa preta`
- Conflito modo (pre-PM6): `conflito.*modo`, `mutuamente exclusivos`
- Fail-safe (Mentor down): `mentor indisponivel`

Replay analyzer reorganizado: classes `improved` (bugs fixed) / `consistent` (merit) / `infra_issue` (fail-safe) / `needs_attention` (ambigu). Audit: **39 merit-vetos** (não 55 inflated).

**ZEC decision**: mantido TIER_B_PAPER conscientemente. Razão: beta 1.565 estructural, phase 3 bear ainda ~3 meses, Druckenmiller "preserve capital first". Reavaliar quando phase_4_bull OR β cair OR capital > $5K. Doc: `project_zec_decision_2026_05_20.md`.

**Daily replay metrics**: integrado em `daily_summary_digest.ps1` linha "Replay 50: merit=N improved=M".

**Skill nova**: `feedback_metrics_exclude_structural_noise.md` — métricas LLM sempre filtrar bugs estruturais antes de validar checklist.

### 3.1.9 ✅ Bug semântico TIER_A_PAPER fix (ENTREGUE 2026-05-20 PM6)

**Diagnose user (cadeia exata)**: triagem.tier (A/B/C/D = qualidade score) e wl.tier (live/observe = autorização regime) eram tratados como propriedade unificada. Quando colidem (BTC Tier A quality + BULL_WEAK regime defensivo), `orchestrator_v6.ps1:211-218` mapeava `wl.tier='observe'` → `mentorMode='TIER_B_PAPER'`. Mentor recebia tier=A + Mesa=skipped (by design TIER_A_LIVE) + mode=TIER_B_PAPER (exige Mesa) → "CONFLITO CRÍTICO DE MODO" veto.

**Fix**: 4 modes ortogonais em orchestrator_v6.ps1:211-225:
- `triagem=A + wl=live` → TIER_A_LIVE
- `triagem=A + wl=observe` → **TIER_A_PAPER** (NOVO — Tier A quality + regime limita paper)
- `triagem=B + wl=observe` → TIER_B_PAPER
- GEM source → GEM

System prompt atualizado com regra explícita: "NUNCA tratar TIER_A_PAPER como conflito".

**Validação prod BTC pós-fix (15:22 BRT)**: Mentor agora APROVAR conf=82 anthropic_sonnet citando "TIER_A_PAPER = paper-only por regime defensivo, sem conflito". Decisão final ABORTAR por MCE_BLOCK 0.1215 (macro desfavorável) — gates ortogonais funcionando (Mentor aprova quality, MCE bloqueia macro).

### 3.1.8 ✅ Raw numbers persisted + BTC validation prod end-to-end (ENTREGUE 2026-05-20 PM5 final)

**Bug discovery**: `coingecko_enrichment.py` derivava `supply_capped` e `recovered_2021_ath` (booleans) mas NUNCA persistia raw numbers (`max_supply`, `current_price_usd`, `ath_all_time_usd`, `circulating_supply`). FQS V1.6 partial path (`current/ath >= 0.5 → recovered_partial`) era cego porque dados nao chegavam ao registry.

**Fix**: `coingecko_enrichment.py:107-128` agora persiste 4 raw numbers em todos enriquecimentos. Re-run 9 markets PM5: todos têm max_supply/current_price/ath/circulating.

**BTC prod validation 15:12 BRT**: `Invoke-OrchestratorV6 -Market BTCUSDT -Mode paper -DryRun`
- Triagem: tier=A score=92 ✅
- Mentor: VETAR conf=78 provider=**anthropic_sonnet**
- Razão: "CONFLITO CRÍTICO DE MODO" — Mentor detectou tier=A vs mode=TIER_B_PAPER inconsistência (gate intelligence legítimo, não hallucination)
- **0 hallucination FQS** (runspace fix validado end-to-end prod)
- Provider trace persistido ✅

---

## ONDA 4: Multithread Infrastructure + FARO V3 Pump Detection (2026-05-23 a 2026-06-02)

### 4.1 ✅ FARO V3: 7-signal pre-pump detection + CoinEx auto-entry (ENTREGUE 2026-05-27)

**Sistema completo novo**: 11 libs (`lib_faro_*.ps1`) + 12 scripts de deploy + scoring engine 0-100.

**7 sinais**: momentum (volume rate-of-change), pattern (Wyckoff spring + bull pennant), sentiment (onchain), entry timing (Livermore breakout), whale flow (accumulation), ML confidence (gradient boosting), margin safety (liquidation cascade).

**Deployment**: $500 capital inicial, target +$25-40/dia. Live em 2026-05-26 (commit f4cea00). Backtest histórico captura 4/4 pumps (PEPE/WIF/BONK/SKYAI) em 2-3 dias antes do peak (commit b5f0ad2).

**Threshold calibrado**: score ≥35 + 4/7 signals non-noise edge. Paper validation passou 100/100 candles sem false positive.

### 4.2 ✅ GitHub Actions 24/7 + Supabase state store (ENTREGUE 2026-05-25)

**Infraestrutura de execução**: CI/CD workflow substituiu cron local. 4 jobs contínuos:
- Layer 1: price freshness monitor
- Layer 2: Mentor reflection 6h checkpoint  
- Layer 4: Tori proximity + adaptive time-based stops
- Layer 5: Moon Bag 50/50 harvest+upside

**State store central**: Supabase com 6 tabelas (positions, trades, capital_context, trailing_stops, mentor_reflections, performance). 4 posições migradas de arquivo JSON para Supabase (idempotency + audit trail).

**Idempotency schema**: (market, timestamp, operation_id) unique constraint. Todos os writes agora idempotent (commit 397eb6a).

### 4.3 ✅ SHORT Execution Stack Block 2 (ENTREGUE 2026-05-24)

**Wiring completo**: scanner (lib_signal_generator_short) → orchestrator → enhanced short entry (lib_enhanced_short_entry).

**TDD**: 216/216 testes passando. Scanner detecta SHORT signals via Mentor direction + DSR per-direction. Tier 2 gates wire 100%.

**Finding**: SHORT em BEAR_STRONG com BTC daily 0/4 pass strict (resultado esperado — mercado não permite SHORT alavancado em tendência baixa). Documentado em project_short_btc_refined_2026_05_18.md.

### 4.4 ✅ Trailing Multicamadas Layer 1-5 (ENTREGUE 2026-05-26)

**Layer 1**: ATR adaptativo baseado em regime (volatility scaling).

**Layer 2**: Mentor Reflection 6h checkpoint (LLM reavalia setup a cada 6h).

**Layer 4**: Tori Proximity + Time-Based Stops (se 11.99% acima linha Tori = liquidar; se +6h sem movimento = hardstop).

**Layer 5**: Moon Bag 50/50 (harvest profit-taking + upside open).

**Integration**: Todos 5 layers execução automática via LAYER4_AUTO_EXECUTE flag (commit fc451e7).

### 4.5 ✅ Dashboard unificado manu.html (ENTREGUE 2026-05-26)

**Single pane**: capital, posições ativas, tier atual, trailing stop status, LLM costs/RPD, ciclo log últimas 100 linhas.

**Data source**: manu_data.js auto-gerado por orchestrator a cada ciclo (JSON-LD estructura).

**Feat**: sem CORS (file:// protocol) — roda localmente.

### 4.6 ✅ Mistral substitui Gemini como fallback 2 (ENTREGUE 2026-05-26)

**Reason**: Gemini rate-limited 60 RPD; Mistral 250 RPD + $0.14/MTok (vs Gemini $0.075 — mas Mistral 5× mais rápido = -60% latency). TDD 27/27 passando (commit 6f6e02b).

**Cascade atual**: Sonnet (primary) → Haiku (fallback 1) → Groq (fallback 2, free) → Mistral (fallback 3, pago).

### 4.7 ✅ Mesa Consensus Relaxado: Tier C com FORTE_3 (ENTREGUE 2026-05-24)

**Antes**: Tier B paper exigia consensus FORTE (2/3 colunas bullish). Tier C bloqueado.

**Depois**: Tier C agora pode executar com consensus FORTE_3 (todos 3 pilares neutro/bullish, sem conflito). TDD 8/8 passando (commit 5eb68a0).

**Impact**: 3-5 trades/semana adicionais em BULL_WEAK (antes bloqueados por consensus).

### 4.8 ✅ Paralelização SPOT micro-scalps + FUTURES macro-swings (ENTREGUE 2026-05-23)

**Orquestrador paralelo** (`lib_orchestrator_parallel.ps1`): rodar gem_loop (SPOT) e macro scanner (FUTURES) simultaneamente em runspaces isolados.

**Velocidade**: 100s → 25s por ciclo (4× speedup). 11/11 resultados coletados em ordem determinística.

**Feat**: ambas estratégias independentes (não se interferem). FARO V3 roda em SPOT; SHORT+Long legs em FUTURES.

### 4.9 ✅ Mentor evolutions A+B+C: 9 features em TDD (ENTREGUE 2026-05-26)

**A**: Phantom sync — Mentor memória sincroniza com regime atual sem recompile.

**B**: Reflection wire — 6h checkpoints (Mentor reavalia posições abertas).

**C**: Time context + alpha_history + 5tier schema + multishot voting + calibration mode + self-consistency validation + unified prompts.

**TDD**: 65/65 testes + 22/22 smoke testes (commit 33a304b). Mentor agora stateful, não stateless.

---

**ONDA 4 SUMMARY**: Infrastructure escalável (GitHub Actions + Supabase) + novo sistema de detecção (FARO V3) + hardening operacional (trailing 5 layers, Mentor stateful). Capital deployado em LIVE (2026-05-26). Próxima wave (ONDA 5): forward-test FARO V3 até 2026-07 antes de scale capital.
- paperOnly=true (V6_LIVE flag absent, correto)

**Sistema confirmado operacional fim-a-fim em prod**:
- Cascade Triagem→Whitelist→Mesa→Mentor→MCE funcional
- FQS chega ao prompt corretamente (registro de 40 markets)
- Provider observability ativa
- Veto Mentor com razão acionável (não hallucinated)

### 3.1.7 ✅ CoinGecko auto-enrichment loop fechado (ENTREGUE 2026-05-20 PM5)

**Problema**: 4 markets em `fqs_enrichment_queue.jsonl` (KITE/PENGU/RIVER/TAO) eram skipados por `coingecko_enrichment.py` por falta de mapping em `MARKET_TO_CG`. Auto-enrich workflow tinha hole.

**Fix**: WebFetch CoinGecko search API → identificou IDs corretos (e.g. KITE = `kite-2` não `kite-ai`). Adicionados **9 entries** em `MARKET_TO_CG` (TAO/PENGU/KITE/RIVER/ARB/XCH/LIT/RON/BU). Re-run enrichment: **9 updated / 0 failed**. Registry 36→**40** com dados reais (max_supply/ath/current_price).

**Impacto**: 4 markets adicionais elegíveis pra GEM auto-approve (ARB/LIT/RON/TAO QUALITY). ARBUSDT subiu 0 AVOID → 5 QUALITY (Arbitrum L2 reconhecido).

**Auto-enrich agora end-to-end**:
```
Mentor detecta market sem registry
  → Build-MentorFullContext enqueue
  → weekly_data_refresh (Sat 22:00) ou process_fqs_queue manual
  → CoinGecko fetch (com MARKET_TO_CG ampliado)
  → registry atualizado com dados reais
  → próximo cycle Mentor cita FQS preciso
```

### 3.1.6 ✅ Resiliência daemon + GEM auto-approve + 3 bugs prod fixed (ENTREGUE 2026-05-20 PM4)

**Trigger**: User mostrou Telegram log com **3 bugs em produção** descobertos por inatividade do daemon:
1. Tori path errado (`agents\..\tech_agent.ps1` sem `scripts/`) — gem_loop daemon de 46h carregou versão antiga em memória
2. Sizing config.ps1 mudado pra 0.5% NÃO foi recarregado (daemon não hot-reload)
3. Score 95 GEM perdido por #1

**Root cause**: PowerShell daemon não hot-reload libs/config em runtime. Sem cron de restart, daemon drift acumula.

**Fixes resiliência**:
1. **Watchdog process-primary** ([watchdog_paper.ps1:322](scripts/watchdog_paper.ps1#L322)): revertido pra `$gemNeedsRespawn = -not $gemAlive` (process check + CIM retry 3x). AND-logic anterior era conservador demais (kill manual = 90min downtime).
2. **Drift detector em watch_status**: mostra `[DRIFT: Xh pre-config update]` quando daemon.StartTime < config.LastWriteTime + lista libs alteradas 24h
3. **`scripts/daily_daemon_restart.ps1`** + cron `CoinExDaemonRestart` 03:00 BRT — rolling kill+respawn de 4 daemons (gem_loop, scan_master, tg_listener, watchdog_paper). Anti-drift automático.
4. **GEM sizing 0.2% → 0.5%** ([config.ps1:135](agents/config.ps1#L135)): math realista. $13.81/trade vs $5.52, EV $34/mês vs $14.
5. **GEM auto-approve strict** ([lib_gem_auto_approve.ps1](agents/lib_gem_auto_approve.ps1)): captura GEMs quando user dorme. Critérios: opt-in flag + score≥90 + FQS≥QUALITY + registry + sizing≤1% + cap 3/dia. Audit log `journal/gem_auto_approve_log.jsonl`.

**TDD**: 9 GREEN gem_auto_approve + 11 GREEN runspace_audit + 7 GREEN runspace_warnings = 27 cumul.

**Cron count**: 5 → **8** (+ DaemonRestart + DailyDigest + WeeklyCostReport).

**Estado pós-fix 14:25 BRT**: ZERO drift detectado em 4 daemons via rolling restart manual + drift detector ativo em hourly heartbeat.

### 3.1.5 ✅ Root cause arquitetural FQS + UX heartbeat (ENTREGUE 2026-05-20 PM3)

**Diagnostico**: 3o ciclo prod (11:33) showed Mentor citando "FQS indisponivel" para LIT (FQS=3 SPEC) e VVV (FQS=1 AVOID) **mesmo registry tendo entries**. Build-MentorFullContext funcional em main thread mas falhava em runspace.

**Root cause arquitetural**: `lib_orchestrator_parallel.ps1` cria `RunspacePool [InitialSessionState::CreateDefault()]` — runspace ISOLADO. Lista hardcoded de 20 libs no script child omitia 6 libs criticas:
- `lib_fundamental_quality.ps1` (Get-FundamentalScore retornava null silenciosamente)
- `lib_pump_buy_gate.ps1`, `lib_order_routed.ps1`, `lib_market_router*.ps1`, `lib_entry_score_boost.ps1`, `lib_news_entry_boost.ps1`

`Get-Command X -ErrorAction SilentlyContinue` retornava $null → branch silently skipped → ctx.fqs = $null → prompt sem FQS → Mentor diz "indisponível".

**Fix**: 6 libs adicionadas à lista. Validacao prod pendente cron 09:00 BRT.

**UX gap (heartbeat)**: daemon scan_master em DAILY sleep 1440min = 0 heartbeats por 24h. User percebia sistema morto.

**Fix UX**: novo cron `CoinExHourlyHeartbeat` chama `watch_status.ps1 -Telegram` 1x/hora (desacoplado de scan cycle). Script: `scripts/register_hourly_heartbeat.ps1`.

**4 follow-ups do user validados**:
1. DASHUSDT cascade fail: mix Groq+Sonnet saudavel, foi burst momentaneo 1/30
2. ZEC beta 1.565: design correto, ZEC nao em Tier A, cap protege portfolio
3. Cycle silent: heartbeat hourly resolve
4. observations.csv so APROVAR: decisions.csv JA loga ABORT (wired hoje)

### 3.1.4 ✅ FQS hallucination secundária + auto-enrich (ENTREGUE 2026-05-20 PM2)

**Diagnóstico**: Após fix da hallucination primária ("Mesa pulou"), descoberta secundária: Mentor citava "FQS não declarado" para DYDX (FQS=5) e CHZ (FQS=4) que ESTAVAM no registry. `Build-MentorFullContext` populava corretamente — mas LLM ignorava o campo no meio das outras ctx lines.

**Fixes**:
1. **Prompt FQS proeminente**: `fqs=N/7` → `FQS=N/7` (uppercase, fácil de identificar)
2. **System prompt rule**: adicionado `"ANTI-HALLUCINATION: se CONTEXTO tem 'FQS=N/7 CATEGORY' NUNCA escreva 'FQS nao declarado'"`
3. **Markets sem registry**: `Build-MentorFullContext` agora detecta `reason="market_not_in_registry"` e injeta `FQS=N/A_no_registry` explícito (em vez de skipar)
4. **Auto-enqueue**: markets faltantes append em `journal/fqs_enrichment_queue.jsonl`
5. **Processor**: novo `scripts/process_fqs_queue.ps1` dedupe + `coingecko_enrichment.py --markets X,Y,Z --apply`
6. **Wire**: `weekly_data_refresh.ps1` stage 5c roda processor → market faltante é auto-enriquecido próximo Sábado 22:00 BRT

**Bridge manual**: 5 markets adicionados ao registry agora (XCH/LIT/RON/BU/ARB) com baseline conservador. Auto-enrich vai refinar depois.

**TDD**: 31 GREEN Mentor suite (+3 novos: FQS proeminente + FQS=N/A_no_registry + system prompt rule).

### 3.1.3 ✅ Pipeline gaps fechados (ENTREGUE 2026-05-20 PM)

- `Invoke-OrderRouted` wired em gem_executor (era dead code)
- `Invoke-OrderRouted` wired em V6 PostMentorExecution (arquitetura unificada)
- 4 gates antes dormentes wired no caller `Invoke-PromotionPropose` (params opt-in)
- `Invoke-PromotionCycle -EnforceGates` opt-in: cobre 13 gates antes de promote (era so Test-Gate*ToB)
- V6 PlaceOrder A+B (paper default + `V6_LIVE_ENABLED.flag` opt-in + Wait-TelegramApproval)
- `tier_a_drawdown_monitor.py source-aware` (GEM tolera -45%, tier_a strict -25%)
- `scripts/watch_status.ps1` NOVO: snapshot KPIs (workers/drawdown/Mentor/V6/Kelly)

### 3.2-3.4 (anteriormente listado) — deferred next session



### 3.1 📋 Fundamental Quality Score (FQS)

**Identificado 2026-05-19 PM**: sistema atual ignora qualidade fundamental.
Trade puro de momentum/Sharpe pode operar tokens com tokenomics ruins.

**Dimensoes propostas (FQS 0-7)**:

| Dim | Sinal+ | Sinal- | Fonte |
|---|---|---|---|
| Idade | >3y sobreviveu bear | <6mo unproven | CoinGecko genesis_date |
| Supply | hard cap finito | unlimited mint | CoinGecko max_supply |
| Burn | regular burns | sem burn + alta inflacao | protocolo |
| Utility | TVL real / tx/day | "vapor token" | DefiLlama, on-chain |
| Holders | distribuido | top10 > 60% supply | etherscan |
| Recovery | recuperou ATH 2021 | nunca recuperou | price history |
| Listing | >2y exchange stable | <6mo pode delistar | exchange history |

**Aplicacao**:
- BLUE_CHIP (FQS 6-7): Tier A LIVE + GEM, qualquer mode
- QUALITY (4-5): Tier B PAPER + Tier A LIVE seletivo
- SPECULATIVE (2-3): GEM only, size reduzido
- AVOID (0-1): bloqueado em todos tiers

**Estimativa tier A LIVE atual**:
- BTC: 7/7 BLUE_CHIP
- INJ: 5/7 QUALITY
- ZEC: 4/7 QUALITY (mas amplifier risk)
- RENDER: 5/7 QUALITY
- **CFG: 3/7 SPECULATIVE** -> candidato a demote junto com ZEC

**Implementacao (2 opcoes)**:
1. MVP hardcoded registry (1h) -- curated manual pros ~30 markets pipeline
2. CoinGecko API integration (3-4h) -- live fetch + auto-score

### 3.2 📋 News-driven sentiment + entry boost
- Sistema ja tem lib_idea_triggers + news tracker
- Falta: extrair sentiment score, somar ao Mentor score, registrar correlacao news -> outcome

### 3.3 📋 Adaptive trend persistence
- Trend_persistence.py existe (2.1)
- Adicionar: Hurst rolling window detection (regime change implicit)
- Wire: KER alto + Hurst > 0.6 = entry boost; reverso = block

### 3.4 📋 Meta-labeling Lopez de Prado completo
- Capitulo 3 AFML: 2-step classifier
- Step 1: primary signal (atual orchestrator)
- Step 2: meta-label (deve tradar? size?)
- Triple barrier outcome -> training data
- ~8h trabalho, requer infraestrutura ML pipeline

---

## ONDA 4 — Long-term evolution

### 4.1 Vol threshold calibrado por tier (defer ate dados forward 60d)
Empirical analysis (2026-05-19) mostrou $500K era 2.5x conservador demais.
Mas validar com forward 60d antes de migrar:
- TIER A LIVE: $200K (defensavel literatura + math)
- TIER B PAPER: $50K
- GEM/DISCOVERY: $10K

### 4.2 Pairs-trade HYPE/BTC
HYPE unico inverse-correlator real (beta -0.26, cross-window stable).
Validar com triple-barrier backtest antes de operar.

### 4.3 Beta normalization advanced
Hoje: avg(|beta|). Considerar: regime-conditional beta (BULL beta vs BEAR beta separados).

### 4.4 Multi-timeframe orchestration
4h + 1d + 1w confluence pra alta-conviccao setups.

---

## Priority matrix (custo vs valor)

```
                        VALOR ALTO  |  VALOR MEDIO  |  VALOR BAIXO
                       -------------+---------------+---------------
CUSTO BAIXO  (<2h)    | 2.2 news    | 4.1 vol cal   | (none)
                      | 4.2 pairs   |               |
                      -------------+---------------+---------------
CUSTO MEDIO  (2-4h)   | 2.3 spot    | 3.3 trend     |
                      | 3.1 FQS MVP | 2.5 Kelly     |
                      -------------+---------------+---------------
CUSTO ALTO   (4h+)    | 2.4 feedback| 3.4 meta-lbl  |
                      | 3.1 FQS API |               |
```

**Prioridade imediata**: 2.2 news boost (esta sessao), 2.3 spot routing (proxima),
3.1 FQS MVP (logo apos news + spot)

---

## Retroalimentacao

Este roadmap evolui baseado em:
- Trades executados (feedback loop ONDA 2.4)
- Drawdowns capturados (drawdown monitor)
- Markets graduated/demoted (ladder events)
- Insights cross-sessao (memory bank user)

Revisar mensalmente. Ondas concluidas viram historicos em
`docs/handbook/sessions/*.md`.

---

## Anti-padroes evitados

1. **Big-bang refactor**: cada onda fechada antes da proxima
2. **Hardcoded magic numbers**: tudo configuravel + documentado
3. **Skip TDD**: sempre testes antes de wire em prod
4. **Burlar gates**: nunca force-promote skipping Sharpe gate
5. **Beta concentration cego**: avg gate scale-aware ja capturado
6. **Bootstrap stale**: bootstrap < real (feedback_bootstrap_conservador)
