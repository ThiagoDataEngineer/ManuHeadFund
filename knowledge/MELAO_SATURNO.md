# MELÃO / SATURNO V — Princípios de Trading Quantitativo

> Referência: Hindemburg Melão Jr. — criador do Saturno V (sistema automático de IA para mercado
> financeiro, operando em conta real desde agosto 2010, +43% a.a. em dólar, 21 prêmios internacionais).
> Autodidata brasileiro, recordista mundial de xadrez (1998), psicometrista (Sigma Test),
> autor do Melão Index (SSRN 2024).
>
> **Importante**: a estratégia interna do Saturno V é caixa preta (não divulgada).
> O que está documentado aqui são os **princípios e críticas públicas** — suficientes para
> guiar decisões de design sem acesso ao algoritmo proprietário.

---

## 1. Ergodicidade e Isotropia — o critério mais importante

> "Os resultados do Saturno V se destacam por sua homogeneidade, isotropia e ergodicidade."
> — saturnov.org

### O que significa na prática

**Ergodicidade**: o resultado médio no tempo converge para o resultado médio entre diferentes
ativos e cenários. Um sistema ergódico funciona em bull, bear e lateral — não por "adaptação
manual" mas por robustez estrutural.

**Isotropia**: os resultados não dependem da direção do mercado. O sistema é indiferente se
o ativo sobe ou cai.

### Por que é o critério certo

A maioria dos sistemas parece funcionar porque foi testado em bull market. Quando o regime
muda, quebra. Um sistema verdadeiramente robusto tem **baixa variância de performance entre
regimes** — não necessariamente retorno máximo em cada um.

```
Sistema A: +40% win_rate em bull | +5% em bear | +15% em lateral
           → Aparentemente bom no agregado, mas quebrará em bear prolongado

Sistema B: +28% win_rate em bull | +22% em bear | +25% em lateral
           → Inferior no bull, mas confiável — sistema ergódico
```

### Critério de aceite de parâmetros

Ao otimizar qualquer parâmetro do sistema, o critério não deve ser retorno máximo agregado,
mas **menor coeficiente de variação de win_rate entre regimes**:

```python
# Ergodicity Score — 0 a 1 (1 = perfeitamente consistente)
ergodicity_score = 1 - (std(win_rates_por_regime) / mean(win_rates_por_regime))

# Critério de aceite: ergodicity_score > 0.70
# Rejeitar parâmetros com score < 0.50 mesmo que retorno agregado seja alto
```

**Testado em 130+ anos** (Dow Jones 1885–2015, incluindo 1929 e 2008): a volatilidade
do Saturno V se manteve constante mesmo em crises — outros fundos explodiram nesses períodos.

---

## 2. Melão Index — limitações das métricas tradicionais

> "The Melao Index: A New Standard for Risk-return Analysis, Resolving Fundamental
> Inconsistencies in the Sharpe Ratio and Related Metrics"
> — SSRN, setembro 2024 (abstract_id=5188185)

### O que está errado no Sharpe ratio

| Problema | Impacto em Crypto |
|----------|-------------------|
| Penaliza volatilidade positiva = negativa | Um gem +441% "piora" o Sharpe |
| Assume distribuição normal (gaussiana) | Crypto tem fat tails — retornos não são normais |
| Não comparável entre frequências diferentes | Sharpe diário ≠ Sharpe semanal de forma simples |
| Não captura path dependency (sequência de perdas) | Drawdown longo não aparece no Sharpe |

### Problemas no Calmar, Sortino, MAR, Modigliani

Melão argumenta que todos têm "erros conceituais e quantitativos" — não apenas o Sharpe.
O Melão Index propõe correções para fatores que esses índices negligenciam.

### Hierarquia prática de métricas (do mais ao menos confiável)

```
1. Expectancy R (Van Tharp)   → quanto ganha em média por R arriscado — simples e honesto
2. Profit Factor              → ganhos brutos / perdas brutas — intuitivo
3. Sortino Ratio              → como Sharpe mas penaliza só downside — melhor para crypto
4. Calmar Ratio               → retorno anual / max drawdown — foco em sobrevivência
5. Sharpe Ratio               → útil para comparação mas cheio de ressalvas
```

### O que o Melão Index corrige (sem acesso à fórmula completa)

