# NARRATIVE_CATALYSTS.md — Como Narrativas Criam Pumps

> Narrativas são o combustível dos pumps em micro-caps.
> Sem narrativa = sem pump sustentado. Volume sem narrativa = whale dump disfarçado.
> Este documento cobre taxonomia, detecção, ciclo de vida e sinais de extinção.

---

## Por Que Narrativas Movem Micro-Caps

Em large-caps (BTC, ETH), o preço é movido por fluxo de capital institucional.
Em micro-caps, o preço é movido por **atenção humana** convertida em compra impulsiva.

```
Narrativa forte
    → atenção cresce
    → FOMO de novos compradores
    → volume aumenta
    → preço sobe
    → mais atenção (ciclo)
    → pump

Quando a atenção diminui:
    → sem novos compradores
    → holders vendem o lucro
    → preço cai
    → mais vendas
    → dump
```

**Consequência**: a velocidade de propagação da narrativa é tão importante quanto a narrativa em si.
Uma narrativa que viraliza em 48H > narrativa que leva 2 semanas para se propagar.

---

## Taxonomia de Narrativas por Potencial de Pump

### Tier 1 — Explosivo (potencial 50x–200x+)

**AI / Machine Learning**
- Keywords: AI, GPT, AGENT, NEURAL, BOT, AGI, LLM
- Catalisador: qualquer anúncio de IA big tech (OpenAI, Anthropic, Google)
- Velocidade: alta (Twitter nerd → mainstream em 24H)
- Ciclo médio: 2-4 semanas
- Exemplo: SKYAIUSDT +441% em ~20 dias

**Memes com referência cultural imediata**
- Keywords: DOGE, SHIB, PEPE, GHIBLI, CAT, TRUMP, ELON, BASED, WIF, BONK
- Catalisador: momento viral (tweet de celebridade, meme viral no TikTok/Reddit)
- Velocidade: máxima (pode pumpar em horas)
- Ciclo médio: 3-14 dias (muito mais curto que AI)
- Risco: dump mais abrupto (emoção resfria rápido)

**Novo paradigma tech**
- Keywords: ZK, L2, RESTAKE, MODULAR, INTENT, DEPIN, DESCI, RWATOKEN
- Catalisador: paper de pesquisa, protocol launch, parceria com chain principal
- Velocidade: média (nicho técnico antes de mainstream)
- Ciclo médio: 4-8 semanas

### Tier 2 — Moderado (potencial 5x–50x)

**DeFi com utilidade real percebida**
- Keywords: YIELD, FARM, STAKE, VAULT, PROTOCOL, DEX, AMM
- Ciclo médio: 2-6 semanas, menos explosivo, mais sustentável

**GameFi / NFT**
- Keywords: GAME, PLAY, NFT, META, PIXEL, PIXEL
- Catalisador: launch de jogo popular, collab com IP conhecida
- Sazonalidade: picos em Q4 (gastos de lazer aumentam)

**RWA (Real World Assets)**
- Keywords: GOLD, SILVER, REAL, ESTATE, BOND, TOKENIZED
- Ciclo mais longo, menos explosivo em micro-caps

### Tier 3 — Fraco (evitar no GemAgent)

**Exchange / token de utility genérico**
- Sem diferenciação narrativa clara
- Pump baseado apenas em listagem nova (sem story)
- Duração: 1-3 dias, dump rápido

**Copycats de narrativa velha**
- Quinta coin "AI" da semana
- Narrativa já saturada, últimos compradores entrando

---

## Ciclo de Vida de Uma Narrativa

```
FASE 0 — GERAÇÃO (dias -30 a -7 antes do pump)
  Insider/early adopters compram
  Sem coverage mainstream
  Volume baixo mas crescente
  GemAgent não detecta ainda (abaixo do threshold)

FASE 1 — EMERGÊNCIA (dias -7 a -2)
  Primeiros tweets de KOLs cripto
  CoinGecko trending começa a subir (rank 100-500)
  Volume spike inicial (1.5x–2.0x média)
  GemAgent começa a monitorar

FASE 2 — ACELERAÇÃO (dias -2 a 0)
  KOLs mainstream entram
  TikTok/YouTube começam a cobrir
  Volume spike forte (2.3x+ média) ← ENTRADA GemAgent
  Trending rank < 200

FASE 3 — PICO DE FOMO (dias 0 a +5)
  Mainstream entra (redes sociais genéricas)
  Volume no máximo
  Preço no máximo potencial ou próximo
  ← SAÍDA PARCIAL (50% da posição no +200% / +90%)

FASE 4 — DISTRIBUIÇÃO (dias +5 a +15)
  Whales e early buyers vendem
  Volume ainda alto mas preço para ou cai
  Narrativa repetida sem novidade
  ← TRAILING STOP 30% ativo

FASE 5 — EXTINÇÃO (dias +15 a +30)
  Sem nova narrativa para sustenter
  Volume colapsa
  Preço cai 60-90%
  ← VOLUME DEATH trigger ou stop
```

---

## Fontes de Detecção de Narrativa (por velocidade)

