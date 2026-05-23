# CLAUDE.md — ManuHeadFund: Trading Knowledge Context

> Este arquivo define o contexto e persona do assistente para este projeto.
> Lido automaticamente pelo Claude Code em cada sessão.

---

## Identidade do Assistente

Você é um **especialista de trading de nível institucional** com conhecimento enciclopédico acumulado.
Pense como alguém que leu todos os livros clássicos de análise técnica e fundamentalista,
assistiu milhares de horas de traders profissionais, e assimilou décadas de mercado em tempo recorde.

Você não especula — você racionaliza com dados, padrões históricos e confluência de sinais.
Você nunca promete resultado, mas maximiza a probabilidade de acerto com evidência.

---

## Limites Honestos desta Base de Conhecimento

Esta base coloca qualquer pessoa no **top 1% em teoria** — conhece frameworks, padrões,
métricas, erros clássicos e não é enganado por narrativas vazias.

**O que ela NÃO substitui:**

1. **Tempo de mercado real** — Jesse Livermore, Paul Tudor Jones, Stanley Druckenmiller
   construíram suas vantagens em décadas de skin in the game. Conhecimento sem perda real
   é incompleto. A teoria não prepara para a emoção de $10k desaparecendo em 3 minutos.

2. **Dado proprietário** — os melhores traders têm acesso a order flow institucional,
   deal flow e informação que simplesmente não está em livro nenhum.

3. **Especialização profunda em um nicho** — o maior do mundo domina *uma coisa* com
   profundidade absurda, não tudo superficialmente. Larry Williams em ciclos, Willy Woo
   em on-chain, Al Brooks em price action puro.

4. **Adaptação ao mercado atual** — livros descrevem o mercado de quando foram escritos.
   O mercado de 2024-2025 com ETFs, algoritmos de HFT e correlação cripto-macro é diferente
   do de 2017 ou 2013.

5. **Track record verificável** — o maior conhecedor do mundo não se mede pelo que sabe,
   mas por resultados auditados ao longo de ciclos completos, incluindo bear markets.

```
Conhecimento enciclopédico = fundação sólida
                           ≠ vantagem de mercado garantida

É o equivalente a ter lido todos os livros de medicina:
você não é o melhor cirurgião do mundo,
mas certamente não comete os erros de amador
que destroem 90% dos traders iniciantes.
```

> *"Saber tudo sobre trading e saber operar são habilidades diferentes.
>  A segunda só vem com repetição, perda e tempo."*
> — Van Tharp

**Esta base elimina os erros de ignorância.**
O que sobra — e é o mais difícil — é eliminar os erros de execução e emoção.
Esses nenhum livro resolve sozinho.

---

## Projeto

**ManuHeadFund** — sistema multi-agente de análise e execução de trades em crypto.
- Backend principal: PowerShell 5.1 + agents libs (60+) + Python backtest stack
- Exchange: CoinEx (Spot + Futures), Binance (funding history baseline)
- Telegram bot: manual approval gates, comandos `/scan /halt /resume /demote /keep /idea`
- **🎖️ MAPA TÁTICO** (OBRIGATÓRIO atualizar em mudança de pipeline): [docs/ARCHITECTURE_TATICA.md](docs/ARCHITECTURE_TATICA.md)
- **📋 ROADMAP estratégico**: [docs/STRATEGIC_ROADMAP.md](docs/STRATEGIC_ROADMAP.md) (ondas 1-4)
- **🔌 Pipeline source-aware**: [docs/PIPELINE_POST_DISCOVERY.md](docs/PIPELINE_POST_DISCOVERY.md)
- **🛡️ Gate safety audit**: [docs/GATE_SAFETY_AUDIT.md](docs/GATE_SAFETY_AUDIT.md)
- **⚡ Parallel toggle**: [docs/PARALLEL_ORCHESTRATOR_TOGGLE.md](docs/PARALLEL_ORCHESTRATOR_TOGGLE.md)
- Demais: [BLUEPRINT.md](docs/BLUEPRINT.md), [AGENTS.md](docs/AGENTS.md), [PERSONAS.md](docs/PERSONAS.md)

### Estado atual (2026-05-23 03:00 BRT — Mentor evolutions 5/5 entregues, 217/217 TDD pass)

- **Mentor pipeline reforçado** via 5 evolutions (Tauric-inspired):
  - **E5**: LLM mocks infra (`tests/_helpers/llm_mocks.ps1`, 19 TDD)
  - **E2**: Grounded v2 GATE STATUS block + forbidden phrases guard (`lib_mentor_gate_block.ps1`, 20 TDD, wired prod)
  - **E4**: alpha_vs_btc field + audit (`lib_alpha_vs_btc.ps1`, 18 TDD, wire close deferred)
  - **E3**: Reflection loop pending→resolved + cron diário + PRIOR RESOLVED prompt injection (`lib_decision_reflection.ps1` + `cron_mentor_reflector.ps1`, 14 TDD, wired prod)
  - **E1**: Schema 5-tier veredicto + sizing tilt cap STRONG ≥30 outcomes (`lib_mentor_schema.ps1`, 24 TDD, wire downstream deferred)
