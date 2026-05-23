# Market Timing — Referência Canônica (BRT São Paulo)

> **Referência permanente** para decisões de trade, re-validação, scans e backtests.
> Usada por `lib_market_context_engine.ps1` como base dos 6 fatores de contexto.
> Atualizada quando regime macro muda significativamente.

---

## 1. Sessões globais (BRT — São Paulo UTC-3)

| Sessão | Abertura BRT | Fechamento BRT | Característica |
|---|---|---|---|
| **Sydney** | 19h | 04h | Início Ásia, vol baixo |
| **Tokyo (Ásia)** | 21h | 06h | Bots Ásia + retail JP/KR |
| **Hong Kong / China** | 22h | 07h | Pico Ásia, manipulation alta |
| **Londres (UK)** | 04h | 13h | Institucional EU |
| **New York (US)** | **09h30** | **16h** | NYSE — maior volume mundial |
| **Overlap London-NY** | **09h30-13h** | (3.5h) | 🏆 GOLDEN HOURS — maior volume crypto |

### Session factor por janela BRT

| Janela BRT | Vol relativo | session_factor |
|---|---|---|
| **09h-13h** (golden) | 100% | **1.0** |
| **13h-16h** (NY only) | 85% | 0.9 |
| **16h-19h** (US close transition) | 50% | 0.7 |
| **19h-22h** (Sydney/Tokyo early) | 35% | 0.5 |
| **22h-02h** (Asia pico) | 60% | 0.6 (stop hunts overnight) |
| **02h-04h** (Asia close) | 25% | 0.4 |
| **04h-09h** (London open) | 70% | 0.8 |

---

## 2. SP500 / macro events (BRT)

Correlação BTC/SP500: 0.1 (2017) → **0.6+ (2024)** com ETFs.

| Evento | Frequência | BRT | macro_factor |
|---|---|---|---|
| **FOMC** | 8×/ano | 15h00 | 0.0 dia ±24h |
| **CPI US** | mensal (dia 10-15) | 09h30 | 0.3 dia |
| **NFP** | 1ª sexta do mês | 09h30 | 0.4 dia |
| **NYSE Open** | diário | 10h30 | (normal) |
| **NYSE Close** | diário | 16h00 | (normal) |

### Calendário FOMC 2026 (hardcoded — atualizar 2027)

- 28 Jan 2026
- 18 Mar 2026
- 29 Abr 2026 (☑ passou)
- 17 Jun 2026
- 29 Jul 2026
- 16 Set 2026
- 28 Out 2026
- 09 Dez 2026

---

## 3. Sazonalidade BTC (2013-2024 backtest)

### Retorno médio mensal

| Mês | Retorno % | Bias |
|---|---|---|
| **Janeiro** | +5.1% | 🟢 |
| Fevereiro | +13.6% | 🟢 alto |
| Março | +4.8% | 🟢 |
| Abril | +13.3% | 🟢 (pós halving particularly) |
| **Maio** | **-3.8%** | 🔴 ruim |
| Junho | -1.4% | 🔴 |
| Julho | +9.8% | 🟢 recovery |
| Agosto | -3.0% | 🔴 |
| **Setembro** | **-7.1%** | 🔴 PIOR mês |
| **Outubro** | +21.0% | 🟢 recovery brutal |
| **Novembro** | **+42.4%** | 🟢🟢 MELHOR mês |
| Dezembro | +5.6% | 🟢 |

### Resumo Sell in May (válido)

| Período | Retorno médio mensal |
|---|---|
| Maio-Outubro | +1.2%/mês |
| **Novembro-Abril** | **+11.4%/mês** ← 10× melhor |

### season_factor por mês

```
mes_factor = {
  1: 1.2,   # Jan bull recovery
  2: 1.3,   # Feb alto
  3: 1.1,   # Mar
  4: 1.4,   # Apr halving bias
  5: 0.5,   # May Sell-in-May
  6: 0.6,   # Jun continuation bear
  7: 1.1,   # Jul recovery
  8: 0.7,   # Aug summer doldrums
  9: 0.4,   # Sep worst month
  10: 1.3,  # Oct recovery
  11: 1.5,  # Nov best month
  12: 1.0   # Dec mixed
}
```

---

## 4. Day of Week (validated 14y BTC)

```
Mon  +0.55%   ✅ melhor          dow_factor = 1.2
Tue  +0.31%                     dow_factor = 1.0
Wed  +0.10%                     dow_factor = 0.9
Thu  -0.16%   ❌ pior            dow_factor = 0.4 (Block LONG)
Fri  +0.21%                     dow_factor = 1.0
Sat  -0.08%   weekend (low vol) dow_factor = 0.7
Sun  +0.18%                     dow_factor = 0.8
```

p-value 0.0068 — estatisticamente significativo.

---

## 5. Halving cycles BTC

