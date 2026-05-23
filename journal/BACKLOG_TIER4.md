# BACKLOG_TIER4.md -- Features avaliadas mas DIFERIDAS

> Created 2026-05-18 apos avaliacao rigorosa. Tier 4 = features com ROI
> potencial mas que VIOLAM principio "validar antes de implementar".
> NAO implementar agora -- reabrir apos Mode 2 LIVE micro validar 30d.

---

## Criterio de re-abertura

Cada item abaixo so pode ser implementado se:

1. Mode 2 LIVE micro completou 30+ dias
2. N trades real >= 15
3. Sharpe real annualized >= 1.5
4. Dados reais existem para validar a hipotese (nao soh teoria)

Se algum item passa criterio mas continua incerto: triple barrier + WF + PBO/CSCV antes de production.

---

## Item 1: Whale-follower trading (Nansen/Glassnode integration)

### Tese original (user)
- 100 wallets controlam 60% supply BTC
- Cluster 5+ smart money wallets acumulando 7d = sinal
- Boost etf_flow_factor em 1.2x
- Validacao historica n=3: 2022-11, 2024-03, 2024-10

### Por que diferido
- **Post-ETF pollution**: labels Glassnode/Nansen misturam organic acc com IBIT/FBTC cold storage
- "5+ wallets" e "1.2x boost" sao magic numbers sem backtest
- Free tier insuficiente; paid tier $$$
- Mesmo conceito ja coberto como info-only em `Get-WhaleAccumulationContext`

### Esforco real estimado
- 8-12h (scraping + paid integration + backtest formal + PBO)

### Pre-requisitos pra reabrir
- Definir cluster size + threshold via backtest, NAO heuristica
- Source data confiavel (paid tier Glassnode ou alternativa peer-reviewed)
- N >= 100 wallet movements historicos pra teste rigoroso

---

## Item 2: Asymmetric pyramid sizing (Soros-style)

### Tese original (user)
- Add to winners: +0.3% em +2R, +0.2% em +4R, +0.1% em +6R
- Close all em +7R target
- Promised: Sharpe 5 -> 6-7, expectancy +40-60%

### Por que diferido
- **Backtest atual e com 1% fixo + close 7R**. Pyramid e logica DIFERENTE
- "+40-60% expectancy" sem dado = especulacao
- Math citado tem erro: cada "add" e trade NOVO com stop NOVO = exposicao real > 1.1%
- Viola "validar antes de implementar" -- principio cardeal LdP

### Esforco real estimado
- 8-12h (modificar triple_barrier_simulator + WF + PBO + comparison report)

### Pre-requisitos pra reabrir
- 30d Mode 2 LIVE com >= 15 trades reais
- Hipotese formal: "trades vencedores em BULL_STRONG ultrapassam +7R em X% dos casos"
- Backtest dedicado validando Sharpe pyramid vs Sharpe fixo
- PBO < 0.30 sobre grid pyramid configs

---

## Item 3: Intraday seasonality formal (Versao C)

### Tese original (user)
- DoW ja validado (Mon +0.55%, Thu -0.16%)
- Extender pra 3 windows intraday (Asia/EU/US)
- Promised: Sharpe 5 -> 6-7

### Por que diferido
- **Sample collapse**: BTC daily Mon trades = ~190; particionado em 3 windows = ~63/window
- 63 trades INSUFICIENTE pra DSR rigoroso (precisa N >= 100)
- Multi-test inflation: 3 windows * 7 DoW * 8 markets = 168 testes = PBO explode
- DAILY edge demonstrado morreria se voltar a hourly (CRYPTO_MARKET_MICROSTRUCTURE §5.1)

### Esforco real estimado
- 6-8h (coleta hourly Bitstamp + intraday simulation + PBO sobre 12+ windows + WF)

### Pre-requisitos pra reabrir
- Coletar Bitstamp HOURLY BTC (>= 30k candles, gratis via paginacao)
- N >= 100 trades por window apos filtros
- Versao A info-only ja implementada -- coletar 60d dados antes de Versao C

### Versao A (info-only) JA IMPLEMENTADA
- `Get-IntradayWindowContext` mostra janela atual no painel macro
- Esta coletando dados implicitamente em cada cycle

---

## Item 4: Carry trade BTC (funding rate)

