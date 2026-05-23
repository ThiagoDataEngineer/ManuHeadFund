# PARITY CONTRACTS -- Python <-> PowerShell

> Documento vivo. Atualizacao OBRIGATORIA em PR que toca regra invariante.
> Tests em `backtest/tests/test_parity_contracts.py` e `tests/parity_contracts.Tests.ps1`
> verificam que refs apontam para codigo existente e que regimes documentados continuam
> presentes em `signal_generator.py:ALLOWED_PERMISSIVE`.

**Versao:** 1.0 (2026-05-15)
**Status: ACTIVE**
**Nivel:** 1 (documentacao disciplinada) -- ver `memory/framework_paridade_python_ps.md`

---

## Por que este doc existe

O CoinEx AI Agent tem **duas implementacoes paralelas** das mesmas regras de negocio:

- **PowerShell** (live): scan_master + orchestrator + agents
- **Python** (backtest): signal_generator + regime_8state_classifier + benchmarks

Paralelismo eh necessario (live tem LLM/Telegram/human-in-loop; backtest eh batch puro),
mas cria **5 anatomias de divergencia silenciosa** -- enumeradas em
`memory/framework_paridade_python_ps.md`.

Esta tabela enumera as **regras invariantes**: aquilo que TEM que ser identico nos dois
mundos sob pena de "backtest diz +PF, live perde dinheiro".

---

## Como usar

1. Antes de tocar logica de regime/whitelist/sizing/score em qualquer lado, leia o
   contrato correspondente abaixo.
2. Se mudar a regra: edite o contrato (atualize `last_verified`, refs e `status`).
3. Se quebrar paridade deliberadamente: mude `status` para `DIVERGENT` com nota
   explicando o motivo + ticket de re-sync.
4. PR deve passar suite `parity_contracts` antes de merge (Python + Pester).

---

## Regras Invariantes

Cada contrato eh um bloco YAML machine-parseable.
Campos obrigatorios: `id`, `rule`, `ps_ref`, `python_ref`, `status`.
Status valido: `SYNCED | DIVERGENT | PS_ONLY | PYTHON_ONLY`.

### 1. Regimes canonicos (definicao 8-estados)

Os 8 regimes canonicos do sistema sao:
`BULL_STRONG`, `BULL_WEAK`, `SIDEWAYS`, `TRANSITION_UP`,
`TRANSITION_DOWN`, `BEAR_WEAK`, `BEAR_STRONG`, `CAPITULATION`.

PS define a lista em `$script:VALID_REGIMES`; Python em `VALID_REGIMES`.
Qualquer adicao/remocao/renomeacao de regime exige update sincronizado.

```yaml
contract:
  id: regime_canonical_set
  rule: 8 regimes canonicos (BULL_STRONG, BULL_WEAK, SIDEWAYS, TRANSITION_UP, TRANSITION_DOWN, BEAR_WEAK, BEAR_STRONG, CAPITULATION)
  ps_ref: agents/lib_operational_whitelist.ps1:19
  python_ref: backtest/signal_generator.py:29
  status: SYNCED
  last_verified: 2026-05-15
```

```yaml
contract:
  id: regime_bull_strong
  rule: BULL_STRONG = price > SMA200 AND ADX > 25 AND PDI > NDI AND nao-transition
  ps_ref: scripts/scan_master.ps1:148
  python_ref: backtest/regime_8state_classifier.py:230
  status: SYNCED
  last_verified: 2026-05-15
  note: PS classifica via Resolve-RegimeForLog (delega ao triagem regime canonico); Python via classify_8state_fast.
```

```yaml
contract:
  id: regime_bull_weak
  rule: BULL_WEAK = price > SMA200 AND (ADX <= 25 OR PDI <= NDI) AND nao-transition
  ps_ref: scripts/scan_master.ps1:148
  python_ref: backtest/regime_8state_classifier.py:230
  status: SYNCED
  last_verified: 2026-05-15
  note: Live blacklist em BULL_WEAK+LONG (STRUCTURAL_BREAK holdout -0.37R em 2025).
```

