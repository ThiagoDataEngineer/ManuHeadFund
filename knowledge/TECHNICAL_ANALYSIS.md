# TECHNICAL ANALYSIS — Referência Completa

> Conhecimento consolidado de: Al Brooks, John Murphy, Stan Weinstein, Thomas Bulkowski,
> Steve Nison, Martin Pring, John Bollinger, Welles Wilder, Linda Raschke.

---

## 1. Princípios Fundamentais (Dow Theory)

Formulados por Charles Dow (1900s), base de toda análise técnica:

1. **O mercado desconta tudo** — preço reflete toda informação disponível
2. **Mercados se movem em tendências** — tendências persistem até prova contrária
3. **Tendências têm três fases**: acumulação → participação pública → distribuição
4. **Índices devem se confirmar** — divergência entre índices é sinal de fraqueza
5. **Volume confirma tendência** — volume deve aumentar na direção da tendência
6. **Tendências persistem até reversão clara** — não antecipar, confirmar

---

## 2. Estrutura de Mercado

### Topos e Fundos
```
TENDÊNCIA DE ALTA:
  Fundo 2 > Fundo 1  →  topos e fundos ascendentes = uptrend
  Topo 2 > Topo 1

TENDÊNCIA DE BAIXA:
  Topo 2 < Topo 1   →  topos e fundos descendentes = downtrend
  Fundo 2 < Fundo 1

LATERALIZAÇÃO:
  Topos e fundos sem direção clara = range/consolidação
```

### Higher Highs / Higher Lows (HH/HL)
- **HH + HL**: confirmação de uptrend, comprar pullbacks
- **LH + LL**: confirmação de downtrend, vender rallies
- **Quebra de HL**: primeiro sinal de enfraquecimento de alta
- **Quebra de LH**: primeiro sinal de enfraquecimento de baixa

---

## 3. Suporte e Resistência

### Tipos
| Tipo | Como Identificar |
|------|-----------------|
| Horizontal | Zonas onde preço inverteu múltiplas vezes |
| Dinâmico | Médias móveis, linhas de tendência |
| Psicológico | Números redondos (100, 1000, 50000) |
| Volume Profile | POC, VAH, VAL (zonas de maior transação) |
| Fibonacci | 38.2%, 50%, 61.8%, 78.6% de retracement |

### Troca de Papéis (Polarity Principle)
> Suporte rompido vira resistência. Resistência rompida vira suporte.
> Quanto mais vezes testado, mais relevante — e mais explosivo quando rompido.

### Zonas vs Linhas
- Nunca usar suporte/resistência como linha exata — são **zonas** de 0.5-2%
- Fakeout (stop hunt) é normal antes da reversão — esperar fechamento

---

## 4. Tendências

### Identificação
```
ADX > 25          → tendência presente (Welles Wilder)
ADX 25-50         → tendência moderada
ADX > 50          → tendência forte (raro, explosivo)
ADX < 20          → mercado em range — evitar estratégias de tendência
```

### Linhas de Tendência
- Mínimo 3 toques para validar uma trendline
- Inclinação muito íngreme (>45°) = insustentável, risco de break
- Após quebra da trendline: aguardar reteste antes de entrar contra

### Canais
- Canal de alta: linha de tendência + linha paralela pelos topos
- Opera comprado perto da linha inferior, reduz perto da superior
- Quebra do canal superior = aceleração (extensão)
- Quebra do canal inferior = reversão ou correção profunda

---

## 5. Múltiplos Timeframes (MTF)

**Regra de ouro**: nunca operar contra o timeframe maior.

```
SWING TRADING (dias a semanas):
  HTF: Semanal → define tendência macro
  MTF: Diário  → identifica estrutura e setup
  LTF: 4h      → executa a entrada

DAY TRADING (horas a dia):
  HTF: Diário  → define tendência macro
  MTF: 4h/1h   → identifica estrutura
  LTF: 15m/5m  → executa a entrada

SCALPING (minutos):
  HTF: 1h/15m  → define bias direcional
  MTF: 5m      → identifica estrutura
  LTF: 1m      → executa a entrada
```

**Triple Screen (Alexander Elder)**:
1. Tela 1 (HTF): direção da tendência — só operar a favor
2. Tela 2 (MTF): oscilador para encontrar pullback/setup
3. Tela 3 (LTF): entrada precisa com stop apertado

---

## 6. Padrões de Candle — Biblioteca Completa (Steve Nison)