### Tese
- Long spot + short perpetual quando funding rate > 0.05%/8h
- Edge ESTRUTURAL (premio dos longs alavancados)
- Nao-direcional = nao compete com edge atual

### Por que diferido
- Conceito **mais robusto** que itens 1-3 (Robot Wealth, fundos institucionais fazem)
- Mas requer **novo stack**: position management dual (spot + futures), funding rate API, hedge logic
- Esforco maior, mas ROI maior tambem
- Atual prioridade = validar Mode 2 LIVE primeiro

### Esforco real estimado
- 10-15h (lib_carry_trade.ps1 + position_dual.ps1 + lib_funding_rate.ps1 + TDD)

### Pre-requisitos pra reabrir
- Mode 2 LIVE 30d validado
- Tier 3 expansion completada se ainda quiser ampliar Tier A
- Comparar ROI esperado vs continuar refinando direcional

---

## Item 9: GemAgent late pump penalty -- calibração formal

### Tese (2026-05-18, caso TRAC validou empiricamente)
- GemAgent é DETECTOR (não preditor) → detecta pumps DEPOIS de iniciados
- Caso TRACUSDT 18/05: detectou às 09:26 com pct_change +51.72%
- Pump real começou ~02-06h BRT, alertou com 70% do movimento já rodado
- Tori bloqueou tecnicamente ("range lateral + spike isolado sem trendline")
- Tier 4 fix Item 9 implementado heuristicamente:
  - pct > 60%: -25 score (very late/blow-off)
  - pct > 40%: -15 score (late stage)
  - pct > 25%: -5 score (mid-stage)

### Por que ainda precisa Tier 4 (calibração formal)
- Thresholds heuristicos (25/40/60%) sem backtest
- Penalty magnitudes (-5/-15/-25) também sem validação
- Mode 2 LIVE vai gerar dados pra refinar

### Pre-requisitos pra reabrir
- 30+ GEMs alertadas com pct_change registrado em journal
- Backtest:
  - Resultado real (win/loss) por bucket pct_change
  - Calibrar threshold ótimo (provavelmente entre 25-50%)
  - Validar penalty magnitude

### Esforço estimado
- 3-4h (coleta dados + análise + recalibração)

### Status atual
✅ Heurística aplicada (Item 9 quick fix)
🟡 Calibração formal aguardando 30+ samples reais

---

## Item 8: 4h cycle option (middle ground entre daily e hourly)

### Tese (2026-05-18, user feedback "ciclos longos")
- DAILY 1×/dia: edge validado (Sharpe 5.04 daily backtest) mas user sente "parado"
- HOURLY 24×/dia: edge ZERO comprovado (0/16 grid, microstructure noise)
- **4h cycle** = 6×/dia: middle ground não testado formalmente

### Pros
- 6× mais oportunidades que daily
- Ainda fora do território MM/HFT puro (que dominam minute-level)
- Custo LLM = 1/4 do hourly (~$2.5/mês vs $10)
- Mais ação = user mais engajado em paper trade learning

### Contras CRÍTICOS
- **Não validado** em backtest (Sharpe 4h desconhecido)
- Pode estar em zona cinza microstructure (MM ainda atua em 4h windows)
- Multi-test inflation: 4h × 7 dow × 8 markets = 224 testes, PBO penalty severa
- Stop hunts intra-day podem matar edge em momentum trades

### Implementação se reabrir
1. Coletar BTC 4h candles (Bitstamp ou CoinEx) 5+ anos
2. Rodar triple_barrier + walk_forward + PBO em grid 4×4
3. Comparar Sharpe 4h vs Sharpe 1d
4. Se Sharpe 4h > 0.8 × Sharpe 1d com PBO < 0.40: usar
5. Se < 0.8 × ou PBO > 0.40: ficar em daily

### Esforço estimado
- 4-6h (coleta + backtest formal + comparison)

### Pré-requisitos pra reabrir
- 30d Mode 2 LIVE micro completados (validar primeiro o que tem)
- User sentir falta concreta de mais ação (não só percepção)

### Workaround imediato (NÃO precisa de backtest)
- **GemAgent loop paralelo** já implementado 2026-05-18 (cycle 1h)
- Captura micro-cap pumps tempo-sensíveis
- User percebe mais ação sem mexer no edge daily core

