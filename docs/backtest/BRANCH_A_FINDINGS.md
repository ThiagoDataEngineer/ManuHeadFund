# Branch A — OOS Methodology Validation Findings (2026-05-22)

> **Pattern**: doc-alongside-TDD. Cada componente backtest tem markdown documentando
> objetivo, metodologia, findings, e implicações ANTES de mover pra próximo.

## Objetivo

Resolver questão: nosso "OOS lift +3.20pp em h20" foi inflado por **cluster days**
(múltiplos markets disparando mesmo dia = 1 macro-bet, não N trades independentes)?

## Methodology

3 metodologias side-by-side em mesmo dataset OOS Tier S:

| Method | O que mede |
|---|---|
| M1 per-event | Cada signal = 1 trade independente (potentially inflated n) |
| M2 alphabetical | Per day, primeiro market alfabético (matches scanner behavior) |
| M3 max-WSS | Per day, market com maior WSS score (potential scanner refactor) |
| M4 portfolio mean | Per day, média outcomes (cluster as portfolio) |

+ Bootstrap CI 1000x resample-by-day (preserva cluster structure).

## TDD Coverage

`backtest/test_methodology.py`:
- 4 unit tests (funções básicas)
- 5 property-based tests (invariants matemáticos)
- 5 methodology tests (invariants de processo)
- **14/14 PASS**

## Results

### h20_p3_bear OOS (3 distinct days, 2022-06 a 2022-11)

| Method | n_evs | n_days | sig_hit | base_hit | lift | CI 95% |
|---|---|---|---|---|---|---|
| M1 per-event | 5 | 3 | 60.0% | 49.7% | +10.3pp | N/A |
| **M2 alphabetical** | 3 | 3 | 33.3% | 53.0% | **-19.6pp** | [-58.9, +47.7] |
| M3 max-WSS | 3 | 3 | 33.3% | 53.0% | -19.6pp | (same as M2) |
| M4 portfolio mean | 3 | 3 | 66.7% | 64.9% | +1.8pp | cluster-as-1 |

### h24_p3_bear OOS (2 distinct days, 2026-02 a 2026-05)

| Method | n_evs | n_days | sig_hit | base_hit | lift | CI 95% |
|---|---|---|---|---|---|---|
| M1 per-event | 2 | 2 | 50.0% | 48.8% | +1.2pp | N/A |
| M2 alphabetical | 2 | 2 | 50.0% | 49.0% | +1.0pp | insuf (<3 days) |
| M3 max-WSS | 2 | 2 | 50.0% | 46.1% | +3.9pp | (same as M2) |
| M4 portfolio mean | 2 | 2 | 50.0% | 63.7% | -13.7pp | cluster-as-1 |

### COMBINED OOS (6 distinct days)

| Method | n_evs | n_days | sig_hit | base_hit | lift | CI 95% |
|---|---|---|---|---|---|---|
| M1 per-event | 6 | 6 | 66.7% | 46.4% | +20.3pp | N/A |
| **M2 alphabetical** | 6 | 6 | 66.7% | 49.2% | **+17.5pp** | [-20.3, +52.5] |
| M3 max-WSS | 6 | 6 | 66.7% | 48.0% | +18.6pp | (same as M2) |
| M4 portfolio mean | 6 | 6 | 66.7% | 57.0% | +9.7pp | cluster-as-1 |

## 🚨 Findings — sobering

### Finding 1: O "+3.20pp h20 lift" anterior foi inflado por cluster
Quando properly dedup-by-day (M2 = matches scanner behavior real), h20 OOS Tier S
lift = **-19.6pp** (não +3.20pp). O cluster day 2022-06-14 (3 markets simultâneos
classificados Tier S) com 2 wins + 1 win parecia "3 confirmações", mas era 1 macro-bet.

Após dedup, o único dia "winner" (2022-11-08 SKYUSDT +23%) vs 2 days "losers"
(2022-06-14 BCH e 2022-06-15 COMP) = 1/3 hit = 33.3%, abaixo do baseline 53%.

