# ✅ CRON JOBS CONFIGURADOS COM SUCESSO!

## 📋 Tarefas Criadas

### 1. **CoinEx_PositionRisk** (15 minutos)
- **Script**: `scripts\position_risk_cron.ps1`
- **Função**: Trailing stops, leverage adjustment, liquidation protection
- **Próxima execução**: Verificar com `schtasks /query /tn "CoinEx_PositionRisk"`

### 2. **CoinEx_Dashboard** (5 minutos)
- **Script**: `scripts\generate_position_dashboard.ps1`
- **Função**: Gera dashboard HTML com métricas
- **Output**: `dashboard\position_metrics.html`

### 3. **CoinEx_ToriMonitoring** (30 minutos)
- **Script**: `scripts\tori_monitoring_cron.ps1`
- **Função**: Monitora proximidade de trendlines
- **Alertas**: `journal\tori_proximity_alerts.jsonl`

---

## 🎯 Comandos Úteis

### Verificar Status das Tarefas
```powershell
# Listar todas as tarefas CoinEx
schtasks /query | findstr "CoinEx"

# Ver detalhes de uma tarefa específica
schtasks /query /tn "CoinEx_PositionRisk" /fo LIST /v
schtasks /query /tn "CoinEx_Dashboard" /fo LIST /v
schtasks /query /tn "CoinEx_ToriMonitoring" /fo LIST /v
```

### Executar Manualmente
```powershell
# Executar Position Risk Manager
schtasks /run /tn "CoinEx_PositionRisk"

# Executar Dashboard Generator
schtasks /run /tn "CoinEx_Dashboard"

# Executar Tori Monitoring
schtasks /run /tn "CoinEx_ToriMonitoring"
```

### Pausar/Retomar Tarefas
```powershell
# Pausar tarefa
schtasks /change /tn "CoinEx_PositionRisk" /disable

# Retomar tarefa
schtasks /change /tn "CoinEx_PositionRisk" /enable
```

### Remover Tarefas
```powershell
# Remover uma tarefa
schtasks /delete /tn "CoinEx_PositionRisk" /f

# Remover todas as tarefas CoinEx_*
schtasks /delete /tn "CoinEx_PositionRisk" /f
schtasks /delete /tn "CoinEx_Dashboard" /f
schtasks /delete /tn "CoinEx_ToriMonitoring" /f
```

---

## 📊 Monitoramento

### Dashboard
```powershell
# Abrir dashboard no navegador
Start-Process "C:\Users\thiag\Coinex_AI_USER_API\dashboard\position_metrics.html"

# Verificar se dashboard existe
Test-Path ".\dashboard\position_metrics.html"
```

### Logs
```powershell
# Ver logs de execução
Get-Content ".\journal\position_risk_log.txt" -Tail 50

# Ver alertas de liquidação
Get-Content ".\journal\liquidation_alerts.txt" -Tail 20

# Ver alertas Tori
Get-Content ".\journal\tori_proximity_alerts.jsonl" -Tail 10
```

### Task Scheduler (GUI)
```powershell
# Abrir Task Scheduler
taskschd.msc
```

---

## 🧪 Teste Manual

### Testar Position Risk Manager
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API

# Executar manualmente
.\scripts\position_risk_cron.ps1

# Ou via schtasks
schtasks /run /tn "CoinEx_PositionRisk"
```

### Testar Dashboard Generator
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API

# Executar manualmente
.\scripts\generate_position_dashboard.ps1

# Abrir dashboard
Start-Process ".\dashboard\position_metrics.html"
```

### Testar Tori Monitoring
```powershell
cd C:\Users\thiag\Coinex_AI_USER_API

# Executar manualmente
.\scripts\tori_monitoring_cron.ps1

# Ver alertas
Get-Content ".\journal\tori_proximity_alerts.jsonl" -Tail 5
```

---

## ⚙️ Configuração Avançada

### Alterar Intervalo de Execução

#### Position Risk Manager (mudar de 15 para 10 minutos)
```powershell
schtasks /delete /tn "CoinEx_PositionRisk" /f
schtasks /create /tn "CoinEx_PositionRisk" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\thiag\Coinex_AI_USER_API\scripts\position_risk_cron.ps1" /sc minute /mo 10 /f
```

#### Dashboard (mudar de 5 para 3 minutos)
```powershell
schtasks /delete /tn "CoinEx_Dashboard" /f
schtasks /create /tn "CoinEx_Dashboard" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\thiag\Coinex_AI_USER_API\scripts\generate_position_dashboard.ps1" /sc minute /mo 3 /f
```

### Executar Apenas em Horário Específico
```powershell
# Executar apenas das 9h às 18h (horário de trading)
schtasks /create /tn "CoinEx_PositionRisk_Trading" /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\thiag\Coinex_AI_USER_API\scripts\position_risk_cron.ps1" /sc minute /mo 15 /st 09:00 /et 18:00 /f
```

---

## 🔔 Alertas Telegram

Os scripts enviam alertas via Telegram quando:
- ⚠️ Posição próxima de liquidação
- 📊 Trailing stop ativado
- 🎯 TP hit (ladder exits)
- 📈 Setup ripening (Tori)

Verifique se `lib_telegram.ps1` está configurado com seu bot token.

---

## 📈 Métricas de Performance

### Dashboard Mostra:
- Win rate (%)
- PnL total (USDT)
- Profit factor
- Posições abertas
- Top 5 markets
- Melhores e piores trades

### Atualização:
- Dashboard: A cada 5 minutos
- Position Risk: A cada 15 minutos
- Tori Monitoring: A cada 30 minutos

---

## 🚨 Troubleshooting

### Tarefa não executa
```powershell
# Verificar status
schtasks /query /tn "CoinEx_PositionRisk" /fo LIST

# Ver último resultado (0 = sucesso)
schtasks /query /tn "CoinEx_PositionRisk" /fo LIST /v | findstr "Último"

# Executar manualmente para ver erros
.\scripts\position_risk_cron.ps1
```

### Dashboard não gera
```powershell
# Verificar se script existe
Test-Path ".\scripts\generate_position_dashboard.ps1"

# Executar manualmente
.\scripts\generate_position_dashboard.ps1

# Verificar erros
$Error[0]
```

### Permissões
```powershell
# Verificar execution policy
Get-ExecutionPolicy

# Ajustar se necessário
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## 📊 Status Atual

```
✅ CoinEx_PositionRisk     - Criado (15 minutos)
✅ CoinEx_Dashboard        - Criado (5 minutos)
✅ CoinEx_ToriMonitoring   - Criado (30 minutos)
```

**Próxima execução**: Verificar com `schtasks /query /tn "CoinEx_PositionRisk"`

---

## 🎯 Próximos Passos

1. **Aguardar primeira execução** (5-15 minutos)
2. **Verificar dashboard** (`dashboard\position_metrics.html`)
3. **Monitorar logs** (`journal\*.txt`, `journal\*.jsonl`)
4. **Ajustar parâmetros** se necessário
5. **Testar em paper trading** (3-5 dias)

---

**Criado em**: 2026-05-23  
**Status**: ✅ **CRON JOBS ATIVOS**  
**Monitoramento**: 24/7 automático