---

## Item 7: ETF flow automation (Farside CF-bypass)

### Tese (2026-05-18)
- Farside Investors tem dados grátis HTML mas bloqueado por Cloudflare (HTTP 403 mesmo com browser UA)
- Alternativas grátis testadas: blockchain.info (whale ✅), CoinGlass (free tier exige registro)

### Opções avaliadas
1. **Farside scrape com Selenium/Playwright** — ~3h dev + browser headless dependency
2. **CoinGlass free API key** — registro grátis em coinglass.com, 30 req/min, suficiente pra 1×/dia
3. **TheBlock data** — CF-blocked também
4. **SoSoValue** — endpoint não-documentado, frágil
5. **Pagar tier ETF.com / CME** — ~$30-100/mês

### Por que diferido
- Painel macro funciona sem ETF (5 outros sinais ativos)
- ETF é confirmação de tendência, não trigger principal
- Trade-off: 3h dev vs 1min consulta manual semanalmente

### Pre-requisitos pra reabrir
- Mode 2 LIVE precisar de ETF como filter formal (provavelmente nunca)
- OU encontrar source público estável (improvável)

### Esforço estimado se reabrir
- 1-3h dependendo da source (CoinGlass registro = 1h, Selenium = 3h)

---

## Item 6: Refresh dinâmico custodial cap (TOTAL_CAPITAL)

### Tese (2026-05-18)
- Hoje: `$global:TOTAL_CAPITAL_USD = 202580` hardcoded em `agents/config.local.ps1`
- Custodial ratio = `CoinExLive / 202580` -- denominador estático
- Quando CoinEx ganha/perde P&L OU user move capital cold→exchange:
  - Numerator atualiza (CoinExLive)
  - Denominator NÃO atualiza
  - Ratio subestimado/superestimado, guard fica errado

### Fix proposto
```powershell
# config.local.ps1 — split capital "fora" (raro mudar) vs "live" (dinâmico)
$global:CAPITAL_OFF_EXCHANGE = 200000.0   # hardcoded, atualizar manual quando mover

# Get-AllocationContext / Test-CustodialCap:
$coinexLive = CoinEx-GetTotalCapitalUSDT
$total = $CAPITAL_OFF_EXCHANGE + $coinexLive
$ratio = $coinexLive / $total
```

### Por que diferido (não crítico hoje)
- Atual ratio 1.27% -- folga absurda (até 30% cap)
- Discrepância matemática ~0.001% por trade -- irrelevante
- Pra preocupar: precisaria mover capital ou >$5k P&L na CoinEx

### Esforço real estimado
- 30min implementação + TDD + restart

### Pre-requisitos pra reabrir
- Você mover capital pra CoinEx (>= $5k) OU
- P&L acumulado CoinEx > $1k OU
- Quiser auditoria precisa de allocation

---

## Item 5: Meta-labeling (LdP cap 3) -- M2 P(win) filter

### Tese
- M1 = whitelist atual (binario: trade ou nao)
- M2 = LightGBM com features: halving_phase, etf_flow, mining_ratio, intraday_window, regime, sharpe_pred
- Output M2 = P(win) -> filtra trades M1 com low confidence

### Por que diferido
- **REQUER dados reais** -- M2 nao pode treinar em backtest se features nao foram registradas
- Mode 2 LIVE = unico source de dados real onde features estao gravadas
- Apos 6m+ Mode 2 com 60+ trades, M2 viavel

### Esforco real estimado
- 4-6h (apenas a parte ML; coleta de dados e via Mode 2 organic)

### ROI esperado
- LdP claim historico: M2 melhora Sharpe 20-40% via filtering trades baixa confianca
- Mais defensavel cientificamente que itens 1-3

### Pre-requisitos pra reabrir
- 60+ trades reais com features completas registradas em journal
- Dataset balanced (>= 20 wins + >= 20 losses)
- M1 baseline performance estabelecido empiricamente

---

## Resumo: ordem ideal de reabertura

