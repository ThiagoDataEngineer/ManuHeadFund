# LOPEZ_DE_PRADO.md — Marcos López de Prado & AFML Stack

> Bíblia operacional do método científico em finanças quantitativas.
> Referência para gates estatísticos, feature engineering, validação anti-overfit,
> meta-labeling, position sizing e portfolio construction.
>
> Cruza diretamente com `SIMONS_RENTECH.md` (filosofia) — este é o **toolkit prático**.

---

## 1. Identificação

**Marcos López de Prado** — único peer institucional real dos quants modernos.

**Credenciais verificáveis:**
- PhD Financial Economics + PhD Mathematical Finance (Complutense Madrid)
- Postdoc Harvard
- **Global Head of Quantitative R&D na ADIA** (Abu Dhabi Investment Authority, ~$1T AUM)
- Founding board member do **ADIA Lab**
- Professor of Practice — Cornell College of Engineering
- Research Fellow — Lawrence Berkeley National Lab
- Fundou **True Positive Technologies** (licenciou patentes em deals 8-figure; advised $1T+ AUM)
- **8.620+ citações** no Google Scholar
- Top 10 mais-lido na SSRN em Economics
- **Prêmios**: Quant Researcher of the Year (2019 PMR); Buy-Side Quant of the Year (2021 Risk.net); Bernstein Fabozzi/Jacobs Levy Award (2024)
- Testemunhou no Congresso dos EUA sobre AI policy
- Inventor nomeado em múltiplas patentes

**Por que importa para este projeto:**
- Skin in the game ($1T ADIA) + rigor acadêmico (8k+ citações) + replicabilidade (mlfinlab open-source)
- Resolve diretamente os gaps abertos do pipeline: DSR, PBO, purged CV, feature importance, meta-labeling, sizing dinâmico

---

## 2. Estrutura completa do AFML (Advances in Financial Machine Learning, 2018)

**21 capítulos numerados** (não 22 — correção comum).

