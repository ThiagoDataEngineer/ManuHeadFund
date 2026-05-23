# SIMONS & RENAISSANCE TECHNOLOGIES — Knowledge Base

> Síntese da filosofia, matemática e disciplina do trader mais bem-sucedido da história,
> traduzida para o contexto cripto 24/7 com **Bitcoin como ativo-base não-inflacionário**.

---

## 1. Persona

**Jim Simons (1938–2024)** — matemático (PhD Berkeley aos 23), code-breaker da NSA durante
a Guerra Fria, co-autor da teoria **Chern-Simons** (matemática pura, base de teoria de cordas
e física de matéria condensada). Fundou a **Renaissance Technologies** em 1982 já com 44 anos.

Nunca foi trader no sentido clássico — era cientista aplicando método rigoroso ao problema mercado.
Não lia notícia, não olhava balanço, não sabia o que as empresas faziam.

**Elwyn Berlekamp** (1940–2019) — aluno de Claude Shannon (MIT), trabalhou com John Kelly
em Bell Labs. Assumiu Medallion em 1989 e fez as 3 mudanças que viraram o jogo.

**Marcos López de Prado** — ex-AQR, autor de *Advances in Financial Machine Learning* (2018).
Não foi RenTech, mas é o autor público que mais perto chega de um "manual operacional" da filosofia.

---

## 2. Os números que importam

| Métrica do Medallion Fund (1988–2018) | Valor |
|---|---|
| Retorno bruto médio anual | ~66% |
| Retorno líquido (após 5% fixo + 44% performance) | ~39% a.a. |
| Sharpe Ratio sustentado | ~2.5 (picos > 6.0 em 2003) |
| Pior ano | Lucro positivo (até 2008 inclusive: +82% bruto) |
| Capacity cap | $10B (devolvem o excedente — edge satura) |
| Status | Fechado a externos desde 1993 |

Buffett ~20% a.a. Soros ~30% no auge. Druckenmiller ~30%. Simons **39% líquido por 30 anos**.
Não há paralelo registrado na história.

---

## 3. Filosofia central — 3 princípios

### Princípio 1 — Método científico, não opinião

> *"The advantage scientists bring is not the math. It's the scientific method. Test, measure, refute."*

Sinais são propostas científicas. São aceitos quando:
- Estatisticamente significantes em walk-forward com purga
- Sobrevivem ao desconto por múltiplos testes (**Deflated Sharpe Ratio**)
- **Não precisam ser explicáveis** — em 1997, >50% dos sinais de Medallion eram inexplicáveis em termos econômicos

> *"The name of the game is not to always be right, but to be right often enough."*

### Princípio 2 — Disciplina mecânica (com nuance honesta)

> *"I don't want to worry about the market every minute. I want models that will make money while I sleep."*

A verdade documentada por Zuckerman:
- Simons fez override em **2003 (Iraq)** — errou
- Override em **2007 (crash)** — errou
- Override em **2000–01 (dotcom)** — *desligou* momentum strategy, **acertou**: o sinal tinha decaído

Conclusão: override **não é proibido** — é **caro, registrado, auditado**.
A diferença entre override-de-pânico e override-de-evidência é tudo.

> *"LTCM's basic error was believing its models were truth.
>  We never believed our models reflected reality — just some aspects of reality."*

### Princípio 3 — Combinação de sinais fracos em sistema único

> *"Renaissance uses a single, monolithic trading system."* — Zuckerman

**Não é** "9 indicadores votando". É **um sistema integrado** com milhares de features
e duas etapas de decisão (meta-labeling: direção + execução).

**Matemática central — Sharpe de ensemble:**
```
SR_ensemble = SR_individual · √( N / (1 + (N−1)·ρ) )
```
- N independentes (ρ=0): Sharpe escala com **√N**
- Correlação alta: ganho satura em **√(1/ρ)**
- Implicação: buscar **muitos sinais fracos descorrelacionados** > buscar 1 sinal forte

| N | ρ=0 | ρ=0.3 | ρ=0.5 | ρ=0.9 |
|---|---|---|---|---|
| 10 | **3.16×** | 1.69× | 1.35× | 1.05× |
| 100 | **10×** | 1.82× | 1.41× | 1.05× |

---

## 4. A matemática operacional

### 4.1 Deflated Sharpe Ratio (Bailey & López de Prado, 2014)

Corrige o Sharpe observado pelo número de tentativas feitas durante a pesquisa.

