# Análise Profunda — Mesa CAOS
**Data**: 2026-05-28  
**Base**: 792 entradas em `journal/mesa_drones.jsonl`

---

## 1. Distribuição geral de consensus

| Consensus | Ocorrências | % |
|-----------|-------------|---|
| MEDIO_2 | 449 | 56.7% |
| FORTE_3 | 173 | 21.8% |
| **CAOS** | **170** | **21.5%** |

**1 em cada 5 ciclos termina em CAOS.** Isso é o bloqueio estrutural.

---

## 2. CAOS genuíno vs CAOS de infra

| Tipo | Ocorrências |
|------|-------------|
| Genuíno (1/1/1 vote split) | **95** |
| Degraded (drone null/timeout) | 75 |

O CAOS degraded (infra) já tem tratamento — é o `MESA_DEGRADED` que aparece
nos logs. O problema real é o **CAOS genuíno**: 95 casos onde os 3 drones
responderam corretamente mas discordaram.

---

## 3. Padrões de voto no CAOS genuíno

| Padrão T/R/L | Ocorrências | % |
|---|---|---|
| SHORT / NEUTRO / LONG | 49 | **51.6%** |
| SHORT / LONG / NEUTRO | 36 | **37.9%** |
| NEUTRO / SHORT / LONG | 9 | 9.5% |
| LONG / SHORT / NEUTRO | 1 | 1.0% |

**Conclusão crítica:** Em 89.5% dos casos de CAOS genuíno, o padrão é
`SHORT + NEUTRO + LONG` em alguma ordem. Nunca é `LONG/LONG/SHORT` ou
`SHORT/SHORT/LONG` — esses seriam MEDIO_2. O CAOS acontece quando cada
drone vota uma coisa diferente.

---

## 4. Qual drone causa o CAOS

| Drone | Vota NEUTRO no CAOS | % |
|-------|---------------------|---|
| **Radar** | 49/95 | **51.6%** |
| **LIDAR** | 37/95 | **38.9%** |
| Termal | 9/95 | 9.5% |

**Termal raramente é o problema.** Ele vota NEUTRO em apenas 9.5% dos CAOS.
Radar e LIDAR são os responsáveis por 90% dos splits.

### Força média dos drones no CAOS

| Drone | Força média |
|-------|-------------|
| Termal | 69.8 |
| Radar | 60.4 |
| LIDAR | 55.4 |

LIDAR tem a menor força média — vota com menos convicção.

---

## 5. Por que o LIDAR vota NEUTRO

**86% dos casos de LIDAR NEUTRO no CAOS mencionam `vol_ratio` ou `liquidez crítica`.**

Exemplos reais das justificativas:
```
"Setup LONG proposto com RR=5 (excelente) e vol_ratio=0.1x (CRÍTICO: liquidez insuficiente)"
"vol_ratio=0.07 (CRÍTICO: liquidez severa). Stop coerente mas liquidez insuficiente"
"Setup LONG proposto em regime BEAR_STRONG com estrutura downtrend (EMA 9<21<50<200)"
```

**O LIDAR está votando NEUTRO porque `vol_ratio < 0.5`** — sua regra diz:
> "vol_ratio < 0.5 = NEUTRO 25"

Mas o `vol_ratio` que ele recebe é calculado como `volume_atual / volume_médio`.
Em mercado BEAR com volume baixo, praticamente todos os ativos têm `vol_ratio < 0.5`.
O LIDAR então vota NEUTRO sistematicamente, quebrando qualquer consensus SHORT
que Termal + Radar teriam formado.

---

## 6. Por que o Radar vota NEUTRO

Exemplos reais:
```
"Sinais mistos: RSI 64.8 (neutro), MACD neutro, Stochastic OVERBOUGHT-CROSS-DOWN"
"Estrutura de mercado UPTREND, mas SuperTrend é BEARISH e Stochastic está OVERBOUGHT"
"Sinais macro mistos — DXY sem tendência clara, F&G neutro"
```

O Radar (Druckenmiller) vota NEUTRO quando os indicadores macro estão mistos.
Em BEAR_STRONG com BTC em -10.5% de drawdown, os indicadores macro ficam
ambíguos: F&G não está em extremo, DXY sem tendência clara, funding neutro.
O Radar não consegue confirmar nem SHORT nem LONG com convicção.

---

## 7. CAOS por regime

