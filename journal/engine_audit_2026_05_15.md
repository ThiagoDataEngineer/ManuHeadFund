# ENGINE AUDIT 2026-05-15

> READ-ONLY. Zero edits em codigo de producao.
> Auditoria externa do funil completo CoinEx -> Trade real.
> Trigger: 35+ ciclos em 24h, 100% Tier D, nenhum dos 13 cases reais (LONG +18-56% / SHORT -18 a -36%) gerou trade.
> Builds on top of: `diagnose_triagem_tier_d_2026_05_15.md` (EUREKA A/B), `diagnose_macro_bias_2026_05_15.md`,
> `diagnose_prescreen_block_2026_05_15.md`.

---

## 1. Funil de descarte (tabela cumulativa %)

Universo CoinEx (estimativa baseada no log "237 futuros + 1.000+ spot USDT" no header do scanner.ps1):

| # | Etapa | Codigo | Filtro | % UNIV restante | % cumulativo descartado |
|---|-------|--------|--------|----------------|------------------------|
| 0 | Universo bruto | CoinEx-GetAllFuturesTickers + Spot | ~1.250 pares USDT | 100% | 0% |
| 1 | Vol 24h >= $500k USDT | `scan_master.ps1::Get-ScannerCandidates:211` `if ($vol -lt $MinVolUsd) { return $null }` | ~250-350 (estim) | 25% | 75% |
| 2 | Score `|change|*log10(vol/1000)` -> Top 20 | `scan_master.ps1:215, 250` | 20 fixo | 1.6% | 98.4% |
| 3 | Filtra so FUTURES (spot descartado do orchestrator) | `scan_master.ps1:367` `Where-Object marketType -eq FUTURES` | ~12-18 | <1.5% | >98.5% |
| 4 | Pre-screen 4 gates (>=3/4) | `scan_master.ps1:402-409`: ADX>=18, RSI gate (28-78 OR 78-88+vol1.5x+adx25), EMA spread>=0.02%, vol>=0.5x | ~8-17 (log: 8-17) | ~1% | ~99% |
| 5 | Top-N composto (default 7) | `scan_master.ps1:430-435` Sort by compScore desc | 7 | 0.56% | 99.44% |
| 6 | Triagem -> tier != D | `triagem_agent.ps1:_Compute-Tier` | OBSERVADO: 0/7 | **0%** | **100%** |
| 7 | Whitelist (Wave 2) | `lib_operational_whitelist.ps1` | n/a (nunca chegou) | 0% | 100% |
| 8 | Mesa CAOS check | `orchestrator_v6.ps1:103` | n/a | 0% | 100% |
| 9 | Mentor APROVAR | `mentor_agent.ps1` | n/a | 0% | 100% |

**Onde estamos cegos:**
- Etapa 1 (vol>=$500k): pares com vol baixo NUNCA chegam ao radar. PNK/MRSOON/IDOL (micro-caps em queda forte) tem volume freq < $500k em 24h normal.
- Etapa 2 (Top-20 por |change|*log10(vol)): a formula favorece pares grandes em movimento medio sobre micro-caps em movimento extremo. DEGEN +55% mas vol $2M score = 55*log10(2000) = 55*3.3 = 181 vs HYPE +18% vol $11.7B score = 18*log10(1.17e7) = 18*7.07 = 127 -- DEGEN VENCE matematicamente, MAS so 1 spot no top-20 e descartado em (3) porque DEGEN nao tem futures listado (precisa confirmar).
- Etapa 3 (so FUTURES): SPOT-only pares (memes recem-listadas tipicas) sao monitorados mas NUNCA chegam ao orchestrator.
- Etapa 6 (Tier D): bloqueia em scanner.score < 50. Vide EUREKA do diagnose anterior -- `Get-QuickTechScore` clamp 65 e change_24h-driven; macro_bias=NEUTRAL constante (FRED 400, EUREKA do diagnose macro).

---

## 2. Drill-down 13 cases

**Importante:** ZERO dos 13 pares aparece em `logs/master_20260515.log`. Reconstrucao manual baseada em mecanica conhecida e historico do par no log de 14/05 (HYPE).

### LONG (3 cases)