> Fonte primária: *Japanese Candlestick Charting Techniques* e *Beyond Candlesticks* (Nison).
> Frequência de acerto em crypto: Bulkowski validou em ações — crypto amplifica força dos padrões
> em suportes/resistências relevantes e reduz confiabilidade fora de contexto.

### Regra Universal de Confirmação
> **Padrão isolado = ruído. Padrão + zona relevante + volume + confluência = sinal.**
> Nenhum padrão nesta lista deve gerar entrada sem pelo menos 2 fatores adicionais alinhados.

---

### A. Padrões de 1 Candle

#### Neutros / Indecisão
| Padrão | Anatomia | Leitura |
|--------|----------|---------|
| **Doji padrão** | Abertura ≈ fechamento, sombras curtas iguais | Indecisão — aguardar próximo candle |
| **Long-Legged Doji** | Abertura ≈ fechamento, sombras longas dos dois lados | Batalha intensa compradores/vendedores — alta volatilidade, direção indefinida |
| **Four Price Doji** | Open = High = Low = Close | Mercado parado — sem liquidez, ignorar |
| **Spinning Top** | Corpo pequeno, sombras médias dos dois lados | Indecisão leve — contexto define bias |
| **High Wave Candle** | Corpo muito pequeno, sombras extremamente longas dos dois lados | Volatilidade extrema, mercado perdido — aguardar resolução |

#### Reversão Bullish (1 candle)
| Padrão | Anatomia | Contexto | Força |
|--------|----------|----------|-------|
| **Hammer** | Corpo pequeno no topo, sombra inferior ≥ 2x corpo, sombra superior mínima | Após tendência de baixa, em suporte | Alta |
| **Inverted Hammer** | Corpo pequeno na base, sombra superior ≥ 2x corpo, sombra inferior mínima | Após queda — compradores tentaram, fechamento baixo; confirmar no próximo candle | Média |
| **Dragonfly Doji** | Open = Close = High, sombra inferior longa | Em suporte após queda = rejeição forte de preços baixos | Alta |
| **Bullish Belt Hold** | Abre na mínima (sem sombra inferior), fecha perto da máxima | Após queda, corpo longo sem sombra abaixo | Alta |
| **Bullish Marubozu** | Corpo longo sem sombras, verde | Em qualquer posição — força compradora absoluta | Muito Alta |

#### Reversão Bearish (1 candle)
| Padrão | Anatomia | Contexto | Força |
|--------|----------|----------|-------|
| **Shooting Star** | Corpo pequeno na base, sombra superior ≥ 2x corpo, sombra inferior mínima | Após alta, em resistência | Alta |
| **Hanging Man** | Mesma anatomia do Hammer, mas após tendência de alta | Em topo — vendedores apareceram intraday; confirmar no próximo | Média |
| **Gravestone Doji** | Open = Close = Low, sombra superior longa | Em resistência após alta = rejeição forte de preços altos | Alta |
| **Bearish Belt Hold** | Abre na máxima (sem sombra superior), fecha perto da mínima | Após alta, corpo longo sem sombra acima | Alta |
| **Bearish Marubozu** | Corpo longo sem sombras, vermelho | Em qualquer posição — força vendedora absoluta | Muito Alta |

---

### B. Padrões de 2 Candles

#### Reversão Bullish (2 candles)
| Padrão | Anatomia | Força |
|--------|----------|-------|
| **Bullish Engulfing** | Candle verde engole completamente o corpo do vermelho anterior | Muito Alta |
| **Piercing Line** | Verde abre abaixo da mínima anterior, fecha acima de 50% do corpo vermelho | Alta |
| **Bullish Harami** | Vermelho grande → verde pequeno dentro do corpo do anterior | Média (aguardar confirmação) |
| **Bullish Harami Cross** | Vermelho grande → Doji dentro do corpo do anterior | Alta |
| **Tweezer Bottom** | Dois candles com mínimas exatamente iguais | Média |
| **Bullish Kicker** | Candle vermelho → gap de alta → verde que abre acima do fechamento anterior | Muito Alta (raro) |
| **Bullish Meeting Lines** | Vermelho fecha na mesma região que o verde seguinte abre | Média |
| **Bullish Counterattack** | Vermelho grande → verde que fecha exatamente no mesmo nível do fechamento anterior | Média |

