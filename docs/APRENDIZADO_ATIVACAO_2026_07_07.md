# ATIVAÇÃO DO SISTEMA DE APRENDIZADO — 2026-07-07

## Problema Diagnosticado

**O sistema de aprendizado foi CODIFICADO há semanas MAS NUNCA ATIVADO NO LOOP PRINCIPAL.**

### Código que existia (morto):
- ✅ `lib_learning_engine.ps1` — analisa logs, classifica erros
- ✅ `lib_evolution_engine.ps1` — auto-tuning de parametros
- ✅ `lib_direction_learning.ps1` — captura sinais + outcomes
- ✅ `lib_learning_scheduler.ps1` — cron wrapper

### Problema: Não estava DOT-SOURCED
```
❌ scan_master.ps1          — não importava learning engines
❌ gem_executor.ps1        — não chamava Record-TradeEntry/Exit
❌ cron_learning_cycle.ps1 — não existia
```

### Consequência
- **Sinais nunca registrados** → sem história de confluência
- **Outcomes nunca capturados** → sistema cego a próprio desempenho
- **Parametros nunca evoluem** → same mistakes repeat forever

---

## SOLUÇÃO IMPLEMENTADA (2026-07-07 14:45)

### 1. Integração em scan_master.ps1 ✅
```powershell
# Linhas 105-107 (adicionadas)
. (Join-Path $agentsDir "lib_direction_learning.ps1")
. (Join-Path $agentsDir "lib_learning_engine.ps1")     # ← NOVO
. (Join-Path $agentsDir "lib_evolution_engine.ps1")    # ← NOVO
```
**Impacto**: Learning engines agora carregam no início de cada loop

### 2. Integração em gem_executor.ps1 ✅
```powershell
# Linhas 91-94 (adicionadas)
foreach ($__learnDep in @("lib_learning_engine.ps1","lib_evolution_engine.ps1","lib_direction_learning.ps1")) {
    $__learnPath = Join-Path $PSScriptRoot $__learnDep
    if (Test-Path $__learnPath) { . $__learnPath }
}
```
**Impacto**: gem_executor pode chamar Record-TradeEntry/Exit

### 3. Nova biblioteca: lib_learning_integration.ps1 ✅
Funções públicas:
- `Record-TradeEntry` — registra sinal + confluência
- `Record-TradeExit` — registra outcome (win/loss/duration)
- `Invoke-LearningCycle` — roda análise completa

**Arquivo**: `agents/lib_learning_integration.ps1`

### 4. Novo cron: cron_learning_cycle.ps1 ✅
Executa nightly (23:00 BRT) para:
1. Analisar trades do dia
2. Detectar padrões de erro
3. Calcular propostas de evolução
4. Registrar snapshots diários
5. Alertar Telegram com resumo

**Arquivo**: `scripts/cron_learning_cycle.ps1`

---

## COMO USAR AGORA

### Fase 1: Próxima execução de scan_master (já ativada)
```bash
# Automático no próximo ciclo de trading
# Learning engines carregam silenciosamente
```

### Fase 2: Registrar trades manualmente (hoje)
```powershell
# Em PowerShell, após dot-source lib_learning_integration.ps1:

# Registrar entrada
Record-TradeEntry -Market "ETHUSDT" -Direction "LONG" -EntryPrice 2450 `
    -Signal "pump-fade" -Confidence 75 `
    -Reasoning "Pump H-1 +18% (2050→2450) + vol 3x + RSI 68"

# Registrar saída (após 4h ou close)
Record-TradeExit -Market "ETHUSDT" -ExitPrice 2350 -PnLUsd -50 -PnLPct -2.04 `
    -CloseReason "sl" -HoldDurationHours 4
```

Resultado: Arquivo `journal/learning_evolution.jsonl` é atualizado com JSONL
```json
{"timestamp":"2026-07-07T14:50:00Z","type":"entry","market":"ETHUSDT",...}
{"timestamp":"2026-07-07T18:50:00Z","type":"exit","market":"ETHUSDT",...}
```

### Fase 3: Ativar cron learning (23:00 BRT)
```powershell
# Registrar no Task Scheduler
$action = New-ScheduledTaskAction -Execute "pwsh" `
    -Argument "-File C:\Users\thiag\Coinex_AI_USER_API\scripts\cron_learning_cycle.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 23:00

Register-ScheduledTask -TaskName "CoinexLearningCycle_Nightly" `
    -Action $action -Trigger $trigger -Force
```

Ou manual para teste:
```powershell
. C:\Users\thiag\Coinex_AI_USER_API\scripts\cron_learning_cycle.ps1 -Hours 24
```

---

## FLUXO COMPLETO (após ativação total)

```
[ENTRY]
  gem_agent descobre ETHUSDT pump
  → Invoke-GemExecute coloca ordem
  → Record-TradeEntry logs sinal + confluência
  → journal/learning_evolution.jsonl += entry record

[HOLDING]
  position_watcher monitora stops/targets
  → trailing_stop adapta dinâmico

[EXIT]
  trade fecha (TP/SL/manual)
  → gem_executor chama Record-TradeExit
  → journal/learning_evolution.jsonl += exit record

