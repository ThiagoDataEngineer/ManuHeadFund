# 🚀 START HERE - CoinEx AI Trading System

## ⚡ Ações Rápidas

### 1. Dashboard PowerShell (Interativo)
```powershell
.\DASHBOARD.ps1
```
Menu interativo com todas as opções.

### 2. Dashboard HTML (Visual)
```powershell
# Atualizar dados
.\UPDATE_DASHBOARD_HTML.ps1

# Abrir no navegador
Start-Process "dashboard\index.html"
```
Dashboard visual profissional (auto-refresh 5 min).

### 3. Proteger NEAR (URGENTE)
```powershell
.\PROTECT_NEAR_NOW.ps1
```

### 4. Parar Janelas do PowerShell
```powershell
.\RECONFIGURAR_TASK_OCULTA.ps1
```

---

## 📊 Dashboards Disponíveis

### Dashboard PowerShell (`DASHBOARD.ps1`)
**Tipo**: Interativo (terminal)

**Recursos**:
- ✅ Tasks agendadas e status
- ✅ Posições abertas com PNL
- ✅ Capital disponível
- ✅ Logs recentes (últimas 10 linhas)
- ✅ Menu interativo
- ✅ Ações rápidas (proteger NEAR, ver logs, etc.)

**Quando usar**: Monitoramento rápido e ações imediatas

### Dashboard HTML (`dashboard/index.html`)
**Tipo**: Visual (navegador)

**Recursos**:
- ✅ Design profissional (estilo terminal financeiro)
- ✅ Métricas em cards
- ✅ Tabela de posições
- ✅ Auto-refresh a cada 5 minutos
- ✅ Responsivo (mobile-friendly)
- ✅ Alertas visuais (posições sem stop)

**Quando usar**: Monitoramento contínuo em segunda tela

**Atualizar dados**:
```powershell
.\UPDATE_DASHBOARD_HTML.ps1
```

---

## 📁 Estrutura do Projeto

### Scripts Principais (Raiz)
- `DASHBOARD.ps1` - Dashboard PowerShell interativo
- `UPDATE_DASHBOARD_HTML.ps1` - Atualizar dashboard HTML
- `PROTECT_NEAR_NOW.ps1` - Proteger posição NEAR
- `FIX_MISSING_STOPS.ps1` - Verificar todas as posições
- `RECONFIGURAR_TASK_OCULTA.ps1` - Tasks ocultas
- `EXECUTE_NEAR_LONG.ps1` - Executar ordem NEAR

### Dashboard HTML (dashboard/)
- `index.html` - Dashboard visual (atualizado por UPDATE_DASHBOARD_HTML.ps1)
- `position_metrics.html` - Dashboard antigo (não usado)

### Documentação Atual (docs/current/)
- `RESUMO_VALIDACAO_COMPLETO_2026_05_24.md` - Sistema de validação
- `TRAILING_STOP_INTELLIGENT_COMPLETE.md` - Trailing stop
- `NEAR_EXECUTADO_2026_05_24.md` - Execução NEAR

### Guias (docs/guides/)
- `QUICK_START_VALIDACAO.md` - Quick start
- `TASK_OCULTA_GUIA.md` - Tasks ocultas
- `TELEGRAM_SETUP_GUIDE.md` - Setup Telegram

### Código (agents/)
- `lib_coinex.ps1` - API CoinEx
- `lib_order_validation.ps1` - Validação pós-execução
- `lib_trailing_stop_intelligent.ps1` - Trailing stop

### Testes (tests/)
- `lib_order_validation.Tests.ps1` - Testes (9/9 passando)

### Logs (logs/)
- `trailing_stop_monitor.log` - Logs do monitor

---

## 🎯 Workflows Recomendados

### Workflow 1: Monitoramento Diário
```powershell
# 1. Abrir dashboard HTML
.\UPDATE_DASHBOARD_HTML.ps1
Start-Process "dashboard\index.html"

# 2. Deixar aberto em segunda tela (auto-refresh 5 min)

# 3. Verificar ações urgentes no PowerShell
.\DASHBOARD.ps1
```

### Workflow 2: Verificação Rápida
```powershell
# Dashboard interativo
.\DASHBOARD.ps1

# Escolher opção:
# [R] Atualizar
# [L] Ver logs
# [P] Proteger NEAR
# [F] Verificar stops
```

### Workflow 3: Setup Inicial
```powershell
# 1. Proteger NEAR
.\PROTECT_NEAR_NOW.ps1

# 2. Configurar tasks ocultas
.\RECONFIGURAR_TASK_OCULTA.ps1

# 3. Verificar outras posições
.\FIX_MISSING_STOPS.ps1

# 4. Abrir dashboard HTML
.\UPDATE_DASHBOARD_HTML.ps1
Start-Process "dashboard\index.html"
```

---

## 📊 Status Rápido

### Posições
```
BNBUSDT  : +2.13% ✅
SOLUSDT  : +0.69% ✅
LINKUSDT : +0.29% ✅
UNIUSDT  : -0.33% ✅
NEARUSDT : -0.96% ❌ SEM STOP LOSS
```

### Tasks
```
CoinEx_TrailingStop_Monitor: Ready
Executa a cada 5 minutos
```

### Testes
```
✅ 9/9 testes passando
```

---

## 🔧 Comandos Úteis

```powershell
# Dashboard PowerShell
.\DASHBOARD.ps1

# Dashboard HTML
.\UPDATE_DASHBOARD_HTML.ps1
Start-Process "dashboard\index.html"

# Ver logs
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ver tasks
Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }

# Executar testes
Invoke-Pester tests\lib_order_validation.Tests.ps1
```

---

## 🚨 Ações Urgentes

1. ⚠️ **URGENTE**: Proteger NEAR (`.\PROTECT_NEAR_NOW.ps1`)
2. 🔇 Reconfigurar tasks para oculto (`.\RECONFIGURAR_TASK_OCULTA.ps1`)
3. 📊 Abrir dashboard HTML (`.\UPDATE_DASHBOARD_HTML.ps1` + `Start-Process "dashboard\index.html"`)

---

## 📚 Documentação Completa

Ver `README.md` para documentação completa.

---

**Comece pelo Dashboard: `.\DASHBOARD.ps1` ou `.\UPDATE_DASHBOARD_HTML.ps1`** 🚀