#### Reversão Bearish (2 candles)
| Padrão | Anatomia | Força |
|--------|----------|-------|
| **Bearish Engulfing** | Candle vermelho engole completamente o corpo do verde anterior | Muito Alta |
| **Dark Cloud Cover** | Vermelho abre acima da máxima anterior, fecha abaixo de 50% do corpo verde | Alta |
| **Bearish Harami** | Verde grande → vermelho pequeno dentro do corpo do anterior | Média |
| **Bearish Harami Cross** | Verde grande → Doji dentro do corpo do anterior | Alta |
| **Tweezer Top** | Dois candles com máximas exatamente iguais | Média |
| **Bearish Kicker** | Candle verde → gap de baixa → vermelho que abre abaixo do fechamento anterior | Muito Alta (raro) |
| **Bearish Meeting Lines** | Verde fecha na mesma região que o vermelho seguinte abre | Média |
| **Bearish Counterattack** | Verde grande → vermelho que fecha exatamente no mesmo nível do fechamento anterior | Média |

#### Continuação (2 candles)
| Padrão | Anatomia | Direção |
|--------|----------|---------|
| **Rising Window** | Gap de alta entre dois candles — gap = suporte | Bullish |
| **Falling Window** | Gap de baixa entre dois candles — gap = resistência | Bearish |
| **Separating Lines (Bull)** | Dois verdes que abrem no mesmo nível (belt hold seguido de outro) | Bullish |
| **Separating Lines (Bear)** | Dois vermelhos que abrem no mesmo nível | Bearish |
| **On Neck** | Vermelho grande → verde pequeno que fecha na mínima do anterior | Bearish fraco |
| **In Neck** | Vermelho grande → verde que fecha ligeiramente acima da mínima do anterior | Bearish fraco |
| **Thrusting** | Vermelho grande → verde que fecha dentro do corpo mas abaixo de 50% | Bearish (continuação) |

---

### C. Padrões de 3 Candles

#### Reversão Bullish (3 candles)
| Padrão | Anatomia | Força |
|--------|----------|-------|
| **Morning Star** | Vermelho grande → corpo pequeno (qualquer cor) → verde grande | Muito Alta |
| **Morning Doji Star** | Vermelho grande → Doji → verde grande | Muito Alta |
| **Abandoned Baby (Bull)** | Vermelho grande → Doji com gap dos dois lados → verde grande com gap | Máxima (extremamente raro) |
| **Three Inside Up** | Bearish Harami + candle verde confirmando acima do topo do harami | Alta |
| **Three Outside Up** | Bullish Engulfing + candle verde confirmando acima | Alta |
| **Three White Soldiers** | 3 verdes consecutivos, cada um abrindo dentro do corpo anterior e fechando perto da máxima | Muito Alta |
| **Unique Three River Bottom** | Padrão raro: vermelho grande → inverted hammer → verde pequeno | Alta (raro) |
| **Bullish Breakaway** | 5 candles: tendência de queda + gap + recuperação no 5º | Alta (raro) |
| **Three Stars in the South** | 3 candles vermelhos com corpos e sombras progressivamente menores | Alta (raro) |
| **Concealing Baby Swallow** | 4 Marubozus vermelhos com o 2º engolfando o 3º | Alta (muito raro) |
| **Ladder Bottom** | 3 vermelhos + shooting star + verde de confirmação | Alta (raro) |

#### Reversão Bearish (3 candles)
| Padrão | Anatomia | Força |
|--------|----------|-------|
| **Evening Star** | Verde grande → corpo pequeno (qualquer cor) → vermelho grande | Muito Alta |
| **Evening Doji Star** | Verde grande → Doji → vermelho grande | Muito Alta |
| **Abandoned Baby (Bear)** | Verde grande → Doji com gap dos dois lados → vermelho com gap | Máxima (extremamente raro) |
| **Three Inside Down** | Bearish Harami + candle vermelho confirmando abaixo | Alta |
| **Three Outside Down** | Bearish Engulfing + candle vermelho confirmando abaixo | Alta |
| **Three Black Crows** | 3 vermelhos consecutivos, cada um abrindo dentro do anterior e fechando perto da mínima | Muito Alta |
| **Identical Three Crows** | 3 vermelhos que abrem no fechamento do anterior (sem gap) | Muito Alta |
| **Upside Gap Two Crows** | Verde grande → gap de alta → 2 vermelhos que fecham dentro do verde original | Alta |
| **Two Crows** | Verde grande → vermelho com gap → segundo vermelho engolfa o primeiro | Alta |
| **Bearish Breakaway** | 5 candles: tendência de alta + gap + queda no 5º | Alta (raro) |
| **Ladder Top** | 3 verdes + hammer invertido + vermelho de confirmação | Alta (raro) |
| **Stick Sandwich** | Vermelho → verde que fecha acima → vermelho que fecha no mesmo nível do primeiro | Média |

