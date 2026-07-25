# CLAUDE.md — ManuHeadFund

> Lido automaticamente em cada sessão. Manter ENXUTO.

---

## Projeto

**ManuHeadFund** — sistema multi-agente de trading em crypto (CoinEx Futures/Spot).
- Backend: PowerShell 5.1 + 60+ agent libs + Python backtest
- Exchange: CoinEx (principal), Binance (funding baseline)
- Telegram bot: approval gates, comandos `/scan /halt /resume /demote /keep /idea`
- Docs técnicos: `docs/ARCHITECTURE_TATICA.md`, `docs/STRATEGIC_ROADMAP.md`, `docs/AGENTS.md`

### Estado atual (2026-07-25)

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
