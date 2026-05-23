# Cascade Desbloqueada — 2026-05-15 ~19:30 BRT

## Antes / Depois (snapshot)

**Antes (paper trades hoje 11:00-18:42):**
- 30+ ciclos consecutivos: **100% Tier D**
- Cascade nunca chegou em PORTEIRO/MESA/GENERAL em produção
- STORJUSDT erro "Path argument null" em todo ciclo onde estava nos candidatos
- gems=0 mesa=0 exec=0 em todos os ciclos

**Depois (paper trade restart 19:12, primeiro cycle 19:14):**
- STORJUSDT: **Tier B**, regime BULL_STRONG, Mesa rodou 3 drones, consensus=CAOS
- Cascade ATIVOU pela primeira vez end-to-end
- Decisão correta: ABORTAR por CAOS (drones divergem) — sistema funcional

## 2 Fixes Aplicados

### Fix 1: Mesa _Mesa_RunDrones Path null
**Arquivo:** `agents/mesa_agent.ps1:124`
**Bug:** `$MyInvocation.MyCommand.Path` retorna `$null` quando função chamada via cadeia dot-source.
**Fix:** captura de `$PSScriptRoot` em script-load time como `$script:_MESA_AGENT_DIR`, referenciada dentro da função.
**Stack trace capturada via instrumentação:** `em _Mesa_RunDrones, mesa_agent.ps1:129 | em Invoke-Mesa, mesa_agent.ps1:233 | em Invoke-V6Cascade, orchestrator_v6.ps1:102`

### Fix 2: Triagem Thresholds (escala empírica)
**Diagnóstico:**
- Scanner produz `|change%| × log10(vol/1000)` → range 5-35 em mainstream, 50-80 em movers extremos
- Triagem `_Compute-Tier` exigia `score >= 50` → 100% Tier D matemática
- EUREKA B anterior (clamp 65→85 em `Get-QuickTechScore`) foi cosmético — função não está no pipeline live

**Fix:** Nova função pura `Get-TriagemThresholds`
- Default 50/60/75 (compat backward)
- Override OPT-IN via `$global:TRIAGEM_THRESHOLDS = @{D=15; B=25; A=40}` em config.local.ps1
- Validação completa: hashtable, valores 1..100, ordem D<B<A, fallback default em qualquer falha

**TDD:** 14 tests em `tests/triagem_thresholds_override.Tests.ps1`
- 8 tests `Get-TriagemThresholds` (default, override completo, parcial, invalid types, fora range, ordem incoerente)
- 6 tests `_Compute-Tier` integração (D/B/A com default e com override)
- BeforeEach + AfterEach reset isolam contra global state leak
- Pre-existing `triagem_agent.Tests.ps1` ganhou BeforeEach reset

## Validação Runtime

Log paper trade `master_20260515.log` linha 19:14:11:
```
[19:14:11] [TRADE] STORJUSDT: ABORTAR regime=BULL_STRONG direction=NEUTRO
  scanner_score=75.93 score_predicted=42 tier=B consensus=CAOS
  razao=Mesa dividida (CAOS) -- sem consensus minimo
```

Observações:
- `tier=B` (era D em 100% dos ciclos pre-fix)
- `consensus=CAOS` ⟹ Mesa rodou os 3 drones (Termal/Radar/Lidar) sem Path null
- `regime=BULL_STRONG` ⟹ orchestrator desceu até Mesa (não abortou em Triagem)
- `direction=NEUTRO` ⟹ drones divergem entre LONG/SHORT
- Decisão correta: ABORTAR (cascade não força entrada quando Mesa não tem consenso)

## Suite Pester

| Snapshot | Passed | Failed |
|---|---|---|
| Pré-Wave 2 (manhã) | 320 | 46 |
| Pós-Wave 2 (Simons real + 4 libs fix) | 1016 | 2 (order-dep) |
| **Pós-cascade unblock (Task B+C TDD)** | **1030** | **2** (mesmos order-dep) |

Zero regressão. +14 testes novos. 2 fails residuais order-dep passam isolados (24/24).

## Próxima Validação (24h)

Critérios de sucesso:
- ✅ Cascade ativa em pelo menos 1 ciclo (já confirmado em 19:14)
- ⏳ Distribuição Tier observada: esperado mix B/C com ocasional A em breakouts fortes
- ⏳ MESA consensus FORTE_3 ou MEDIO_2 ao menos 1× (não só CAOS)
- ⏳ GENERAL (mentor) recebe pelo menos 1 dispatch
- ⏳ Custo Anthropic incremental sob controle (cap $0.10/dia em test mode)

Rollback (se cascade aprovar trade ruim):
- Comentar `$global:TRIAGEM_THRESHOLDS = @{ ... }` em config.local.ps1 → volta default 50/60/75
- Cascade volta a 100% Tier D (estado anterior, comprovadamente conservador)

## Arquivos modificados

- `agents/mesa_agent.ps1` (fix 1)
- `agents/triagem_agent.ps1` (fix 2 — Get-TriagemThresholds + _Compute-Tier dinâmico)
- `agents/config.local.ps1` (override `$global:TRIAGEM_THRESHOLDS` ativo + nota EUREKA B obsoleta)
- `tests/triagem_thresholds_override.Tests.ps1` (novo — 14 tests TDD)
- `tests/triagem_agent.Tests.ps1` (BeforeEach reset adicionado)
- `scripts/scan_master.ps1:597-606` (instrumentação stack trace no catch — ajudou pinpoint Mesa bug)
- `docs/ARCHITECTURE_TATICA.md` v1.10

---

Gerado pelo orquestrador (Opus 4.7) durante diagnose Task B+C com TDD strict.