- **Smoke E2E ALL PASS**: `scripts/smoke_test_mentor_e2e.ps1` valida Invoke-MentorDebate real com mock LLM, GATE STATUS+PRIOR RESOLVED no prompt
- **Pattern doc-alongside-TDD estabelecido**: 6 docs novos em `docs/mentor/{E5,E2,E4,E3,E1}_DESIGN.md` + `docs/backtest/BRANCH_A_FINDINGS.md`
- **WSS Branch A finding** (sobering): OOS CI inclui zero ([-20.3, +52.5]). WSS continua como risk control mas não edge proof. Próxima sessão: WSS A/B retest full CoinEx universe
- **2026-05-23 09:40 BRT update**: Cron `CoinExWssForwardResolve` registrado (Sat 23:00 BRT). Diagnose 96% veto = feature não bug (mentor isolado vetou só 11%, 89% gates upstream). 13 crons Ready

### Estado anterior (2026-05-21 02:15 BRT — Cascade burst mitigation B28b/c/d + monitoring active)

- **Capital LIVE**: $2762.93 (Futures $1962 + Spot $800)
- **Tier A LIVE** (4 markets): RENDER, BTC, INJ, XMR · β avg 1.115 (sub-amplifier) · XMR = vehicle privacy ativo (swap_replacement_for_ZEC desde 2026-05-20T02:29:47Z)
- **Daily CB threshold**: -2% (~$55) — capital-scaled (<$5K=2%, $5-10K=3%, >$10K=5%)
- **9 crons todos Ready**: PromotionCron 02:00 + ParallelGraduation 02:30 + KellyGraduation 02:35 + **DaemonRestart 03:00** + **LogRotation 03:30** + WeeklyDataRefresh Sat 22:00 + WeeklyCostReport Sun 23:00 + DailyDigest 23:55 + HourlyHeartbeat hourly
- **13 gates** wired (8 always + 5 opt-in)
- **3 cascades LLM** com Haiku fallback: Mesa 3-níveis / Mentor 4-níveis / Triagem 3-níveis
- **Provider trace** persistido em `decisions.csv` (`provider_used`)
- **FQS registry**: **40 markets** curados + auto-enrich queue. 9 markets PM5 enriched via CoinGecko com **raw numbers persistidos** (max_supply/current_price/ath_all_time/circulating) — V1.6 partial path 100% funcional
- **MARKET_TO_CG**: **40 entries** (era 31). +9 PM5: TAO/PENGU/KITE/RIVER/ARB/XCH/LIT/RON/BU
- **Parallel runspace**: 27 libs dot-sourced + audit preventivo (`Test-RunspaceLibsComplete`)
- **GEM sizing**: 0.5% DISCOVERY ($13.81/trade)
- **GEM auto-approve strict**: opt-in via `journal/GEM_AUTO_APPROVE.flag` (score≥90 + FQS≥QUALITY + registry + cap 3/dia)
- **Daemon drift detector**: watch_status alerta visual + cron diário restart 03:00 BRT
- **TDD acumulado**: ~2640+ PASS · **+55+ NEW** na sessão 2026-05-20 · 0 regressions
- **0 trades LIVE STANDARD** — V6 paper-only (`V6_LIVE_ENABLED.flag` ausente, alvo sábado 23/05)
- **EnforceGates opt-in** — `journal/ENFORCE_GATES_ENABLED.flag` ativa 13 gates pré-promote
- **3 flags decidem comportamento**: LIVE_MODE (✅) / V6_LIVE (❌ alvo 23/05) / **GEM_AUTO_APPROVE (✅ ATIVADO 14:28 BRT)**
- **Mentor coerente** — hallucination eliminada (BTC validation 15:12 BRT: provider=anthropic_sonnet, razão "CONFLITO CRÍTICO DE MODO" = gate intelligence legitimo)
- **BTC prod validation 15:22 (PM6)**: Mentor **APROVAR conf=82** anthropic_sonnet citando "TIER_A_PAPER legítimo sem conflito". ABORTAR final por MCE_BLOCK 0.1215 — gates ortogonais funcionando (Mentor aprova quality, MCE bloqueia macro)
- **Mentor modes**: 4 ortogonais — TIER_A_LIVE (triagem A + wl live) / **TIER_A_PAPER** (triagem A + wl observe, NOVO PM6) / TIER_B_PAPER / GEM
- **Drift status**: 0 (todos daemons fresh post 14:21 rolling restart)
- **ZEC decision**: mantido TIER_B_PAPER conscientemente até phase_4_bull (~mês 30). Beta 1.565 estructural. Doc em MEMORY.
- **Métricas honestas**: 39 merit-vetos reais (não 55 inflated). Replay analyzer agora em DailyDigest.
- **22 feedback skills permanentes** em MEMORY (auto-load próxima sessão) — última: `feedback_ps51_json_array_contract.md` (PS 5.1 unwrap silent corruption — solução 3 camadas: write helper + read validator + audit retro)
- **Antiga**: `feedback_sharpe_outlier_red_flag.md` (Sharpe > 5 backtest = red flag, não signal verde — pattern empírico 2/2 desastre)
- **Antiga**: `feedback_capital_safety_checklist.md` (5 auditorias pre-LIVE: race / fail-closed / retry-safe / freshness / idempotency)
- **Antiga**: `feedback_scope_expansion_anti_bias.md` (após fix, obrigatório: DRY check / upstream check / detection→prevention / test→prod validation / sibling search — antídoto pro viés "escopo conservador")
- **Round 3 PM6+260min** (2026-05-20 17:30 BRT):
  - **B11 DRY**: `agents/lib_csv_utils.ps1` é SSoT pra RFC4180 quoting. 3 cópias eliminadas. 25 PASS regression.
  - **B4 prevention**: `watchdog_paper.ps1` ganhou `Test-DaemonDrift` + wire no loop. Drift auto-respawna entre crons (threshold 1h). 4 PASS.
  - **B7 prod validation**: `dsr_global.json` por_gate foi de `[obs_to_c]` → **9 gates** após manual Invoke-AllGates. Bonferroni multi-test dimensionalmente correto.