- Separa upside de downside volatility de forma mais rigorosa que o Sortino
- Incorpora path dependency (não só magnitude do drawdown, mas duração)
- Normalização temporal independente de frequência
- Penaliza assimetria na distribuição de retornos

---

## 3. Anti-Scalping — argumento matemático

> "O tamanho do ruído se torna comparável ao tamanho do sinal em escalas temporais micro."
> — Hindemburg Melão Jr.

### A matemática

```
Estratégia A (swing): alvo +25%, custo total 0.5%
  → Breakeven: 51% de acurácia

Estratégia B (scalp): alvo +1%, mesmo custo 0.5%
  → Breakeven: 50% de acurácia
  → Mas a dificuldade de identificar o sinal correto é ordens de magnitude maior
```

O problema não é a matemática do breakeven — é que em timeframes curtos o sinal se dissolve
no ruído. A proporção sinal/ruído degrada rapidamente abaixo de certos timeframes.

### A armadilha do stop largo

Scalpers que parecem lucrativos frequentemente usam alvos pequenos com stops largos.
Isso cria uma sequência de pequenos ganhos seguida de uma perda catastrófica quando o
stop largo é atingido. O P&L parece positivo por meses até o drawdown eliminar tudo.

**Validação no projeto**: RR mínimo 1:5 (`$RR_MINIMO = 5.0`) e timeframe operacional 1H/4H
são consistentes com esse princípio. Scalp em 1min/5min seria matematicamente desvantajoso
após fees da CoinEx (0.03% maker + 0.05% taker = 0.08% round trip).

---

## 4. Reconhecimento de Padrões Complexos — arquitetura do Saturno V

> "O futuro da análise de mercado depende de máquinas capazes de reconhecer padrões simples,
> balanceá-los por relevância, identificar como esses padrões interagem para formar padrões
> mais complexos e usar um algoritmo acurado para balancear esses padrões mais complexos
> por relevância."
> — Hindemburg Melão Jr.

### Princípio central

Nenhum indicador, padrão ou ferramenta funciona em todos os contextos. O mercado exige:

1. Múltiplos padrões primários identificados independentemente
2. Balanceamento dinâmico da relevância de cada padrão
3. Análise das interações entre padrões (confluência)
4. Predição baseada no conjunto — não em um único sinal

### Anti-dogmatismo

Ferramentas usadas como dogma falham. Fibonacci é o exemplo mais citado por Melão:
a proporção áurea é uma generalização excessiva — estruturas fractais diferentes têm
proporções distintas (Koch: 0.667, Sierpinski: 0.5). Usar 0.618 como nível universal
é ritualismo, não análise.

```
Errado: "O preço retrocedeu exatamente 61.8% — sinal confirmado"
Certo:  "61.8% coincide com OB 4H + VWAP + volume POC — confluência de 3 fatores"
```

**Validação no projeto**: arquitetura multi-agente com pesos (Tech 40%, Chain 25%,
Sent 20%, Fund 15%) implementa exatamente esse princípio. Cada agente é um "padrão primário"
balanceado por relevância. O MentorAgent é a camada que avalia as interações.

### Pesos adaptativos por regime

O Saturno V otimiza os pesos dinamicamente via CANTOR (algoritmo genético proprietário).
A aproximação prática é tabelas de pesos por regime:

```
BULL:    Fund↑ (narrativas importam), Tech padrão
BEAR:    Chain↑ (whale activity crítico), Sent↑ (fear signals), Fund↓
LATERAL: Tech↑ (price action domina), demais iguais
```

---

## 5. CANTOR — Otimização de Parâmetros

A plataforma CANTOR é um otimizador próprio de Melão para o Saturno V. Em ~20 horas
encontrou parâmetros superiores aos obtidos em 9 anos com MetaTrader — porque o MetaTrader
usa busca por grid (simplório) enquanto o CANTOR usa heurísticas genéticas customizadas.

### O problema do grid search

```
Grid search em 10 parâmetros com 10 valores cada = 10^10 combinações
Algoritmo genético: explora o espaço de forma inteligente, converge em frações do tempo
```

### Equivalente open source: Optuna

Para o projeto, o equivalente é **Optuna** (Python, Bayesian optimization):

```python
import optuna

def objective(trial):
    rr_minimo = trial.suggest_float("rr_minimo", 3.0, 8.0)
    score_minimo = trial.suggest_float("score_minimo", 55.0, 80.0)
    # ... rodar backtest_runner com esses parâmetros
    # retornar ergodicity_score (não apenas retorno agregado)
    return ergodicity_score

study = optuna.create_study(direction="maximize")
study.optimize(objective, n_trials=500)
```