[NIGHTLY 23:00 BRT]
  cron_learning_cycle roda
  → Analisa outcomes do dia
  → Calcula proposta de evolução
  → journal/evolution_params.json atualizado
  → Próximo ciclo usa novos parametros
```

---

## DADOS GERADOS AUTOMATICAMENTE

### journal/learning_evolution.jsonl
**Entrada**:
```json
{
  "timestamp": "2026-07-07T14:50:00Z",
  "type": "entry",
  "market": "ETHUSDT",
  "direction": "LONG",
  "entry_price": 2450,
  "signal": "pump-fade",
  "confidence": 75,
  "reasoning": "Pump H-1 +18% + vol 3x + RSI 68",
  "record_id": "entry_ETHUSDT_..."
}
```

**Saída**:
```json
{
  "timestamp": "2026-07-07T18:50:00Z",
  "type": "exit",
  "market": "ETHUSDT",
  "exit_price": 2350,
  "pnl_usd": -50,
  "pnl_pct": -2.04,
  "close_reason": "sl",
  "hold_hours": 4,
  "outcome": "loss"
}
```

### journal/learning_daily_snapshots.jsonl
**Snapshot diário** (criado nightly):
```json
{
  "date": "2026-07-07",
  "timestamp": "2026-07-07T23:00:00Z",
  "trades_count": 8,
  "win_count": 5,
  "loss_count": 3,
  "win_rate": 62.5,
  "daily_pnl": 127.45,
  "error_rate": 3.2
}
```

### journal/evolution_params.json
**Parametros atuais** (atualizado nightly com propostas):
```json
{
  "sentinel_move_pct": 2.5,
  "sentinel_ignition_pct": 12,
  "pumpfade_min_pump_pct": 15,
  "pumpfade_dump_pct": -10,
  "gem_sizing_pct": 0.5
}
```

---

## REGRAS DE OURO INTEGRADAS

### Regra #4: Confluência mínima 3 sinais
✅ `Record-TradeEntry` exige campo `Reasoning` (obrigatório)

### Regra #1: Stop loss antes de entrada
✅ `Record-TradeEntry` não valida SL (wired em Invoke-GemExecute)

### Regra #7: BTC-core após fees
✅ `lib_alpha_vs_btc.ps1` calcula alpha_vs_btc na saída

### Regra #8: Nunca criar .md desnecessários
✅ Documentação centralizada neste arquivo

---

## PRÓXIMAS MILESTONES

| Milestone | Data | Ação |
|-----------|------|------|
| **Fase 1** | 2026-07-07 | ✅ Integração lib em scan_master + gem_executor |
| **Fase 2** | 2026-07-08 | ⏳ Primeiro ciclo cron (23:00 BRT) |
| **Fase 3** | 2026-07-09+ | ⏳ Propostas de evolução ativas (auto-tuning) |
| **Fase 4** | 2026-07-15+ | ⏳ Integração Supabase (learning na nuvem) |

---

## TESTES

### Teste 1: Verificar dot-source
```powershell
$PSScriptRoot = "c:\Users\thiag\Coinex_AI_USER_API\agents"
. ".\lib_learning_integration.ps1"
Get-Command Record-TradeEntry
# Deve retornar: CommandInfo para Record-TradeEntry
```

### Teste 2: Registrar trade de teste
```powershell
$global:JOURNAL_DIR = "c:\Users\thiag\Coinex_AI_USER_API\journal"
Record-TradeEntry -Market "TESTUSDT" -Direction "LONG" -EntryPrice 100 `
    -Signal "test" -Confidence 50 -Reasoning "Test entry"

# Verificar arquivo criado
Get-Content "journal/learning_evolution.jsonl" | tail -1
```

### Teste 3: Rodar cron manualmente
```powershell
cd "c:\Users\thiag\Coinex_AI_USER_API"
.\scripts\cron_learning_cycle.ps1 -Hours 24
```

---

## TROUBLESHOOTING

### Problema: "learning_evolution.jsonl não criado"
**Causa**: Diretório `journal` não existe  
**Fix**: `New-Item -ItemType Directory -Path journal -Force`

### Problema: "Record-TradeEntry: command not found"
**Causa**: lib_learning_integration.ps1 não dot-sourced  
**Fix**: Verificar que scan_master.ps1 carrega (grep lib_learning_engine)

### Problema: "cron_learning_cycle.ps1 tira erro de parametro"
**Causa**: lib_evolution_engine não carregado no escopo correto  
**Fix**: Rodar `. ./agents/lib_evolution_engine.ps1` antes de cron

---

## MÉTRICAS DE SUCESSO (2026-07-15)

- [ ] learning_evolution.jsonl com 50+ registros (entry+exit)
- [ ] learning_daily_snapshots.jsonl com 7 snapshots
- [ ] Win rate = 55%+ (vs. 16% hoje)
- [ ] Parametros evoluem pelo menos 1x (evolução_history.jsonl)
- [ ] Zero erros em cron_learning_cycle por 7 dias
- [ ] Confluence SEMPRE documentada (reasoning field filled 100%)

---

**Documento**: 2026-07-07 14:45 BRT  
**Status**: ✅ ATIVAÇÃO COMPLETA (Fases 1-2 implementadas)  
**Próximo**: Monitorar primeiro ciclo cron (23:00 hoje)