| Fonte | Latência | Custo | Implementado |
|-------|----------|-------|-------------|
| Twitter/X search (trending) | < 1H | API paga ou scraping | Futuro |
| CoinGecko trending top 7 | ~4H delay | Grátis | ✅ |
| CoinGecko rank < 500 | ~4H delay | Grátis | ✅ |
| Nome da coin (keyword match) | Imediato | Zero | ✅ |
| Telegram group monitoring | Minutos | Complexo | Futuro |
| Google Trends cripto | 24H delay | Grátis | Futuro |

### Keyword Match (implementado)

```powershell
$NARRATIVE_KEYWORDS_TIER1 = @(
    # AI
    "AI","GPT","AGENT","NEURAL","BOT","AGI","LLM","CHAT","CLAUDE","GROK",
    # Memes estabelecidos
    "DOGE","SHIB","PEPE","CAT","WIF","BONK","FLOKI","ELON","TRUMP",
    # Memes culturais
    "GHIBLI","PIXEL","WOJAK","CHAD","BASED","MEME","FROG","APE",
    # Tech emergente
    "ZK","L2","DEPIN","DESCI","RWA","INTENT","RESTAKE"
)

$NARRATIVE_KEYWORDS_TIER2 = @(
    "YIELD","FARM","STAKE","DEX","SWAP","GAME","PLAY","NFT","META",
    "GOLD","SILVER","REAL","BOND","VAULT","PROTOCOL"
)
```

### CoinGecko Trending (implementado via Get-CoinGeckoTrending)

```
Top 7 diário do CoinGecko = proxy de narrative momentum
Rank < 100: narrativa no pico (pode ser tarde para entrar)
Rank 100-300: narrativa acelerando (bom timing)
Rank 300-500: narrativa nascendo (melhor timing, mais risco)
Não listado: sem tração mainstream ainda
```

---

## Cross-Reference: Narrativa + Vol Spike + Mcap

O modelo de scoring do GemAgent combina:

```
Narrativa TIER 1 + Vol 2.3x+ + Mcap < $2M = DISCOVERY
  Score narrativa: +15 pts (peso máximo)
  Timing: fase 1-2 do ciclo narrativo
  Upside esperado: 50x–200x

Narrativa TIER 1 + Vol 2.3x+ + Mcap $2M–$20M = MOMENTUM
  Score narrativa: +15 pts
  Timing: fase 2-3 do ciclo (menos upside, mais confiança)
  Upside esperado: 20x–50x

Narrativa TIER 2 + Vol 2.3x+ + qualquer mcap = MOMENTUM reduzido
  Score narrativa: +8 pts
  Sizing: 50% do normal
  Upside esperado: 5x–20x

Sem narrativa + Vol spike = SKIP
  Score narrativa: 0 pts
  Se score total < 70: bloqueado pelo gate
  Exemplo: SDUSDT (vol 9.3x, sem narrativa → declining)
```

---

## Sinais de Extinção de Narrativa

Vender quando 3+ destes sinais aparecerem:

| Sinal | Significado |
|-------|-------------|
| CoinGecko trending rank piora por 2 dias | Atenção diminuindo |
| Volume do dia < 50% do pico de volume | Interesse esfriando |
| Novos tokens com mesma keyword lançam | Narrativa saturando |
| Evento catalisador foi precificado ("sell the news") | FOMO acabou |
| Preço faz novo máximo mas volume não confirma | Distribuição disfarçada |
| > 5 KOLs postando "ainda não é tarde" | Geralmente É tarde |
| Preço cai -30% em um dia sem notícia negativa | Whale saindo |

---

## Sazonalidade das Narrativas

```
Q1 (Jan-Mar): narrativas de "novo ciclo", resoluções, tech
Q2 (Abr-Jun): narrativas de halving aftermath, DeFi summer anticipation
Q3 (Jul-Set): GameFi, altseason, narrativas de verão
Q4 (Out-Dez): AI (Black Friday tech), gaming, "end of year rally"

Contexto atual (Maio 2026 = Q2):
  Pós-halving (25 meses) = distribuição macro
  Mas narrativas individuais ainda funcionam independentemente
  Foco: AI (mercado de AI tech aquecido) e memes resilientes
```

---

## Integração com os Outros Agentes

O GemAgent não opera em isolamento:

```
MentorAgent → bloqueia GemAgent se:
  - Sharpe do OrchestratorAgent backtest < 1.0
  - Max drawdown geral > 20%
  - Contexto macro extremamente negativo (BTC -40% em 30d)

OrchestratorAgent → pondera GemAgent:
  - Score GemAgent (0-100) tem peso no score final
  - Se score < 70: não gera alerta
  - Se score ≥ 70 + MentorAgent aprova: alerta com sizing

TechAgent → fornece contexto:
  - BTC no suporte major? (reduz risco de mercado geral)
  - Funding rate negativo? (bom para longs, incluso gems)
```

O GemAgent é **especializado e autônomo** para seu universo micro-cap, mas respeita os bloqueios dos agentes sênior para o contexto macro.