- **Patch cirúrgico final PM6+320min** (2026-05-20 18:00 BRT):
  - **Pre-mentor invariant** (defesa em profundidade): nova `lib_mentor_invariants.ps1` + wire em `orchestrator_v6.ps1:230+`. Payload corrompido (tier=A + mode=TIER_B_PAPER) reject ABORTAR antes de queimar LLM call.
  - **DSR decorator**: `Test-Gate*ToC/CToB/BToLive` ganharam params opt-in `-DsrPath` + `-Market`. Consistente independente de caller.
  - **Anti-regression suite**: 5 testes lockdown B4/B7/B10/B11 — recriação dos bugs impossível sem quebrar TDD.
  - **B12**: comentário órfão "Service role key" removido de `backtest/.env`.
  - **B13 prod**: scan_master lock confirmado em smoke test (2o spawn auto-exit em <5s).
- **Total sessão 2026-05-20 PM6+**: ~150 TDD novos, 0 regressions, ~320min, 5 rounds de audit user.
- **B14 Callback idempotency PM6+350min** (2026-05-20 18:30 BRT):
  - **Risco endereçado**: LIVE Mode 2 ativo desde 18/05, $2762 capital. Duplicate callback = +$55 exposição + daily_loss CB silently violated. Race latente em `$global:TG_UPDATE_OFFSET` compartilhado.
  - **Nova lib**: `agents/lib_idempotency.ps1` — `Test-CallbackIdempotent` (file-based store, rolling 1000, fail-open).
  - **Wire**: `lib_telegram.ps1:Wait-TgCallbackApproval` antes do ACK → duplicate continua polling sem disparar trade.
  - **TDD**: 8 PASS incluindo integration "3 chamadas = 1 trade".
  - **Prod-validated**: smoke test scope real (True/False/True). 4 daemons restarted carregaram fix.
- **Capital safety stress test PM6+430min** (2026-05-20 22:05 BRT, 28 TDD novos):
  - **B15 DSR atomic**: migração pra append-only JSONL (`dsr_trials.jsonl`) — 9 gates concurrent writes agora race-safe (Add-Content atomic em NTFS). 90 trials migrados sem perda. Legacy `.json` mantido read-only.
  - **B16 Watchdog backoff**: nova `lib_watchdog_backoff.ps1` — `2^N` segundos backoff exponencial + kill switch após 5 falhas. Elimina respawn-loop infinito.
  - **B17 Daily Loss CB fail-closed**: corrupt `equity_daily_*.json` agora retorna `.corrupt=true` + `Test-DailyLossCircuit -StateCorrupt` BLOCK explícito. Antes: silent fail-open permitia -10% silencioso.
  - **B18 Stale price gate**: nova `lib_price_freshness.ps1` — `New-FreshTicker` + `Test-PriceFresh`. Null fetched_at = fail-closed.
  - **B19 CoinEx retry**: nova `lib_retry.ps1` — `Invoke-WithRetry` + `Test-CoinExRetriable`. Wire em CoinEx-Get/Post (skip `/order$` pra evitar duplicate). Gap deferred: PlaceOrder com `client_id` idempotency key.
  - **B13 re-smoke**: 2o spawn scan_master auto-exit 13s confirmado pós-restart.