**Critério de otimização**: maximizar `ergodicity_score`, não retorno bruto. Isso garante
que os parâmetros encontrados são robustos entre regimes — não apenas overfitados em bull.

---

## 6. Gestão de Capital — princípios inferidos

O método exato não é divulgado. Com base nos resultados e princípios públicos:

### Volatilidade constante como meta

O Saturno V mantém volatilidade **constante** mesmo em crises — outros fundos explodem
nesses períodos. Isso implica **position sizing dinâmico inverso à volatilidade**:

```
Vol baixa do mercado → posição maior (mais espaço para o trade respirar)
Vol alta do mercado  → posição menor (risco de ruído aumenta)

Implementação: Get-PositionSize baseado em ATR já faz isso parcialmente
```

### Relação com Kelly Criterion

Kelly Criterion maximiza crescimento geométrico de longo prazo:
`f* = (p * b - q) / b`
onde `p` = probabilidade de ganho, `b` = payoff ratio, `q` = 1-p.

**Problema do Kelly puro**: com estimativas ruidosas de `p` e `b`, Kelly frequentemente
recomenda tamanhos de posição que causam ruína antes da convergência assintótica.

**Solução padrão institucional**: Half-Kelly ou Quarter-Kelly. Com RR 1:5 e win rate ~30%:
`Kelly = (0.30 * 5 - 0.70) / 5 = 0.16 = 16% do capital` — número perigoso em crypto.
`Half-Kelly = 8%` — ainda alto. `Quarter-Kelly = 4%` — conservador mas sobrevivível.

A regra de 1% por trade (`$RISCO_MAXIMO_PCT = 0.01`) está bem abaixo de Quarter-Kelly
para os parâmetros do sistema — o que é correto dado o histórico curto e incerteza nos
estimadores `p` e `b`.

---

## 7. Backtesting Rigoroso — princípios

> "Diferenças entre simulado e real são comparáveis às variações entre contas reais separadas."
> — Saturno V, sobre confiabilidade do backtest

### O que torna um backtest confiável segundo Melão

1. **Escala temporal**: mínimo 10 anos, ideal 30+ anos — capturar múltiplos ciclos completos
2. **Tick-by-tick quando possível**: elimina lookahead bias intra-candle
3. **Incluir crises**: 1929, 1987, 2000, 2008 — regimes extremos são o teste real
4. **Comparar backtest com conta real**: se a diferença for maior que variação entre contas
   reais, o backtest tem problemas (overfitting ou lookahead bias)
5. **Milhões de testes, não centenas**: o CANTOR rodou "milhões de backtests" para o Saturno V

### Armadilha do overfitting

Otimizar parâmetros no mesmo dataset que será avaliado = overfitting garantido.
Solução: **walk-forward validation** — treinar em período A, testar em período B, nunca
usar B para ajustar parâmetros.

---

## Conexão com o CoinEx Agent

| Princípio Melão | Implementação atual | Próximo passo |
|----------------|---------------------|---------------|
| Ergodicidade | `classify_regime` + `calc_metrics_by_regime` | `ergodicity_score` em `metrics.py` |
| Métricas ajustadas ao risco | Sharpe + Calmar em `metrics.py` | Adicionar Sortino |
| Anti-scalping | RR mínimo 1:5, timeframe 1H/4H | já implementado ✅ |
| Múltiplos padrões balanceados | OrchestratorAgent com pesos | Pesos adaptativos por regime |
| Otimização inteligente | parâmetros fixos em config.ps1 | Optuna para walk-forward |
| Volatilidade constante | `$RISCO_MAXIMO_PCT = 0.01` (1% fixo) | Position sizing ATR-adaptativo |
| Backtesting rigoroso | 721 candles reais, zero lookahead bias | Walk-forward validation |

---

## Referências

- [saturnov.org](https://www.saturnov.org) — site oficial, apresentação, FAQ, artigos
- [SSRN — Melão Index](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5188185) — paper acadêmico 2024
- [Saturno V — Scalping](https://www.saturnov.org/artigosp/scalping) — crítica matemática ao scalping
- [Projeto T](https://www.saturnov.org/artigosp/projeto-t) — visão de longo prazo, IA inspirada em MuZero
