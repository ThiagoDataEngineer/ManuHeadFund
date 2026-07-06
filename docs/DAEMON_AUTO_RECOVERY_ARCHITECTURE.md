# Daemon Auto-Recovery Architecture v2

**Data**: 2026-07-06  
**Status**: IMPLEMENTED  
**Objetivo**: Eliminar recorrência de daemons stale que causam "0 trades" em 10+ horas

---

## Problema Histórico

| Incident | Data | Duração | Causa | Impacto |
|----------|------|---------|-------|---------|
| gem_loop morto | 2026-07-02 15:55 | 4 dias | Daemon crashed, lock stale → ninguém reinicia | 163 signals PENDING, 0 trades |
| Frota morta pós-reboot | 2026-07-04 noite | 23h | Nada religava daemons em startup | 0 processamento |
| Phantom watchdog | 2026-07-03 | ~1h | Watchdog agendado mas desabilitado/não roda | Ninguém monitora |

**Root cause**: Watchdog existe mas NÃO RODA. Task agendada sem trigger ativo.

---

## Solução: 3 Camadas de Proteção

### **Camada 1: Self-Healing (Dentro do Daemon)**
Cada daemon (`gem_loop`, `scan_master`, etc) implementa **heartbeat + liveness**:
- A cada ciclo, escreve timestamp em lock file
- Antes de sleep, valida que lock é recente
- Se lock virar stale (>5min sem update) → daemon auto-termina graceful

**Arquivo**: `agents/lib_daemon_singleton.ps1` (já existe, aguardando enhancement)

**Vantagem**: Previne zumbi silencioso  
**Desvantagem**: Reativo (demora ~5min para detectar)

---

### **Camada 2: External Watchdog (Novo!)**
Daemon independente `daemon_watchdog_loop.ps1` que:
- Roda forever (idempotent singleton próprio)
- A cada 60sec: verifica health de cada daemon crítico
- Se daemon está MORTO ou STALE (>5min sem heartbeat):
  - Remove lock stale
  - Reinicia daemon
  - Log a ação
  
**Arquivo**: `scripts/daemon_watchdog_loop.ps1`  
**Lib**: `agents/lib_daemon_watchdog_v2.ps1`

**Verificação de health**:
```powershell
Test-DaemonHealthy(name):
  1. Lock file existe? → NO = MORTO
  2. PID vivo? → NO = MORTO
  3. Lock age > 5min? → SIM = STALE
  → return $false = reinicia
```

**Vantagem**: Proativo, detecta em <60sec  
**Desvantagem**: Depende do watchdog estar rodando

---

### **Camada 3: Scheduled Task (Fallback)**
Se watchdog morrer, scheduled task roda `watchdog_autonomous_recovery.ps1`:
- Task agendada a cada 5 minutos
- Checks health de daemons
- Reinicia qualquer coisa morta

**Arquivo**: `scripts/watchdog_autonomous_recovery.ps1` (já existe, foi ignorada)

**Configuração necessária**:
```powershell
$trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 30)
$action = New-ScheduledTaskAction -Execute "pwsh" -Argument "-NoProfile -File C:\...\watchdog_autonomous_recovery.ps1"
Register-ScheduledTask -TaskName "ManuHeadFund-AutoRecoveryLoop" -Trigger $trigger -Action $action
```

**Vantagem**: Sempre roda se Windows rodando  
**Desvantagem**: Latência até 5min

---

## Fluxo Integrado

```
start_fleet.ps1 (boot/logon)
├── inicia: scan_master ✓
├── inicia: sentinel_movers ✓
├── inicia: collect_1h_klines ✓
├── inicia: gem_loop ✓
└── inicia: daemon_watchdog_loop ← NOVO

daemon_watchdog_loop (runs forever)
├── a cada 60sec
├── verifica: [scan_master, sentinel, collect_1h, gem_loop]
├── se qualquer um MORTO/STALE
│   └── Invoke-DaemonRestart → remove lock stale + Start-Process
└── log em watchdog_loop.log

(fallback) ManuHeadFund-AutoRecoveryLoop task
└── a cada 5min (if watchdog itself dies)
    └── idem: check + restart
```

---

## Integração