| Etapa | HYPEUSDT +17.92% / $11.7B | DEGENUSDT +55.92% / micro-cap | PEAQUSDT +28.85% / mid DePIN |
|-------|---------------------------|-------------------------------|------------------------------|
| Existe CoinEx? | **SIM, FUTURES** (visto em master_20260514.log:349 "HYPEUSDT score 85" via GemScan) | **PROVAVEL SPOT-only** (meme micro-cap, futures listing duvidoso) | **SIM, FUTURES** (PEAQ tem listing dual) |
| Vol > $500k? | SIM (~$11.7B >>> $500k) | SIM (micro-cap pumpado tipicamente passa $500k 24h) | SIM (mid-cap DePIN com narrativa) |
| Apareceu top-20? | SIM (logo 18% change + vol enorme = score ~127) | SIM (55% * log10(2M/1k) ~180 -- score MAIOR que HYPE) | SIM (~28*log10(50M/1k) ~118) |
| Passou pre-screen? | RSI 80 (caso classico Bug A), com vol 4.46x + ADX 29 -> agora passa (KB-fix) | Provavel: RSI > 88 (overbought extremo) -> **REJEITA na faixa >88** | Provavel passa (28% suave, RSI 65-75) |
| Foi top-7? | SIM (compScore alto -- mom 18 vol alto ADX 29) | Filtrado em FUTURES gate se for spot-only | SIM |
| Tier? | **D** (scanner.score < 50 porque GetQuickTechScore acoplado a change > +3% so chega a 65) | Nunca chegou aqui (futures gate ou RSI>88) | **D** (mesmo) |
| Whitelist V2? | Nunca chegou (Tier D aborta antes) | n/a | n/a |
| Mesa rodou? Mentor? | NAO | NAO | NAO |
| Decisao final | **ABORTAR** (tier D) | **ABORTAR** (futures gate OU RSI 88) | **ABORTAR** (tier D) |
| Causa | **DESIGN (Tier D ceiling) + CALIBRACAO (clamp 65, macro NEUTRAL)** | **DESIGN (futures-only) OR CALIBRACAO (RSI>88 rejeita pumps)** | **DESIGN + CALIBRACAO** mesmo de HYPE |

**Detalhe HYPE:** o `GemScan` separado DETECTOU HYPE 14/05 com score 85-95 (4x em ~3h). MAS:
- 18:34 BRT: GEM execucao falhou: "PlaceOrder error: Invalid Parameter" (linha 350) -- **BUG**: ordem rejeitada por param invalido na CoinEx (provavelmente lot size, ticker format, ou precisao decimal).
- 19:13 BRT: usuario rejeitou via Telegram (timeout ou cancel manual).
- 20:34 BRT: novo Invalid Parameter de novo (linha 430).

Ou seja: **HYPE foi detectado, MAS execucao quebrou 2x em sequencia por bug de param e usuario perdeu confianca.**

### SHORT (10 cases)

Todos sao alts pequenas/micro com queda extrema 18-36%. Predicao confiante:

| Par | -change% | Existe? | Vol>$500k? | Top-20? | Pre-screen? | Tier? | Whitelist? | Final | Causa |
|-----|---------|---------|-----------|---------|-------------|-------|------------|-------|-------|
| PNKUSDT | -36.55% | provavel SPOT-only | provavel SIM (queda pumpada) | SIM (36*log10(vol)) | RSI<28 **REJEITA** | n/a | n/a | NUNCA AVALIADO | **DESIGN: pre-screen RSI<28 rejeita oversold** |
| AINUSDT | -30.19% | duvidoso | depende | talvez | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | mesmo |
| MODEUSDT | -30.00% | SIM FUT | provavel | SIM | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | mesmo |
| BTRSTUSDT | -23.33% | provavel SPOT | duvidoso | talvez | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | mesmo |
| ZEREBROUSDT | -23.28% | SIM | SIM (queda ATR alto) | SIM | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | mesmo |
| DONKEYUSDT | -21.67% | provavel SPOT | duvidoso | talvez | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | mesmo |
| RTMUSDT | -19.85% | SPOT-only provavel | duvidoso | talvez | n/a | n/a | n/a | NUNCA AVALIADO | DESIGN futures-only + RSI<28 |
| MRSOONUSDT | -19.19% | SPOT-only | duvidoso | talvez | n/a | n/a | n/a | NUNCA AVALIADO | mesmo |
| IDOLUSDT | -19.13% | SPOT | duvidoso | talvez | n/a | n/a | n/a | NUNCA AVALIADO | mesmo |
| MITOUSDT | -18.37% | SIM FUT | SIM | SIM | RSI<28 reject | n/a | n/a | NUNCA AVALIADO | **DESIGN: pre-screen RSI<28** |