```yaml
contract:
  id: regime_transition_up
  rule: TRANSITION_UP = SMA200 cruzou para cima nos ultimos TRANSITION_BARS (20) bars
  ps_ref: scripts/scan_master.ps1:148
  python_ref: backtest/regime_8state_classifier.py:46
  status: SYNCED
  last_verified: 2026-05-15
  note: TRANSITION_UP + LONG + DoW=1 (Monday BRT) = execute em live (+0.98R holdout, n=25).
```

```yaml
contract:
  id: regime_transition_down
  rule: TRANSITION_DOWN = SMA200 cruzou para baixo nos ultimos TRANSITION_BARS (20) bars
  ps_ref: scripts/scan_master.ps1:148
  python_ref: backtest/regime_8state_classifier.py:46
  status: SYNCED
  last_verified: 2026-05-15
```

### 2. Whitelist regime+direcao (gate critico)

```yaml
contract:
  id: allowed_permissive
  rule: Permissive filter bloqueia LONG em BEAR_* e SHORT em BULL_*. ALLOWED_PERMISSIVE COMPRA = (BULL_STRONG, BULL_WEAK, TRANSITION_UP); VENDA = (BEAR_STRONG, BEAR_WEAK, TRANSITION_DOWN, CAPITULATION).
  ps_ref: agents/lib_operational_whitelist.ps1:27
  python_ref: backtest/signal_generator.py:35
  status: SYNCED
  last_verified: 2026-05-15
  note: Python tem ALLOWED_PERMISSIVE dict; PS expressa o mesmo via cadeia de if em Test-RegimeDirectionAllowed. Test test_allowed_permissive_contains_documented_regimes garante presenca dos regimes documentados.
```

```yaml
contract:
  id: allowed_strict_v2
  rule: Strict v2 whitelist (live default) = BULL_STRONG+LONG | TRANSITION_UP+LONG+DoW=1 (Monday BRT). SHORT desabilitado (0 regimes com edge cross-period). BULL_WEAK+LONG removido (STRUCTURAL_BREAK).
  ps_ref: agents/lib_operational_whitelist.ps1:50
  python_ref: backtest/signal_generator.py:91
  status: SYNCED
  last_verified: 2026-05-15
  note: PS define em regras 1+2 de Test-RegimeDirectionAllowed; Python em apply_regime_filter(mode="strict_v2").
```

```yaml
contract:
  id: short_blacklist_live
  rule: SHORT em qualquer regime = skip em live (blacklist); observe em paper (coleta amostra)
  ps_ref: agents/lib_operational_whitelist.ps1:101
  python_ref: backtest/signal_generator.py:98
  status: SYNCED
  last_verified: 2026-05-15
```

### 3. Sizing/precision (locale-safe)

```yaml
contract:
  id: invariantculture_serialization
  rule: Serializacao numerica para API/CSV usa InvariantCulture para evitar virgula PT-BR corromper payload (CoinEx rejeita com code 3639)
  ps_ref: agents/lib_coinex.ps1:149
  python_ref: N/A
  status: PS_ONLY
  last_verified: 2026-05-15
  note: Python usa repr/format default (ja produz "1.23" com ponto). PS precisava fix explicito (4 funcoes em lib_coinex.ps1:149,209,250,269 + gem_executor:115). Equivalente Python eh garantir CSV escrito com locale='C' (sem locale-aware formatting).
```

```yaml
contract:
  id: calculate_stop_target_precision
  rule: Stop/target sempre usa [decimal] em PS para evitar erro de precisao em pares sub-dollar (ex AIUSDT a $0.000123). Direction LONG = target > entry > stop; SHORT = stop > entry > target.
  ps_ref: agents/gem_executor.ps1:43
  python_ref: N/A
  status: PS_ONLY
  last_verified: 2026-05-15
  note: Backtest Python usa SL/TP simples direto em trade_simulator.py (sem helper dedicado). Bug sub-dollar so se manifesta em ordem real -- backtest ignora rounding pre-API. Re-sync quando paper trade live introduzir mesmo cenario em Python.
```

### 4. Macro context (FRED)