**Sharpe-limite esperado por puro acaso após N testes:**
```
SR₀ = √V[SRₙ] · ( (1−γ)·Φ⁻¹[1 − 1/N] + γ·Φ⁻¹[1 − 1/(N·e)] )

V[SRₙ] = variância cross-sectional dos Sharpes testados
γ      = Euler-Mascheroni ≈ 0.5772
N      = número de tentativas independentes
Φ⁻¹    = inverse standard normal CDF
```

**Deflated Sharpe (probabilidade do edge ser real):**
```
DSR = Φ( (SR* − SR₀) · √(T−1) / √(1 − γ₃·SR₀ + ((γ₄−1)/4)·SR₀²) )

SR*  = Sharpe observado (não anualizado)
γ₃   = skewness dos retornos
γ₄   = kurtosis dos retornos
T    = comprimento da amostra
Φ    = normal CDF (resultado em [0,1])
```

**Gate operacional**: estratégia só vai pra live se **DSR > 0.95**.

### 4.2 Purged K-Fold Cross-Validation (AFML cap. 7)

Walk-forward simples vaza informação via labels temporais sobrepostos. Solução:
1. **Purge**: remover do treino observações cujos labels overlapam com test set
2. **Embargo**: gap de N períodos entre treino e teste (cobre serial correlation residual)

Sem isto, números "out-of-sample" estão otimistas.

> *"Backtesting is not a research tool. Feature importance is."* — López de Prado

### 4.3 Meta-Labeling (AFML cap. 3)

Separa **direção** de **execução** em dois modelos sequenciais:

```
PRIMARY MODEL (alta recall, baixa precision):
  Input  : features brutas
  Output : side ∈ {long, short, flat}

SECONDARY MODEL (binary classifier):
  Input  : features + decisão do primary + contexto
  Target : "este trade do primary teria sido vencedor?" (1/0)
  Output : P(win)

EXECUÇÃO:
  if P(win) < threshold: SKIP (mesmo com sinal primary)
  else: size = Kelly_fracionário(P(win), R:R) · cap_de_risco
```

### 4.4 Fractional Differentiation (AFML cap. 5)

Diferenciar séries por inteiro destrói memória. Solução:
```
(1−B)^d = 1 − dB + d(d−1)/2 · B² + ...
```
Encontre o **menor d** que produz estacionariedade preservando informação.
Crucial para features cripto altamente autocorrelacionadas (price, on-chain).

### 4.5 Feature Importance (AFML cap. 8)

Três métodos complementares:
- **MDI** (Mean Decrease Impurity): tree-based; `max_features=1` para isolar efeitos
- **MDA** (Mean Decrease Accuracy): permutation-based; funciona em qualquer classifier
- **SFI** (Single Feature Importance): out-of-sample por feature individual

Validar contra PCA via Kendall τ.

### 4.6 Ensemble com max_samples por unicidade (AFML cap. 6)

Bagging padrão é IID. Em finanças, observações se sobrepõem temporalmente.
Solução: `max_samples = média de unicidade dos labels`.

---

## 5. Berlekamp 1989 — os 3 fixes que dobraram Medallion

Em 1989 Medallion perdeu 4%. Berlekamp aplicou 3 mudanças.
Resultado em 1990: **+77.8% bruto / +55.9% líquido**.

| Fix | Mecânica |
|---|---|
| **Kelly sizing fracionário** | Carregar quando edge > média, cap por volatilidade |
| **Holding period curto** | De 1.5 semanas → 1.5 dias; reduz volatility drag |
| **Diversificação serial** | Muitos trades sequenciais > poucos paralelos (lei dos grandes números) |

---

## 6. Frases de referência

> *"We don't override the models. If you start overriding, you have no idea how they'll perform."*

> *"Bad ideas is good, good ideas is terrific, no ideas is terrible."*

> *"Past performance is the best predictor of success — of the strategy, not of the trader."*

> *"Some aspects of reality, not reality itself."*

> *"The name of the game is not to always be right, but to be right often enough."*

---

## 7. Tradução para o contexto cripto

O método é agnóstico ao mercado — mas precisa adaptação para 24/7, **Bitcoin como base
não-inflacionária**, e a fauna de ativos discrepantes.

### 7.1 Bitcoin é a unidade de conta — não USD

> Em equity, o benchmark cresce com inflação. Em cripto, **HODL BTC é o benchmark real**.

