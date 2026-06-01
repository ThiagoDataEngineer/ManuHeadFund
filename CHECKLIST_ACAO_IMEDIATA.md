# ✅ Checklist de Ação Imediata

**Data**: 2026-06-01 09:30 UTC  
**Status**: Pronto para reinicialização

---

## 🎯 O Que Fazer Agora

### 1. Sincronizar Local (SE NÃO FEITO)
```powershell
cd c:\Users\thiag\Coinex_AI_USER_API
git pull origin main --no-edit
```
**Status**: ✅ Já feito

---

### 2. Reiniciar chain_agent.ps1

**Opção A: Parar e Reiniciar (Recomendado)**
```powershell
# Parar o processo atual
Stop-Process -Name powershell -Filter "chain_agent" -Force

# Aguardar 5 segundos
Start-Sleep -Seconds 5

# Reiniciar
cd c:\Users\thiag\Coinex_AI_USER_API
.\agents\chain_agent.ps1
```

**Opção B: Usar Script de Restart**
```powershell
# Se existir script de restart
.\restart_with_fix.ps1
```

---

### 3. Monitorar por 3 Ciclos (15-30 minutos)

**O que procurar nos logs:**

#### ✅ Sinais de Sucesso
- [ ] BTCUSDT processado normalmente
- [ ] Nenhum timeout de 240s
- [ ] Nenhuma INVARIANT_VIOLATION
- [ ] Ciclos completam em 150-180s (vs 300s antes)

#### ❌ Sinais de Problema
- [ ] BTCUSDT ainda sofre timeout
- [ ] INVARIANT_VIOLATION ainda aparece
- [ ] Ciclos ainda levam 300s+

**Comando para monitorar logs:**
```powershell
# Ver últimas linhas do log
Get-Content logs/master_*.log -Tail 50 -Wait

# Procurar por timeout
Select-String "timeout_240s" logs/master_*.log

# Procurar por INVARIANT_VIOLATION
Select-String "INVARIANT_VIOLATION" logs/master_*.log

# Procurar por BTCUSDT
Select-String "BTCUSDT" logs/master_*.log
```

---

### 4. Validar Resultado

#### Métrica 1: Timeout Desapareceu?
```powershell
# Procurar por timeouts
Select-String "timeout_240s" logs/master_*.log | Measure-Object

# Esperado: 0 resultados
```

#### Métrica 2: INVARIANT_VIOLATION Desapareceu?
```powershell
# Procurar por invariant violations
Select-String "INVARIANT_VIOLATION" logs/master_*.log | Measure-Object

# Esperado: 0 resultados
```

#### Métrica 3: BTCUSDT Processado?
```powershell
# Procurar por BTCUSDT
Select-String "BTCUSDT" logs/master_*.log | Select-Object -Last 5

# Esperado: Deve aparecer com razão válida (não INVARIANT_VIOLATION)
```

#### Métrica 4: Performance Melhorou?
```powershell
# Procurar por tempo de ciclo
Select-String "Ciclo completo em" logs/master_*.log | Select-Object -Last 3

# Esperado: 150-180s (vs 300s antes)
```

---

## 📋 Checklist de Monitoramento

- [ ] **Hora de Início**: ___________
- [ ] **Ciclo 1 Completado**: ✅ / ❌
  - Timeout BTCUSDT? ✅ Não / ❌ Sim
  - INVARIANT_VIOLATION? ✅ Não / ❌ Sim
  - Tempo: _________ s

- [ ] **Ciclo 2 Completado**: ✅ / ❌
  - Timeout BTCUSDT? ✅ Não / ❌ Sim
  - INVARIANT_VIOLATION? ✅ Não / ❌ Sim
  - Tempo: _________ s

- [ ] **Ciclo 3 Completado**: ✅ / ❌
  - Timeout BTCUSDT? ✅ Não / ❌ Sim
  - INVARIANT_VIOLATION? ✅ Não / ❌ Sim
  - Tempo: _________ s

---

## 🚨 Se Problema Persistir

### Passo 1: Verificar Logs
```powershell
# Ver últimas 100 linhas
Get-Content logs/master_*.log -Tail 100

# Procurar por erros
Select-String "ERROR|WARN" logs/master_*.log | Select-Object -Last 20
```

### Passo 2: Verificar Código
```powershell
# Verificar se fix está presente
Select-String "BTCUSDT_TIMEOUT_FIX" agents/orchestrator_v6.ps1

# Esperado: Deve encontrar a warning
```

### Passo 3: Verificar Git Status
```powershell
git status
git log --oneline -5

# Esperado: Deve mostrar commits 41ba1c9, 62116b5, f21b7a7
```

### Passo 4: Forçar Reload
```powershell
# Parar tudo
Stop-Process -Name powershell -Filter "chain_agent" -Force
Stop-Process -Name powershell -Filter "scan_master" -Force

# Aguardar 10 segundos
Start-Sleep -Seconds 10

# Limpar cache PowerShell
Remove-Item -Path "$env:TEMP\*" -Force -ErrorAction SilentlyContinue

# Reiniciar
cd c:\Users\thiag\Coinex_AI_USER_API
.\agents\chain_agent.ps1
```

---

## 📞 Resumo

**O que foi feito:**
- ✅ Identificado bug na lógica de roteamento de mode
- ✅ Fix foi refatorado para ser completo
- ✅ Commitado e pushed para GitHub
- ✅ Local sincronizado

**O que você precisa fazer:**
1. Reiniciar `chain_agent.ps1`
2. Monitorar por 3 ciclos
3. Validar que timeout desapareceu
4. Confirmar que INVARIANT_VIOLATION desapareceu

**Tempo estimado**: 30-45 minutos

---

**Status**: ✅ PRONTO PARA REINICIALIZAÇÃO