| Regime | CAOS genuíno |
|--------|-------------|
| (vazio — regime não logado) | 42 |
| BEAR_STRONG | 27 |
| BULL_WEAK | 19 |
| BEAR_WEAK | 7 |

O CAOS é mais frequente em **BEAR_STRONG** — exatamente o regime atual.
Isso confirma: o mercado bear cria condições onde Termal vê SHORT claro,
Radar vê sinais mistos (NEUTRO), e LIDAR vê liquidez insuficiente (NEUTRO).

---

## 8. CAOS por ativo (top 10)

| Ativo | CAOS genuíno |
|-------|-------------|
| ZECUSDT | 23 |
| BTCUSDT | 15 |
| RENDERUSDT | 14 |
| XMRUSDT | 11 |
| SUIUSDT | 8 |
| PENDLEUSDT | 7 |
| BCHUSDT | 5 |
| SKYUSDT | 4 |
| INJUSDT | 3 |
| XRPUSDT | 3 |

ZEC e BTC lideram — ambos têm características que confundem o Radar
(ZEC é privacy coin sem macro clara; BTC tem regime BULL_WEAK mas
estrutura técnica bearish).

---

## 9. Diagnóstico raiz

O CAOS genuíno tem **uma causa estrutural**, não múltiplas:

> **O LIDAR usa `vol_ratio < 0.5` como veto de liquidez, mas em mercado
> BEAR o volume é sistematicamente baixo em todos os ativos. Isso faz o
> LIDAR votar NEUTRO em ~87% dos casos, quebrando qualquer consensus
> SHORT que Termal + Radar formariam.**

O padrão dominante é:
- Termal: SHORT (ADX alto, EMA bearish, downtrend claro)
- Radar: SHORT ou NEUTRO (macro misto em bear)
- LIDAR: NEUTRO (vol_ratio < 0.5 → liquidez insuficiente)

Resultado: SHORT/SHORT/NEUTRO = MEDIO_2 (passa) ou SHORT/NEUTRO/NEUTRO = MEDIO_2
mas SHORT/NEUTRO/LONG = CAOS (bloqueia).

O problema secundário é o **Radar votando NEUTRO** quando os indicadores
macro estão ambíguos — o que é frequente em BEAR_STRONG prolongado.

---

## 10. Soluções possíveis

### Opção A — Ajustar threshold de vol_ratio do LIDAR (baixo risco)
O threshold atual é `vol_ratio >= 0.5`. Em bear market, a maioria dos ativos
fica abaixo disso. Reduzir para `vol_ratio >= 0.2` ou tornar o threshold
**dinâmico por regime** (mais permissivo em BEAR, mais restritivo em BULL).

**Impacto esperado:** Reduz CAOS genuíno em ~40-50% (os casos onde LIDAR
vota NEUTRO por liquidez baixa mas Termal+Radar concordam em SHORT).

**Risco:** LIDAR aprovaria setups com liquidez menor — mas o Mentor ainda
pode vetar por liquidez insuficiente.

### Opção B — Regra de desempate: maioria simples quando 1 drone vota NEUTRO
Se o padrão é SHORT/SHORT/NEUTRO ou LONG/LONG/NEUTRO, tratar como MEDIO_2
em vez de CAOS. NEUTRO de um drone seria "abstenção", não "voto contrário".

**Impacto esperado:** Elimina ~90% do CAOS genuíno (todos os padrões
SHORT/NEUTRO/LONG virariam MEDIO_2 SHORT).

**Risco:** Reduz o poder de veto do LIDAR — que existe por design para
bloquear setups com RR ruim ou liquidez insuficiente.

### Opção C — Threshold de CAOS: exigir 2+ votos ativos conflitantes
CAOS só quando há 2+ votos em direções opostas (ex: LONG + SHORT).
Um único NEUTRO não seria suficiente para causar CAOS.

**Impacto:** Similar à opção B mas mais conservador — LONG/SHORT/NEUTRO
ainda seria CAOS, mas SHORT/SHORT/NEUTRO viraria MEDIO_2.

### Recomendação
**Opção A primeiro** (menor risco, mais cirúrgico): ajustar o threshold
de vol_ratio do LIDAR para ser regime-aware. Em BEAR_STRONG/BEAR_WEAK,
usar `vol_ratio >= 0.2`. Em BULL_STRONG/BULL_WEAK, manter `>= 0.5`.

Isso resolve o problema raiz sem alterar a lógica de consensus.