**EUREKA SHORT (HIGH): o pipeline SHORT nao existe efetivamente.** Tres barreiras compostas tornam SHORT matematicamente impossivel hoje:

1. **Pre-screen RSI < 28 rejeita** (scan_master.ps1:116). Queda 18-36% em 24h gera RSI 15-25 invariavelmente -> bloqueio absoluto antes de qualquer score.
2. **`Get-QuickTechScore` change<-3% -> score=35** (clamp 65). Score 35 < 50 -> Tier D automatico.
3. **Whitelist `(*, SHORT, *)` -> observe em paper / skip em live** (lib_operational_whitelist.ps1:101). Mesmo se um SHORT chegasse a virar `direction=SHORT` na triagem, modo live abortaria.

**Adicional: `_Compute-DirectionFromRegime` so produz SHORT em BEAR_*/CAPITULATION/TRANSITION_DOWN.** Como `macro_bias` esta travado em NEUTRAL (FRED 400 bug), regime cai em SIDEWAYS/TRANSITION_*, nunca em BEAR_*. Direction = LONG sempre.

### Resumo causal por classe

| Classe de drop | LONG (3) | SHORT (10) | Causa-raiz |
|----------------|----------|-----------|------------|
| BUG | 1 (HYPE PlaceOrder Invalid Parameter) | 0 | execucao quebrada do GemAgent na CoinEx |
| CALIBRACAO | 2 (HYPE/PEAQ Tier D ceiling) | 0 | Get-QuickTechScore clamp 65, threshold Tier D=50 |
| DESIGN | 0 (DEGEN futures gate -- design pelo risco) | 10 (todos) | (a) Pre-screen RSI<28, (b) whitelist SHORT skip, (c) regime SHORT depende de BEAR_* que macro-bug previne, (d) futures-only |
| MERCADO | 0 | 0 | nenhum |

---

## 3. Gabarito MOEDA_TRADAVEL (draft)

Baseado nos 13 cases reais, checklist proposto. Valores derivados de:
- HYPE $11.7B = upper bound trade-quality
- DEGEN micro-cap $20-200M = lower bound aceitavel
- PEAQ $100-500M = sweet spot mid-cap narrativa

```
PRE-SCANNER (idealmente NOVA etapa antes do top-20):

[ ] Marketcap minimo:                 $5M USD     (filtra fraudes/test tokens)
[ ] Marketcap maximo opcional:        $50B USD    (corta BTC/ETH/USDT/stables -- ja temos)
[ ] Idade minima desde listagem:      14 dias     (filtra rugpulls semana 1; HYPE/PEAQ passariam)
[ ] Volume 24h medio rolling 7d:      >= $1M USD  (filtra liquidez ilusoria)
[ ] Spread bid-ask:                   < 0.5%      (executabilidade real)
[ ] Tem narrativa? (tag CoinGecko/manual): DePIN, AI, Meme-trending, L2, RWA -- opt-in priority booster (nao gate)
[ ] PUMP_FINGERPRINTS check:          < 70 score wash-trading (anti-fraude)
[ ] Whales acumulando? (on-chain):    bonus, nao gate (free tier nao tem on-chain)
[ ] Listado em CoinEx FUTURES?        gate-rigido se trade SHORT (futures only)
                                       opt-in se LONG via spot path (atualmente fechado)

POS-SCANNER (ja existe parcialmente):

[ ] ADX >= 18:                        OK (existe)
[ ] EMA9/EMA21 spread >= 0.02%:       OK (existe)
[ ] Vol ratio >= 0.5x:                OK (existe)
[ ] RSI gate ADAPTATIVO POR DIRECTION (NOVO):
      LONG:    28 <= RSI <= 78  OR  (78-88 + vol 1.5x + ADX 25)   -- ja existe
      SHORT:   12 <= RSI <= 72  OR  (12-22 + vol 1.5x + ADX 25)   -- AUSENTE HOJE
      (mirror do gate LONG para o lado short)
```

