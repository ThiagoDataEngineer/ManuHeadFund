# RISK MANAGEMENT — Gestão de Risco e Sizing

> Referências: Ray Dalio, Van Tharp, Ralph Vince, Ed Seykota, Paul Tudor Jones,
> Alexander Elder, Mark Douglas. A única coisa que separa sobrevivência do colapso.

---

## A Verdade Sobre Gestão de Risco

> "The first rule of trading is to not lose money.
>  The second rule is to not forget rule number one."
> — Warren Buffett (adaptado para trading)

> "Risk management is what separates gamblers from traders."
> — Ed Seykota

> "I've learned that it doesn't matter how good your analysis is
>  if your position sizing is wrong."
> — Van Tharp

---

## 1. Risco por Trade

### Regra do 1% (sistema deste projeto)

```
Risco máximo por trade = 1% do capital total

Exemplo:
  Capital: $1.000  → risco máximo = $10 por trade
  Capital: $10.000 → risco máximo = $100 por trade
  Capital: $50.000 → risco máximo = $500 por trade

Por que 1%?
  → 10 perdas seguidas = -10% (recuperável)
  → 20 perdas seguidas = -20% (ainda recuperável)
  → Permite sobreviver a longas sequências de perdas sem destruir a conta
```

### Cálculo do Tamanho da Posição
```
Passo 1: Defina onde fica o stop loss ANTES de entrar
  distancia_stop_pct = |preco_entrada - stop_loss| / preco_entrada

Passo 2: Calcule o tamanho máximo
  risco_monetario = capital_total × 0.01
  tamanho_posicao = risco_monetario / distancia_stop_pct

Exemplo:
  Capital: $10.000
  Entrada BTC: $95.000
  Stop loss: $93.500 → distância = 1.58%
  Risco máximo = $10.000 × 0.01 = $100
  Tamanho = $100 / 0.0158 = $6.329

  → Comprar $6.329 em BTC (0.0666 BTC)
  → Se stop for atingido: perde exatamente $100 = 1% do capital

Com alavancagem:
  Alavancagem 2x: tamanho real = $6.329, margem necessária = $3.164
  Risco permanece $100 — a alavancagem não muda o risco, só a margem
```

---

## 2. Relação Risco/Retorno (R:R)

### Por que R:R importa mais que Win Rate

```
Cenário A: Win rate 70%, R:R 1:1
  10 trades: 7 wins × $100 = $700
             3 losses × $100 = -$300
  Resultado: +$400 (+40%)

Cenário B: Win rate 40%, R:R 1:3
  10 trades: 4 wins × $300 = $1.200
             6 losses × $100 = -$600
  Resultado: +$600 (+60%)

→ Cenário B com 40% de acerto supera Cenário A com 70% de acerto
→ Obsessão com win rate é amadora — foque em R:R
```

### Relação R:R Mínima por Estilo
```
Scalping:      1:1.5 mínimo (velocidade compensa o R:R menor)
Day trading:   1:2 mínimo
Swing trading: 1:3 mínimo
Position:      1:5+ (pode aguardar mais)
```

### Expected Value (EV)
```
EV = (Win Rate × Ganho Médio) - (Loss Rate × Perda Média)

Para ser lucrativo a longo prazo: EV > 0

Exemplo:
  Win rate 50%, R:R 1:2
  EV = (0.50 × $200) - (0.50 × $100) = $100 - $50 = +$50 por trade

Break-even win rate para dado R:R:
  R:R 1:1   → precisa de 50% de acerto
  R:R 1:1.5 → precisa de 40% de acerto
  R:R 1:2   → precisa de 33% de acerto
  R:R 1:3   → precisa de 25% de acerto
```

---

## 3. Diversificação e Correlação

### Máximo de Risco Simultâneo
```
Regra conservadora: máximo 3-5% do capital em risco ao mesmo tempo
  → Se 1% por trade: máximo 3-5 trades simultâneos

Risco de correlação:
  → BTC e altcoins são altamente correlacionados em quedas
  → 5 trades em altcoins diferentes = 1 trade de 5% na prática (em crash)
  → Ajustar: reduzir o risco por trade quando múltiplas posições abertas
```

