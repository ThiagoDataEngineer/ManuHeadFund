# MICRO_LIQUIDITY.md — Operação em Mercados de Baixíssima Liquidez

> Operação em coins com vol diário < $500K na CoinEx.
> 97.5% dos 1.017 pares USDT da CoinEx estão neste universo.
> As regras aqui são diferentes das que se aplicam a BTC/ETH.

---

## O Problema Fundamental

Em um mercado com $50K de vol/dia, uma ordem de compra de $500 é **1% do volume diário**.
Isso não acontece em BTC. Aqui, você MOVE o preço com entradas pequenas.

```
BTC/USDT: vol $25B/dia
  → $500 de impacto = 0.000002% do vol → slippage ≈ 0.001%

GEMCOIN/USDT: vol $50K/dia
  → $500 de impacto = 1% do vol → slippage pode ser 2-5%
```

**Consequência direta**: nunca usar ordens a mercado. Sempre limit orders.
**Consequência 2**: sizing máximo calibrado pelo vol diário da coin, não pelo capital total.

---

## Regras de Sizing por Liquidez

```
Vol diário < $10K:   máximo $50 de entrada (0.5% do vol)
Vol diário $10K–50K: máximo $200 de entrada (0.4% do vol)
Vol diário $50K–500K: máximo $500 de entrada (0.1-1% do vol)
Vol diário > $500K:  saiu do universo gem — use regras normais
```

Para o GemAgent com capital de $1.000:
- Sizing padrão: $2–$4 (0.2–0.4% do capital)
- Impacto de mercado: negligível mesmo nos pares mais ilíquidos
- Saída fracionada pode ser necessária se vol cair pós-entrada

---

## Spread e Slippage Real

### Estrutura do Spread em Micro-Caps

```
ORDER BOOK TÍPICO de uma coin com vol $30K/dia:

ASK: $0.1050  (10,000 tokens)
ASK: $0.1045  (5,000 tokens)
ASK: $0.1040  (8,000 tokens)
ASK: $0.1035  (2,000 tokens)
─────────────────────────────
     SPREAD = 0.48%
─────────────────────────────
BID: $0.1035  (não existe — vazio)
BID: $0.1030  (3,000 tokens)
BID: $0.1025  (1,000 tokens)
BID: $0.1010  (20,000 tokens — wall de baixo)
```

**Spread médio esperado**: 0.3%–2.0% em micro-caps (vs 0.01% no BTC)
**Estratégia**: entrar no ask mais baixo disponível, nunca cruzar o spread inteiro

### Como Calcular Slippage Real

```
Entrada: $200 a mercado em coin com ask ladder acima

Quantidade alvo: $200 / $0.1035 = 1,932 tokens
Disponível no ask: 2,000 @ $0.1035
Slippage: zero (ordem encaixada completamente no melhor ask)

Entrada: $500 a mercado
Quantidade alvo: $500 / $0.1035 = 4,831 tokens
Disponível no ask:
  2,000 @ $0.1035 = $207
  5,000 @ $0.1040 = $297 (pega 2,831)
Preço médio: ($207 + $2,831 × $0.1040) / $500 = $0.1038
Slippage efetivo: 0.29%

Entrada: $1,000 a mercado (NUNCA fazer em micro-cap)
Varrer o ask até $0.1050 → slippage 1.4%
```

**Regra**: nunca varrer mais de 1 nível do ask/bid. Se a posição não cabe no primeiro nível, reduzir o sizing.

---

## Estratégias de Entrada em Alta Liquidez Momentânea

O paradoxo das micro-caps: o melhor momento de entrar (spike de vol) é quando a liquidez está momentaneamente ALTA. Usar isso.

```
Vol spike = janela de liquidez temporária
  → Order book mais cheio que o normal
  → Spreads menores durante o spike
  → MELHOR momento para entrada

Depois que o spike normaliza:
  → Order book volta a ser raso
  → Saída se torna cara
  → Por isso o timing de SAÍDA é mais crítico que a entrada
```

---

## Estratégias de Saída

### O Problema da Saída em Micro-Cap

Você comprou numa janela de alta liquidez. Agora o vol voltou ao normal.
Se tentar sair tudo de uma vez:
- Vai cruzar vários níveis do bid
- Vai mover o preço contra você
- Vai avisar o mercado que alguém está saindo (outros copiam e a queda acelera)

### Saída Fracionada (Obrigatória para DISCOVERY)