### **1. Boot Chain** ✅
`start_fleet.ps1` agora inicia watchdog junto:
```powershell
Start-DaemonIfDead -ScriptName "daemon_watchdog_loop.ps1"
```

Resultado: watchdog roda sempre que frota inicia (reboot, logon)

### **2. Idempotent Guards**
Watchdog usa singleton próprio (`watchdog_loop.lock`):
- Só uma instância roda por vez
- Se morrer, outra pode iniciar
- Start-fleet pode ser chamada 2x sem problema

### **3. Lock Cleanup Protocol**
Antes de restart, watchdog:
1. Valida que PID não existe
2. Remove lock file (fail-safe)
3. Inicia novo daemon
4. New daemon adquire lock com novo PID

**Previne**: Deadlock de locks stale

---

## Monitoring

### **Log Files**
```
journal/watchdog_loop.log          ← Camada 2 (external watchdog)
journal/watchdog_auto_recovery.log ← Camada 3 (scheduled task, fallback)
journal/daemon_locks/*.lock        ← Health heartbeats (atualizado a cada ciclo)
```

### **Example Healthy Output**
```
[2026-07-06 10:00:12] [WATCHDOG-V2] Iniciado (interval=60s)
[2026-07-06 10:01:12] [CYCLE 1] All daemons healthy
[2026-07-06 10:02:12] [CYCLE 2] All daemons healthy
...
[2026-07-06 10:15:30] [DOWN] gem_loop detected as dead/stale
[2026-07-06 10:15:31] [RESTARTED] gem_loop — OK
[2026-07-06 10:15:32] [CYCLE 9] Down=1 | Restarted=1
```

### **Alert Conditions**
```
If watchdog_loop.log has no entry in last 15min
  → watchdog itself is dead
  → rely on scheduled task (Camada 3)

If watchdog_auto_recovery.log shows restart on same daemon repeatedly
  → daemon crash loop
  → needs investigation + fix
```

---

## Deployment Checklist

- [ ] **Copy files**:
  - `agents/lib_daemon_watchdog_v2.ps1` ✅
  - `scripts/daemon_watchdog_loop.ps1` ✅

- [ ] **Update start_fleet.ps1** ✅
  - Add: `Start-DaemonIfDead -ScriptName "daemon_watchdog_loop.ps1"`

- [ ] **Verify scheduled task**:
  - Task `ManuHeadFund-AutoRecovery` exists
  - Trigger: every 5 minutes
  - Enabled: YES

- [ ] **Manual test**:
  ```powershell
  # Kill gem_loop manually
  Get-Process -Name pwsh | Where-Object {lock says gem_loop} | Stop-Process -Force

  # Should restart within 60sec
  # Verify: watchdog_loop.log shows [DOWN] + [RESTARTED]
  ```

---

## SLA Expectation

| Scenario | Old Behavior | New Behavior |
|----------|--------------|--------------|
| Daemon crashes | ~4 days (manual fix) | <60sec (Camada 2) |
| Watchdog crashes | N/A | <5min (Camada 3) |
| Full reboot | 20+ min (manual) | <2min (start_fleet) |
| Lock corruption | Manual cleanup | Auto cleanup (Camada 2) |

**Result**: No incident should last >5 minutes without auto-restart.

---

## Future Enhancements

1. **Metrics Export**
   - Count restarts per daemon per day
   - Alert if any daemon restarted >10x in 24h (crash loop)

2. **Graceful Shutdown**
   - Watchdog signals daemon with SIGTERM (not KILL)
   - Daemon has 10sec to cleanup
   - Then KILL if needed

3. **Circuit Breaker**
   - If daemon restarts >5x in 10min → disable it (don't keep restarting)
   - Manual enable required after fix

4. **Health Metrics to Supabase**
   - heartbeat table: daemon_id, last_seen, restart_count
   - Dashboard: "System Health" with uptime %, restart frequency

---

## Reference

- Designed to prevent: "[audit_zero_trades_2026_07_06.md]"
- Implementation: `lib_daemon_watchdog_v2.ps1`, `daemon_watchdog_loop.ps1`
- Deployment: Modified `start_fleet.ps1`
- Monitoring: `watchdog_loop.log`, scheduled task logs
