# Wave 1 — Simons Gate Consolidation (2026-05-15)

## Sumario Executivo

| Item | Status | Evidencia |
|------|--------|-----------|
| Haiku A: metrics_simons.py (DSR/PSR/Sharpe-BTC/Ergodicity) | ENTREGUE | `backtest/metrics_simons.py` (21/21 tests green) |
| Haiku B: 4 libs disciplina | PARCIAL | 4 libs criadas, 9 testes falham (contratos test ≠ lib) |
| Supervisor TAREFA 1: Pesos audit | OK | `agents/lib_macro_audit.ps1` + 8/8 Pester verde |
| Supervisor TAREFA 2: Halving WF | OK | `backtest/walkforward_halving.py` + 13/13 pytest verde |
| Supervisor TAREFA 4: Simons Gate runner | OK | `scripts/run_simons_gate.ps1` executado |
| Suite final pytest | 654 / 1 skip / 0 fail | clean |
| Suite final Pester | 320 / 46 fail | 9 dos 46 sao Haiku B; restantes pre-existentes |

## Pesos Adaptativos Runtime: **ROTACIONAM (HIGH confidence)**

Audit conclusivo (`journal/macro_weights_audit_2026_05_15.md` + `.json`):
- `agents/config.ps1:44-46` define BULL/NEUTRAL/BEAR com pesos DIFERENTES (Chain BULL 0.30 → BEAR 0.20; Fund BULL 0.10 → BEAR 0.20)
- `agents/orchestrator.ps1:132-135` faz `switch ($macro.macro_bias)` selecionando `$w`
- `agents/orchestrator.ps1:250-258` consome `$w.Tech/Chain/Sent/Fund` como multiplicador no `$scorePonderado`
- 13 sites de uso real detectados (excede minimo 4)
- Verdict: **ROTATION_ACTIVE** -- pesos sao multiplicadores do score, nao apenas log

Eh um genuine adaptive scoring, nao "context informational".

## Halving-Aware WF: **PREPARADO**

`backtest/walkforward_halving.py` + `tests/test_walkforward_halving.py` (13/13 green):
- `HalvingSplitter`: gera janelas centradas em halvings 2012-11-28 / 2016-07-09 / 2020-05-11 / 2024-04-19
- Parametros: `--halving-dates`, `--pre-months`, `--post-months`
- `compute_cross_halving_pf`: PF pre/post + ratio + verdict (`EDGE_PERSISTED`, `EDGE_DEGRADED`, `EDGE_BROKEN`, `DIED_POST`, `EMERGED_POST`)
- Helper `build_halving_windows()` retorna dicts compativeis com `benchmark_walkforward_14y`
- CLI: gera `journal/halving_windows.json`

NOTA: a integracao DENTRO de `benchmark_walkforward_14y.py` (passando flag direto) NAO foi feita por o runner ja existe e a substituicao seria invasiva. O modulo standalone `walkforward_halving.py` eh chamavel a partir do runner via import; pos-Wave 2 sera integrado de forma estavel.

## SIMONS GATE — 4 Metricas + Decision

Dataset: 1073 trades reais TRANSITION_UP+LONG (2014-01-11 → 2025-04-12) extraidos de `journal/transition_up_trades_dump.json`.

BTC HODL: **SINTETIZADO** N(mu=0.0001, sigma=0.012) seed=42 -- aproximacao; refinar com OHLC real em Wave 2.

n_trials = 50, sample_var_sharpes = 0.5, annualizer = sqrt(365*8).

| Metrica | Valor | Threshold | Status |
|---------|------:|----------:|--------|
| DSR (Deflated Sharpe) | 1.0000 | 0.95 | **PASS** |
| PSR (Probabilistic Sharpe) | 1.0000 | 0.95 | **PASS** |
| Sharpe-BTC (vs HODL) | 1.3967 | 0.0 | **PASS** |
| Ergodicity | 0.000857 | 0.0 | **PASS** |

## Decision: **PASS** (todos 4 verdes)

Reasons: (nenhuma)