### Portfolio Approach
```
Distribuição sugerida para crypto:
  BTC:          40-50% do capital crypto (âncora)
  ETH:          20-30% (beta menor que alts)
  Large caps:   10-20% (SOL, BNB, etc.)
  Mid/small:    5-10% (maior risco/retorno)
  Cash/stables: 10-20% sempre reservado para oportunidades

Nunca: 100% em um único altcoin especulativo
```

---

## 4. Drawdown e Recuperação

### A Matemática do Drawdown
```
Perda    → Necessário para recuperar
-10%     → +11%
-20%     → +25%
-30%     → +43%
-40%     → +67%
-50%     → +100%
-75%     → +300%
-90%     → +900%

→ Evitar drawdowns > 25% é mais importante que maximizar ganhos
→ Capital preservado é capital que pode crescer
```

### Regras de Proteção de Capital
```
Regra dos 3 Stops Seguidos:
  → 3 perdas seguidas no mesmo dia = parar de operar no dia
  → Resetar, revisar, não perseguir perdas

Drawdown Diário Máximo:
  → Definir limite: ex. -3% do capital = encerrar o dia
  → Hard stop psicológico: nenhuma exceção

Drawdown Mensal Máximo:
  → Ex. -10% do capital no mês = reduzir tamanho de posições à metade
  → Sinaliza que estratégia ou condição de mercado mudou

Revenge Trading:
  → Nunca aumentar tamanho depois de perda para "recuperar"
  → Pior erro em trading — leva a perdas aceleradas
```

---

## 5. Kelly Criterion (Dimensionamento Ótimo)

```
Fórmula: f* = (bp - q) / b

Onde:
  b = R:R (quanto você ganha por unidade arriscada)
  p = probabilidade de ganho
  q = 1 - p = probabilidade de perda

Exemplo:
  Win rate: 55% (p = 0.55, q = 0.45)
  R:R: 1:2 (b = 2)
  f* = (2 × 0.55 - 0.45) / 2 = (1.10 - 0.45) / 2 = 0.325 = 32.5% do capital

→ Full Kelly é muito agressivo para trading — usar Half Kelly ou Quarter Kelly
→ Half Kelly: 16.25% por trade (ainda agressivo para crypto)
→ Quarter Kelly: 8% por trade (mais conservador)
→ Na prática: usar 1-2% (muito abaixo do Kelly) = preservação máxima
```

---

## 6. Stop Loss

### Tipos de Stop
```
Hard Stop:
  → Ordem no sistema, executa automaticamente
  → Obrigatório — nunca confiar em stop mental

ATR Stop (baseado em volatilidade):
  → Stop = entrada - (2× ATR(14))
  → Ajusta-se à volatilidade atual do ativo
  → Menos chance de stop prematuro em ativos voláteis

Estrutural Stop:
  → Stop abaixo do último suporte / mínima significativa
  → Não arbitrário — tem lógica de mercado
  → "Se quebrar esse nível, minha análise está errada"

Time Stop:
  → Se o trade não se mover na direção esperada em X tempo → fechar
  → Ex: setup de 15m que não se desenvolve em 1h = sair
  → Capital estacionado tem custo de oportunidade
```

### Onde NÃO colocar o Stop
```
❌ Em números redondos óbvios ($50.000, $100.000)
   → Stop hunt alvo certo para market makers

❌ Exatamente no suporte (colocar alguns % abaixo)
   → Fakeouts passam o suporte exato com frequência

❌ Muito apertado baseado apenas no preço de entrada
   → Stop deve ser baseado na estrutura, não no quanto quer perder
```

---

## 7. Take Profit e Saída