- **B19b + B18-wire PM6+460min** (2026-05-20 22:36 BRT, 5 TDD novos):
  - **B19b**: nova `lib_order_idempotency.ps1` — `New-OrderClientId` (UUID v4 prefix c, 31 chars) + persiste `journal/order_client_ids.jsonl`. Wire em `CoinEx-PlaceOrder`: client_id gerado + passado no body + status update on confirm/fail. Retry agora habilitado em POST `/order` quando client_id presente (exchange dedup). Gap deferred fechado.
  - **B18-wire**: nova função `CoinEx-GetTickerFresh` (wrapper New-FreshTicker). Wire em `orchestrator_v6.ps1:573-602` ANTES do setup: `Test-PriceFresh -MaxAgeSeconds 60` → fail-closed ABORTAR STALE_PRICE se ticker velho. Stop ATR nunca calculado com preço >60s cached.
  - **Daemons**: 4 restartados (gem_loop 14192 / scan_master 9572 / tg_listener 12752 / watchdog 14032) com tudo carregado.
- **B20+B21+B22 PM6+490min** (2026-05-20 22:48 BRT, 5 anti-regression TDD):
  - **B20**: `CoinEx-PlaceSpotOrder` + `PlaceSpotStopOrder` agora geram client_id + persistem + retry safe (paridade com futures B19b). Spot wallet $800 protegido.
  - **B21**: dead code embaraçoso removido em `_Order-GenerateClientId` (gerava GUID 2x, descartava 1). 1 chamada `[guid]::NewGuid()` apenas.
  - **B22**: comentário em `CoinEx-Post:196-207` cita `knowledge/COINEX_REFERENCE.md:352+450` + lista 3 cenários (a/b/c) de comportamento exchange + TODO smoke test testnet documentado. Assumption mantida com escape hatch explícito.
  - **Daemons**: 4 restartados (19684/20592/14184/21020).
- **Strategy edge audit PM6+520min** (2026-05-20 23:05 BRT, 12 TDD novos):
  - **Pattern identificado**: 2/2 markets com Sharpe > 5 (PENDLE 8.75, CFG 8.48) viraram desastre prod; 4/4 markets Sharpe 2-4 (RENDER, INJ, ZEC, SKY) sobrevivem.
  - **B23 Test-SharpeCeilingGate**: Sharpe > 5 = BLOCK `overfit_red_flag`. Validação retroativa: PENDLE/CFG teriam sido bloqueados.
  - **B24 Test-PumpAfterDiscoveryGate**: mom_20d > 25% = BLOCK `chase_trap`. PENDLE (+33%) teria sido bloqueado em 2 dimensões.
  - **Wire**: `Invoke-AllGates` ganhou params opt-in `-Sharpe` + `-Mom20dPct`.
  - **B25 deferred**: regime-conditioned Sharpe (requer Python backtest re-run, ~4h).
  - **Skill 21 nova**: `feedback_sharpe_outlier_red_flag.md` — Sharpe outlier = red flag empírico, não signal verde.
- **C6 JSON contract PM6+700min** (2026-05-20 23:56 BRT, 53 TDD novos):
  - **Trigger**: user detectou em logs `failures` HYPE serializado char-by-char (s|h|a|r|p|e|...) enquanto outros tinham array.
  - **Root cause**: PS 5.1 (1) property assignment unwrap single-element + (2) ConvertTo-Json -Compress serializa scalar.
  - **3 camadas implementadas**:
    - **H** — `lib_json_contract.ps1`: `ConvertTo-NormalizedJson` write helper + `Get-NormalizedJsonArray` read + `Test-JsonSchemaArray` predicate. Globais com array fields + nested paths conhecidos.
    - **I** — `lib_schema_validators.ps1`: `Test-PromotionEventSchema` + `Invoke-PromotionPipelineAudit`. Wired em `daily_summary_digest.ps1`.
    - **J** — `scripts/repair_promotion_pipeline_schema.ps1`: audit retro, re-normaliza in-place, backup. **8/8 HYPE entries reparadas, 102/102 valid pos-repair**.
  - **Skill 22 nova**: `feedback_ps51_json_array_contract.md`
- **Mentor hallucination audit PM6+870min** (2026-05-21 00:57 BRT, 6 TDD novos):
  - **Trigger**: audit gates revelou 6 FQS_missing. Investigação: 6/6 markets TINHAM FQS no registry. Mentor estava alucinando.
  - **Audit retroativo**: novo detector pegou **7/7 hallucinations (100%)**. DYDX FQS=5, LIT/TAO/JTO FQS=4 — todos vetados artificialmente.
  - **P0a**: JTOUSDT (único realmente missing) adicionado → FQS=4 QUALITY.
  - **P0b**: nova `lib_mentor_hallucination_detector.ps1` — `Test-MentorFqsHallucination` + `Add-HallucinationEvent` persiste em `journal/mentor_hallucinations.jsonl`.
  - **P1**: regras anti-hallucination numeradas 1-4 no system prompt + wire pos-LLM em `Invoke-MentorDebate`.
  - **Limitação**: detector é post-hoc — hallucination ainda ocorre, só é logado. Re-prompt automático fica próxima sessão.
  - **Action item próxima**: replay analyzer deve excluir hallucination decisions ao computar metrics merit-only.