```
Posição: 10,000 tokens @ $0.16 = $1,600
Preço atual: $0.866 (meta atingida)

Vol diário atual: $80K
Limite de impacto: 0.5% do vol = $400 por ordem

Saída em 4 partes de $400:
  → $400 no bid atual
  → aguardar 15-30min para mercado absorver
  → $400 no bid restante
  → aguardar
  → etc.

Tempo total de saída: 1-2H
Slippage estimado vs saída única: -0.8% vs -3.5%
Diferença em $1,600: +$43 preservados
```

### Saída por Trailing Stop (Moon Bag)

Para os 50% que ficam como moon bag:
```
Trailing stop: 30% abaixo do máximo atingido
  Máximo até agora: $0.866
  Stop: $0.866 × (1 - 0.30) = $0.606

Novo máximo: $1.20
  Stop atualiza: $1.20 × 0.70 = $0.84

Coin cai de $1.20 para $0.84 → saída automática
Preservação de ganho vs pico: 70% do máximo garantido
```

### Volume Death — Saída de Emergência

Se vol diário cai abaixo de 30% do vol do dia de entrada por 3 dias:
```
Dia entrada: vol = $150K
Dia +5:      vol = $40K (27% do dia de entrada)
Dia +6:      vol = $35K (23%)
Dia +7:      vol = $30K (20%)
→ SAÍDA IMEDIATA independente de P&L
Motivo: liquidez insuficiente para saída ordenada se continuar
```

---

## Armadilhas Clássicas de Micro-Liquidez

### 1. Rug Pull vs Dump Orgânico

```
Rug pull (exit scam):
  - Candle de queda -50%+ em < 1 minuto
  - Volume explode durante a queda (todos vendendo)
  - Não há candles de recuperação
  - Developers venderam todos os tokens

Dump orgânico (whale saindo):
  - Queda em escadas (não vertical)
  - Volume alto na queda mas diminui
  - Normalmente há pullback parcial após o dump inicial
  - Recovery possível se narrativa ainda existe
```

**Resposta**: rug = saída imediata a qualquer preço. Dump = avaliar se é distribuição ou pullback.

### 2. Thin Order Book Trap

```
Situação: coin com bid wall artificial a $0.10 (parece suporte forte)
Realidade: wall desaparece quando você tenta vender (flash wall)

Como identificar:
  - Wall aparece apenas quando preço está caindo (não quando sobe)
  - Tamanho do wall = exatamente o volume que estava sendo vendido
  - Após qualquer compra significativa, wall se move para baixo
```

### 3. Pump and Dump Coordenado

Diferente de um gem orgânico:
- Anúncio em grupos do Telegram com call simultânea
- Volume explode em segundos (não minutos)
- Organizadores vendem na mesma hora que o call é feito
- Duração do pump: 2-10 minutos, não dias

**Detecção**: vol spike de 10x+ em < 5 minutos sem notícia associável = P&D.
GemAgent ignora picos de < 5 minutos de duração.

---

## Parâmetros de Risco Específicos para Micro-Liquidez

```powershell
# config.ps1 — parâmetros específicos do GemAgent

$GEM_CAPITAL_DISCOVERY  = 0.002  # 0.20% do capital por trade
$GEM_CAPITAL_MOMENTUM   = 0.004  # 0.40% do capital por trade
$GEM_STOP_DISCOVERY     = 0.50   # -50% (aceitar perda total em micro-cap)
$GEM_STOP_MOMENTUM      = 0.30   # -30%
$GEM_TARGET_PARTIAL     = 2.00   # +200% para saída parcial DISCOVERY
$GEM_TARGET_PARTIAL_MOM = 0.90   # +90% para saída parcial MOMENTUM
$GEM_TRAILING_PCT       = 0.30   # trailing stop 30% abaixo do máximo
$GEM_MAX_DAYS           = 30     # dias máximos na posição
$GEM_VOL_DEATH_PCT      = 0.30   # saída se vol cai < 30% do vol de entrada
$GEM_MAX_IMPACT_VOL     = 0.005  # tamanho máximo = 0.5% do vol diário
```

---

## Fee Real na CoinEx para Micro-Caps

CoinEx: 0.1% por lado = 0.2% roundtrip (com desconto VIP: até 0.05%)
Slippage estimado em micro-cap: 0.3%–1.5% por lado dependendo do tamanho

```
Custo total real de um roundtrip em micro-cap:
  Fees: 0.20%
  Slippage entrada: ~0.5%
  Slippage saída (fracionada): ~0.3%
  Total: ~1.0%

Para um trade de $4 (0.4% de $1.000):
  Custo total: $0.04
  Irrelevante dado o upside de 20-200x
```

Para micro-caps com sizing pequeno, fees e slippage são irrelevantes frente ao upside.
O risco real é a perda total do sizing (coin zerar), não as taxas.