```yaml
contract:
  id: fred_api_macro
  rule: Macro context puxa DXY (DTWEXBGS), M2 (WM2NS), 10Y (DGS10), 2Y (DGS2), Fed Funds via FRED. PS usa endpoint authed JSON com FRED_API_KEY; Python usa fredgraph CSV publico.
  ps_ref: agents/lib_macro.ps1:91
  python_ref: backtest/macro_gate_bull_strong.py:114
  status: DIVERGENT
  last_verified: 2026-05-15
  note: Endpoints divergem deliberadamente (PS authed JSON eh recomendado pela FRED para tempo real; Python CSV publico simplifica backtest historico). Risco: server-side filters podem retornar datasets sutilmente diferentes em corte de data. Acao futura: backfill cache compartilhado parquet para garantir bit-identico.
```

### 5. Day-of-week seasonality

```yaml
contract:
  id: dow_brt_convention
  rule: DayOfWeekBRT convencao = 0:Sunday, 1:Monday, ..., 6:Saturday. Conversao UTC->BRT (UTC-3) eh responsabilidade do caller.
  ps_ref: agents/lib_operational_whitelist.ps1:17
  python_ref: backtest/signal_generator.py:50
  status: SYNCED
  last_verified: 2026-05-15
  note: Python tem default -1 (desconhecido) -> skip filtro v2 quando indefinido. PS exige int 0-6 (throw fora do range).
```

---

## Excluidos (diferencas legitimas)

Estes itens NAO precisam paridade -- divergem por design:

- **Human-in-loop**: Telegram bot (`agents/lib_telegram.ps1`) so existe em live; backtest eh batch puro.
- **Cost tracking**: `agents/lib_cost_tracker.ps1` rastreia gasto LLM real; backtest nao chama API.
- **LLM agents**: Mentor/Mesa/Sent/Fund (`agents/*_agent.ps1`) consultam Claude; backtest usa regras deterministicas.
- **Latencia/timeout**: live tem timeout 5min em fetch macro; backtest eh sincrono e tolera horas.
- **Cache TTL**: live cacheia FRED por horas; backtest deduplica via SQLite (db.py).

---

## Checklist PR

Quando o PR toca codigo em `agents/lib_operational_whitelist.ps1`, `backtest/signal_generator.py`,
`backtest/regime_8state_classifier.py`, `scripts/scan_master.ps1`, `agents/lib_macro.ps1`,
`agents/gem_executor.ps1` ou `agents/position_sizer.ps1`:

- [ ] Identifiquei qual contrato deste doc eh afetado?
- [ ] O outro lado (Python ou PS) precisa do mesmo update? Se sim, fiz?
- [ ] Atualizei `last_verified` do contrato afetado
- [ ] Atualizei `status` se a paridade mudou (SYNCED -> DIVERGENT com nota)
- [ ] Rodei `pytest backtest/tests/test_parity_contracts.py -v` (verde)
- [ ] Rodei `Invoke-Pester -Path tests/parity_contracts.Tests.ps1` (verde)
- [ ] Suite completa zero regressao (PS 790+ e Python 620+ tests)
- [ ] Se mudei ALLOWED_PERMISSIVE: atualizei a constante `DOCUMENTED_LONG_REGIMES` no test
- [ ] Se mudei InvariantCulture em PS: documentei equivalente Python (ou justifiquei N/A)

---

## Proximo nivel (futuro -- nao agora)

**Nivel 2: Suite cross-validation** (1-2 dias de trabalho)

Para cada contrato, criar par de tests input/output declarativo:

```yaml
parity_test_001:
  rule: regime_bull_strong
  input: { price: 100, sma200: 90, adx: 30, pdi: 25, ndi: 15 }
  expected_regime: "BULL_STRONG"
```

PS e Python carregam o mesmo YAML e rodam contra a propria classificacao. Detecta
divergencia numerica sutil (ex: half-up vs half-even em borderline ADX=25.0001).

Trigger para subir de Nivel 1 -> Nivel 2: primeira vez que algo divergir em producao.

---

## Historico

- **v1.0 (2026-05-15)**: documento inicial. 10 contratos cobrindo regime canonical set,
  4 regimes individuais, allowed_permissive, allowed_strict_v2, short_blacklist,
  invariantculture, calculate_stop_target, fred_api, dow_brt. Tests Python (7) + Pester (9).
  Marco da Nuance D do MAPA TATICO.