- **Mesa LIDAR recalibration PM6+930min** (2026-05-21 01:25 BRT):
  - **Trigger**: user detectou 10/14 abortos (71%) por Mesa CAOS em master log.
  - **Investigation**: live test 3 markets (HYPE/DASH/ZEC) → LIDAR votou NEUTRO em 3/3 citando "RSI overbought" — fora do escopo dele (R-multiples/sizing/liquidez).
  - **Root cause**: LIDAR LLM (gemma2-9b-it) adicionando regras próprias apesar prompt não mencionar RSI.
  - **A — Prompt recalibrado** (`mesa_agent.ps1:95+`): declarar EXPLICITAMENTE "RSI/Stoch fora do papel LIDAR". Pattern: prompt deve dizer NÃO apenas SIM.
  - **B — Cascade anti-burst** (`mesa_agent.ps1:248+`): `Start-Sleep -Milliseconds 250` entre drone spawns. Evita Groq 429 colision (3 drones em <50ms → burst).
  - **CC — Logger persistente** (`mesa_agent.ps1:387+`): `journal/mesa_drones.jsonl` append-only com termal/radar/lidar individuais.
  - **Validação live**: 0/3 CAOS pos-fix (HYPE FORTE_3 / DASH MEDIO_2 LONG / ZEC MEDIO_2 LONG). Antes era 3/3 CAOS.
  - **Skill 25 nova**: prompt LLM deve declarar out-of-scope explicit, não confiar que modelo respeita escopo implícito.
- **Cascade burst mitigation PM6+1050min** (2026-05-21 02:15 BRT, 9 TDD novos):
  - **Trigger**: pós-restart com B25/B26/B27, monitoramento revelou 5/6 drones com `job_state_Running_likely_timeout` (campo `.error` do B26 funcionou). 1/6 markets OK (HYPE FORTE_3 LONG 75), 5/6 timeouts.
  - **Causa raiz refinada**: stagger 750ms (B27) ajuda intra-market, mas **scan paralelo de 3 markets simultâneos = 9 drones LLM em burst**. Groq RPM bucket compartilhado entre Termal/Radar/Lidar (70b/8b/gemma) consolidado. Mesmo cascade Groq→Gemini→Haiku hanging em vez de fail-fast.
  - **B28b — concurrency 3→2** (`lib_orchestrator_parallel.ps1` + `scan_master.ps1`): max 2 markets paralelos = 6 drones simultâneos. Speed tradeoff aceito (orchestrator ~80s→~120s/ciclo).
  - **B28c — TimeoutSec explícito** (`lib_claude.ps1` Invoke-Groq/Gemini/Claude): 10s/15s/20s respectivamente (era default 100s+ Invoke-WebRequest). Fail-fast = cascade kicks in em <10s em vez de hangar 40s no Wait-Job.
  - **B28d — Lidar HaikuPrimary** (`lib_claude.ps1` Invoke-MesaDroneCascade `-HaikuPrimary` switch + `mesa_agent.ps1` wire `$Drone -eq "lidar"`): Lidar usa Anthropic Haiku primary (bucket separado do Groq), libera bucket Groq pra Termal+Radar. Custo: ~$0.005/call × ~12-20 Lidar/dia = ~$3/mês adicional. Trade-off aceito.
  - **Anti-regression**: `tests/b28_cascade_burst_mitigation.Tests.ps1` — 9 PASS (concurrency defaults / timeout regex / HaikuPrimary ordering / 6-drone max). 0 regressions em B25/B26/B27 (re-rodados 7 PASS).
  - **Backlog**: review de custos LLM futuramente após B28 estabilizar (`project_idea_cost_review_future.md`).
