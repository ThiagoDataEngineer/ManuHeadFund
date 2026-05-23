# GEM_COINS.md — Anatomia de Micro-Caps Explosivos

> Especialização: coins com mcap < $20M na CoinEx com potencial de 20x–200x+.
> Este conhecimento cobre o ciclo de vida completo, desde listagem até dump.

---

## Definição Operacional

**Gem** = par na CoinEx com:
- Market cap < $20M (preferencialmente < $2M para DISCOVERY)
- Volume spike > 2.3x a média dos últimos 3 dias
- Narrativa identificável (ou listagem nova < 10 dias)
- Liquidez suficiente para entrada/saída em < $500 (slippage aceitável)

Não é sobre "qualidade do projeto". É sobre **momentum de preço impulsionado por narrativa ou descoberta nova**.

---

## Dois Modos de Operação

### DISCOVERY — O Primeiro Spike (mcap < $2M)

```
Listagem nova (dia 0-10) → primeiros compradores → spike de vol
    Dia 1-2: descoberta, volume baixo, spreads largos
    Dia 3-5: JANELA DE ENTRADA — vol/avg_3d > 2.3x, mcap ainda < $2M
    Dia 6-10: awareness cresce, mcap pode 5-20x nesta janela
    Dia 15-30: distribuição se narrativa não sustenta
```

**Upside potencial**: 50x–200x do ponto de entrada no spike
**Risco**: coin pode zerar se narrativa morrer (aceitar perda total)
**Sizing**: 0.20% do capital (risco assimétrico puro)

**Exemplo histórico**: SKYAIUSDT
- Listagem CoinEx → spike dia 4 com 4.2x vol ($0.16)
- Máximo em ~20 dias: $0.866 = **+441%**
- Quem entrou no spike dia 4 com $2 → saiu com $10.82

### MOMENTUM — Narrativa Confirmada (mcap $2M–$20M)

```
Coin já tem histórico na exchange → narrativa explode → segundo pump
    Semana 1: narrativa aparece (trending CoinGecko ou tweet viral)
    Semana 2: volume acumula, mcap cresce de $2M para $5M+
    Semana 3-4: pump principal se narrativa sustenta
    Semana 5+: distribuição, sell the news
```

**Upside potencial**: 20x–50x
**Risco**: narrativa pode morrer abruptamente (stop -30%)
**Sizing**: 0.40% do capital

---

## Ciclo de Vida Completo de um Gem

```
FASE 0 — INVISÍVEL
  Mcap < $500K, vol diário < $10K
  Nenhum scanner pega (ruído puro)
  Apenas insiders/whales acumulam silenciosamente

FASE 1 — PRIMEIRO SINAL (JANELA DE ENTRADA)
  Vol spike > 2.3x avg_3d
  Pct range > 15% no dia
  Mcap ainda < $2M
  ← GemAgent DISCOVERY entra aqui

FASE 2 — AWARENESS
  Aparece em trending CoinGecko (rank < 500)
  Traders de micro-cap descobrem
  Vol 5x–10x do normal
  Mcap $2M–$10M

FASE 3 — FOMO
  Twitter/Telegram explodem
  Mcap $10M–$100M
  Preço pode ser 10x–50x do spike inicial
  ← GemAgent MOMENTUM pode entrar aqui (mais seguro, menor upside)

FASE 4 — DISTRIBUIÇÃO
  Volume alto mas preço trava ou cai
  Grandes detentores vendem (bag size > $10K)
  Red candles com volume igual ou maior que green candles
  ← SAÍDA obrigatória ou trailing stop apertado

FASE 5 — DUMP
  Narrativa morreu
  Volume colapsa
  Preço cai 70-90% em dias
  Quem não saiu na fase 4 perde a maioria
```

---

## Padrões Históricos Validados (CoinEx)

### SKYAIUSDT — Gold Standard DISCOVERY
```
Spike dia 4: vol 4.2x avg_3d, preço $0.16, mcap ~$1.2M
Máximo dia ~24: $0.866
Resultado do entry no spike: +441%
Padrão: AI narrative + new listing + organic accumulation (vol crescente, wicks pequenos)
```

### ATRUSDT — MOMENTUM Confirmado
```
Spike: vol 2.4x, padrão ATR como narrativa DeFi
Máximo: +267% em ~15 dias
Padrão: segundo spike após consolidação de 5 dias
```

### GIGAUSDT — Meme + Listing
```
Spike: vol 3.1x, meme coin nova
Máximo: +216% em ~10 dias
Padrão: GIGA = referência cultural + coinex listing recente
```

### SDUSDT — Falso Positivo (Bloqueado Pelo Gate 4)
```
Spike: vol 9.3x (MAIOR do dia — passaria G1 e G2)
Sem narrativa identificável, sem trending, sem keyword
Resultado: declining após spike
GemAgent CORRETO em bloquear
```

### AIDOGEUSDT — Armadilha de Timing
```
Spike forte dia 1 → fade dias 2-7 → pump real dia 8
Quem entrou no primeiro spike: drawdown -60% antes do pump
Quem identificou o segundo spike: entrou melhor
Lição: micro-caps podem ter dois spikes, o segundo é mais confiável
```

---

## Métricas Alvo do GemAgent

| Métrica | Mínimo | Target |
|---------|--------|--------|
| R:R esperado | 1:20 | 1:200 |
| Win rate | >25% (R:R compensa) | >35% |
| Expectancy R | >3R/trade | >10R/trade |
| Trades/mês | 3–5 | 5–10 |
| Capital por trade | 0.20–0.40% | nunca > 0.5% |

**Por que win rate baixo é aceitável**: com R:R 1:50, precisamos acertar apenas 2% dos trades para não perder dinheiro. 25% de acerto com R:R médio de 30x = expectancy de +7.25R por trade.

---

## Sinais de Que NÃO É um Gem

| Sinal | Interpretação |
|-------|--------------|
| Volume alto mas preço flat | Wash trading — sem demanda real |
| Spike em par com mcap > $50M | Sem upside suficiente para o risco |
| Sem narrativa identificável | Pump de whale para dump em seguida |
| 3+ dumps de 20%+ na última semana | Distribuição em andamento |
| Exchange desconhecida promovendo | Possível rug pull |
| Listing nova mas token unlock iminente | Sell pressure estrutural |

---

## Regras de Saída (Invioláveis)

1. **Stop automático**: -50% para DISCOVERY, -30% para MOMENTUM
2. **Take profit parcial obrigatório**: 50% da posição ao atingir +200% (DISCOVERY) ou +90% (MOMENTUM)
3. **Moon bag**: 50% restante sem stop fixo, trailing de 30%
4. **Tempo máximo**: 30 dias para DISCOVERY, 21 dias para MOMENTUM — se não atingiu target, saída independente de P&L
5. **Volume death**: se vol diário cai abaixo de 30% do dia de entrada por 3 dias consecutivos → saída imediata

---

## Contexto de Ciclo (Maio 2026)

BTC dominância atual: ~58%. Não é altseason clássico.
Gems individuais ainda funcionam (catalisadores narrativos independem do ciclo macro).
Ajuste: priorizar DISCOVERY sobre MOMENTUM em dominância > 55%.
Quando dominância < 50% → ambos os modos com sizing pleno.