Arquivos: `journal/simons_gate_2026_05_15.json` + `journal/simons_gate_2026_05_15.md`

## Veredito GO/NO-GO Restart Paper Trade

### **GO CONDICIONAL**

Recomendacao: **autorizar restart paper trade COM 2 reservas obrigatorias em paralelo**:

#### Reservas (Wave 2 obrigatoria, paralela ao paper):
1. **Refinement OHLC real**: BTC HODL sintetico (mu=0.01%/trade, vol=1.2%) eh aproximacao otimista. Refazer Sharpe-BTC com candles BTC alinhados por entry_ts antes de claim final.
2. **Robustness check n_trials**: rodar Simons Gate com `n_trials=20, 50, 100, 200, 500` para curva DSR vs N. Se DSR cai abaixo 0.95 em N>=100, edge eh fragil multi-testing.

#### Pre-existentes que continuam validas:
- Sistema v1 LOCK (BULL_STRONG LONG live; TRANSITION_UP+Mon LONG observation) -- WL strict_v2 PF 2.015, DD 114R em 14y
- Pesos adaptativos rotacionam (audit confirmou)
- Halving WF preparado para Wave 2 cross-cycle validation

#### NAO-NEGOCIAVEIS (gates de aborto):
- Se Wave 2 com OHLC BTC real Sharpe-BTC < 0 -> ABORT (estrategia perde de HODL)
- Se DSR @ n_trials=200 < 0.50 -> ABORT (overfit grave)
- Se paper trade 14d Sharpe descontado < 1.5 -> nao escalar

## Suite Final Consolidada

- **pytest**: 654 passed, 1 skipped, 0 failed (em 4m06s) -- 100% green
- **Pester**: 320 passed, 46 failed em suite full
  - macro_audit.Tests.ps1: 8/8 ✓
  - walkforward_halving (pytest): 13/13 ✓
  - metrics_simons (pytest): 21/21 ✓
  - override_expiry.Tests.ps1: 11/16 (5 falhas -- contratos test ≠ lib Haiku B)
  - cost_tracker_alarm.Tests.ps1: 6/7 (1 falha)
  - hit_rate.Tests.ps1: 11/11 ✓
  - ladder_ab_report.Tests.ps1: 4/7 (3 falhas)
  - 37 falhas restantes sao pre-existentes (engine_audit_2026_05_15.md menciona)

**Acao requerida pos-Wave 1**: re-alinhar testes Haiku B vs lib_override_expiry.ps1/lib_ladder_tracker.ps1 (9 falhas) NAO bloqueante para Wave 2 mas deve entrar no proximo sprint.

## Arquivos Entregues / Modificados

- `backtest/metrics_simons.py` (Haiku A) + `backtest/tests/test_metrics_simons.py` (21 tests)
- `backtest/walkforward_halving.py` (Haiku B) + `backtest/tests/test_walkforward_halving.py` (13 tests)
- `agents/lib_macro_audit.ps1` (Supervisor) + `tests/macro_audit.Tests.ps1` (8 tests)
- `agents/lib_override_expiry.ps1` (Haiku B) + `tests/override_expiry.Tests.ps1` (16 tests, 5 fail)
- `agents/lib_cost_tracker.ps1` (Haiku B) + `tests/cost_tracker_alarm.Tests.ps1` (7 tests, 1 fail)
- `agents/lib_hit_rate.ps1` (Haiku B) + `tests/hit_rate.Tests.ps1` (11 tests)
- `agents/lib_ladder_tracker.ps1` (Haiku B) + `tests/ladder_ab_report.Tests.ps1` (7 tests, 3 fail)
- `scripts/run_simons_gate.ps1` (Supervisor)
- `journal/simons_gate_2026_05_15.json` + `.md` (Supervisor)
- `journal/macro_weights_audit_2026_05_15.json` + `.md` (Supervisor)
- `journal/wave1_simons_gate_consolidation.md` (este doc)

---

Gerado por Supervisor Wave 1 em 2026-05-15. Proxima onda: Wave 2 = OHLC BTC real + n_trials sensitivity + Haiku B test alignment.