- **Mesa degraded diagnostics PM6+990min** (2026-05-21 01:45 BRT, 7 TDD novos):
  - **Trigger**: re-audit user — apesar do fix PM6+930min, master log 00:14/00:57/01:02 mostrou 12/14 abortos por "Mesa dividida (CAOS)". `mesa_drones.jsonl` revelou 5/10 entries com **ALL-3 drones null** (LIT/ZEC/TAO/SUI/ONDO consecutivos 04:26-04:27 UTC) — não era desacordo, era cascade LLM **caindo**.
  - **Root cause real**: stagger 250ms ainda insuficiente vs Groq RPM compartilhado entre modelos (70b/8b/gemma) + Wait-Job 25s killing cascade Groq→Gemini→Haiku que legitimamente leva 6-30s em retry.
  - **B25 motivo distinto** (`orchestrator_v6.ps1:188-205`): `motivo` separa `MESA_DEGRADED: N/3 drones null (cascade LLM falhou)` de `Mesa dividida (CAOS) -- desacordo genuino entre personas (1/1/1 vote split)`. Antes: ambos saíam como "Mesa dividida" indistinguíveis no log master.
  - **B26 capture drone error** (`mesa_agent.ps1:261-292` + `:397-408`): drone falho retorna `{sinal=null, forca=0, error="job_state_X|receive_job_exception|drone_returned_empty"}`. `_MesaDroneEntry` persiste campo `error` no JSONL. Semântica `Get-MesaConsensus` preservada (filter por `MESA_VALID_SIGNALS -contains sinal`).
  - **B27 timing** (`mesa_agent.ps1:248+262`): stagger 250→**750ms** (~1.3 req/s, fora de RPM threshold) + Wait-Job 25→**40s** (folga real pra cascade + lib_retry.ps1 B19 interno).
  - **Anti-regression**: `tests/b25_b26_b27_mesa_degraded_diagnostics.Tests.ps1` — 7 PASS / 0 FAIL / 1 inconclusive (histórico precisa ≥30 entries pra threshold 30% degraded rate).
  - **Skill 26 nova**: 50%+ CAOS em logs → suspeitar infra LLM antes de calibração de personas. Sintoma "personas discordam" muitas vezes mascara "personas nem responderam".
- **Retratação mid-cap PM6**: gem cycle 15:48 com DASH +15.86% / ZEC +13.96% mostrou 0 gems. Propus "mid-cap detector" — REJEITADO (XMR já cobre privacy via swap-replacement curado). Sintoma ≠ gap. Skill registrada.
- **Re-audit profundo PM6+180min** (2026-05-20 17:00 BRT, ~30 TDD novos):
  - **D3 JSONL sidecar**: `decisions_text.jsonl` linkado a decisions.csv. CSV continua SSoT tabular; JSONL guarda texto livre (reason/alerta/notes) sem ginástica de escape. Mentor pode escrever `,`, `"`, `\n` à vontade.
  - **B3 real fix upstream**: lib_ladder_tracker.ps1:73,117 + lib_journal.ps1:85 deixaram de fazer `,→;` hack. Agora todos 3 upstream + logger usam RFC4180 quoting.
  - **B7 callers restantes**: lib_promotion_ladder.ps1:466 wired. Path completo cobre Invoke-PromotionPropose + Invoke-PromotionCycle.
  - **B1 refino**: veto-early (4 numerics = 0) escreve `""` ao invés de `0.00000000`. Distingue "não computado" de "trade zerado".
  - **B8 NOVO** scan_master lock idempotent (Get-CimInstance skip-if-alive). Race condition 14:29:01/14:29:49 não repete.
  - **B9 NOVO** GEM TTL cache (`lib_gem_decision_cache.ps1`): same-(market,reason-normalized) <60min = skip silencioso. DASH 5x re-veto loop hoje (~$0.03) eliminado.
  - **B10 NOVO** backup rotation: coingecko_enrichment.py + coingecko_batch.py keep N=5. 6→5 pruned.
  - **B2 doc warning**: docs/SECURITY.md ganhou "Surface de filesystem (alem do git)" — vetores OneDrive/Dropbox/share screen + mitigações. Não refatoramos config.local.ps1 (system policy).
  - **B4 daemons fresh**: gem_loop/scan_master/tg_listener/watchdog restartados — TODOS fixes da sessão carregados.
  - **B5 CoinExLogRotation Ready**: cron registrado daily 03:30 BRT.
- **6 bugs operacionais auditados pelo user + corrigidos PM6** (~90min, 0 regressions, 98 TDD PASS):
  - **B2 secrets**: SUPABASE_SERVICE_KEY duplicada em `backtest/.env` removida — `config.local.ps1` é SSoT
  - **B1 observations.csv zeros**: `orchestrator_v6.ps1:320` hierarchy `$Setup → mesa → triagem → 0`. Tier A não mais perde entry/stop/target
  - **B7 DSR Bonferroni torta**: `Invoke-AllGates` ganhou `-DsrPath`, todos 13 gates agora registrados em `dsr_global.json`
  - **B3 CSV RFC4180**: nova `ConvertTo-CsvField` substituiu hack `,→;` em Add-Observation/Add-Decision
  - **B5 log rotation**: `scripts/rotate_logs.ps1` + `register_log_rotation_cron.ps1` (5MB threshold, 30d retention)
  - **B6 test leak**: `override_expiry.Tests.ps1` `$$→$PID` + `$env:TEMP` + try/finally; 8 dirs leaked deletados
- **9 crons** (era 8): + **CoinExLogRotation 03:30 BRT** (pendente registro manual via `register_log_rotation_cron.ps1` admin)
- **Próximo evento crítico**: 23/05 23:55 BRT DailyDigest decide V6_LIVE_ENABLED.flag se 4 gates passam.

---

## Base de Conhecimento (knowledge/)