**Onde encaixar:**
- **PRE-scanner** (entre vol>=$500k e top-20): mcap, idade, spread. Custo: 1 chamada CoinGecko por par (~250-350 pares). Latencia 30-60s extra. **Beneficio: elimina spam tokens.**
- **POS-scanner**: ajuste RSI gate por direction. Custo zero (so logica). **Beneficio CRITICO: destrava SHORT pipeline.**

### Valores SUGERIDOS (revisitaveis)

| Metric | Conservador | Moderado | Agressivo | Justificativa |
|--------|-------------|----------|-----------|---------------|
| Mcap min | $50M | $10M | $5M | 13 cases todos passam em $5M |
| Vol 24h | $5M | $1M | $500k (atual) | atual e baixo demais; permite micro-caps frageis |
| Idade min | 30d | 14d | 7d | rugpulls concentrados <7d |
| Spread max | 0.3% | 0.5% | 1.0% | spread > 1% drena edge em scalp |

---

## 4. Benchmarking conceitual

**Caso HYPE +17.92% (24h, +37% em 2 dias):**

| Ferramenta | O que teria mostrado | Nosso gap |
|-----------|---------------------|----------|
| CoinGecko Trending | TOP-3 trending crypto-wide; tag DePIN/Infra; mcap rank visivel | nos detectamos via GemScan score 95 mas execucao quebrou (Invalid Parameter); nao temos UI para reagir manualmente |
| CoinMarketCap Hot/Gainers | TOP-5 24h gainers $1B+; chart 7d up only; volume +400% | scanner top-20 viu, pre-screen passou (RSI 80 com vol/ADX OK pos-Bug-A fix), MAS Triagem em Tier D porque macro=NEUTRAL (bug FRED) e Get-QuickTechScore clamp 65 |
| DEX Screener | HYPE em DEX (Hyperliquid native) com $11B vol; LP locked; holders +20% week | nao olhamos DEX -- HYPE eh principalmente nativo do Hyperliquid; CoinEx CEX volume eh derivado |
| Whale Alert / on-chain | acumulacao on-chain (gratuita); netflow exchange -> wallets | ChainAgent atual e mock (lib_cycle_mocks.ps1); on-chain real desabilitado free-tier |

**Gap estrutural:**
1. **Macro context quebrado** (FRED API 400) trava regime em NEUTRAL/SIDEWAYS -> Triagem nunca emite tier alto e SHORT direction nunca dispara.
2. **Get-QuickTechScore clamp 65** torna Tier A matematicamente impossivel (precisa >=75).
3. **Whitelist V2 muito agressiva no live** (so BULL_STRONG+LONG OU TRANSITION_UP+LONG+Monday) -- combinada com macro=NEUTRAL = 0 trades possiveis em live.
4. **Pipeline SHORT inexistente:** 4 barreiras independentes bloqueiam.
5. **GemAgent execucao quebrada na CoinEx** (PlaceOrder Invalid Parameter) -- caminho LONG micro-cap funcional ate o gate de ordem.

---

## 5. CONCLUSOES

### Top 3 gaps reais

1. **Macro context constante NEUTRAL (FRED 400, key ausente).** Esse e o **bug raiz** que cascateia em tudo. Sem BULLISH/BEARISH, nunca temos BULL_STRONG/BEAR_STRONG -> whitelist V2 live nunca executa, SHORT direction nunca emerge. **HIGH severity. Fix: 2min (registrar FRED key gratuita).** Vide `diagnose_macro_bias_2026_05_15.md` opcao A.

2. **Get-QuickTechScore clamp 65 + threshold Tier D=50 acoplado a change_24h.** Tier A inalcancavel; Tier B exige change > +3%. Em janela morna -> 100% Tier D garantido por mecanica. **MEDIUM severity. Fix: override OPT-IN ja existe (`$global:SCANNER_SCORE_CLAMP_OVERRIDE=100` em config.local.ps1).** Pode-se validar destravando para 100 + recalibrando Get-QuickTechScore com vol/ADX/EMA spread.

