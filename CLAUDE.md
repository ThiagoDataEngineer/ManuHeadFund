# CLAUDE.md — ManuHeadFund

> Lido automaticamente em cada sessão. Manter ENXUTO.

---

## Projeto

**ManuHeadFund** — sistema multi-agente de trading em crypto (CoinEx Futures/Spot).
- Backend: PowerShell 5.1 + 60+ agent libs + Python backtest
- Exchange: CoinEx (principal), Binance (funding baseline)
- Telegram bot: approval gates, comandos `/scan /halt /resume /demote /keep /idea`
- Docs técnicos: `docs/ARCHITECTURE_TATICA.md`, `docs/STRATEGIC_ROADMAP.md`, `docs/AGENTS.md`

### Estado atual (2026-08-04)

- **Instrumentação `sl_source`/`tp_source`/`stop_pct_used` em `trade_outcomes`** (commit `2c20d71`, 2026-08-04, SÓ GRAVAÇÃO — nenhuma auto-calibragem ainda): owner perguntou se o sistema se recalibra sozinho (LLM/aprendizado); mapeamento revelou que sim existe um motor real (`lib_evolution_engine.ps1`, rodando a cada 6h desde 07-17, com bounds duros + anti-oscilação + `class=risk` nunca auto-aplica), mas cobre só parâmetros de detecção (sentinela/pump-fade/tori), não TP/SL. Ao tentar estender pra `stop_pct` (o fallback fixo de `Get-StructuralStopTarget` e o stop por Mode de `Calculate-StopTarget`), achamos que **não dava pra medir o ganho**: a origem do SL/TP (pivot estrutural vs % fixo) nunca sobrevivia até o fechamento do trade. Fechado o elo: `Add-TrailingPosition`/`Repair-PositionProtection` gravam a origem no `trailing_state`, `Close-TrailingPosition` repassa pro `Add-TradeOutcome`, cai no payload JSONB de `trade_outcomes` (sem coluna nova). **Retomar quando houver ~1-2 semanas de trades fechados com o campo populado** — só então desenhar bounds/kill-switch da auto-calibragem com dado real, não estimativa. Bug real encontrado no caminho (corrigido junto): bloco de journal-write de `Repair-PositionProtection` usava dot-assign direto que lançava exceção silenciosa em registros mínimos (orphan-detection), perdendo TODOS os campos, não só os novos — trocado por `Add-Member -Force`.
- **Bug crítico do Evolution Engine corrigido** (commit `3db5533`, 2026-08-04): `journal/evolution_params.json` estava commitado no git desde 07-25 (`!journal/evolution_params.json` no `.gitignore`, pensado pro mesmo padrão de `coin_registry.json` — curadoria estática). Mas esse arquivo é ESCRITO pelo próprio motor a cada ciclo — versionar fazia todo checkout limpo (cron a cada 6h) resetar o overlay pro valor congelado no commit, apagando qualquer progresso real. Histórico mostrava a mesma proposta (`sentinel_move_pct: 3.25→3`) tentando aplicar 41x seguidas sem nunca colar. Fix: untrack + volta pra regra genérica `journal/*.json` (Supabase já é a fonte de verdade funcional pro cloud).
- **Fix crítico paginação `CoinEx-GetPendingPositions`** (commit `01c003a`, 2026-08-04): chamada bulk (sem filtro de market) não passava `limit=`, caindo no default de paginação da CoinEx (~10). Com 11 posições FUTURES abertas, a 11ª (mais recente) nunca aparecia — SOLUSDT SHORT ficou 5h40 sem TP/SL porque todo mecanismo que varre "todas as posições" (auditoria de proteção, `Repair-PositionProtection -All`) nunca a via. `CoinEx-GetPosition -market X` (chamada direta) não tinha esse problema. Fix: `limit=100` explícito. Reparo manual confirmado (SL=74.29/TP=70.59).
- **Execução real de PARTIAL/EXIT do trailing unificado** (commit `89123e0`, 2026-07-31, gated OFF por padrão): `Resolve-TrailingDecision` já recomendava PARTIAL/EXIT mas `trailing_stop_monitor.ps1` só logava, nunca executava — achado ao avaliar o trade DOGEUSDT ao vivo (owner pediu). Problema de design: `size_pct` é stateless ("quanto DEVERIA restar", recalculado a cada ciclo), então executar via ordem de mercado a cada 5min re-venderia contra o que já resta (oversell). Solução: `Register-PartialExitLadder` (`lib_trailing_partial_exit.ps1`) registra um ladder de saída nativo na CoinEx (`CoinEx-PlaceMultiExitLadder`, já testado em produção) UMA vez por posição, idempotente via nova tabela `manuheadfund.partial_exit_ladders`. Bug auto-detectado no TDD: 1ª versão tratava PARTIAL e EXIT igual — perfil "runner" tem `partials=[]` por design (dinheiro da casa), então um EXIT desse perfil registraria ladder vazio em vez de fechar a posição. Fix: EXIT fecha via `CoinEx-ClosePosition` (posição inteira), só PARTIAL registra ladder. Gated por `journal/PARTIAL_EXIT_EXECUTION_ENABLED.flag` — **ausente por padrão**, comportamento antigo (só log) preservado até o owner decidir ativar. Suite completa 6013 pass/29 fail (zero regressão, falhas conhecidas por contaminação cruzada de mock).
- **Motor de trailing unificado ATIVO** (commits `bc89952`..`054b812`, 2026-07-29/30): substitui 3 motores fragmentados que colidiam entre si na mesma posição (`Update-AllTrailingStops`, `Invoke-TrailingPolicyLive`, `Sync-TrailingToExchange` — cada um chamava `set-position-stop-loss` de forma independente, e essa API da CoinEx cancela/recria a ordem inteira a cada chamada, causando o "seta apaga" real reportado pelo owner). `Resolve-TrailingDecision` (`lib_trailing_unified.ps1`) agora decide sozinho, com fatores de exhaustion + trendline (Tori) + suporte/resistência (pivot) + piso de 0.05% de melhora mínima antes de empurrar update (evita push por ruído de arredondamento).
- **TP/SL estrutural** (commits `054b812`, `c2e74ea` 2026-07-31): `Repair-PositionProtection`/auto-repair calculava TP sempre a 32% fixo do entry, sem nenhuma leitura de suporte/resistência — confirmado que isso deixava o TP fora do range de 30 dias inteiro em várias posições reais. `Get-StructuralStopTarget` (nova) tenta pivot real primeiro, cai pro % fixo só se não achar estrutura dentro de um raio de 25%. Refinado no dia seguinte: owner acompanhou OPUSDT (modo MOMENTUM, alvo de design 150%) fechar via TP estrutural a só 1.65% — confirmado padrão real (3 de 4 trades do dia). Fix: `MinTargetFractionOfMode` (piso de 50% do alvo original) + `Repair-PositionProtection` agora busca o alvo real do trade via `Get-TrailingPositions` em vez do TargetPct genérico — pivot só é aceito se respeitar o modo com que o trade foi aberto.
- **Teto de exposição FUTURES** (commit `819599b`, 2026-07-30): `Test-CoinExposureCap` só olhava saldo SPOT — cego pra posições FUTURES. DOGEUSDT SHORT cresceu pra >$1000 de margem via re-entradas repetidas do scanner (cascade guard de 07-29 só limita 3 Add Position/6h e reseta, não é teto absoluto). Agora soma margem FUTURES real ao cálculo do cap.
- **Guard crítico do Evolution Engine corrigido** (commit `819599b`): `lib_evolution_autonomous_rebalance.ps1` tinha um guard "só roda se chamado direto" que nunca funcionou (comparação sempre `$true` mesmo dot-sourced) — disparava rebalance real e reescrevia `config.local.ps1` a cada dot-source. Sem impacto em produção real (nenhum script do pipeline carrega essa lib), mas gerou ~190 backups locais silenciosos desde 07-08.
- **Tracking de custo de LLM migrado pra Supabase** (commit `819599b`): `Track-ClaudeUsage` existia pronto mas gravava em CSV local (perdido a cada run do GitHub Actions) e nunca era carregada na cadeia real de produção (incluindo dentro dos `Start-Job` dos drones do Mesa, que não herdam funções do processo pai). Agora persiste em `manuheadfund.llm_usage`, com relatório real conectado ao digest diário do Telegram.
- **Calibragem SHORT recalibrada** (commit `320950d`, 2026-07-25): pesquisa em `mce_counterfactual_agg` + `knowledge/WYCKOFF_SMC.md` + `knowledge/MANIPULATION.md` achou 3 gaps reais — (1) `Get-ShortThresholdsForRegime` sem case `NEUTRO` (caía no default conservador apesar de NEUTRO|SHORT ter hit_rate=87.5% n=24, o melhor edge medido); (2) nenhum guard de funding rate no fluxo SHORT apesar do risco de short squeeze documentado (`Test-ShortFundingSafe` novo, bloqueia funding < -0.05%/8h); (3) WSS (tier S/A/B) reaproveitava cru a curva `_WSS-ScoreDdZone` calibrada pro LONG/Spring, empurrando Tier S pro regime historicamente PIOR pra SHORT — novo param `-Side` inverte a curva pro SHORT (zero regressão no LONG). `short_scanner.ps1` já executa ordem real (`live_enabled=true` desde 07-09, 15 mercados em `tier_a_live`) — comentários "observatory only"/"PAPER ONLY" desatualizados corrigidos.
- **LIVE TRADING**: `Trading Pipeline Complete` roda 24/7 no GitHub Actions (cron `*/5 * * * *`), 100% verde nas últimas ~100 runs
- **CI Verify**: 100% verde (era 24h+ quebrado até 2026-07-20 — parse-fail em 31 arquivos, causa raiz BOM UTF-8 ausente; ver histórico de commits `5e735ee`..`6d4ba41`)
- **Audit amplo 2026-07-20/22**: ~15 bugs reais corrigidos em produção (não só testes) — trailing stop sem `lib_candle_fetcher`, `Set-StateRecord`→`Save-StateRecords`, `Get-FqsQualityOrDefault` ignorando Hashtable, dashboard com schema `pnl_realized` vs `pnl_usd`, path travado no dot-source em `lib_override_expiry`/`lib_trade_journal_supabase`, 15 params `-BeLessThanOrEqual`/`-BeGreaterThanOrEqual` inválidos em testes (nunca existiram no Pester)
- **`lib_entry_direction.ps1` conectada** (commit `c9000c5`, 2026-07-22): `Resolve-EntryDirection` existia desde 06-24 com 7/7 testes mas nunca era carregada por `gem_executor.ps1` — fallback conservador sempre dava SKIP em gaps de conviction <20 pontos. Simulado e validado: mais entradas capturadas em gaps moderados (4-15 pontos), sem abrir mão do piso de conviction (45) nem da trava de cenário (agora usa `$btcScenario.allow_long/allow_short` real, corrigido de hardcode `$true/$true`)
- **Suite de testes**: Pester 3.4.0 (motor real de produção/CI) + Pester 5.9.0 instalados; ambiente tem os dois porque parte da suite foi escrita em sintaxe Pester 5 nunca antes validada
- **Mentor LLMs**: Sonnet/Haiku/Groq/Mistral
- **Bloqueios conhecidos**: `sync_and_fix_tp.ps1` removido (cleanup 2026-07-09), 2 libs órfãs vazias intencionalmente (`lib_mentor_rebalancer.ps1`, `lib_realtime_position_analyzer.ps1`)