#### Continuação (3 candles)
| Padrão | Anatomia | Direção |
|--------|----------|---------|
| **Advance Block** | 3 verdes mas com corpos progressivamente menores + sombras crescentes — soldiers enfraquecendo | Warning bullish (cautela) |
| **Deliberation** | 3 verdes, o terceiro muito pequeno + possível gap = força esgotando | Warning bullish |
| **Tasuki Gap (Up)** | Verde → gap de alta → verde → vermelho que fecha dentro do gap mas não preenche | Bullish |
| **Tasuki Gap (Down)** | Vermelho → gap de baixa → vermelho → verde que fecha dentro do gap mas não preenche | Bearish |
| **Side-by-Side White Lines (Up)** | Verde grande → gap → dois verdes de mesmo tamanho lado a lado | Bullish |
| **Mat Hold (Bull)** | Verde grande → 3 pequenos recuos → verde que rompe a máxima do 1º | Bullish |

---

### D. Padrões de 4–5 Candles

| Padrão | Anatomia | Direção | Força |
|--------|----------|---------|-------|
| **Three Line Strike (Bull)** | 3 verdes consecutivos → 1 vermelho que engolfa todos os 3 | Bullish continuação (contra-intuitivo) | Alta |
| **Three Line Strike (Bear)** | 3 vermelhos consecutivos → 1 verde que engolfa todos os 3 | Bearish continuação (contra-intuitivo) | Alta |
| **Rising Three Methods** | Verde grande → 3 pequenos vermelhos dentro do range → verde que rompe máxima | Bullish | Muito Alta |
| **Falling Three Methods** | Vermelho grande → 3 pequenos verdes dentro do range → vermelho que rompe mínima | Bearish | Muito Alta |
| **Mat Hold (Bear)** | Vermelho grande → 3 pequenos altos → vermelho que rompe a mínima do 1º | Bearish | Alta |

---

### E. Mapa de Frequência e Utilidade Prática

```
ALTA FREQUÊNCIA + ALTA CONFIABILIDADE (operar com confluência):
  Engulfing Bull/Bear, Morning/Evening Star, Three White Soldiers/Black Crows,
  Hammer/Shooting Star em zona, Doji em extremo de tendência

ALTA FREQUÊNCIA + CONFIABILIDADE MODERADA (exigir 2+ confluências):
  Harami, Piercing Line, Dark Cloud Cover, Inside Bar, Tweezer

BAIXA FREQUÊNCIA + ALTA CONFIABILIDADE (quando aparecem, são poderosos):
  Kicker, Abandoned Baby, Morning/Evening Doji Star, Rising/Falling Three Methods

BAIXA FREQUÊNCIA + CONTEXTO ESPECÍFICO (conhecer mas não priorizar):
  Three Line Strike, Concealing Baby Swallow, Unique Three River,
  Ladder Top/Bottom, Breakaway, Deliberation

CONTEXTO-DEPENDENTE (nunca usar isolados):
  Spinning Top, Long-Legged Doji, High Wave, Hanging Man, Inverted Hammer
```

---

### F. Nuances Específicas para Crypto

1. **Crypto amplifica padrões**: gaps noturnos são raros (24/7), mas gaps de fim de semana existem em mercados que fecham. Em crypto, o equivalente são gaps em exchanges menores.

2. **Doji em crypto tem menor peso**: mercado 24/7 produz dojis naturalmente. Só relevante em HTF (4H, Daily) ou em zonas técnicas claras.

3. **Engulfing + volume spike = gem alert**: num micro-cap, Bullish Engulfing com volume 3x+ a média das últimas barras é o padrão mais confiável de entrada.

4. **Marubozu + gap = momentum trade**: em altcoins, um Bullish Marubozu no Daily após semanas laterais costuma ser o início do pump — não o final.

5. **Three Black Crows em crypto = sair imediatamente**: diferente de ações onde pode recuperar, em crypto micro-cap três vermelhos fortes seguidos geralmente precedem dump adicional de 30-50%.