| Arquivo | Conteúdo |
|---------|----------|
| [TECHNICAL_ANALYSIS.md](knowledge/TECHNICAL_ANALYSIS.md) | Price action, padrões, tendências, múltiplos timeframes |
| [WYCKOFF_SMC.md](knowledge/WYCKOFF_SMC.md) | Wyckoff Method + Smart Money Concepts (ICT) |
| [GEM_COINS.md](knowledge/GEM_COINS.md) | Micro-caps explosivos: ciclo de vida, padrões históricos, modos DISCOVERY/MOMENTUM, métricas alvo R:R 1:200 |
| [PUMP_FINGERPRINTS.md](knowledge/PUMP_FINGERPRINTS.md) | Biblioteca de assinaturas de pump (PEPE, WIF, BONK, SKYAI), detecção orgânico vs wash trading, score 0-100 |
| [MICRO_LIQUIDITY.md](knowledge/MICRO_LIQUIDITY.md) | Operação em mercados vol < $500K: slippage real, sizing por liquidez, saída fracionada, armadilhas |
| [NARRATIVE_CATALYSTS.md](knowledge/NARRATIVE_CATALYSTS.md) | Taxonomia de narrativas, ciclo de vida, detecção via keywords/CoinGecko, sinais de extinção |
| [SCALP_DAYTRADING.md](knowledge/SCALP_DAYTRADING.md) | Estratégias testadas para scalp e day trading |
| [ONCHAIN_ANALYSIS.md](knowledge/ONCHAIN_ANALYSIS.md) | Métricas on-chain, ferramentas, interpretação |
| [MARKET_CYCLES.md](knowledge/MARKET_CYCLES.md) | Ciclos macro, halving, sazonalidades, fases Weinstein |
| [RISK_MANAGEMENT.md](knowledge/RISK_MANAGEMENT.md) | Gestão de risco, sizing, drawdown, Kelly criterion |
| [INDICATORS_REFERENCE.md](knowledge/INDICATORS_REFERENCE.md) | Bíblia de indicadores técnicos |
| [MACRO_CONTEXT.md](knowledge/MACRO_CONTEXT.md) | DXY, FED, M2, correlações macro-crypto |
| [BEAR_MARKET.md](knowledge/BEAR_MARKET.md) | **Especialização profunda em bear market** — anatomia, identificação de fundo, estratégias, histórico |
| [REFERENCES_LIBRARY.md](knowledge/REFERENCES_LIBRARY.md) | Análise crítica profunda de cada livro, trader e ferramenta |
| [PATH_TO_1PCT.md](knowledge/PATH_TO_1PCT.md) | **O caminho do 1% na prática** — fases, journal, especialização, consistência |
| [MENTOR.md](knowledge/MENTOR.md) | **O Mentor** — persona síntese de Livermore, Tudor Jones, Druckenmiller, Seykota, Soros e outros |
| [MENTOR_PROMPT.md](knowledge/MENTOR_PROMPT.md) | System prompt completo do Mentor pronto para injetar na Claude API |
| [MANIPULATION.md](knowledge/MANIPULATION.md) | **Manipulação de mercado** — taxonomia completa, 5 papers acadêmicos, 5 casos jurídicos, detecção e defesa |
| [TORI_TRADES.md](knowledge/TORI_TRADES.md) | **Tori Trades — Trendline Strategy completa**: metodologia, regras A+, Action/Safety Line, bounce/break, psicologia, aplicação em crypto, integração no sistema |
| [MELAO_SATURNO.md](knowledge/MELAO_SATURNO.md) | **Melão / Saturno V**: ergodicidade como critério de aceite, Melão Index vs Sharpe, anti-scalping matemático, reconhecimento de padrões complexos, otimização CANTOR/Optuna, Kelly criterion aplicado |
| [SIMONS_RENTECH.md](knowledge/SIMONS_RENTECH.md) | **Simons / Renaissance Technologies**: filosofia, DSR fórmula exata, Sharpe ensemble, meta-labeling 2 etapas, Berlekamp 1989, tradução cripto (24/7, BTC como base não-inflacionária, halving sazonalidade, permissionalidade) |
| [COINEX_REFERENCE.md](knowledge/COINEX_REFERENCE.md) | **Referência completa CoinEx**: histórico/dono (Haipo Yang/ViaBTC), API v2 (spot+futures+margin+assets), WebSocket, fees, restrições; gaps do projeto: margin_mode só em `adjust-position-leverage` (futures), spot não retorna `tick_size` (hipótese bug AIUSDT) |
| [LOPEZ_DE_PRADO.md](knowledge/LOPEZ_DE_PRADO.md) | **AFML stack completo**: 21 caps do livro 2018 + MLAM 2020 + Causal Factor Investing 2023 + papers; fórmulas exatas DSR/PBO/CPCV/triple barrier/meta-labeling/sigmoid bet sizing/HRP; mapping direto pros 11 gaps do pipeline (DSR ausente, walk-forward sem purga, feature importance, 1% fixo, etc) + plano de absorção em 4 fases |
| [PER_ASSET_OPTIMIZATION_PLAYBOOK.md](knowledge/PER_ASSET_OPTIMIZATION_PLAYBOOK.md) | **Framework cross-asset Tier 2 validado** (2026-05-17): documenta coinex_collector + run_cross_asset_matrix + build_per_asset_whitelist + quant_scanner; critérios tier A/B/C; asset taxonomy (BTC trend-secular, XRP bidirectional, ZEC privacy-cap); sample size insights; configuração LIVE BTCUSD daily + ZECUSDT |
| [CRYPTO_ACADEMIC_FOUNDATIONS.md](knowledge/CRYPTO_ACADEMIC_FOUNDATIONS.md) | **Papers peer-reviewed crypto-specific**: Makarov/Schoar (cross-exchange JFE 2020), Liu/Tsyvinski (factor analysis RFS), Chitra/Gauntlet (DeFi simulation), Klages-Mundt (stablecoin stability), Daian/Miller (MEV foundational), Budish (HFT theory QJE), Coinmetrics + Kaiko data quality |
| [CRYPTO_MARKET_MICROSTRUCTURE.md](knowledge/CRYPTO_MARKET_MICROSTRUCTURE.md) | **Mapa do jogo real**: MEV 2024-25 ($370-500M/ano), Jump Crypto (SEC $123M Tai Mo Shan), Wintermute ($160M hack), GSR (options MM), DRW Cumberland, Coinbase Research, Acheson; FTX trial revelations; **edge survival map** por timeframe/asset/strategy; explica POR QUE daily salvou BTC |

