# 🔇 Task Oculta - Guia Rápido

## 🎯 PROBLEMA

PowerShell abre e fecha sozinho a cada 5 minutos (Task Scheduler do trailing stop monitor).

## ✅ SOLUÇÃO

Reconfigurar task para rodar **OCULTA (sem janela)**.

---

## 🚀 RECONFIGURAR AGORA

### Opção 1: Script Automático (Recomendado)
```powershell
.\RECONFIGURAR_TASK_OCULTA.ps1
```

### Opção 2: Manual
```powershell
# 1. Remover task antiga
Unregister-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -Confirm:$false

# 2. Criar nova task oculta
.\scripts\setup_trailing_stop_task_hidden.ps1
```

---

## 🔧 O QUE MUDA

### Antes (Janela Visível)
```powershell
-Argument "-NoProfile -ExecutionPolicy Bypass -File ..."
-LogonType Interactive  # Abre janela
```
- ❌ Janela do PowerShell abre a cada 5 minutos
- ❌ Interrompe trabalho
- ❌ Visualmente poluído

### Depois (Oculto)
```powershell
-Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ..."
-LogonType S4U  # Service For User - sem janela
-Hidden  # Task oculta
```
- ✅ Roda em background (sem janela)
- ✅ Não interrompe trabalho
- ✅ Logs continuam funcionando

---

## 📊 VERIFICAR STATUS

### Ver Task
```powershell
Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
```

### Ver Logs (Confirmar que está rodando)
```powershell
# Últimas 50 linhas
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ao vivo (Ctrl+C para sair)
Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait
```

### Ver Última Execução
```powershell
Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" | Get-ScheduledTaskInfo
```

---

## 🎛️ CONTROLAR TASK

### Desabilitar Temporariamente
```powershell
Disable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
```

### Habilitar Novamente
```powershell
Enable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
```

### Remover Completamente
```powershell
Unregister-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -Confirm:$false
```

### Executar Manualmente (Teste)
```powershell
Start-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
```

---

## 🔍 TROUBLESHOOTING

### Task Não Está Rodando
```powershell
# Verificar status
Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"

# Ver última execução e resultado
Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" | Get-ScheduledTaskInfo

# Ver logs
Get-Content logs\trailing_stop_monitor.log -Tail 50
```

### Task Ainda Abre Janela
```powershell
# Reconfigurar
.\RECONFIGURAR_TASK_OCULTA.ps1
```

### Verificar se Logs Estão Sendo Criados
```powershell
# Ver data de modificação do log
Get-Item logs\trailing_stop_monitor.log | Select-Object LastWriteTime

# Deve ser recente (últimos 5 minutos)
```

---

## 📝 LOGS

### Localização
```
logs\trailing_stop_monitor.log
```

### Formato
```
[2026-05-24 08:30:00] === TRAILING STOP MONITOR START ===
[2026-05-24 08:30:01] Buscando posicoes abertas...
[2026-05-24 08:30:02] Total positions: 5
[2026-05-24 08:30:02] Updated: 0
[2026-05-24 08:30:02] No update needed: 5
[2026-05-24 08:30:02] === VALIDACAO DE STOP LOSS ===
[2026-05-24 08:30:03] All positions have stop loss configured.
[2026-05-24 08:30:03] === TRAILING STOP MONITOR END ===
```

### Ver Logs ao Vivo
```powershell
Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait
```

---

## ✅ CHECKLIST

- [ ] Executar `.\RECONFIGURAR_TASK_OCULTA.ps1`
- [ ] Aguardar 5 minutos
- [ ] Verificar que janela NÃO abriu
- [ ] Verificar logs: `Get-Content logs\trailing_stop_monitor.log -Tail 10`
- [ ] Confirmar última execução: `Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" | Get-ScheduledTaskInfo`

---

## 🎉 RESULTADO

### Antes
- ❌ PowerShell abre a cada 5 minutos
- ❌ Janela pisca na tela
- ❌ Interrompe trabalho

### Depois
- ✅ Roda em background (oculto)
- ✅ Sem janelas
- ✅ Logs continuam funcionando
- ✅ Monitor ativo 24/7

---

## 📞 COMANDOS RÁPIDOS

```powershell
# Reconfigurar para oculto
.\RECONFIGURAR_TASK_OCULTA.ps1

# Ver logs
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ver status
Get-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"

# Desabilitar
Disable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"

# Habilitar
Enable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
```

---

**Execute agora: `.\RECONFIGURAR_TASK_OCULTA.ps1`**