```
Estratégia +50% em USDT enquanto BTC fez +80%
   → DESTRUIU valor (medido em BTC, a moeda dura)
```

Toda métrica deve ter versão dupla:
- **Sharpe_USDT** (poder de compra fiat)
- **Sharpe_BTC** (acumulação no ativo-mãe não-inflacionário)

Se `Sharpe_BTC < 0` sustentado, a estratégia perde ao tempo independente do P&L em fiat.

### 7.2 Anualização 24/7

Crypto não fecha. Anualizador correto:

| Timeframe | Anualizador correto | Erro comum |
|---|---|---|
| Daily | **√365** | √252 (calendário equity) |
| 4h | **√(6·365) ≈ 46.8** | √(6·252) |
| 1h | **√(24·365) ≈ 93.6** | √(24·252) |

Em alta frequência, autocorrelação infla Sharpe artificialmente.
Usar **Newey-West HAC** standard errors.

### 7.3 Halving como sazonalidade dominante

Ciclo BTC é quase-determinístico em ~4 anos. Walk-forward que **não atravessa múltiplos
halvings** é overfit por construção:
- Pré-halving: distribuição
- Halving: fundo de bear / transição
- Pós-halving (6-18 meses): bull
- ATH + 12 meses: distribuição/bear

Treinar 2020-2024 e testar 2024-2025 ignora que ambos estão na **mesma fase do ciclo**.
Não vale como out-of-sample.

### 7.4 Tipos de ativo — não tratar como classe única

| Classe | Liquidez típica | Manipulação | Sinal/ruído | Edge sustentado |
|---|---|---|---|---|
| BTC | $30-50B/dia | Baixa | Alto | Pequeno mas confiável |
| ETH / top-5 | $10-30B | Baixa-média | Alto | Pequeno |
| Top 50 | $100M-1B | Média | Médio | Médio (sector rotation) |
| Mid-cap | $10-100M | Alta | Médio | Alto mas raro |
| Micro-cap | < $10M | Altíssima | Baixo | Explosivo mas curto |

**Implicação para meta-labeling**: o secondary model **DEVE ser separado por classe**.
Um classificador único trata BTC como shitcoin e vice-versa — desastre.

### 7.5 Permissionalidade — Spot vs Perpetual vs Futures

| Aspecto | Spot | Perpetual | Futures dated |
|---|---|---|---|
| Funding rate | Não | Sim (8h) | Não |
| Liquidação forçada | Não | Sim | Sim |
| Basis | N/A | Sim (vs spot) | Sim (vs spot) |
| Custo de carry | Zero | Funding rate | Premium decay |
| Slippage em pump | Alta | Baixa-média | Média |

Features que só existem em perpetual e são **ouro Simons-style**:
**funding rate**, **open interest delta**, **liquidation cascades**, **long/short ratio**.
Sinais fracos, reais, descorrelacionados de price action.

### 7.6 Tempestividade — janelas operacionais

- Usuário opera Brasil (UTC-3); janela documentada de melhor edge: **11h-15h BRT**
- Day-of-week effect BTC validado (p=0.0068): Mon LONG +0.55%, Thu LONG −0.16%
- Sazonalidade < 24h existe e é mensurável → feature do secondary model

### 7.7 24/7 muda a noção de "sample"

T cresce 3.5× mais rápido em crypto (365·24h vs 252·6.5h). Parece bom, mas:
- Autocorrelação intra-day é massiva → effective sample size << T
- Notícias asiáticas vs europeias vs US criam regimes distintos por hora
- Paper trade de 14 dias = ~50 trades possíveis em swing intraday. Estatisticamente pouco.
- Mínimo confortável: **60 dias** para significância marginal.

### 7.8 BTC não inflaciona — implicação filosófica

Em USD, capital perde poder de compra por inflação se ficar em caixa.
Em BTC, capital **ganha** poder de compra ao longo do ciclo se ficar parado.

Consequência: **o custo de "aguardar é uma posição" é menor em cripto que em fiat**.
A Regra de Ouro #6 (CLAUDE.md) está cripto-otimizada por design — não é dogma, é matemática.

### 7.9 Microestrutura cripto — orderbook fragmentado e CVD agregado

> Em equity centralizado (NYSE/CME), order flow é tape único. Em cripto, **a liquidez
> está fragmentada entre 50+ exchanges (Binance, OKX, Coinbase, Bybit, CoinEx, DEXs)**.
> CVD lido em uma exchange isolada é informação parcial; pode confirmar acumulação
> local enquanto o agregado real está distribuindo.