```
HOJE / qualquer momento (low effort, low risk):
   Item 6 (Refresh dinamico capital) -- 30min, faz quando mover capital ou >$1k P&L
   |
   v
30d Mode 2 LIVE micro VALIDADO
   |
   v
Item 5 (Meta-labeling) -- ROI mais alto + base ML
   |
   v
Item 4 (Carry trade) -- edge estrutural complementar
   |
   v
Item 2 (Pyramid sizing) -- otimizacao do M1 atual
   |
   v
Item 3 (Intraday formal) -- refino marginal
   |
   v
Item 1 (Whale-follower) -- ROI incerto, postpone indefinidamente
```

---

## Por que rigor importa

Cada item destes representa 6-15h de trabalho. Adicionar sem validacao = stack inflado.

Sistema atual (2026-05-18):
- 174+28=202 TDD GREEN (SHORT refino +28)
- 5 sinais macro
- 4 LIVE guards
- Daily cycle + autostart
- Tier 3 whitelist
- Mode 2 LIVE PREPARADO

**Falta apenas: ATIVAR + COLETAR dados.**

Nao adicionar mais features ate que dados validem hipoteses.

---

## Item 10: SHORT BTC meta-labeling (LdP cap 3)

### Tese
- Refino SHORT 4-rules em 2026-05-18 FALSIFICOU 0/4 strict gate (Bitstamp 14.7y)
- rule_a SMA200 break MARGINAL (Sharpe 0.92 / DSR 0.26 / WF ROBUST 3/5 OOS+1.25)
- Hipotese: meta-labeling de 2 etapas (rule_a fires -> ML decide if take) podria salvar edge
- Combinar com features on-chain (NUPL, exchange netflow) -- nao free-tier

### Por que diferido
- Custo dados on-chain pagos (~$200/mes Glassnode/CryptoQuant)
- Sem PnL real LONG-only validado, adicionar SHORT layer eh estack premature
- Rule_a marginalmente positiva sozinha: ganho meta-labeling provavelmente modesto

### Criterio reabertura
- LONG-only Mode 2 LIVE completou 60+ dias com Sharpe real >= 1.5
- Dataset on-chain disponivel (paid ou via parceria)
- Backtest 2nd-stage meta-labeling em rule_a entries (precision-recall ROC)
- Custo opex on-chain coberto por PnL LONG-only

### Ref impl ja existe
- `backtest/short_features.py` (12 TDD GREEN)
- `backtest/short_rules.py` (16 TDD GREEN)
- `backtest/run_short_btc_refined.py`
- Reutilizar como input pra meta-label model

---

## Item 11: Living Whitelist — universo dinamico semanal

### Tese (proposta user 2026-05-18)
- Whitelist atual eh foto estatica 2026-05-17: HYPE/TON/novos listings invisiveis
- Markets podem ganhar/perder edge ao longo do tempo
- Renaissance/Two Sigma: universo dinamico com auto-discovery semanal
- Implementacao "Lite" sinaliza propostas via Telegram, user decide promote/demote
- NAO auto-promove Tier A (anti-blow-up)
- DSR global cumulative counter ajusta gate ao longo do tempo (Bailey-LdP rigor)

### Funcionamento desenhado
```
1x POR SEMANA (cron domingo 03:00 BRT):
  - Fetch top 30 markets CoinEx por volume
  - Run cross_asset_matrix com criterios CONGELADOS
  - Diff vs whitelist_v3 anterior:
    NEW_QUALIFIES -> Telegram alerta "promote Tier B?"
    LOST_EDGE      -> Telegram alerta "demote?"
    STABLE         -> silencio
  - Append journal/whitelist_history_<DATE>.json (audit trail)
  - Atualiza journal/dsr_global_registry.json (multi-testing counter)

USER:
  decide Telegram approve/reject/wait
  cooldown 30d antes de Tier A sair de LIVE
  Tier B precisa 4 semanas consecutivas falhando para demote
```

### Por que diferido
- Sistema atualmente 0 trades reais; adicionar auto-discovery sem ter validado um trade do existente = aumentar superficie sem cobertura
- Multi-testing risk: testar 30 markets/sem -> 1560 trials/ano -> gate efetivo Sharpe 3.2+
- Survivorship bias (delisted markets somem)
- Implementacao serio: 6h dev + 30 TDD
- Operacional: precisa cron Windows + diff engine + cumulative DSR tracker

