# Critério de Promoção SHORT observe→live (2026-05-15)

> **Escrito ANTES de coletar dados, para evitar viés de confirmação.**
> Qualquer mudança nesse critério durante a janela de 14d deve ser registrada
> com data, motivo e responsável (= o usuário Thiago).

## Contexto

Backtest 14y BTCUSD (memory `project_strict_v2_validated_14y.md`) refutou shorts em
todos os regimes testados:
- `CAPITULATION SHORT` = -0.734R/trade em ~11k trades cross-period
- `BEAR_STRONG SHORT` = desastre
- `BULL_WEAK SHORT` = quebrado (estrutural)

Whitelist v2 strict_v2 atual: zero células SHORT em LIVE. Regra 5 da
[lib_operational_whitelist.ps1:100-114](../agents/lib_operational_whitelist.ps1#L100-L114)
mantém SHORT em `observe` no paper para coleta de amostras pós-2026.

## Hipótese a testar

**H₁:** "Após calibração Wave 2.5 (regime classifier dinâmico + cascade desbloqueada
+ scanner formula log10), alguma célula `<regime>+SHORT+<dow>` pode emergir com edge
positivo cross-period que o backtest 14y antigo não capturou."

**H₀ (default):** "Shorts continuam sem edge. Whitelist mantém zero células SHORT live."

## Critério quantitativo de promoção observe→live

Para promover uma célula `<regime>+SHORT+<dow>` de observe para live, **TODOS** os
critérios abaixo devem ser atendidos. Não negociar threshold mid-window.

### 1. Sample size
- **N ≥ 30 observations** da célula específica nos 14d.
- Se uma célula tem N<30 ao fim dos 14d, **não decidir** (estende observação, não promove).
- Sample size pequeno = ruído estatístico (intervalo de confiança 95% explodido).

### 2. Expectancy
- **Expectancy_R ≥ +0.40R/trade simulado** considerando:
  - Entry no preço da observação
  - Stop simulado = entry × (1 + ATR_proxy × 1.5) para SHORT
  - Target simulado = entry × (1 - ATR_proxy × 4.5) (R:R 1:3)
  - Outcome = primeiro hit (stop ou target) nas 168 horas subsequentes (7 dias intra-trade)
  - Timeout = -0.1R se não hit em 168h (custo de capital)
- Comparação: trade execute-tier atual (BULL_STRONG+LONG live) tem expectancy +0.39R/trade.
- Threshold +0.40R = "ao menos competitivo com a melhor célula long atual".

### 3. Profit Factor
- **PF ≥ 1.5** (mesmo threshold das células LONG live atuais).
- PF abaixo de 1.5 = não justifica risco operacional adicional.

### 4. Max Drawdown simulado
- **DD ≤ 15R** no período de 14d.
- 1% risk por trade × 30 trades = exposição teórica 30R. DD 15R = 50% da exposição.
- Acima de 15R = volatilidade incompatível com Kelly fracionário.

### 5. Cross-period sanity check
- Re-rodar a célula em **3 backtests separados** do passado:
  - 2014-2016 (pre-halving 1)
  - 2018-2020 (BEAR + COVID)
  - 2022-2024 (BEAR + 2024 BULL)
- A célula deve ter expectancy positivo em **pelo menos 2 dos 3 períodos**.
- Se cross-period falhar = paper foi sorte de regime atual, não edge real.

### 6. Macro coerência
- A célula precisa fazer sentido macro:
  - SHORT em CAPITULATION = OK (pânico continua)
  - SHORT em BEAR_STRONG = OK (estrutura confirmada)
  - SHORT em BULL_STRONG = anti-tendência, viés de pump-and-dump → **bloquear mesmo se números passarem**
  - SHORT em SIDEWAYS = ranging trade, requer banda lateral confirmada → revisar caso a caso

## Critério de promoção observe → execute (paper)