**O que muda na prática:**

```
Equity (Bookmap/Jigsaw em ES, NQ):
  → CVD de UMA exchange = CVD do mercado inteiro
  → Iceberg detectado = absorção real

Cripto (BTC, ETH, alts):
  → CVD Binance pode estar comprando enquanto OKX vende
  → Spoof em uma exchange não se vê em outra
  → Whale spread em 5 exchanges parece "volume orgânico" em cada uma
```

**Implicação para o sistema:**

1. **Para tomar order flow como sinal, agregar é obrigatório.**
   Ferramentas que fazem agregação real: Velo Data, Coinalyze, CoinGlass.
   Bookmap só funciona se assinar feed multi-exchange (custo institucional).

2. **No CoinEx AI Agent (live):** CVD não é gate. Funding (proxy de pressão derivativa
   agregada) e open interest delta são gates práticos — eles refletem o agregado
   sem precisar ler 50 orderbooks.

3. **Detecção de manipulação cripto-específica:**
   - Wash trading inter-exchange (volume nasce em A, morre em B)
   - Spoofing distribuído (cancel orders em multiplas exchanges)
   - Liquidity pulling pré-evento (orderbook some 5min antes de notícia)

4. **Regra prática:** se a estratégia precisa de order flow para funcionar,
   ou paga feed agregado (≥$200/mês) ou abandona como gate. CVD single-exchange
   é "scalp daytrader profissional" do SCALP_DAYTRADING.md §2.2 — não escala.

**Conexão com Simons:** RenTech opera HFT com colocation. Em cripto, o equivalente
funcional não é colocation — é **agregação de tape**. Quem tem o tape consolidado
mais rápido e mais completo tem o edge informacional. Para retail/algo small,
a saída é usar **proxies agregados** (funding, OI, exchange netflow) em vez de tentar
reconstruir o tape sozinho.

---

## 8. Aplicação ao CoinEx AI Agent — gap analysis

| Princípio | Onde já está | Próximo upgrade |
|---|---|---|
| Método científico | feedback_metrics_validation_rule.md | DSR threshold > 0.95 como gate |
| Walk-forward | Train/holdout split | + Purga + embargo (López de Prado cap. 7) |
| Sinais fracos combinados | Confluência ≥3 | Meta-labeling de 2 etapas |
| Sizing | 1% fixo | Kelly fracionário cap 1% |
| No override | Regra Ouro #7 | t-test pareado de overrides reais |
| Asset class | BTC/ETH lock | Secondary model separado por classe |
| Base currency | USDT-centric | Dual Sharpe (USDT + BTC) |
| Features perpetual | Funding peak module criado | Adicionar OI delta, liq cascades |
| Cycle awareness | NUPL + Pi Cycle no ChainAgent | Walk-forward que cruza halvings |

---

## 9. Bibliografia verificada

| Fonte | Tipo | Contribuição |
|---|---|---|
| Zuckerman, G. *The Man Who Solved the Market* (2019) | Livro | Cronologia, frases verificadas, episódio Berlekamp |
| Bailey, D. & López de Prado, M. *The Deflated Sharpe Ratio* (2014) JoPM 40(5) | Paper | Fórmula central, anti-overfit |
| López de Prado, M. *Advances in Financial Machine Learning* (2018) Wiley | Livro | Manual técnico — meta-labeling, purged CV, frac diff |
| Berlekamp interviews via Breaking the Market | Web | Os 3 fixes de 1989 detalhados |
| Simons — MIT Lecture (2010) | YouTube | Voz própria, ~1h |
| López de Prado, M. *The 10 Reasons Most ML Funds Fail* | Paper | Anti-overfit prático |

---

## 10. Limites honestos (alinhados ao CLAUDE.md)

Conhecer Simons em profundidade ≠ replicar Simons.

**Falta-nos:**
- $1-10B de capital cap-eável
- Co-location, tick data desde 1970
- 100 PhDs em física e linguística computacional
- Décadas de iteração com skin in the game

**Temos:**
- O **método**
- A **disciplina**
- A **matemática**

Isso é fundação suficiente para **não cometer erros de amador**.
O edge real ainda precisa ser conquistado em paper trade,
depois em live com escala gradual.

> *"Saber tudo sobre Simons e operar como Simons são habilidades diferentes.
>  A segunda só vem com repetição, perda e tempo."*