3. **Pipeline SHORT inexistente.** 4 barreiras compostas (pre-screen RSI<28, score<50 em change<-3%, regime SHORT exige BEAR_* que macro-bug previne, whitelist (*,SHORT,*) skip live). Mercado teve 10 quedas 18-36% nas ultimas 24h: 0 avaliacoes. **HIGH severity para edge SHORT em correcoes.** Fix: estrutural -- requer (a) consertar macro, (b) RSI gate mirror para SHORT, (c) revisitar whitelist SHORT design.

### Top 3 propostas priorizadas

| # | Proposta | Esforco | Retorno | Risco |
|---|----------|---------|---------|-------|
| 1 | Registrar FRED API key + adicionar &api_key= em lib_macro.ps1 | 15 min | **ALTISSIMO** (destrava 3 cascades cegas) | BAIXO (so muda fallback fake -> dado real) |
| 2 | Setar `$global:SCANNER_SCORE_CLAMP_OVERRIDE=100` em config.local.ps1 e observar 48h | 1 min | ALTO (destrava Tier B/C/A em janelas moderadas) | BAIXO (so destrava topo do score) |
| 3 | Recalibrar Get-QuickTechScore para usar vol+ADX+EMA spread alem de change_24h | 2-4h + testes | ALTO (score distribuido 0-100, nao 35-65) | MEDIO (mudanca de base critica -- precisa walkforward retroativo 30d minimo) |

**Bonus barato (1 hora):** consertar `PlaceOrder Invalid Parameter` no GemExecutor. HYPE/AI 14/05 mostraram que o GemPath DETECTA bem (score 95), mas a ordem CoinEx falha. Provavelmente lot size / decimal precision / market type mismatch. Ja temos 4 trades perdidos comprovados nesse caminho.

### O que NAO mudar (validado empiricamente)

- **Tier D ABORTA sem chamar Mesa/Mentor.** Economia de custo Claude correta. Manter.
- **Whitelist V2 paper observa SHORT.** Coleta amostra cega -- correto. Manter.
- **Pre-screen vol>=0.5x + EMA spread>=0.02% + ADX>=18.** Filtros corretos para LONG saudavel.
- **Bug A/B/C fixes (RSI trend-aware + composite score).** Ja resolvem casos HYPE-like.
- **Whitelist live BULL_STRONG+LONG.** Decisao arquitetural com 14y backtest -- nao destravar live sem nova validacao.

### Risco maior se nao agir

Em mercado lateral/correcao (50%+ do tempo), **engine roda 24/7 consumindo ciclos sem capacidade matematica de gerar trade.** Custo: API CoinEx pings + log ruido + falsa sensacao de "sistema funcionando". Pior: psicologia do operador erode quando ve 100% ABORTAR por dias -- ou:
- abandona o paper trade (perde validacao do go-live)
- baixa thresholds sem rigor (introduz vies long em mercado errado)
- assume FOMO em sinal manual (viola Regra de Ouro #6)

**Acao minima recomendada (este final de semana):** Fix 1 (FRED key) + Fix 2 (clamp 100). Esforco total: 20 min. Retorno: destrava 3 cascades simultaneas; teste empirico em janela 48h dira se Tier B/C aparecem.

---

## Anexos

- Engine: `scripts/scan_master.ps1`, `agents/scanner.ps1`, `agents/triagem_agent.ps1`, `agents/orchestrator_v6.ps1`, `agents/lib_operational_whitelist.ps1`
- Diagnoses anteriores: `journal/diagnose_triagem_tier_d_2026_05_15.md` (EUREKA A/B), `journal/diagnose_macro_bias_2026_05_15.md` (FRED bug root), `journal/diagnose_prescreen_block_2026_05_15.md`
- Logs: `logs/master_20260515.log` (37+ Tier D), `logs/master_20260514.log:349-430` (HYPE GemScan detected x4, 2x PlaceOrder Invalid Parameter)