### Criterio reabertura
- 30+ dias Mode 2 LIVE validados com 3-5 trades reais Sharpe annualized >= 1.5
- whitelist atual entregou edge real (nao soh papel)
- Dataset DSR global registry desenhado (formato journal/dsr_global.json)
- Telegram approve/reject flow ja implementado (atual eh trade approve, nao whitelist edit)

### Sub-items se reaberto
- Item 11a: weekly cron + scheduler Windows Task (1h, +5 TDD)
- Item 11b: dsr_global_registry tracking + gate adjustment (1h, +8 TDD)
- Item 11c: diff engine vs prev whitelist (1.5h, +6 TDD)
- Item 11d: Telegram propose/approve flow whitelist (1.5h, +6 TDD)
- Item 11e: demote logic + cooldown 30d (1h, +5 TDD)

### O que NAO fazer mesmo se reaberto
- Auto-promote Tier A (= confiar 100% em backtest = blow-up risk)
- Demote sem cooldown (= sair de posicao rentavel por ruido)
- Tune criterios em runtime (= overfit factory)
- Esquecer DSR cumulativo (= mentir pra si mesmo)

---

## Item 12: CoinEx news-driven listing tracker (Level 2)

### Tese (proposta user 2026-05-18 apos analisar artigo CLARITY Act)
- CoinEx publica feed de noticias com frequencia: 2-5 listings/mes, 1-2 delistings/mes
- Listings sao gatilho de movimentos significativos (pre-pump signal)
- Delistings sao risk-management critico (auto-demote do tier)
- Atualmente NAO consumimos esse feed -- 100% dependente do user ler manualmente

### Avaliacao do feed (filtro brutal, 80% e ruido)
| Tipo | Signal pra sistema |
|---|---|
| Listing announcement | ALTO - auto-cria DESCOBERTA candidate |
| Delisting warning | ALTO - auto-propoe Telegram demote |
| Fee schedule change | MEDIO - recalibra TB_FEE_TAKER_PCT |
| Maintenance/downtime | MEDIO - pausa cycle scan_master |
| Macro/regulatory commentary | BAIXO - opiniao promocional |
| Token spotlight | BAIXO - marketing disfarcado |

### Funcionamento desenhado
```
CoinEx feed RSS/API (verificar se tem endpoint estavel):
1x/dia (ou 6x/dia cycle scan):
  - Fetch latest articles
  - Filter por keywords (regex curado):
    "listing"|"sera listado"|"new pair"|"trading begins"
       -> auto-create DESCOBERTA entry na promotion ladder
    "delisting"|"removido"|"trading suspended"|"deprecated"
       -> auto-propose Telegram demote do tier atual
    "fee"|"taxa"|"comission"
       -> log + alerta user pra revisar TB_FEE_TAKER_PCT
    "maintenance"|"manutencao"|"upgrade"
       -> pausa scan_master proximo cycle (config flag temporaria)
  - Log journal/coinex_news.jsonl (audit + history)
  - Telegram alerta apenas tipos ALTO

USER:
  - Confirma DESCOBERTA via promotion ladder normal
  - Confirma demote via Telegram (mesmo flow do Item 11)
```

### Por que diferido
- Promotion ladder (Item 12 acima) precisa estar funcional primeiro -- esse e o consumer
- Sem ladder, "auto-create DESCOBERTA" nao tem destino
- 30+ dias Mode 2 LIVE com whitelist atual validada antes
- ~3h dev + 12 TDD

### Criterio reabertura
- Promotion ladder (Opcao 2) implementada e rodando
- 15+ dias com promotion_pipeline.jsonl populado
- API/RSS endpoint CoinEx mapeado (verificar autenticacao e rate limit)

### Sub-items se reaberto
- Item 12a: mapeamento endpoint CoinEx news feed (15min research)
- Item 12b: keyword filter + categorizador (1h, +5 TDD)
- Item 12c: integration com promotion_ladder (DESCOBERTA auto-create) (1h, +4 TDD)
- Item 12d: integration com demote flow (Item 11e) (30min, +3 TDD)
- Item 12e: docs + journal coinex_news.jsonl schema (15min)

### Habito manual interim (zero codigo, agora)
- User le feed 1x/semana CoinEx
- Cross-referencia com pipeline DESCOBERTA da ladder
- Anotacao em journal manual se identificar acionavel
- Custo 5min/semana
