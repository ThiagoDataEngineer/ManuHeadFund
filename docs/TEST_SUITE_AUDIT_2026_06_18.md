# 🧪 Test Suite Audit (2026-06-18)

## Summary
- **Total test files**: 266+
- **Estimated total tests**: 2000+
- **Status**: NEED CLEANUP — muitos obsoletos (local daemon mode)

---

## 📊 Triagem por Categoria

### ❌ OBSOLETOS (Remover — 15-20 arquivos)
Assumem loop local contínuo ou position_watcher local:

```
retire_position_watcher.Tests.ps1       — position_watcher aposentado
daily_cycle_mode.Tests.ps1              — daemon loop local (cloud agora)
b16_watchdog_backoff.Tests.ps1          — watchdog local (cloud agora)
watchdog_*.Tests.ps1                    — qualquer teste de watchdog local
```

**Ação**: DELETE

---

### ✅ CRÍTICOS — MANTER + VALIDAR (150-170 arquivos, ~1200+ testes)

#### Cloud Infrastructure (50 testes)
```
cloud_only_mode.Tests.ps1               — ✅ 34 testes GREEN
cloud_trading.Tests.ps1                 — ✅ 8 testes (gem_loop -Once)
cloud_conviction_scan.Tests.ps1         — ✅ 8 testes (observe mode)
telegram_cloud.Tests.ps1                — ✅ 13 testes (listener -Once)
cutover_online.Tests.ps1                — ✅ 8 testes (migration)
```

#### Gem Engine (140+ testes)
```
gem_agent.Tests.ps1                     — 64 testes (core gem logic)
gem_executor.Tests.ps1                  — 24 testes (order execution)
gem_executor_csv_fix.Tests.ps1          — 11 testes
gem_executor_missed_log_A.Tests.ps1     — 21 testes
gem_executor_tori_gate.Tests.ps1        — 8 testes
gem_executor_trailing_register.Tests.ps1— 8 testes
gem_cache_bypass.Tests.ps1              — 7 testes
gem_cache_match_by_market.Tests.ps1     — 7 testes
gem_safety.Tests.ps1                    — 22 testes
gem_safety_market_dedup.Tests.ps1       — 6 testes
```

#### Trailing Stop (50+ testes)
```
trailing_*.Tests.ps1                    — ~8 arquivos, ~40+ testes
trailing_stop_intelligent_full.Tests.ps1— 8 testes
trailing_sync_exchange.Tests.ps1        — ? testes
trailing_phantom_reconciliation.Tests.ps1— ? testes
```
**Status**: Atualizar pra JOB1 (não assume loop local)

#### Triagem/Mesa/Mentor (300+ testes)
```
triagem_agent.Tests.ps1                 — tier filtering
mesa_agent.Tests.ps1                    — consensus
mentor_*.Tests.ps1                      — debate/approval
orchestrator_v6.Tests.ps1               — main orchestrator
```
**Status**: Core logic — verificar se precisa mudança

#### Conviction/Entry/Exit (100+ testes)
```
entry_conviction_ensemble.Tests.ps1     — 27 testes (7 eixos)
conviction_*.Tests.ps1                  — ~30 testes
exit_ladder.Tests.ps1                   — 28 testes
lib_entry_score_boost.Tests.ps1         — entry scoring
```
**Status**: Cloud-agnostic — OK

#### Supabase State Store (40+ testes)
```
lib_state_store.Tests.ps1               — 12 testes
lib_state_store_schema.Tests.ps1        — ? testes
supabase_*.Tests.ps1                    — ~5 arquivos
capital_snapshot_runner.Tests.ps1       — 7 testes
```
**Status**: CRÍTICO — validar Supabase sync

#### Capital Safety (30+ testes)
```
001_gate_audit_trail.Tests.ps1          — 4 testes
003_capital_safety.Tests.ps1            — 5 testes
011_stress_test_dd.Tests.ps1            — 7 testes
b17_daily_loss_cb_fail_closed.Tests.ps1 — 6 testes
b23_sharpe_ceiling_gate.Tests.ps1       — 12 testes
```
**Status**: OK — não muda

#### DSR/Regime (40+ testes)
```
006_dsr_live_methodology.Tests.ps1      — 6 testes
021_short_pipeline_and_dsr.Tests.ps1    — 13 testes
dsr_*.Tests.ps1                         — ~8 arquivos
lib_dsr_per_direction.Tests.ps1         — ? testes
```
**Status**: OK — não muda

---

## 🚀 Novos Testes (Criar — Adicionar 20+ testes)

### Cloud Execution Safety
```
tests/cloud_execution_safety.Tests.ps1
  - Valida que gem_loop roda com -Once
  - Valida que scan_master não roda LOOP local
  - Valida que trailing roda em JOB1
  - Valida que Supabase é único state backend
```

### GitHub Actions Workflow
```
tests/github_actions_workflow.Tests.ps1
  - Valida job triggers (schedule: */5 min)
  - Valida secrets injection
  - Valida step order (trailing → gem → telegram)
  - Valida job dependencies
```

### Supabase Cloud State
```
tests/supabase_cloud_sync.Tests.ps1
  - Valida estado sincroniza local ↔ Supabase
  - Valida trailing_positions atomicidade
  - Valida trade_outcomes append-only
  - Valida fallback se Supabase cai
```

### Credentials Protection
```
tests/credentials_protection_cloud.Tests.ps1
  - Valida env vars injetadas (não arquivo)
  - Valida config.local.ps1 gitignored
  - Valida secrets não aparecem em logs
```

---

## 📋 Plano de Ação (3 etapas)

### Etapa 1: Limpeza (20 min)
1. Deletar 15-20 arquivos OBSOLETOS
2. Listar quais vão ser removidos
3. Commit: "test: Remove obsolete local-daemon tests"

### Etapa 2: Validação (30 min)
1. Rodar suite CRÍTICA (cloud + gem + trailing + core)
2. Identificar quais falham
3. Atualizar ou marcar como "precisa revisão"
4. Commit: "test: Validate critical cloud-only suite"

### Etapa 3: Novos Testes (20 min)
1. Criar 4-5 novos arquivos (cloud safety, workflow, Supabase, creds)
2. ~20-30 novos testes
3. Rodar TDD completo
4. Commit: "test: Add cloud infrastructure tests (20+ new)"

### Final: Master Index
1. Criar tests/TEST_SUITE_INDEX.md
2. Documentar qual teste roda onde (local vs cloud)
3. Documentar dependências entre testes

---

## 🎯 Resultado Final Esperado

| Categoria | Antes | Depois |
|-----------|-------|--------|
| Arquivos de teste | 266 | ~200 (30 removidos) |
| Total testes | 2000+ | 1800+ (mantém críticos) |
| Cloud-specific | 50 | 70+ (novos) |
| Suite speed | ~8 min | ~6 min (remover obsoletos) |
| Coverage % | ? | ~95% cloud path |

---

## ✅ Sucesso = 

- ✓ Sem testes obsoletos (position_watcher, daily_cycle, watchdog)
- ✓ Suite crítica roda < 5 min
- ✓ Todos cloud-only tests GREEN
- ✓ Novos cloud safety tests criados + PASSING
- ✓ Master index documentando suite inteira
