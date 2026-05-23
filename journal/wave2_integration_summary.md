# Wave 2 -- Integracao whitelist + fixes diagnose
Data: 2026-05-14

Wave 2 do plano de orquestracao: aplica os fixes do diagnose Wave 1a
(Thursday-veto incondicional + scanner.score nao propagada) e pluga
a lib `Test-RegimeDirectionAllowed` (Wave 1c) como gate antes da Mesa.

---

## Arquivos alterados

### Producao

- `agents/triagem_agent.ps1`
  - `_Compute-Tier` reescrito: regra Thursday+alt e agora condicional ao
    flag global `$SKIP_THURSDAY_ALTS` (default `$false`).
  - Sem flag, Thursday+alt aplica penalidade leve (no maximo Tier B,
    nunca Tier A) -- preserva o sinal empirico sem virar veto.
  - Header documenta o flag.

- `agents/orchestrator_v6.ps1`
  - Novo helper `Get-DayOfWeekBRT [-Utc]` -- retorna 0..6 com 0=Sunday,
    convencao alinhada com `lib_operational_whitelist.ps1`.
  - `Invoke-V6Cascade`: depois da Triagem (Tier D check), antes da Mesa,
    chama `Test-RegimeDirectionAllowed` com regime/direction da Triagem,
    DoW BRT do Context (ou Get-DayOfWeekBRT), e mode do Context.
    - `skip` -> ABORTAR com motivo `whitelist:skip:<regime>+<direction> [<reason>]`.
    - `observe` -> cascade roda normal, mas `telegramFire` forcado a `$false`.
    - `execute` -> fluxo inalterado.
  - `Invoke-OrchestratorV6` ganha parametros `-ScannerInfo` e `-Mode`.
    Context agora inclui `scanner` (sub-objeto com score/change/volume),
    `scanner_score`, `mode`, `day_of_week_brt`.
  - Falha defensiva: se whitelist throw, cascade continua sem bloqueio.

- `agents/config.local.ps1`
  - Adicionado bloco "Triagem flags": `$global:SKIP_THURSDAY_ALTS = $false`.
  - Default destrava o paper trade; comentario explica como re-habilitar.

### Tests

- `tests/triagem_agent.Tests.ps1`
  - +7 tests novos (Describe "Thursday-veto flag" e "scanner.score propaga").
  - Adaptacao de 2 tests legados que cravavam o comportamento antigo (Tier D
    incondicional em quinta+alt) para a nova semantica (flag opcional).
  - Total: 33 passed / 0 failed.

- `tests/orchestrator_whitelist_integration.Tests.ps1` (NOVO)
  - 18 tests (BULL_STRONG, TRANSITION_UP+Mon, SHORT live/paper, SIDEWAYS,
    TRANSITION_UP+Tue, BULL_WEAK, BEAR_STRONG, razao do skip, fluxo,
    Get-DayOfWeekBRT helper).
  - Total: 18 passed / 0 failed.

---

## Tests passando

```
triagem_agent                       33/33
orchestrator_v6 (cascade puro)      15/15
orchestrator_whitelist_integration  18/18  (NOVO)
operational_whitelist (Wave 1c)     28/28
trade_logger (Wave 1b)              24/24
mesa_agent                          30/30
mentor_debate                       10/10
lib_seasonality                     32/32
fallbacks                           38/38
scanner_prescreen                   17/17
```

Total relevante: 243 testes verdes.

---

## Comportamento esperado quando o paper trade reiniciar

1. Hoje e quinta-feira. Antes do fix, 100% dos candidatos (alts) caiam em
   Tier D na Triagem. Agora, com `$SKIP_THURSDAY_ALTS=$false` no
   config.local.ps1, Thursday+alt entra normalmente no pipeline (no maximo
   Tier B). Pipeline destravado.

2. Mesa e Mentor passam a ser efetivamente chamados em quintas. Logs vao
   mostrar `consensus=FORTE_3/MEDIO_2/CAOS` e `decision=APROVAR/VETAR`,
   nao mais "Decisao: ABORTAR" generico.

3. Whitelist gate entra em acao apos a Triagem e antes da Mesa. Para o
   modo `paper`:
   - `BULL_STRONG + LONG` em qualquer DoW -> EXECUTAR + telegram (Wave 1c).
   - `TRANSITION_UP + LONG + Mon BRT` -> EXECUTAR + telegram.
   - `BULL_WEAK + LONG` ou `SHORT em qualquer regime` -> EXECUTAR mas
     `telegramFire=$false` (observe / paper-only).
   - `SIDEWAYS`, `BEAR_*`, `TRANSITION_DOWN` -> ABORTAR com motivo
     `whitelist:skip:<regime>+<direction>`.

4. Para `live`, a banda observe vira skip -- so executa as duas combinacoes
   validadas cross-period (BULL_STRONG+LONG e TRANSITION_UP+LONG+Mon).

5. Log estruturado [TRADE] (Wave 1b) captura o `motivo` no campo `razao`
   quando o cascade aborta. Em skip por whitelist, a razao tem o prefixo
   `whitelist:skip:` para filtragem facil em pos-mortem.

---

## Riscos conhecidos / pontos de atencao

1. **Triagem precisa propagar `regime` e `direction` no resultado.**
   Hoje `Invoke-Triagem` retorna `tier/razao/score_predicted/flags/...` mas
   nao retorna explicitamente `regime` nem `direction`. Os tests usam stubs
   que injetam esses campos. Em producao, sera necessario:
   - Garantir que a Triagem real preencha `triagem.regime` e
     `triagem.direction` antes do whitelist gate funcionar.
   - Como fallback temporario, se ambos forem null, o gate e pulado
     (cascade segue como antes) -- comportamento ja implementado.
   - **Acao recomendada (Wave 3)**: estender Invoke-Triagem para extrair
     regime do macro_bias / NUPL / momentum, e direction do scanner change
     ou sinal_consenso preliminar.

2. **`-ScannerInfo` e `-Mode` em `Invoke-OrchestratorV6` sao opcionais**,
   default null/paper. `scan_master.ps1` ainda nao foi atualizado para
   passar esses parametros -- enquanto isso o Context recebera `scanner.score=null`
   e Triagem cairá no default 50. Necessario na Wave 2.1:
   - Em `scan_master.ps1:298-300`, salvar `$scannerResults[$mkt]` e passar
     via `$orchArgs.ScannerInfo = [PSCustomObject]@{ score=...; change=...; volume=... }`.
   - Adicionar `$orchArgs.Mode = $PaperMode ? "paper" : "live"` (ou ler de
     parametro do script master).

3. **DoW BRT helper assume `Get-Date` local = UTC-3.**
   Em servidor com TZ diferente, `Get-DayOfWeekBRT` sem argumento
   `-Utc` ja chama `(Get-Date).ToUniversalTime()` -- portanto correto
   independente do TZ do host. Tests cobrem 3 conversoes UTC->BRT.

4. **PSAvoidGlobalVars warnings** em `triagem_agent.ps1` e
   `config.local.ps1` sao intencionais: o flag precisa ser legivel
   tanto pelo agent quanto pelo config (que dot-sources em globais).
   Documentado no header do triagem_agent.

5. **Calibracao Thursday-veto NAO foi descartada**, apenas rebaixada.
   Se paper trade em 14 dias mostrar quintas com EV negativo significativo
   (>= -0.2R medio em n>=30 trades), recomendar reativacao do flag.
