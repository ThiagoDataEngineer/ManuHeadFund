# CLAUDE.md — ManuHeadFund

> Lido automaticamente em cada sessão. Manter ENXUTO.

---

## Projeto

**ManuHeadFund** — sistema multi-agente de trading em crypto (CoinEx Futures/Spot).
- Backend: PowerShell 5.1 + 60+ agent libs + Python backtest
- Exchange: CoinEx (principal), Binance (funding baseline)
- Telegram bot: approval gates, comandos `/scan /halt /resume /demote /keep /idea`
- Docs técnicos: `docs/ARCHITECTURE_TATICA.md`, `docs/STRATEGIC_ROADMAP.md`, `docs/AGENTS.md`

### Estado atual (2026-05-26)

- **Paper calibration ativa**: `journal/PAPER_CALIBRATION_MODE.flag` presente → SCORE_MINIMO=55, intervalo 30min
- **9 Mentor evolutions** entregues (A+B+C): phantom reconcile, reflection wire, time context, alpha history, 5-tier schema, multi-shot, calibration, self-consistency, unified prompts — ver `docs/mentor/EVOLUTIONS_2026_05_26.md`
- **DNS fix**: `CONSERTAR_DNS_LLM.ps1` resolve Cisco Umbrella bloqueando LLMs
- **4 daemons ativos**: gem_loop / scan_master / tg_listener / watchdog
- **Telegram V2**: `agents/lib_telegram_v2.ps1` criado — integração pendente nos 6 scripts principais

---

## Regras de Ouro

1. Stop loss antes de qualquer entrada
2. Risco máximo por trade: 1% do capital
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