6. **Abandoned Baby é mais comum em crypto do que em ações**: devido à volatilidade extrema e gaps de liquidez em pares de baixo volume — quando aparece num suporte no Daily, tem alta confiabilidade.

7. **Hammer vs Hanging Man — a sombra conta a mesma história**: compradores reapareceram (hammer) ou vendedores voltaram a atuar (hanging). O contexto (fundo vs topo) define tudo.

---

## 7. Padrões Gráficos (Thomas Bulkowski)

### Reversão
| Padrão | Taxa Acerto (Bulkowski) | Observação |
|--------|------------------------|------------|
| Head & Shoulders | 83% | Clássico, volume confirma break do neckline |
| Double Bottom (Adam & Adam) | 79% | Dois fundos iguais, volume cresce no segundo |
| Double Top | 75% | Dois topos, volume cai no segundo |
| Triple Bottom | 77% | Raro, mas muito confiável |
| Rounding Bottom | 74% | Acumulação lenta, explosão no rompimento |

### Continuação
| Padrão | Taxa Acerto | Observação |
|--------|-------------|------------|
| Bull Flag | 67% | Pullback ordenado após impulso — favorito de traders |
| Pennant | 65% | Compressão triangular após impulso |
| Ascending Triangle | 72% | Topos planos + fundos ascendentes, breakout para cima |
| Descending Triangle | 72% | Fundos planos + topos descendentes, breakout para baixo |
| Cup and Handle | 71% | Acumulação em forma de copo, handle = pullback final |
| Symmetrical Triangle | 54% | Neutro — aguardar direção do breakout |

### Medição de Alvo
```
Alvo = ponto de breakout ± altura do padrão

Exemplo Head & Shoulders:
  Altura = cabeça - neckline
  Alvo   = neckline - altura (após break para baixo)
```

---

## 8. Volume

### Princípios
- **Volume confirma tendência**: alta com volume crescente = tendência saudável
- **Volume na contratendência**: pullback com volume baixo = fraqueza temporária
- **Volume no breakout**: rompimento com volume alto = autêntico
- **Volume no breakout sem volume**: false break, aguardar reteste

### VSA (Volume Spread Analysis — Tom Williams)
```
SINAL DE FORÇA (acumulação):
  - Volume muito alto + spread estreito + fechamento no meio ou abaixo
  → Profissionais absorvendo venda do varejo (stopping volume)

SINAL DE FRAQUEZA (distribuição):
  - Volume muito alto + candle de alta + spread estreito ou sombra superior
  → Profissionais distribuindo para compradores do varejo (upthrust)

NO DEMAND (sem demanda):
  - Volume baixo + spread estreito em alta
  → Ninguém comprando = price tende a cair

NO SUPPLY (sem oferta):
  - Volume baixo + spread estreito em baixa
  → Ninguém vendendo = price tende a subir
```

---

## 9. Fibonacci

### Retracement (zonas de entrada em pullback)
```
38.2%  →  pullback raso, tendência muito forte
50.0%  →  pullback moderado, mais comum
61.8%  →  pullback profundo, "golden ratio"
78.6%  →  pullback muito profundo, sinal de enfraquecimento
```

### Extension (alvos de saída)
```
127.2%  →  primeiro alvo após rompimento
161.8%  →  alvo padrão ("golden ratio" extension)
261.8%  →  alvo em movimentos explosivos
```

### Como usar
1. Identificar o impulso (ponto A ao ponto B)
2. Traçar retracement de B para A
3. Zonas de 50-61.8% = alta probabilidade de reversão + retomada
4. Combinar com suporte/resistência horizontal = confluência máxima

---

## 10. Price Action Pura (Al Brooks)

### Conceitos Centrais
- **Trading range**: 80% do tempo o mercado está em range — paciência
- **Sempre em posição (AiP)**: mercado sempre pode subir ou cair — sem certeza
- **Bull bar / Bear bar**: avalia força dos compradores vs vendedores em cada candle
- **Micro canal**: série de candles sem pullback = momentum forte, não contrariar

### Entradas de Alta Probabilidade
```
1. Pullback em tendência clara → comprar fundo do pullback
2. Failed breakout → fade da quebra falsa
3. Breakout de consolidação → entrar na segunda barra após rompimento
4. Final flag → último pullback antes da aceleração final
```

### "Always in Long / Always in Short"
> A pergunta é: se você TIVESSE que estar posicionado agora,
> seria comprado ou vendido? Responda isso antes de cada análise.
