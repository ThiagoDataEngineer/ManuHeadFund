# ESTUDO: Gates SHORT em BEAR (item 3) — 2026-07-03

> Mesa: HeadFund auditor (López de Prado/Simons) + risk officer + benchmark research.
> Método: anatomia do gate → counterfactual com preços reais → knowledge → benchmark → veredicto.
> Gatilho: learning engine 08:11 flagou 6 gates "custando oportunidade" em SHORT|BEAR.

---

## Dados-base

- `journal/signal_snapshots.jsonl`: 2.046 snapshots (1.907 VETAR / 139 APROVAR)
- Counterfactual próprio: veto → candles diários reais (CoinEx) → o que aconteceu D+1/D+2
- Nota metodológica: o "costly" do learning engine (missed_rate ≥50%, n≥8) avalia no
  MELHOR momento pós-veto; nosso estudo usa fechamento D+1/D+2 (honesto) + touch intrabar.

---

## Gate 1: rr|SHORT — VEREDICTO: **BUG DE PIPELINE, CORRIGIDO**

**Anatomia:** os vetos rr|SHORT diziam "target=1.80 ACIMA do entry=1.64 — R:R invertido".
100% dos casos examinados eram setups construídos como LONG e depois flipados pra SHORT
pelo auto-select de regime (scan_master ~linha 522) **sem recalcular stop/target**.

**Não era gate ruim — o gate estava CERTO em vetar setups matematicamente inválidos.**
O defeito estava upstream.

**Fix aplicado:** no ponto do flip LONG→SHORT, espelha stop/target em volta do entry
preservando as distâncias (R:R igual). Log: "GEM setup espelhado p/ SHORT".

---

## Gate 2: fqs|SHORT — VEREDICTO: **FÍSICA INVERTIDA, EXCEÇÃO DIRECIONAL**

**Anatomia:** SHORTs vetados por "FQS=1/7 AVOID eliminatório" ou "FQS indisponível".
FQS mede QUALIDADE de tokenomics — existe pra impedir COMPRA de lixo.

**Física:** para SHORT, fundamentals fracos são A FAVOR (ativo ruim cai mais — coerente
com universe physics lei 4: drift estrutural -41%/ano em microcaps). Vetar um short
porque o ativo é ruim é usar o escudo do LONG contra a lança do SHORT.

**Fix aplicado:** regra 5c no prompt do mentor — FQS baixo nunca aborta SHORT
(vira ponto a favor); FQS indisponível em SHORT = neutro (não bloqueia sozinho).
LONG mantém FQS integral. Mesma classe da exceção do beta (5b).

---

## Gate 3: self_consistency|SHORT — VEREDICTO: **MANTER (dados não suportam relaxar)**

**Anatomia:** mentor roda 2x; ambos VETAR mas magnitudes divergem (HARD_VETO vs ABORTAR)
→ aborta. n=84 vetos SHORT em bear (45 BEAR_WEAK + 39 BEAR_STRONG), 32 únicos (market,dia),
30 avaliáveis com candles.

**Counterfactual (fechamento honesto):**

| Regime | n | win≥3% D+2 | mediana D+2 | tocou TP3% | tocou adverso 3% |
|---|---|---|---|---|---|
| BEAR_WEAK | 9 | **56%** | **+4.9%** | 89% | 22% |
| BEAR_STRONG | 21 | 24% | -0.8% | 62% | **52%** |
| Agregado | 30 | 33% | -0.4% | 70% | — |

- Agregado: edge ~zero no fechamento; cauda -11% (short squeeze USELESSUSDT).
  O "costly ≥50%" do learning engine superestimava (avaliação no melhor momento).
- **Regime split faz sentido físico:** em BEAR_STRONG o mercado já capitulou → short
  atrasado toma bounce (52% tocam adverso); em BEAR_WEAK (moagem) o short trabalha.
- **MAS n=9 em BEAR_WEAK** — López de Prado (cap. 3/10): meta-labeling e gates de
  confiança **degradam com amostra pequena**; effective-N aqui é ainda menor
  (vetos agrupados nos mesmos dias/mercados → correlação amostral).

**Benchmark externo:** literatura de ensemble disagreement trata divergência entre
modelos como sinal de INCERTEZA EPISTÊMICA — abster é a resposta padrão quando o
custo do erro é assimétrico (squeeze -11% > TP +5%). Fundos quant de crypto reportam
squeezes frequentes em altcoins de baixa liquidez e dimensionam leverage por
volatilidade; abster em divergência é prática, não defeito.

**Decisão:** gate MANTIDO. Ação: continuar acumulando counterfactual; revisitar quando
BEAR_WEAK atingir **n≥30 únicos**. Se o padrão 56%/+4.9% se sustentar, a mudança será
downgrade do veto para PAPER (shadow) em BEAR_WEAK — nunca remoção do gate.

---

## Síntese

| Gate | Natureza real | Ação | Risco da ação |
|---|---|---|---|
| rr\|SHORT | Bug (setup LONG flipado) | Espelhar setup no flip ✅ | Nenhum (corrige matemática) |
| fqs\|SHORT | Física invertida | Regra 5c mentor ✅ | Baixo (LONG intacto; SHORT ainda passa por estrutura/regime/R:R/Mesa) |
| self_consistency\|SHORT | Incerteza epistêmica real | Manter; revisitar em n≥30 BEAR_WEAK | — |
| beta\|SHORT (feito antes) | Física invertida | Exceção direcional ✅ (37/37 regressão) | Baixo |

**Princípio consolidado:** gates de QUALIDADE-DO-ATIVO (beta, FQS) protegem LONG e
invertem para SHORT em bear. Gates de QUALIDADE-DA-DECISÃO (self_consistency, Mesa,
R:R válido) protegem ambas as direções e ficam.

## Fontes externas

- López de Prado, Advances in Financial ML (knowledge/LOPEZ_DE_PRADO.md): meta-labeling
  como gate, degradação com amostra pequena, PBO/DSR e fat tails em crypto
- [Crypto Quant Strategies 2026 (Quantt)](https://www.quantt.co.uk/resources/crypto-quant-strategies-2026)
- [Systematic Crypto Hedge Fund (Bluesky Capital)](https://www.blueskycapitalmanagement.com/systematic-crypto/)
- [Short Squeeze em crypto (Gate Wiki)](https://www.gate.com/crypto-wiki/article/short-squeeze-what-it-is-and-how-to-predict-a-bitcoin-short-squeeze-20260112)
- [Crypto chaos jolts hedge funds (InvestmentNews)](https://www.investmentnews.com/alternatives/crypto-chaos-jolts-hedge-funds-in-worst-year-since-2022-crash/263643) — "quant models de altcoin: wipeouts por liquidez"
- [Meta-Labeling Method (Wayland)](https://www.waylandz.com/quant-book-en/Meta-Labeling-Method/)
- [Cross-Model Disagreement as Correctness Signal (arXiv)](https://arxiv.org/html/2603.25450)
