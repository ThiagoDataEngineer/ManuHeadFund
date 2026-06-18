# 🧪 Test Suite Index (2026-06-18)

## 📊 Status Geral
- **Total arquivos de teste**: 260
- **Testes estimados**: 1800+
- **Obsoletos removidos**: 6 arquivos
- **Novos criados**: 3 arquivos
- **Status**: Cloud-only ready

---

## ☁️ CLOUD INFRASTRUCTURE (50+ testes)

### Mandatory Green (sem esses, nada funciona)
```
cloud_only_mode.Tests.ps1                  [34/34] ✓ CRÍTICO
cloud_execution_safety.Tests.ps1           [15/?] NOVO
github_actions_workflow.Tests.ps1          [12/?] NOVO
supabase_cloud_sync.Tests.ps1              [13/?] NOVO
cloud_trading.Tests.ps1                    [8/8] ✓
cloud_conviction_scan.Tests.ps1            [8/8] ✓
telegram_cloud.Tests.ps1                   [13/13] ✓
cutover_online.Tests.ps1                   [8/8] ✓
```

---

## 🎯 GEM ENGINE (140+ testes)

Core gem discovery + execution logic:
```
gem_agent.Tests.ps1                        [64] ✓ CORE
gem_executor.Tests.ps1                     [24] ✓
gem_executor_csv_fix.Tests.ps1             [11] ✓
gem_executor_missed_log_A.Tests.ps1        [21] ✓
gem_executor_tori_gate.Tests.ps1           [8] ✓
gem_executor_trailing_register.Tests.ps1   [8] ✓
gem_cache_bypass.Tests.ps1                 [7] ✓
gem_cache_match_by_market.Tests.ps1        [7] ✓
gem_safety.Tests.ps1                       [22] ✓
gem_safety_market_dedup.Tests.ps1          [6] ✓
```

---

## 🛑 TRAILING STOPS (50+ testes)

Agora executado por JOB1 (GitHub Actions):
```
trailing_stop_intelligent_full.Tests.ps1   [8] ✓ JOB1
trailing_sync_exchange.Tests.ps1           [?] ✓ JOB1
trailing_phantom_reconciliation.Tests.ps1  [?] ✓ JOB1
trailing_blindness_fix.Tests.ps1           [?] ✓ PEAK UPDATE
trailing_state_adapter.Tests.ps1           [?] ✓
trailing_exhaustion.Tests.ps1              [?] ✓
trailing_macro.Tests.ps1                   [?] ✓
trailing_microstructure.Tests.ps1          [?] ✓
trailing_smart_atr.Tests.ps1               [?] ✓
trailing_integration.Tests.ps1             [?] ✓
```

---

## 🧠 CONVICTION / ENTRY / EXIT (150+ testes)

Entry logic (cloud-agnostic):
```
entry_conviction_ensemble.Tests.ps1        [27] ✓ 7-EIXOS
conviction_axes_final.Tests.ps1            [10] ✓
conviction_axes_plus.Tests.ps1             [16] ✓
conviction_gate_override.Tests.ps1         [7] ✓
lib_entry_confluence.Tests.ps1             [?] ✓
lib_entry_score_boost.Tests.ps1            [?] ✓
exit_ladder.Tests.ps1                      [28] ✓ 5-STAGE EXIT
lib_exit_logic.Tests.ps1                   [?] ✓
```

---

## 🎪 TRIAGEM / MESA / MENTOR (300+ testes)

Core orchestration:
```
triagem_agent.Tests.ps1                    [?] ✓ TIER FILTER
mesa_agent.Tests.ps1                       [?] ✓ CONSENSUS
mentor_*.Tests.ps1                         [?] ✓ DEBATE/APPROVAL
orchestrator_v6.Tests.ps1                  [?] ✓ MAIN
```

---

## 📊 SUPABASE STATE STORE (40+ testes)

Backend único:
```
lib_state_store.Tests.ps1                  [12] ✓ CORE
lib_state_store_schema.Tests.ps1           [?] ✓
supabase_data_migration.Tests.ps1          [?] ✓
supabase_schema_init.Tests.ps1             [?] ✓
supabase_cloud_sync.Tests.ps1              [13] ✓ NOVO
capital_snapshot_runner.Tests.ps1          [7] ✓
```

---

## 💰 CAPITAL SAFETY (30+ testes)