| Halving | Data | Peak bull | Bottom bear | Lag peak |
|---|---|---|---|---|
| 1º | nov 2012 | nov 2013 ($1.1k) | jan 2015 ($170) | ~12m |
| 2º | jul 2016 | dez 2017 ($19.7k) | dez 2018 ($3.2k) | ~17m |
| 3º | mai 2020 | nov 2021 ($69k) | nov 2022 ($15.5k) | ~18m |
| **4º** | **abr 2024** | **? Q4 2025 - Q1 2026** | ? Q4 2026 - Q1 2027 | esperado ~18m |

### Bull/Bear cycle anatomy

```
HALVING -> Mês 0-6:   lateralização + acumulação    halving_factor = 0.8
        -> Mês 6-12:  bull primário (50-100%)       halving_factor = 1.3
        -> Mês 12-18: bull blow-off (manias, alts)  halving_factor = 1.5
        -> Mês 18-24: distribuição + topo           halving_factor = 0.7
        -> Mês 24-36: bear (-70 a -85%)             halving_factor = 0.3
        -> Mês 36+:   acumulação pré-next-halving   halving_factor = 0.5
```

**Estamos em mês 24** pós-halving 2024 (Maio 2026, ~24.93 meses corridos). **halving_factor atual = 0.7** (distribuição/topo).

Caveat: ciclo 4 estendido por ETFs. Peak provável Q4 2025 ou Q1 2026 já passou. Pode ter outro test em Q3 2026 se ETF flow voltar.

**Implicação prática:** sistema deve ficar defensivo de Maio 2026 em diante até reset cycle ou novo halving (2028).

---

## 6. Regime factor (via apply_regime_filter)

```
BULL_STRONG       regime_factor = 1.5
BULL_WEAK         regime_factor = 1.0
TRANSITION_UP     regime_factor = 1.2
SIDEWAYS          regime_factor = 0.5
TRANSITION_DOWN   regime_factor = 0.3
BEAR_WEAK         regime_factor = 0.2
BEAR_STRONG       regime_factor = 0.0
CAPITULATION      regime_factor = 0.0
```

---

## Context Score (produto final)

```
CONTEXT_SCORE = dow_factor × season_factor × halving_factor × session_factor × macro_factor × regime_factor

Decisão:
  CONTEXT < 0.20 → BLOCK trade
  CONTEXT 0.20-0.50 → PAPER only
  CONTEXT 0.50-1.00 → LIVE size reduzido (50-100%)
  CONTEXT 1.00+ → LIVE size cheio (cap LIVE_MAX_SIZE_USD × min(2.0, CONTEXT))
```

### Exemplos práticos

| Cenário | DoW | Mês | Halv | Sess | Macro | Reg | CONTEXT | Decisão |
|---|---|---|---|---|---|---|---|---|
| Mon 11h Maio mês13 BULL_STRONG | 1.2 | 0.5 | 1.5 | 1.0 | 1.0 | 1.5 | **1.35** | LIVE FULL |
| Thu 03h Setembro mês25 BEAR | 0.4 | 0.4 | 0.3 | 0.4 | 1.0 | 0.2 | **0.004** | BLOCK |
| Wed 10h FOMC day Nov mês12 BULL_STRONG | 0.9 | 1.5 | 1.3 | 1.0 | **0.0** | 1.5 | **0.0** | BLOCK (FOMC) |
| Sun 22h Nov mês12 BULL_STRONG | 0.8 | 1.5 | 1.3 | 0.6 | 1.0 | 1.5 | **1.40** | LIVE FULL |
| Tue 11h Maio mês13 SIDEWAYS | 1.0 | 0.5 | 1.5 | 1.0 | 1.0 | 0.5 | **0.38** | PAPER only |

---

## TL;DR atual (Maio 2026)

1. **Mês pior do ano** (Sell in May, season_factor 0.5)
2. **Mês 24 pós-halving** = território distribuição/topo (halving_factor 0.7)
3. **BTC -30% do peak** = bear pull típico OU início de bear secular (ainda dúvida)
4. **Sistema deve ficar defensivo** — context_score Mon May 11h BULL_STRONG = **0.63** = LIVE_REDUCED
5. **Janelas ótimas trade:** Outubro-Abril, Mon-Wed, 09h-13h BRT, longe FOMC ±2 dias
6. **Próximo bull window:** Out/Nov 2026 (mês 30-31 — bear cycle clássico) OU 2028 pós-próximo halving

---

## Atualização da referência

Quando atualizar:
- **Anual**: calendário FOMC do ano novo
- **Pós-halving**: re-calibrar halving_factor curve (cada 4 anos)
- **Mudança estrutural**: se correlação SP500-BTC cair abaixo 0.3 ou subir acima 0.8
- **Sazonalidade**: a cada 3-5 anos validar com novo backtest
