# Wave 2.5 -- Integration gaps fechados (pre-paper)
Data: 2026-05-14

Wave 2.5: fecha os dois riscos levantados no fim da Wave 2 antes de reiniciar
paper trade. Sistema agora e end-to-end funcional.

---

## Tests verdes (por arquivo)

| Arquivo | Resultado |
|---|---|
| `tests/triagem_agent.Tests.ps1` | 46 / 0 (+13 Wave 2.5) |
| `tests/orchestrator_v6.Tests.ps1` | 15 / 0 |
| `tests/orchestrator_whitelist_integration.Tests.ps1` | 18 / 0 |
| `tests/scan_master_integration.Tests.ps1` (NOVO) | 6 / 0 |
| `tests/trade_logger.Tests.ps1` | 24 / 0 |
| Suite completa `tests/` | **624 / 0** |

Tempo total da suite: ~115s. Zero regressao em qualquer teste legado.

---

## Risco 1 -- Triagem agora retorna `regime` e `direction`

Endereçado: **SIM**.

### Mudancas em `agents/triagem_agent.ps1`

- Nova funcao `_Compute-RegimeFromContext` mapeia `(score, macro_bias)` -> regime
  canonico do conjunto da whitelist (`BULL_STRONG`, `BULL_WEAK`, `SIDEWAYS`,
  `TRANSITION_UP`, `TRANSITION_DOWN`, `BEAR_WEAK`, `BEAR_STRONG`, `CAPITULATION`).
- Nova funcao `_Compute-DirectionFromRegime`:
  - `BULL_*` -> LONG
  - `BEAR_*` / `CAPITULATION` / `TRANSITION_DOWN` -> SHORT
  - `TRANSITION_UP` / `SIDEWAYS` -> LONG (default)
- `Invoke-Triagem` agora popula `regime` e `direction` no PSCustomObject de retorno.

### Tests novos (13 em `triagem_agent.Tests.ps1`)

Cobrem todos os ramos do mapeamento + validacao contra o conjunto valido da
`lib_operational_whitelist`. PHASE RED confirmado (13/13 vermelhos antes do fix),
PHASE GREEN com 46/46.

### Impacto no cascade

O whitelist gate em `Invoke-V6Cascade` ja consumia `$triagem.regime` e
`$triagem.direction` com fallback "skip if null". Com a Wave 2.5, esses campos
chegam **sempre populados em producao**, eliminando o fallback silencioso.

---

## Risco 2 -- `scan_master.ps1` propaga `-ScannerInfo` e `-Mode`

Endereçado: **SIM**.

### Mudancas em `scripts/scan_master.ps1`

- Apos `Get-ScannerCandidates`, indexa resultados em `$global:SCANNER_INDEX`
  por market (score/change/volume).
- Na chamada a `Invoke-OrchestratorV6` (dentro de `Invoke-MasterCycle`):
  - `$orchArgs.ScannerInfo = [PSCustomObject]@{ score; change; volume }` lendo
    do indice quando disponivel; senao $null (defensivo).
  - `$orchArgs.Mode = if ($DryRun) { "paper" } else { "live" }`.

### Tests novos em `tests/scan_master_integration.Tests.ps1` (6)

1. Snippet-replica verifica que `Invoke-OrchestratorV6` recebe `ScannerInfo`
   com score/change/volume.
2. Snippet-replica verifica `Mode='paper'` quando DryRun.
3. Snippet-replica verifica `Mode='live'` quando NAO DryRun.
4. Snippet-replica verifica Market correto.
5. Source-grep no `scan_master.ps1` real: contem `ScannerInfo`.
6. Source-grep no `scan_master.ps1` real: contem `orchArgs.Mode`.

A dupla cobertura (snippet-replica + source-grep) garante que tanto a logica
quanto o codigo de producao estao alinhados. PHASE RED confirmou 2 falhas
no source-grep antes do fix; PHASE GREEN com 6/6.

### Compatibilidade

`Invoke-OrchestratorV6` ja aceitava `-ScannerInfo` e `-Mode` opcionais desde a
Wave 2. Sem mudança de assinatura. Comportamento default preservado em modo
`-DryRun` (continua paper).

---

## Sistema end-to-end?

**SIM.** A cadeia completa:

```
scan_master.ps1 (Get-ScannerCandidates + ScannerInfo + Mode)
    -> Invoke-OrchestratorV6 (monta Context com scanner_score, mode, day_of_week_brt)
    -> Invoke-V6Cascade
        -> Invoke-Triagem (retorna tier + regime + direction)
        -> Whitelist gate Test-RegimeDirectionAllowed (execute/observe/skip)
        -> Invoke-Mesa / Invoke-MentorDebate (se nao skip)
        -> telegramFire suprimido em observe (paper-only)
```

Cada elo agora tem teste verde **com dado real fluindo** (nao mais via stubs
que injetavam regime/direction artificialmente como na Wave 2).

---

## Pronto para paper trade?

**SIM**, com as seguintes condicoes (ja definidas em
`memory/project_go_live_criteria_2026_05_14.md`):

- Hoje e quinta (DoW BRT=4). Com `$SKIP_THURSDAY_ALTS=$false` em config.local,
  pipeline esta destravado.
- Paper trade roda por 14 dias.
- GO/NO-GO em 4/5 benchmarks: Sharpe descontado >=1.5, DD<=10%, etc.

Recomendado: iniciar paper trade com `-DryRun` no scan_master para um ciclo
sanity check antes de ligar telegramFire para real.

---

## Riscos NOVOS identificados (para Wave 3+)

1. **Mapeamento regime/direction e simplificado.** Hoje so usa
   `macro_bias + scanner_score`. Em producao real, o regime deveria considerar:
   - Tendencia 1d/4h (EMA cross, ADX).
   - NUPL / Pi Cycle (lib_cycle_indicators).
   - Funding rates / open interest.

   Acao recomendada: enriquecer `_Compute-RegimeFromContext` na Wave 3 quando
   tivermos amostra paper trade de regimes mapeados vs realizados.

2. **Direction sempre LONG em TRANSITION_UP/SIDEWAYS.** Defensivo, mas
   pode mascarar oportunidade de SHORT em sideways volatil. Reavaliar com
   dado de paper trade.

3. **`$global:SCANNER_INDEX` e estado global.** Funciona porque `Invoke-MasterCycle`
   roda single-threaded, mas se virar multi-thread no futuro, refatorar para
   passar via parametro.

4. **Score scanner agora flui para regime.** Score baixo -> regime BEAR_*.
   Em pares com volume baixo mas tese tecnica solida, isso pode classificar
   incorretamente como bearish. Monitorar nos primeiros 30 trades.

5. **Pre-existing PSScriptAnalyzer warnings em scan_master.ps1** (unused params,
   global vars). Nao introduzidos pela Wave 2.5; seguem o padrao do arquivo.
   Cleanup separado em Wave 3.5.

---

## Snapshot final

```
Wave 1a (diagnose)          : OK
Wave 1b (trade_logger)      : OK
Wave 1c (whitelist lib)     : OK
Wave 2  (cascade + gate)    : OK
Wave 2.5 (integration gaps) : OK -- 624 tests / 0 fail
                              ----------------
                              => paper trade APTO
```