| # | Título | Tópicos centrais | Algoritmos / fórmulas-chave |
|---|---|---|---|
| 1 | Financial ML as a Distinct Subject | Por que finanças quebra ML clássico (não-IID, low S/N, regime change); paradigma "Sisyphus" | — |
| 2 | Financial Data Structures | Tick/Volume/**Dollar bars** vs Time bars; **Information-Driven Bars** (Imbalance, Run); ETF trick | Imbalance threshold E₀[T]·\|2v⁺−E[v]\| |
| 3 | Labeling | **Triple Barrier Method**; **Meta-Labeling**; trend-scanning labels; volatility-scaled barriers | `getEvents`, `applyPtSlOnT1`; vol estimator EWMA |
| 4 | Sample Weights | Concurrent labels, uniqueness u_{t,i}=1/c_t, average uniqueness, **sequential bootstrap**, time-decay weights | Indicator matrix 1_{t,i}; weights w_i ∝ Σ\|r_t\|/c_t |
| 5 | Fractionally Differentiated Features | **Frac-diff** binomial expansion; FFD (fixed-width window); min-d para estacionariedade preservando memória | (1−B)^d via Σ w_k B^k; w_k = −w_{k-1}(d−k+1)/k |
| 6 | Ensemble Methods | Bagging/Boosting; por que random forest sofre em finanças (correlação amostral); BaggingClassifier com `max_samples` reduzido | Variance reduction com ρ-correlated learners |
| 7 | Cross-Validation in Finance | **Purged K-Fold + Embargo**; por que k-fold padrão vaza | `PurgedKFold` com h = embargo bars |
| 8 | Feature Importance | **MDI** (in-sample, tree-only), **MDA** (OOS permutation), **SFI** (single-feature OOS); substitution effects | MDA_j = (s − s_perm_j)/s_perm_j |
| 9 | Hyper-Parameter Tuning with CV | Grid/Random search com PurgedKFold; log-uniform priors; scoring via neg-log-loss em vez de accuracy | `RandomizedSearchCV` custom CV splitter |
| 10 | Bet Sizing | **Sigmoid bet sizing** via probabilidade; budgeting; concurrent bets; meta-labeling como gate | z = (p−0.5)/√(p(1−p)); size = 2Φ(z)−1 |
| 11 | The Dangers of Backtesting | **PBO/CSCV**; selection bias under multiple testing; "backtest é research tool, não virtual reality" | PBO via logits dos OOS rankings |
| 12 | Backtesting through Cross-Validation | **CPCV (Combinatorial Purged CV)**; múltiplos paths sintéticos; distribuição empírica de Sharpe | (N choose k) splits, purge+embargo |
| 13 | Backtesting on Synthetic Data | Monte Carlo, regime-switching simulation, bootstrap em bars sintéticas | Ornstein-Uhlenbeck, HMM regime |
| 14 | Backtest Statistics | **DSR (Deflated Sharpe Ratio)**, PSR, MinTRL, drawdown distribution | DSR fórmula completa (§3.10) |
| 15 | Understanding Strategy Risk | Strategy risk pricing (asymmetric payoff); breakeven probability; binary symmetric strategies | π = pP − (1−p)L; σ² fórmula |
| 16 | ML Asset Allocation | **HRP (Hierarchical Risk Parity)** — 3 stages: tree clustering, quasi-diagonalization, recursive bisection; **NCO** | Linkage tree; correl→dist d=√(½(1−ρ)) |
| 17 | Structural Breaks | CUSUM filters, **SADF** (Sup Augmented Dickey-Fuller) for bubble detection, explosiveness | SADF_t = sup ADF[τ,t] |
| 18 | Entropy Features | Shannon/plug-in/LZ/Kontoyiannis entropy estimators; informativeness por bar | H = −Σ p log p |
| 19 | Microstructural Features | **Kyle's λ**, **Amihud illiquidity**, **VPIN**, Hasbrouck lambda, roll model, Corwin-Schultz spread | VPIN = Σ\|V⁺−V⁻\|/(n·V); λ via OLS Δp~OF |
| 20 | Multiprocessing & Vectorization | `mpPandasObj`, joblib, vectorization patterns | Linear partition, nested partition |
| 21 | Brute Force & Quantum Computers | Combinatorial optimization via QUBO; D-Wave annealing para portfolio | min x'Qx s.t. constraints |

---

## 3. Técnicas-pilar aprofundadas

### 3.1 Information-Driven Bars (Cap 2)

**Problema:** time bars (1h, 1d) sub-amostram períodos calmos e sobre-amostram períodos voláteis — distribuição de retornos não-Gaussiana, autocorrelação serial.

**Variantes:**
- **Tick bar:** novo bar a cada N ticks
- **Volume bar:** a cada N contratos
- **Dollar bar:** a cada $X traded (robusto a price split, **melhor estatístico em backtests longos**)
- **Imbalance bars (TIB/VIB/DIB):** sample bar quando \|Σb_t·v_t\| > E₀[T]·\|2v⁺−E[v]\|, onde b_t ∈ {−1,+1} é tick rule. Captura **chegada de informação assimétrica**
- **Run bars:** sample quando max(Σv⁺, Σv⁻) excede expectativa — captura rajadas direcionais

**Quando aplicar em crypto:** dataset de alta frequência (tick/L2). Spot CoinEx tem tick stream → **dollar bars de $50M em BTC, $5M em altcoin**.

**Armadilha:** se você só tem OHLCV 1m, não emule imbalance — vai gerar bars sintéticas enviesadas. Use dollar bars (precisa volume) ou faça upgrade pra tick.

---

### 3.2 Fractional Differentiation (Cap 5)

**Problema:** retornos são estacionários mas perdem memória. Preços têm memória mas são não-estacionários. Frac-diff de Hosking (1981), upgrade LdP via FFD.

**Fórmula:**

$$(1-B)^d X_t = \sum_{k=0}^{\infty} w_k X_{t-k}, \quad w_k = -w_{k-1} \cdot \frac{d-k+1}{k}, \quad w_0=1$$

Para d ∈ (0,1) os pesos decaem hiperbolicamente — preservam memória longa. FFD trunca em \|w_k\| < τ (típico τ=1e-5).

**Algoritmo prático:**
1. Para d ∈ {0, 0.1, 0.2, ..., 1.0} calcular ADF test da série frac-diff
2. Escolher **menor d** que rejeita unit root (p < 0.05)
3. Aplicar frac-diff com esse d* — feature para ML preserva memória **e** é estacionária

**Crypto:** BTC log-price típico precisa d* ≈ 0.3-0.45 (mais memória que equity dada autocorrelação de regime).

**Armadilha:** frac-diff de série com missing data (gaps de exchange) gera bias enorme. Forward-fill cuidadoso. E o d* muda com regime — recalcular trimestralmente.

---

### 3.3 Triple Barrier Method (Cap 3)

**Setup:** para cada evento de entrada t₀, três barreiras:
- **Profit Take (PT):** preço sobe a r⁺ = pt · σ_t (σ volatilidade EWMA)
- **Stop Loss (SL):** preço cai a r⁻ = sl · σ_t
- **Vertical (T1):** tempo máximo (típico 5 bars)

**Label y ∈ {−1, 0, +1}** = qual barreira foi tocada primeiro (sign × ret).

**Pseudocódigo:**
```python
def applyPtSl(close, events, ptSl, molecule):
    for loc in molecule:
        df = close[loc:events.at[loc,'t1']]
        df = (df/close[loc] - 1) * events.at[loc,'side']
        out.at[loc,'sl'] = df[df < -ptSl[1]*events.at[loc,'trgt']].index.min()
        out.at[loc,'pt'] = df[df >  ptSl[0]*events.at[loc,'trgt']].index.min()
```

**Quando aplicar:** sempre que você tem stop/alvo definidos — **já é o caso do CoinEx Agent**.

**Armadilha:** se ptSl simétrico (e.g. 1:1) e volatilidade dominante, label vira ruído. Use **side-aware** (label do lado que você vai operar) e ptSl assimétrico (1:5 reflete RR do sistema).

---

### 3.4 Meta-Labeling (Cap 3.6)

**Decoupling brilhante:**
- **Modelo primário (M1):** decide *direção* (alta recall, baixa precisão) — pode ser regra técnica (Tori trendline, regime BULL_STRONG)
- **Modelo secundário (M2):** decide *se executar* — classifica P(win | M1 sinalizou) e converte em bet size

**Output do M2:** Pr(win) ∈ [0,1]. Plugado direto no sigmoid bet sizing (§3.14).

**Por que funciona:** M2 vê features de microestrutura, regime, hora do dia que M1 ignora. Melhora F1 sem ter que mudar lógica do M1.

**Quando falha (empiricamente):** se M1 já tem precisão alta (>65%), M2 trade recall por precisão sem ganho. Hudson & Thames documentou casos de degradação — **não é silver bullet**.

**Para CoinEx Agent:** M1 = whitelist v2 strict (BULL_STRONG LONG + TRANSITION_UP+Mon LONG). M2 treina em features {DXY z-score, BTC dominance, hora UTC, RSI 1h, regime, NUPL} e prediz P(triple-barrier = +1). Sizing = 0% se P<0.55, escala via sigmoid se P>0.55.

---

### 3.5 Sample Weights / Uniqueness (Cap 4)

**Problema:** se trade T1 vai de 10:00-11:00 e trade T2 de 10:30-11:30, ambos compartilham retorno 10:30-11:00 → não-IID, label leakage.

**Concurrency:**

$$c_t = \sum_i \mathbb{1}_{t,i} \quad \text{(quantos eventos cobrem t)}$$

**Uniqueness por evento:**

$$\bar{u}_i = \frac{1}{T_i}\sum_{t \in T_i} \frac{1}{c_t}$$

**Sample weight return-attribution:**

$$w_i \propto \sum_{t \in T_i} \frac{r_t}{c_t}$$

**Sequential bootstrap:** em vez de sample uniforme, probabilidade de selecionar evento j na iteração k+1 é inversamente proporcional à concurrency com já-selecionados. Aumenta avg uniqueness do sample → ML aprende padrões reais, não duplicados.

---

### 3.6 Purged K-Fold + Embargo (Cap 7)

**Problema:** K-fold padrão treina em tempo futuro do test set → leakage.

**Purging:** remove do training set qualquer observação cujo label horizon ([t₀, t₁]) intersecta o test fold.

**Embargo:** após cada test fold, descarta h bars do treino seguinte (h = pctEmbargo · T, típico 1-2%).

**Pseudocódigo:**
```python
class PurgedKFold(KFold):
    def split(self, X, y, groups=None):
        for test_idx in folds:
            t1_test_max = self.t1[test_idx].max()
            t0_test_min = self.t1[test_idx].min() - embargo
            train_idx = self.t1.index.difference(
                self.t1[(self.t1 >= t0_test_min) & (self.t1.index <= t1_test_max)].index
            )
            yield train_idx, test_idx
```

**Para CoinEx:** train/holdout simples gerou FAIL_OVERFIT (memory `project_fail_overfit_double_2026_05_14`). Substituir por `PurgedKFold(k=5, embargo=0.01)` imediatamente.

---

### 3.7 Combinatorial Purged CV — CPCV (Cap 12)

**Upgrade do Purged K-Fold:** em vez de 1 path único, divide série em N grupos, escolhe **todas (N choose k)** combinações de k grupos como test. Cada combinação gera 1 backtest path.

Com N=6, k=2 → **15 paths**. Cada path tem Sharpe próprio → distribuição empírica de Sharpe → você pode calcular P(Sharpe > 0), DSR, drawdown distribution.

**Custo computacional:** treinos ≈ N·(N−1)/2 · k/N. Para N=6, k=2 → 5 treinos. Para N=10, k=2 → 9 treinos. Escala combinatorialmente acima de k=3.

**Para crypto:** janelas de 90 dias (não 252) dado regime change. BTC 14y → 56 grupos de 90 dias → consolidar em N=10, k=2 → **45 paths**.

---

### 3.8 Feature Importance — MDI / MDA / SFI (Cap 8)

| Método | Compute | Score | Substitution effect | Quando usar |
|---|---|---|---|---|
| **MDI** (Mean Decrease Impurity) | só random forest, IS | Σ impurity reduction por feature | Sim — features correlacionadas dividem score | First-pass rápido, free com sklearn |
| **MDA** (Mean Decrease Accuracy) | qualquer model, OOS, permutation | s − s_perm_j | Sim — se permutar feature A e B correlatas, ambos parecem irrelevantes | Score robusto a model class |
| **SFI** (Single Feature Importance) | qualquer model, OOS | OOS score com apenas feature j | **Não sofre** — mede em isolamento | Quando suspeita multi-colinearidade |

**Clustered MDA/MDI:** cluster features correlacionadas, computa importance do **cluster** — elimina substitution. Implementação em mlfinlab.

**Para CoinEx:** rodar **SFI** primeiro nas features atuais (RSI_1h, ADX, BB_width, dominance, dow, regime_score). Suspeita: ADX e BB_width clusterizam. Drop features SFI < cutoff.

---

### 3.9 PBO / CSCV (Cap 11)

**PBO = Probability of Backtest Overfitting** — probabilidade de que a estratégia escolhida como melhor in-sample tenha performance mediana ou pior out-of-sample.

**CSCV (Combinatorially Symmetric CV):** Divide S em S/2 blocos pares e ímpares; para cada combinação:
1. Treina em pares, testa em ímpares
2. Ranqueia N estratégias pelo IS Sharpe; pega estratégia n* = argmax
3. Vê posição de n* no ranking OOS; calcula logit λ = log(rank_OOS / (N − rank_OOS + 1))
4. **PBO = P(λ ≤ 0)**

**Interpretação:** PBO > 0.5 = sua "melhor" estratégia é provavelmente sorte.

**Para CoinEx:** quando você varre 100 combos (regime × dow × side), CSCV diz se o "ganhador" é real. Memória `project_strict_v2_validated_14y` mostra PF 1.39→2.02 — precisa rodar CSCV para confirmar que **não é seleção**.

---

### 3.10 Deflated Sharpe Ratio — DSR (Cap 14 + JPM 2014)

**Setup:** você testou N estratégias, ficou com a melhor (SR_obs). Sob H₀ (sem skill, retornos IID), o expected max SR depois de N trials é:

$$E[\max \text{SR}] \approx \sqrt{V[\text{SR}_n]} \cdot \left[ (1-\gamma)\Phi^{-1}\left(1 - \frac{1}{N}\right) + \gamma\Phi^{-1}\left(1 - \frac{1}{Ne}\right) \right]$$

onde γ ≈ 0.5772 (Euler-Mascheroni), Φ⁻¹ é o quantile da normal padrão, V[SR_n] é a variância dos Sharpes dos N trials.

**Standard error do SR observado** (corrigido por skew/kurtosis Lo 2002):

$$\sigma[\hat{\text{SR}}] = \sqrt{\frac{1 - \hat{\gamma}_3 \hat{\text{SR}} + \frac{\hat{\gamma}_4 - 1}{4} \hat{\text{SR}}^2}{T - 1}}$$

onde γ̂₃ = skew dos retornos, γ̂₄ = kurtosis.

**DSR completo:**

$$\text{DSR} = \Phi\left(\frac{(\text{SR}_{obs} - E[\max\text{SR}])\sqrt{T-1}}{\sqrt{1 - \hat{\gamma}_3 \text{SR}_{obs} + \frac{\hat{\gamma}_4 - 1}{4}\text{SR}_{obs}^2}}\right)$$

**Threshold:** DSR ≥ 0.95 (95% confidence) → estratégia tem skill real.

**Para CoinEx:** sistema v1.0 LOCK precisa reportar SR_BTC-denominated **e** DSR. Se varreu N=200 sub-setups e o "ganhador" tem SR=1.5 com DSR=0.4 → é seleção, não edge.

---

### 3.11 Hyperparameter Tuning com Purged CV (Cap 9)

**Substituições obrigatórias:**
- `KFold` → `PurgedKFold`
- `accuracy` → `neg_log_loss` (calibração probabilística importa pro sizing)
- `GridSearchCV` → `RandomizedSearchCV` com **log-uniform** priors (Reciprocal distribution) para C, gamma, max_depth

```python
from scipy.stats import reciprocal
param_grid = {'C': reciprocal(1e-3, 1e3), 'gamma': reciprocal(1e-4, 1e-1)}
rs = RandomizedSearchCV(SVC(), param_grid,
                        cv=PurgedKFold(n_splits=5, t1=t1),
                        scoring='neg_log_loss', n_iter=100)
```

---

### 3.12 Hierarchical Risk Parity — HRP (Cap 16)

**3 stages:**
1. **Tree clustering:** matriz de correlação → distance d_{ij} = √(0.5(1−ρ_{ij})) → linkage (single linkage típico)
2. **Quasi-diagonalization:** reordena covariância seguindo a hierarquia — clusters relacionados ficam adjacentes
3. **Recursive bisection:** divide o cluster ao meio, aloca peso inverso à variância de cada metade, desce recursivamente

**Vantagens vs Markowitz:** não precisa inverter Σ (funciona em singular), pesos mais estáveis OOS, sem concentração extrema.

**Para CoinEx (multi-par futuro):** quando pipeline operar 5+ pares simultaneamente, HRP define alocação inicial. Para 1 par (BTC) só, HRP é irrelevante.

**Limitação real:** em mercados muito direcionais (bull crypto 2021), inverse-variance simples vence HRP. Comparar baseline antes de adotar.

---

### 3.13 Strategy Risk Pricing (Cap 15)

Estratégia binária com:
- p = prob de win, π⁺ = profit per win, π⁻ = loss per loss, n = bets/year

$$E[\text{annual}] = n \cdot [p \pi^+ - (1-p)\pi^-]$$

$$\sigma[\text{annual}]^2 = n \cdot [(\pi^+ + \pi^-)^2 \cdot p(1-p)]$$

Breakeven probability p* (Sharpe = θ):

$$p^* = \frac{\theta^2 + n \pm \sqrt{n}\theta\sqrt{4 + \theta^2/n - n}}{2(\theta^2 + n)}$$

Útil para responder: "operando 100 trades/ano com RR 1:5, qual hit rate mínimo para Sharpe ≥ 1?" → ~24%.

---

### 3.14 Bet Sizing — Kelly + Sigmoid (Cap 10)

**Kelly clássico:** f* = p − (1−p)/b (b = odds payoff). Problema: explode para 100% se você confia muito; super-bet em regime change.

**LdP sigmoid bet sizing:**
1. Modelo dá probabilidade p ∈ (0,1)
2. Test statistic: z = (p − 0.5) / √(p(1−p)) — Wald z-stat de "p ≠ 0.5"
3. Bet size: m = 2 · Φ(z) − 1 ∈ (−1, +1)
4. **Discretization:** arredonda m para múltiplos de step (e.g. 0.1) → reduz churn

**Para CoinEx:** 1% fixo atual é Kelly fraction sub-ótimo. Migrar para:

```
position_size = base_risk × m
base_risk = 1% (cap mantido como hard limit)
```

Exemplos:
- meta-label p=0.55 → z≈0.2, m≈0.16 → **0.16% risk**
- meta-label p=0.75 → z≈1.15, m≈0.75 → **0.75% risk**

---

### 3.15 Microstructural Features (Cap 19)

| Feature | Fórmula | Intuição |
|---|---|---|
| **Kyle's λ** | OLS: Δp_t = λ · OF_t + ε; OF = signed volume | Price impact por dollar tradeded; alto λ = liquidez baixa |
| **Amihud illiquidity** | \|r_t\| / V_t (dollar) | Quantos % move por $1M; barato de calcular, padrão |
| **VPIN** | Σ\|V_τ⁺ − V_τ⁻\| / (n · V) sobre volume buckets | Toxicidade do order flow; spike = informed trading |
| **Hasbrouck λ** | regressão de Δp em √(volume) | Variant de Kyle com não-linearidade |
| **Corwin-Schultz spread** | 2(e^α − 1)/(1 + e^α), α de high-low | Bid-ask spread estimado de OHLC |

**Para crypto:**
- **VPIN** sobre order book L2 da CoinEx é poderoso — prediz volatilidade 5-15min antes
- **Amihud** em dollar bars dá liquidez ranking para GemScan

---

## 4. Obras posteriores ao AFML

### 4.1 Machine Learning for Asset Managers (2020, Cambridge Elements)

**152 pp, 8 capítulos.** Versão condensada e atualizada com foco em buy-side institucional.

| Cap | Tópico |
|---|---|
| 2 | Denoising covariance via Random Matrix Theory (Marchenko-Pastur) |
| 3 | Distance metrics (correlation, mutual information, VI) |
| 4 | Clustering (**ONC — Optimal Number of Clusters**) |
| 5 | Financial labeling (recap triple barrier + trend-scanning) |
| 6 | Feature importance + **MDI/MDA clustered** |
| 7 | Portfolio construction (**NCO — Nested Clustered Optimization**, upgrade do HRP) |
| 8 | Testing for multiple comparisons (FWER, FDR, DSR, FFE) |

**Diferenças vs AFML:** menos código, mais foco em allocation/risk; introduz **NCO** (mais robusto que HRP); enfatiza causal vs association no cap 1.

---

### 4.2 Causal Factor Investing (2023, Cambridge Elements)

**Tese central:** o factor zoo (300+ factors publicados) é majoritariamente **associational, não causal** — daí o crash OOS sistemático.

| Caps | Conteúdo |
|---|---|
| 1-2 | Distinção association vs causation, philosophy of science (Pearl, Hill criteria) |
| 3-5 | Causal inference em finance — DAGs, do-calculus, backdoor/frontdoor, instrumental variables |
| 6 | Common biases — **confounding**, **collider bias**, selection |
| 7 | Factor mirage — por que Fama-French ainda funciona como descrição mas falha como predição em regime change |

**Para CoinEx:** revisar narrativas como "DXY ↓ → BTC ↑". Existe confounder (Fed liquidity)? Collider (sample só de bull markets)? DAG explícito.

---

### 4.3 Papers principais (com peso)

| Paper | Ano | Vehicle | Conceito-chave |
|---|---|---|---|
| The Probability of Backtest Overfitting | 2014 | J. Computational Finance | CSCV, PBO |
| Deflating the Sharpe Ratio | 2014 | working | MinTRL, PSR |
| The Deflated Sharpe Ratio | 2014 | JPM | DSR fórmula completa |
| Building Diversified Portfolios | 2016 | JPM | HRP |
| Solving Optimal Trading Trajectory (D-Wave) | 2016 | IEEE | QUBO multi-period portfolio |
| The 10 Reasons Most ML Funds Fail | 2018 | JPM | Sisyphus, integer differentiation, chronological sampling |
| Detection of False Investment Strategies | 2019 | Quantitative Finance | ONC clustering + FWER |
| Tactical Investment Algorithms | 2019 | SSRN | Walk-forward vs resampling vs Monte Carlo |
| A Robust Estimator of Efficient Frontier | 2019 | SSRN | NCO |
| Ranking Empirical Evidence in Finance | 2023 | SSRN | Hierarchy of evidence (RCT > causal > associational) |
| How to Use the Sharpe Ratio | 2024+ | SSRN | Updated SR guidance |

---

### 4.4 Quantum portfolio research

Pioneer com Rosenberg et al. 2016 (D-Wave), depois publicou em 2022 com Phys. Rev. Research em **dynamic portfolio optimization** com quantum annealing + tensor networks.

**Aplicabilidade para crypto retail = zero hoje** (acesso restrito, problema overkill para <10 assets), mas vale conhecer existência.

---

## 5. Implementações open-source

### 5.1 mlfinlab (Hudson & Thames)

**Estado:** módulos que eram open-source viraram **commercial** ($300+/yr) em 2022 sob modelo "Unlocking the Commons". O fork 1.5.0 público ainda cobre:

- Data structures (info-driven bars)
- Labeling (triple barrier, meta-labeling, trend scanning)
- Sample weights + sequential bootstrap
- Frac-diff
- Feature importance (MDI/MDA/SFI + clustered)
- Cross-validation (PurgedKFold, CPCV)
- Bet sizing (sigmoid + EF3M)
- Backtest statistics (PBO, DSR)
- Portfolio (HRP, NCO)

Repo: [github.com/hudson-and-thames/mlfinlab](https://github.com/hudson-and-thames/mlfinlab)

### 5.2 Outros repos notáveis

- **boyboi86/AFML** — soluções dos exercícios chapter-by-chapter
- **emoen/Machine-Learning-for-Asset-Managers** — implementação do MLAM 2020
- **charlesrambo/advances_in_financial_ML** — rewrite limpo, clarity
- **CanerIrfanoglu/advances_in_ml** — exercícios + chapter summaries
- **firmai/research** — sub-folder AFML com notebooks
- **mrbcuda/pbo** — implementação standalone PBO/CSCV em R
- **enjine-com/mcos** — Monte Carlo Optimization Selection (paper 2019)
- **mlfinpy** — fork comunitário do mlfinlab pré-commercial

### 5.3 Bibliotecas adjacentes

| Lib | Função | Integração AFML |
|---|---|---|
| **pyfolio** | Tear-sheet, factor exposure | Plug DSR aqui pós-backtest |
| **vectorbt** | Backtest vectorized | Aceita custom CV — wrap PurgedKFold |
| **backtesting.py** | Event-driven backtest | Sample bars não-time customizáveis |
| **skfolio** | Portfolio optim moderno | `CombinatorialPurgedCV` nativo |
| **riskfolio-lib** | HRP, HERC, NCO | Implementa LdP allocators |
| **Optuna** | HPO | Combina com PurgedKFold via pruner customizado |

### 5.4 Datasets recomendados

- **TickData/Kibot** — equity tick history (pago, $$$$)
- **CoinAPI / Tardis.dev** — crypto tick L1/L2 multi-exchange
- **Binance Vision** — gratuito, OHLCV + agg trades, listing-onward
- **CoinEx WebSocket** — primário para este projeto, deve sair pra `lakehouse/` local

---

## 6. Críticas e limites (honestidade brutal)

1. **Replicabilidade dos exemplos é seletiva.** Vários reviewers (Reasonable Deviations, Quant SE) notam que os snippets do livro requerem fix-ups; resultados dos exercises não batem ao primeiro try. O ônus de prova fica no leitor.

2. **Meta-labeling não é silver bullet.** Casos documentados de degradação quando M1 já é precisão alta ou amostra pequena. F1 melhora ≠ PnL melhora dado custo de não-execução.

3. **PBO/DSR conservadores demais para crypto?** DSR assume retornos próximos a normais com ajuste skew/kurt; crypto tem fat tail extremo (kurt > 20). DSR pode rejeitar estratégias reais; mas inversão também é verdade — pode aceitar coisa que era sorte. **Validar com bootstrap não-paramétrico em paralelo.**

4. **HRP/NCO em poucos assets.** O algoritmo brilha em 50+ assets; em 5-10 pares crypto, inverse-variance simples performa comparável com 10% do overhead.

5. **Cross-asset / cross-exchange:** AFML é silent sobre arbitragem cross-venue, perpetual funding rates, basis trades — toda a microestrutura única de crypto perp.

6. **Era pré-transformer.** LdP escreveu pre-2018, em árvores. LLM features (sentiment, news embeddings), state space models (S4/Mamba) não aparecem. A filosofia (frac-diff, CPCV, DSR) é agnóstica ao model class — mas o stack code é tree-centric.

7. **Custo computacional CPCV.** N=10, k=3 → 120 paths → 120 trainos. Em deep learning isso é proibitivo. Mitigar com N pequeno + ensemble shallow.

8. **Causal Factor Investing é programa de pesquisa, não toolkit.** Cap 2023 propõe DAGs e do-calculus, mas operacionalizar em trade real é open problem.

9. **LdP é fund manager + acadêmico** — auto-citação heavy, e suas conclusões servem aos produtos do ADIA/True Positive. Não compromete a matemática, mas vale ceticismo sobre tom evangélico de meta-labeling.

10. **Ground truth em finance é frágil.** Mesmo com CPCV + DSR + PBO, você ainda está olhando 1 path histórico do mundo. Critério Druckenmiller ("posso defender essa thesis em 30 segundos?") segue sendo necessário.

---

## 7. Mapping direto pros gaps do CoinEx AI Agent

| Gap atual | AFML cap/técnica | Caminho de implementação |
|---|---|---|
| **DSR ausente** | Cap 14 + JPM 2014 | Calcular skew/kurt dos R-multiples; pegar N = combos testados (regime × dow × side); reportar DSR junto de SR no backtest report. Threshold = 0.95. ~50 linhas Python. |
| **Walk-forward simples (FAIL_OVERFIT)** | Cap 7 (Purged) + Cap 12 (CPCV) | Substituir train/holdout por `PurgedKFold(k=5, embargo=0.01·T)`. Fase 2: CPCV com N=10, k=2 sobre 14y BTC → 45 paths → distribuição de Sharpe. Cross-halving via groupby ano-halving. |
| **Feature importance ausente** | Cap 8 (MDA/MDI/SFI) | Rodar **SFI** primeiro (sem substitution effect) nas features do score atual (RSI_1h, ADX, BB_width, dow, regime). Depois clustered MDA para confirmar. Drop features com SFI < threshold. |
| **Train/holdout (FAIL_OVERFIT histórico)** | Cap 11 (PBO/CSCV) | Calcular PBO sobre os 100+ sub-setups testados. Se PBO > 0.5, descartar "ganhador" como seleção. `mrbcuda/pbo` como referência. |
| **1% fixo (não Kelly)** | Cap 10 (sigmoid bet sizing) | Treinar meta-label binário (win/loss via triple barrier). Output Pr(win). Sizing = cap_1% × (2Φ(z) − 1). Step discretize 0.1. Inicialmente: gate em p > 0.55. |
| **Time bars 14y backtest** | Cap 2 (info-driven bars) | Se tem volume → dollar bars de $50M para BTCUSDT. Re-rodar score em dollar bars. Comparar estatísticas (skew, kurt, autocorrelation lag-1). |
| **Sharpe BTC-denominated ausente** | Cap 14 / 15 | Calcular retornos em BTC (não USD): r_BTC = r_USD − r_BTC_USD. Sharpe_BTC mede edge real vs HODL. |
| **Frac-diff features** | Cap 5 | Substituir features de log-return puro por log-price frac-diff com d* via ADF scan. Aplicar a BTC, ETH, ratio BTC/ETH. |
| **Sample weights** | Cap 4 | Triple-barrier events com t1 explícito → compute uniqueness → fit do M2 com sample_weight ponderado. Imediato uma vez triple-barrier rodando. |
| **Multi-par allocation (futuro)** | Cap 16 (HRP/NCO) | Quando >5 pares ativos: HRP semanal sobre matriz de retornos. Comparar com inverse-vol baseline. |
| **Multiple-testing (whitelist v2)** | False Strategies 2019 + DSR | ONC para clusterizar sub-setups; FWER controlado; reporta "trials efetivos" — sua whitelist v2 que sobreviveu 11k trades cross-period merece esse benchmark. |

---

## 8. Plano de absorção em 4 fases

### Fase 1 — Statistical Hygiene (2 semanas, ROI máximo)

- [ ] Implementar **DSR** no backtest report (sklearn-style metric)
- [ ] Calcular **SR_BTC-denominated** paralelo a SR_USD
- [ ] Rodar **PBO/CSCV** sobre os 100 sub-setups da whitelist v2 → confirma/rejeita strict_v2
- [ ] Adicionar **PurgedKFold** no signal_generator (precisa de t1 via triple barrier? senão adicionar)

**Decisão:** se PBO > 0.5 ou DSR < 0.9 → voltar pra prancheta. Se passa → Fase 2.

### Fase 2 — Feature Engineering (4 semanas)

- [ ] Implementar **dollar bars** sobre BTCUSDT 14y (precisa volume — checar dataset atual)
- [ ] **Frac-diff scan**: para BTC log-price, ETH, BTC dominance, DXY → encontrar d* por série
- [ ] **SFI** nas features atuais (RSI_1h, ADX, BB_width, dominance, dow, regime_score) → drop features SFI < cutoff
- [ ] Adicionar **microestrutura**: Amihud illiquidity, Kyle's λ proxy (se tem volume signed via tick rule)

**Decisão:** features sobreviventes vão pro pipeline.

### Fase 3 — Meta-Labeling + Sizing (3 semanas)

- [ ] M1 atual = whitelist v2 (regra-based). **M2 = LightGBM** treinado em features (Fase 2) + label triple-barrier (já existente como PT/SL)
- [ ] **Sample weights via uniqueness**; sequential bootstrap se concurrency > 1.5
- [ ] **Sigmoid bet sizing**: substitui 1% fixo por scaled. Cap em 1% mantido como hard limit
- [ ] **Backtest com CPCV** (N=10, k=2 → 45 paths). DSR ≥ 0.95 obrigatório pra promotion live

**Decisão:** vai pra paper trade 30 dias com sizing dinâmico.

### Fase 4 — Multi-par + Causal (8+ semanas, opcional pós-validation)

- [ ] Expansão pra 5-10 pares; **HRP allocation** semanal
- [ ] **DAG explícito** das hipóteses (DXY → BTC, dominance → alts, halving → cycle); identificar confounders
- [ ] **NCO** quando portfolio > 10 ativos
- [ ] Quantum (D-Wave) só se sair do hobby — irrelevante <20 ativos

---

## 9. Hierarquia de evidência (LdP 2023)

| Tier | Tipo de evidência | Crypto exemplo |
|---|---|---|
| **A+** | Randomized Controlled Trial | Inexistente em finanças (não há grupo controle) |
| **A** | Causal inference (DAGs, IV, do-calculus) | Halving → supply shock (causal estrutural) |
| **B+** | Quasi-experimental (DiD, regression discontinuity) | ETF approval 2024 como cutoff |
| **B** | Robust association (out-of-sample, multiple regimes) | BULL_STRONG LONG validado cross-period 14y |
| **C** | Association in-sample (factor zoo) | Maior parte dos "edges" técnicos publicados |
| **D** | Anedote, single backtest | Maior parte do crypto-Twitter |

**Para o CoinEx Agent:** trabalhar em **tier B com aspirações a A** via Causal Factor Investing (Fase 4).

---

## 10. Referências

### Livros
- **AFML** — Wiley 2018 [link Wiley](https://www.wiley.com/en-us/Advances+in+Financial+Machine+Learning-p-9781119482086)
- **MLAM** — Cambridge 2020 [link Cambridge](https://www.cambridge.org/core/books/machine-learning-for-asset-managers/6D9211305EA2E425D33A9F38D0AE3545)
- **Causal Factor Investing** — Cambridge 2023 [link Cambridge](https://www.cambridge.org/core/books/causal-factor-investing/9AFE270D7099B787B8FD4F4CBADE0C6E)

### Papers
- [DSR paper](https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf) — Bailey, López de Prado JPM 2014
- [PBO paper](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf) — Bailey, Borwein, López de Prado, Zhu 2014
- [10 Reasons ML Funds Fail SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3104816)
- [Tactical Investment Algorithms SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3459866)
- [Robust Efficient Frontier (NCO) SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3469961)
- [False Strategies Unsupervised SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3167017)
- [HRP SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2708678)
- [MLAM Cap 1 SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3558728)
- [Causal Factor Investing SSRN](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4205613)

### Sites oficiais
- [LdP Vita](https://www.quantresearch.org/Vita.htm)
- [LdP Innovations](https://www.quantresearch.org/Innovations.htm)
- [LdP SSRN author page](https://papers.ssrn.com/sol3/cf_dev/AbsByAuth.cfm?per_id=434076)
- [Cornell profile](https://www.duffield.cornell.edu/people/marcos-lopez-de-prado/)
- [True Positive Technologies](https://www.truepositive.com/leadership)

### Open source
- [mlfinlab repo](https://github.com/hudson-and-thames/mlfinlab)
- [Hudson & Thames docs](https://hudsonthames.org/)
- [skfolio](https://skfolio.org/)
- [riskfolio-lib](https://riskfolio-lib.readthedocs.io/)

### Tutoriais e notas
- [Reasonable Deviations — AFML notes](https://reasonabledeviations.com/notes/adv_fin_ml/)
- [Hudson & Thames — frac diff](https://hudsonthames.org/fractional-differentiation/)
- [Hudson & Thames — sequential bootstrap](https://hudsonthames.org/bagging-in-financial-machine-learning-sequential-bootstrapping-python/)
- [Hudson & Thames — meta-labeling triple barrier](https://hudsonthames.org/does-meta-labeling-add-to-signal-efficacy-triple-barrier-method/)
- [Quantreo — triple barrier](https://www.newsletter.quantreo.com/p/the-triple-barrier-labeling-of-marco)
- [Quantbeckman — CPCV with code](https://www.quantbeckman.com/p/with-code-combinatorial-purged-cross)
- [Sefidian — info-driven bars](https://www.sefidian.com/2021/06/12/introduction-to-advanced-candlesticks-in-finance-tick-bars-dollar-bars-volume-bars-and-imbalance-bars/)