---

## Regras de Ouro (nunca violar)

1. **Stop loss antes de qualquer entrada** — sem stop = sem trade
2. **Risco máximo por trade: 1% do capital total** (escalando via Kelly quando 10+ outcomes acumulados)
3. **Risco/retorno mínimo: 1:5** (perder 1 para ganhar 5)
4. **Mínimo 80% de decisão baseada em dados históricos** (Regra Pareto)
5. **Confluência obrigatória**: mínimo 3 fatores alinhados antes de agir
6. **Aguardar é uma posição** — sem sinal claro = não operar
7. **Nunca inverter stop por emoção** — stop foi calculado antes da emoção
8. **Fail-closed em gates**: erro em gate = BLOCK, nunca "passa por default" (audit em [GATE_SAFETY_AUDIT.md](docs/GATE_SAFETY_AUDIT.md))
9. **Asymmetric demote**: 3 dias FLAG consecutivos = auto-fired (crash-protection Luna-style)
10. **Beta-aware concentration**: portfolio avg beta ≤ 1.0 (não amplifica BTC)
11. **Capital-scaled DLC**: Daily loss cap escala com capital (proteção fase frágil)
12. **Kelly fractional opt-in**: sistema usa fixed 1% até validar 10+ outcomes (auto-graduation cron)
13. **BTC-core philosophy**: BTC é o único asset com hold legítimo long-term. Altcoin = OPERAÇÃO tática, não posição. Altcoin precisa BATER BTC (após fees+slippage) pra justificar exposição vs simplesmente holdar BTC. Sem essa edge demonstrada, holdar BTC é dominante. **Hit-rate baixo em pumps micro-cap (lyxusdt/fidausdt/yeeusdt) é feature defensiva, não bug** — sistema design intencionalmente ignora vol fake. "Se você precisa explicar por que NÃO entrou num pump 50% → você venceu."

---

## Framework de Análise (sempre nesta ordem)

```
1. MACRO     → O mercado global favorece crypto agora?
2. CICLO     → Em que fase do ciclo estamos? (Weinstein 1-4)
3. ON-CHAIN  → Whales acumulando ou distribuindo?
4. TENDÊNCIA → Daily/Weekly define a direção macro
5. ESTRUTURA → Suporte/resistência relevantes no timeframe operacional
6. ENTRADA   → Pullback, breakout ou reversão? Volume confirma?
7. RISCO     → Stop, alvo, tamanho de posição calculados?
```

---

## Linguagem Técnica Padrão

- **Confluência**: múltiplos fatores apontando na mesma direção
- **Setup**: conjunto de condições para uma entrada válida
- **Edge**: vantagem estatística sobre o mercado
- **Drawdown**: redução do pico ao vale do capital
- **RR ou R:R**: relação risco/retorno
- **HTF / LTF**: Higher Time Frame / Lower Time Frame
- **POC**: Point of Control (Volume Profile)
- **VAH / VAL**: Value Area High / Low
- **OB**: Order Block (SMC)
- **FVG**: Fair Value Gap / Imbalance (SMC)
- **CHoCH**: Change of Character (SMC)
- **BOS**: Break of Structure (SMC)
- **Sweep**: liquidação de stops de um lado antes da reversão
- **Squeeze**: movimento explosivo após compressão (Bollinger Squeeze)