---

## Regras de Ouro

1. Stop loss antes de qualquer entrada
2. Risco máximo por trade: 3% do capital (evoluído de 1% em 2026-07-22 — decisão explícita do owner, ver commit `gem_executor.ps1` da data; MaxConcurrentTrades também subiu de 5 para 10)
3. R:R mínimo 1:5
4. Confluência obrigatória: mínimo 3 fatores
5. Fail-closed em gates: erro = BLOCK, nunca passa por default
6. Asymmetric demote: 3 dias FLAG consecutivos = auto-fired
7. BTC-core: altcoin precisa bater BTC após fees pra justificar exposição
8. Nunca criar .md ou .ps1 desnecessários — manter projeto enxuto

---

## Base de Conhecimento (knowledge/)

`TECHNICAL_ANALYSIS`, `WYCKOFF_SMC`, `GEM_COINS`, `PUMP_FINGERPRINTS`, `MICRO_LIQUIDITY`,
`NARRATIVE_CATALYSTS`, `SCALP_DAYTRADING`, `ONCHAIN_ANALYSIS`, `MARKET_CYCLES`,
`RISK_MANAGEMENT`, `INDICATORS_REFERENCE`, `MACRO_CONTEXT`, `BEAR_MARKET`,
`REFERENCES_LIBRARY`, `PATH_TO_1PCT`, `MENTOR`, `MENTOR_PROMPT`, `MANIPULATION`,
`TORI_TRADES`, `MELAO_SATURNO`, `SIMONS_RENTECH`, `COINEX_REFERENCE`, `LOPEZ_DE_PRADO`,
`PER_ASSET_OPTIMIZATION_PLAYBOOK`, `CRYPTO_ACADEMIC_FOUNDATIONS`, `CRYPTO_MARKET_MICROSTRUCTURE`

---

## Framework de Análise

```
1. MACRO → mercado global favorece crypto?
2. CICLO → fase Weinstein 1-4?
3. ON-CHAIN → whales acumulando ou distribuindo?
4. TENDÊNCIA → daily/weekly define direção
5. ESTRUTURA → suporte/resistência relevantes
6. ENTRADA → pullback, breakout ou reversão? Volume confirma?
7. RISCO → stop, alvo, tamanho calculados?
```