### Finding 2: M3 max-WSS NÃO ajuda (vs M2 alphabetical)
Para os 6 OOS days, max-WSS escolheu mesmo market que alphabetical em todos os casos
(ou diferente mas resultado idêntico). Refatorar scanner pra max-WSS pick **NÃO traria
melhoria visível**. Posterga essa refatoração indefinidamente.

### Finding 3: M4 portfolio mean ajuda em h20, prejudica em h24
M4 captura "se eu splittasse capital entre todos firing markets". Em h20 lift +1.8pp
(positivo). Em h24 lift -13.7pp (negativo). Inconsistente cross-cycle.

### Finding 4: CI 95% INCLUI ZERO em todos os casos
- h20 CI: [-58.9, +47.7] — extremamente largo
- Combined CI: [-20.3, +52.5] — inclui zero

**Statisticamente: não podemos rejeitar a hipótese de que WSS Tier S lift = 0** (noise).
Sample size é insuficiente pra inferência forte.

### Finding 5: Sample independente real é MUITO menor
- Train Tier S: 28 events declarados → 17 dias distintos (n efetivo 17, não 28)
- OOS combinado: 6 events → 6 dias (não inflado neste caso)
- OOS por cycle: h20 = 3 dias, h24 = 2 dias (frágil)

## Implicações

### Para WSS thesis
Não rejeitamos completamente — train sample é razoável (17 dias com cross-cycle).
Mas **OOS validation é estatisticamente fraca**. Não podemos afirmar com confiança
que WSS Tier S tem edge replicável.

### Para scanner deployment
WSS continua útil como **risk control** (filtra Tier B = silent) mesmo sem proof de edge.
Reduz exposure em regimes ruins. Não é edge restorer.

### Para próximas branches
- **Branch B (universe expansion)**: pode rescue se mais markets → mais dias OOS → CI mais estreito
- **Branch C (calibration)**: walk-forward retreino pouco vai ajudar se sample fundamental é pequeno
- **Branch D (ensemble)**: provavelmente reduz n ainda mais

### Para Mentor evolutions (priorização)
Argumento ficou MAIS forte: se predicate edge é incerto, **eliminar hallucination
(7/7 PM6+870min documented) ataca problema MAIS concreto e verificável**.

## Skill insight permanente

> **"Per-event count infla N quando há clustering — OOS measurement deve usar
> effective_n (distinct days) sempre"**.
>
> Pattern detection: se um predicate gera M signals em N days com M > N (cluster days
> existem), per-event metric overestimates statistical power by factor M/N. Bootstrap CI
> deve resample por DAY, não por event, para preservar cluster structure.
>
> **Application**: TODO validation futura deve reportar (a) n_events declared
> (b) n_days effective (c) lift point estimate (d) bootstrap CI by-day. Tudo junto
> ou não é honest.

## Próxima decisão

3 caminhos defensáveis:

1. **Continuar WSS Branch B (universe expansion)** — testa se mais markets rescue CI
2. **Pular pra Mentor evolutions** — maior ROI em problema concreto (hallucination)
3. **Aceitar WSS como risk-control-only** — sem edge proof, mantém scanner mas declara
   "experimental observatory", pivota pra outros trabalhos

Recomendação: **(1) Branch B primeiro** (1.5h, possibly rescue CI), depois
decisão informada entre (2) e (3).

## Artefatos

- Código: [backtest/lib_methodology.py](../../backtest/lib_methodology.py)
- TDD: [backtest/test_methodology.py](../../backtest/test_methodology.py)
- Validator: [backtest/branch_a_oos_validation.py](../../backtest/branch_a_oos_validation.py)
- Test count: 14/14 PASS

## Pattern doc-alongside-TDD (estabelecido aqui)

Cada componente backtest crítico ganha 3 artefatos juntos:
1. **Código** (`backtest/<name>.py`)
2. **TDD** (`backtest/test_<name>.py`) — unit + property + methodology
3. **Documentação** (`docs/backtest/<NAME>_FINDINGS.md`) — objetivo, methodology,
   results, implicações, skill insights

Permite revisão futura sem re-derivar contexto.
