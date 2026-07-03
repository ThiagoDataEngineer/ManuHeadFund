# UNIVERSE_PHYSICS.md — A Física do Universo CoinEx (derivada de dados)

> Estudo empírico 2026-07-03: 921 pares spot USDT, frames 15m→anual.
> Scripts: `backtest/universe_pump_study.py` + `backtest/universe_tf_study.py` (reproduzível).
> Datasets: `backtest/data/universe_*.csv`. NÃO é opinião — cada número foi medido.

---

## As 4 Leis (estrutura temporal completa)

```
ESCALA           FORÇA DOMINANTE          IMPLICAÇÃO OPERACIONAL
minutos–1h       MOMENTUM (cauda +)       LONG só aqui: ignição intraday
4h–1 semana      MEAN-REVERSION           SHORT pós-pump: o reino do edge
semanas–meses    DRIFT NEGATIVO (bear)    nunca hold microcap além de dias
anos             SANGRIA ESTRUTURAL       hold = -41%/ano mediano (survivors!)
```

### Lei 1 — Dissipação (fractal de 15m a 1 semana)
Quanto maior o candle de alta, mais negativo o candle seguinte. Monotônica em TODAS as escalas:
```
15m >10%  → -0.50% mediana (média +0.53 ← cauda de momentum VIVA)
30m >15%  → -1.01% (média +0.28, cauda viva)
1h  >20%  → -2.15% (média +0.71, cauda viva)
4h  >25%  → -4.50% (média -3.43 ← cauda MORTA)
1d  >50%  → -13.8%
1w  >100% → -10.9%
```
**Momentum sobrevive <4h. De 4h em diante, só dissipação.** Pump diário +30%:
D+1 cai em 70% dos casos, mediana -8.3% (n=635). Em onda alta (W↑): -10.2%, 72%.

### Lei 2 — Assimetria (short > long estruturalmente)
Pós-dump diário <-30%: mediana AINDA negativa (-4.4%) — bounce é loteria de cauda.
Pós-pump: reversão confiável. Knife-catching não paga; fade-the-pump paga.
Bounce existe APENAS em 4h (<-15% → +0.37% mediana) e não cobre fees sem seleção.

### Lei 3 — W(t): temperatura do universo
`W(t) = EWMA(pump_rate diário, meia-vida 2d)` — corr +0.56 com pump-rate de amanhã.
Quartil FERVENDO = 2.1x pumps do frio. Ondas de 2-3 dias (AC1 +0.60).
BTC↑1% dia = 13.8 pumps; BTC↓1% = 7.8. Dia da semana: irrelevante.
**Em W alto, a reversão pós-pump é MAIS forte (-10.2% vs -7.9%)** — W amplifica o short.

### Lei 4 — Drift estrutural (o custo de segurar)
```
2023: +15.7%/mês mediana (bull)    2025: -13.2%/mês
2024:  -5.4%/mês                   2026:  -7.4%/mês
```
Retorno ANUAL mediano dos pares 12m+: **-41% | só 30% dos anos positivos** —
e isso é SÓ SOBREVIVENTES (deslistados nem aparecem na amostra; real é pior).
Mensal: mediana negativa em TODOS os bins de retorno anterior (não há bin de compra).
Sazonalidade calendário: fraca/instável com 2.7 anos; o REGIME do ano domina o mês.

---

## Anatomia da ignição (1h, n=663 ignições ret≥10% vol≥3x)

- **Horário**: pico 12h BRT (15 UTC); faixa quente 05h–14h BRT; vale 19h–23h BRT
- **Aviso pré-ignição: 1–2 HORAS apenas.** H-1: ret +0.84%, vol 1.26x (vs 0.89x normal).
  Antes de H-2: indistinguível de par normal. POR ISSO fingerprint diária não existe.
  Requisito p/ capturar LONG: scan ≤30min nos pares certos nas horas quentes.
- **Pós-ignição**: ressaca começa em h+1 (mediana -1.21%), acumula -6% em 12h.
  MAS: 46% dos casos o high de h+1 alcança +5% → janela de SAÍDA de ~1h p/ quem já está dentro.
- Tendência (EMA diária): pumps nascem 2.5x mais em uptrend, MAS revertem IGUAL/mais.
  Tendência = screening de universo (watchlist), NUNCA veto do sinal pós-pump.

## Fingerprint da véspera (diário)

- PUMP: não existe sinal diário acionável (melhor regra: lift 3x com mediana D0 negativa).
- DUMP: **pump ontem ≥30% → P(dump -20%) = 17.6% (lift 33x)**; +upwick≥5% → 12.4% (23x).
- Volume clímax (>5x) hoje → amanhã -2.9% a -3.7%. Volume extremo = sinal de short, não de entrada.

## Fórmula linear (OLS, n=75k, coefs direcionais)

```
E[ret D+1] ≈ +0.66 − 0.51·(pump/10) − 0.48·(upwick/10) − 0.63·ln(1+vol_ratio)
             − 0.27·(dump/10) + 0.19·W_z
```

---

## Implicações de design (deriváveis, ainda NÃO implementadas)

1. SHORT pós-pump ≥30% é o sinal nº1 do universo (70% win, ~5 candidatos/dia, fractal)
2. LONG só intraday: janela 05-14 BRT + scan ≤30min + assinatura H-1 (vol 1.26x acelerando)
3. Time-stop obrigatório em qualquer LONG de microcap (drift come a posição em dias)
4. W(t) como regime-amplificador: onda alta = mais shorts e mais agressivos
5. Tendência/Tori: watchlist p/ LONG; jamais veto do sinal mean-reversion
6. Hold spot de microcap em bear = -41%/ano esperado (mediana, survivors)