### Parciais (Scaling Out)
```
Setup padrão de 3 alvos:
  Alvo 1 (1:1 R:R): fechar 33% → garantir que o trade "paga"
  Alvo 2 (1:2 R:R): fechar 33% → lucro concreto realizado
  Alvo 3 (1:3+ R:R): trailing stop → deixar correr

Benefício psicológico:
  → Reduz ansiedade quando em lucro
  → Garante que winner não vira loser
  → Mantém exposição para grandes movimentos
```

### Saída Total
```
Quando sair completamente:
  → Alvo técnico atingido (resistência, extensão Fibonacci)
  → Candle de reversão forte no alvo
  → Volume esgotando na direção do trade
  → Novo dado ou notícia muda o setup
  → Stop atingido (óbvio)
  → Time stop ativado

Nunca sair por:
  → Medo de perder o lucro já feito
  → "Já subiu muito, vai cair"
  → Intuição sem base técnica
```

---

## 8. Psicologia (Mark Douglas — "Trading in the Zone")

### Os 5 Riscos Fundamentais
```
1. Não saber se o próximo trade vai ganhar ou perder
2. Não saber quanto vai ganhar ou perder
3. Não saber quando o trade vai terminar
4. Não saber quantas entradas serão necessárias para o objetivo
5. Não saber quando o mercado pode colocar em risco o capital

→ Aceitar esses riscos = liberdade para executar sem medo
→ Resistir a esses riscos = erros de execução, hesitação, revenge trading
```

### Regras Mentais
```
"Cada trade é estatisticamente independente do anterior"
→ Uma perda não aumenta a probabilidade do próximo trade ganhar

"O resultado de um trade não me define"
→ Trader de qualidade é julgado por 100 trades, não por 1

"Eu confio no meu edge — deixo o mercado fazer seu trabalho"
→ Uma vez no trade com stop correto: sem microgerenciamento

"Disciplina é executar o plano mesmo quando é difícil"
→ A dificuldade na execução É o teste — não a exceção
```

---

## 9. A Lacuna Entre Saber e Operar

> *"Saber tudo sobre trading e saber operar são habilidades diferentes.
>  A segunda só vem com repetição, perda e tempo."*
> — Van Tharp

### Os dois tipos de erro em trading

```
ERROS DE IGNORÂNCIA (eliminados pelo estudo):
  → Entrar sem stop loss
  → Arriscar 20% do capital em um trade
  → Operar contra a tendência macro
  → Confundir RSI sobrecomprado com sinal de venda em tendência forte
  → Acreditar em "holy grail" ou sistema perfeito

ERROS DE EXECUÇÃO E EMOÇÃO (só eliminados pela experiência real):
  → Saber que o stop deve ser mantido — e mover porque "vai voltar"
  → Saber que não deve dobrar a posição — e dobrar depois de perda
  → Saber que o setup não está claro — e entrar por FOMO
  → Saber que deve sair no alvo — e segurar esperando mais
  → Saber que não deve operar com capital que não pode perder — e operar
```

### O que a experiência real constrói (que livros não constroem)
```
1. Reconhecimento de padrão em tempo real
   → Saber que um candle é engulfing bearish é diferente de
     SENTIR que aquele candle específico, naquele contexto, com aquele volume,
     naquela hora do dia, significa reversão

2. Tolerância emocional calibrada
   → Ver $500 de flutuação negativa sem entrar em pânico
   → Aceitar que 4 perdas seguidas é estatisticamente normal no seu sistema

3. Leitura de caráter do mercado
   → "Este mercado está se comportando diferente hoje"
   → Identificar quando o edge não está presente antes de perder dinheiro

4. Execução mecânica sob pressão
   → Colocar stop, alvo e tamanho de posição corretos em 30 segundos
     enquanto o mercado está se movendo
```

### A única forma de fechar a lacuna
```
Simulação (paper trading):    fecha 20% da lacuna — sem consequência real, sem emoção real
Conta pequena real:           fecha 60% — consequência existe mas não ameaça
Conta relevante ao capital:   fecha os 20% restantes — quando perder doi de verdade

Não há atalho para o terceiro estágio.
O mercado só ensina quando a lição tem custo real.
```