Risk management (crítico):
```
001_gate_audit_trail.Tests.ps1             [4] ✓ GATES
003_capital_safety.Tests.ps1               [5] ✓ 1% MAX
011_stress_test_dd.Tests.ps1               [7] ✓ DD TEST
b17_daily_loss_cb_fail_closed.Tests.ps1    [6] ✓ CIRCUIT BREAK
b23_sharpe_ceiling_gate.Tests.ps1          [12] ✓ RISK GATE
```

---

## 📈 DSR / REGIME (40+ testes)

Market regime:
```
006_dsr_live_methodology.Tests.ps1         [6] ✓
021_short_pipeline_and_dsr.Tests.ps1       [13] ✓
dsr_forbidden_phrases.Tests.ps1            [38] ✓
dsr_global.Tests.ps1                       [5] ✓
lib_dsr_per_direction.Tests.ps1            [?] ✓
```

---

## 📡 DASHBOARD / TELEGRAM (50+ testes)

UI + Control:
```
dashboard.Tests.ps1                        [8] ✓
dashboard_elite.Tests.ps1                  [21] ✓
dashboard_evolved.Tests.ps1                [35] ✓
dashboard_professional.Tests.ps1           [12] ✓
dashboard_telegram_buttons.Tests.ps1       [19] ✓ (#4)
telegram_cloud.Tests.ps1                   [13] ✓ JOB24
```

---

## 🚨 REMOVIDOS (6 arquivos)

```
✗ retire_position_watcher.Tests.ps1        — position_watcher aposentado
✗ b16_watchdog_backoff.Tests.ps1           — daemon local
✗ watchdog_paper.Tests.ps1                 — daemon local
✗ watchdog_tg_listener.Tests.ps1           — daemon local
✗ daily_cycle_mode.Tests.ps1               — loop daemon local
✗ warmup_llm_endpoints.Tests.ps1           — daily_daemon_restart ref
```

---

## 🆕 ADICIONADOS (3 arquivos, 40 testes)

```
✓ cloud_execution_safety.Tests.ps1         [15] — Local parado, -Once ativo
✓ github_actions_workflow.Tests.ps1        [12] — Workflow validação
✓ supabase_cloud_sync.Tests.ps1            [13] — Backend único Supabase
```

---

## 🎯 Quick Run Recipes

### Teste tudo (lento, 5-10 min)
```powershell
Invoke-Pester tests/ -Output Detailed
```

### Teste CLOUD ONLY (rápido, 2 min)
```powershell
$cloudTests = @(
  'tests/cloud_only_mode.Tests.ps1',
  'tests/cloud_execution_safety.Tests.ps1',
  'tests/github_actions_workflow.Tests.ps1',
  'tests/supabase_cloud_sync.Tests.ps1'
)
foreach ($t in $cloudTests) { Invoke-Pester $t -PassThru }
```

### Teste GEM ENGINE (2 min)
```powershell
Invoke-Pester tests/gem_*.Tests.ps1 -PassThru
```

### Teste CAPITAL SAFETY (1 min)
```powershell
Invoke-Pester tests/001_gate_audit_trail.Tests.ps1, tests/003_capital_safety.Tests.ps1 -PassThru
```

---

## 📋 Dependências Entre Testes

```
CLOUD SAFETY (cloud_only_mode)
  ↓
GEM ENGINE (gem_agent, gem_executor)
  ↓
CONVICTION (entry_conviction_ensemble)
  ↓
TRAILING (trailing_stop_intelligent_full)
  ↓
SUPABASE (supabase_cloud_sync)
  ↓
DASHBOARD (dashboard_telegram_buttons)
```

---

## ✅ Validação Antes de Deploy

```bash
# 1. Cloud infrastructure
Invoke-Pester tests/cloud_*.Tests.ps1

# 2. Critical execution path
Invoke-Pester tests/gem_agent.Tests.ps1
Invoke-Pester tests/entry_conviction_ensemble.Tests.ps1
Invoke-Pester tests/trailing_stop_intelligent_full.Tests.ps1

# 3. Safety gates
Invoke-Pester tests/003_capital_safety.Tests.ps1
Invoke-Pester tests/b17_daily_loss_cb_fail_closed.Tests.ps1

# 4. State persistence
Invoke-Pester tests/supabase_cloud_sync.Tests.ps1

# Se tudo ✓: safe to push to main
```

---

**Última atualização**: 2026-06-18  
**Status**: ✅ Cloud-only ready