Antes mesmo de chegar a live, a célula precisa passar de `observe` (passive) para
`execute` (paper trade simulado). Critério mais leve:

- **N ≥ 10 observations**
- **Expectancy_R > 0** (qualquer positivo)
- **Mesa consensus FORTE_3 ou MEDIO_2** em ≥ 60% das observações da célula
- Mentor APROVAR em ≥ 40% das observações (sinal de coerência narrativa)

Se a célula passa para `execute (paper)`, segue por mais 14d como paper trade simulado
**antes** de avaliar promoção live. Total: 28d mínimo entre primeira observation e live.

## Anti-padrões — descartar a célula sem promover

Mesmo se passar threshold quantitativo, descartar se:

1. **>20% das observations da célula vieram de 1 único mercado** = concentração, não edge.
2. **>40% das observations da célula vieram de 1 único dia** = evento específico, não estatística.
3. **Direção do Mesa consensus contradisse whitelist em >30% dos casos** = whitelist não está
   alinhada com a expertise dos drones (revisar whitelist, não promover célula).
4. **Mentor APROVAR <10%** = narrativas não justificam, números mentem.

## Critério de rejeição rápida (pre-14d)

Não esperar 14d se:

1. **DD > 20R nos primeiros 7d** = parar coleta da célula imediatamente.
2. **Mesa CAOS em >70% das observações da célula** = drones sem consenso = sinal ruim.
3. **Custo Anthropic > $0.50/dia em SHORT observations** = otimizar threshold ou parar.

## Schema de dados necessário (informa B.1 logging)

Cada observation precisa registrar:

| Campo | Tipo | Fonte | Uso no critério |
|---|---|---|---|
| `timestamp` | ISO8601 UTC | Get-Date | Filtro temporal |
| `market` | string | $Market | Anti-concentração #1 |
| `regime` | string (VALID_REGIMES) | triagem.regime | Definir célula |
| `direction` | LONG/SHORT | triagem.direction | Definir célula |
| `dow_brt` | int 0-6 | day_of_week_brt | Definir célula |
| `whitelist_tier` | observe/execute/skip | wl.tier | Filtro |
| `whitelist_reason` | string | wl.reason | Auditoria |
| `scanner_score` | float | scanInfo.score | Quality filter |
| `mesa_consensus` | FORTE_3/MEDIO_2/CAOS | mesa.consensus | Anti-padrão #3 |
| `mesa_sinal_consenso` | LONG/SHORT/NEUTRO | mesa.sinal_consenso | Coerência whitelist |
| `mentor_decision` | APROVAR/AGUARDAR/ABORTAR | mentor.decision | Anti-padrão #4 |
| `mentor_confidence` | 0-100 | mentor.confidence | Quality filter |
| `entry_price` | float | setup.entry | Backfill outcome |
| `stop_price` | float | setup.stop | Backfill outcome |
| `target_price` | float | setup.target | Backfill outcome |
| `atr_proxy_pct` | float | indicators.atr | Backfill se setup ausente |
| `mode` | paper/live | Context.mode | Filtro |

## Decisão final

Em 14d (= 2026-05-29), revisar dataset coletado:
1. Executar `backtest/short_observation_analyzer.py --window 14d`
2. Listar todas as células `<regime>+SHORT+<dow>` com N ≥ 10
3. Aplicar critérios 1-6 (promoção live) ou critério execute (paper)
4. Decisão registrada em `journal/short_observation_decision_2026_05_29.md`

Se NENHUMA célula passar: registrar no jornal, manter whitelist v2 atual, considerar
o paper como **falsification reforçada** do backtest (H₀ confirmado por segundo método).
Isso é valor: dois métodos independentes (backtest 14y + paper 14d) convergem.

---

Gerado em 2026-05-15 ~19:45 BRT como pré-registro de hipótese antes de coleta.
Mudanças neste documento devem ser commitadas com SHA do estado atual + justificativa.
