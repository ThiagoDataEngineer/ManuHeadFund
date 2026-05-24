# CoinEx AI Trading System

Sistema automatizado de trading com IA para CoinEx Futures.

---

## 🚀 SETUP RÁPIDO (1 Comando)

### Clique direito → Executar com PowerShell:
```
SETUP_COMPLETO_OCULTO_ADMIN.ps1
```

Isso vai:
1. ✅ Configurar trailing stop para rodar OCULTO
2. ✅ Configurar dashboard HTML para atualizar OCULTO
3. ✅ Abrir dashboard no navegador
4. ✅ Criar atalho na área de trabalho

**Depois disso, você usa APENAS o Dashboard HTML no navegador!**

**PowerShell NÃO vai mais aparecer!** 🔇

---

## 📊 Dashboard HTML

### Abrir Dashboard:
- Clique no atalho "CoinEx Dashboard" na área de trabalho
- OU abra: `dashboard\index.html`

### Recursos:
- ✅ Posições abertas com PNL em tempo real
- ✅ Capital disponível
- ✅ Alertas visuais (posições sem stop loss)
- ✅ Auto-refresh a cada 5 minutos
- ✅ Design profissional (estilo terminal financeiro)

---

## ⚠️ AÇÃO URGENTE: Proteger NEAR

Depois do setup, execute UMA VEZ (clique direito → Executar com PowerShell):
```
PROTECT_NEAR_NOW.ps1
```

Isso configura o stop loss da posição NEAR que está desprotegida.

---

## 📁 Estrutura do Projeto

```
Coinex_AI_USER_API/
├── SETUP_COMPLETO_OCULTO_ADMIN.ps1  ← COMECE AQUI
├── PROTECT_NEAR_NOW.ps1             ← Execute depois do setup
├── dashboard/
│   └── index.html                   ← Dashboard visual
├── agents/                          ← Código principal
├── scripts/                         ← Scripts de automação
├── tests/                           ← Testes TDD
├── logs/                            ← Logs do sistema
└── docs/                            ← Documentação
```

---

## 🔧 Tasks Agendadas (Ocultas)

Depois do setup, estas tasks rodam automaticamente em background:

### 1. CoinEx_TrailingStop_Monitor
- **Frequência**: A cada 5 minutos
- **Função**: Ajustar trailing stops das posições
- **Status**: Oculto (sem janela)

### 2. CoinEx_Update_Dashboard_HTML
- **Frequência**: A cada 5 minutos
- **Função**: Atualizar dashboard HTML com dados da API
- **Status**: Oculto (sem janela)

---

## 📝 Ver Logs (Se Precisar)

```powershell
# Ver últimas 50 linhas
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ver ao vivo (Ctrl+C para sair)
Get-Content logs\trailing_stop_monitor.log -Tail 50 -Wait
```

---

## 🛑 Controlar Tasks (Se Precisar)

### Ver Tasks
```powershell
Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
```

### Desabilitar
```powershell
Disable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
Disable-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML"
```

### Habilitar
```powershell
Enable-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor"
Enable-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML"
```

### Remover
```powershell
Unregister-ScheduledTask -TaskName "CoinEx_TrailingStop_Monitor" -Confirm:$false
Unregister-ScheduledTask -TaskName "CoinEx_Update_Dashboard_HTML" -Confirm:$false
```

---

## 🎯 Funcionalidades

### ✅ Implementado

1. **Validação Pós-Execução**
   - Verifica se stop loss foi configurado
   - Retry automático com fallback
   - Alertas se posição sem proteção

2. **Trailing Stop Inteligente**
   - Baseado em ATR, suportes técnicos e leverage
   - Threshold de ativação: +3% de lucro
   - Ajustes dinâmicos por volatilidade

3. **Dashboard HTML**
   - Design profissional
   - Auto-refresh a cada 5 minutos
   - Alertas visuais
   - Dados reais da API

4. **Tasks Ocultas**
   - Rodam em background
   - Sem janelas do PowerShell
   - Logs auditáveis

---

## 📚 Documentação

### Guias
- `COMECE_AQUI.md` - Setup rápido
- `docs/guides/TASK_OCULTA_GUIA.md` - Tasks ocultas
- `docs/guides/QUICK_START_VALIDACAO.md` - Sistema de validação

### Documentação Técnica
- `docs/current/` - Documentação atual (2026-05-24)
- `docs/archive/` - Documentação antiga

---

## 🧪 Testes

```powershell
# Executar testes
Invoke-Pester tests\lib_order_validation.Tests.ps1
```

**Status**: ✅ 9/9 testes passando

---

## 🔄 Workflow Recomendado

### Setup Inicial (Uma Vez)
1. Execute: `SETUP_COMPLETO_OCULTO_ADMIN.ps1` (como admin)
2. Dashboard abre no navegador
3. Execute: `PROTECT_NEAR_NOW.ps1` (proteger NEAR)

### Uso Diário
1. Abra o dashboard HTML (atalho na área de trabalho)
2. Deixe aberto (atualiza a cada 5 minutos)
3. Pronto! Sistema roda sozinho em background

---

## 📊 Status Atual

### Posições
```
BNBUSDT  : +2.13% ✅ Stop: $627.82
SOLUSDT  : +0.69% ✅ Stop: $82.30
LINKUSDT : +0.29% ✅ Stop: $9.15
UNIUSDT  : -0.33% ✅ Stop: $3.30
NEARUSDT : -0.96% ❌ SEM STOP LOSS (URGENTE)
```

### Tasks
```
CoinEx_TrailingStop_Monitor: Ready (oculto)
CoinEx_Update_Dashboard_HTML: Ready (oculto)
```

---

## 🎓 Lições Aprendidas

1. **Nunca confie na API sem validação**
   - CoinEx-PlaceOrder com -stopLoss não funciona
   - Sempre validar resultado real

2. **Tasks ocultas são essenciais**
   - Rodam em background sem interromper
   - Logs auditáveis para troubleshooting

3. **Dashboard HTML é melhor para monitoramento**
   - Visual e profissional
   - Auto-refresh automático
   - Pode deixar aberto em segunda tela

---

## 📞 Suporte

### Comandos Rápidos
```powershell
# Setup completo
.\SETUP_COMPLETO_OCULTO_ADMIN.ps1

# Proteger NEAR
.\PROTECT_NEAR_NOW.ps1

# Abrir dashboard
Start-Process "dashboard\index.html"

# Ver logs
Get-Content logs\trailing_stop_monitor.log -Tail 50

# Ver tasks
Get-ScheduledTask | Where-Object { $_.TaskName -like "*CoinEx*" }
```

---

## 🚀 Próximos Passos

1. ⚡ **AGORA**: Execute `SETUP_COMPLETO_OCULTO_ADMIN.ps1`
2. ⚠️ **URGENTE**: Execute `PROTECT_NEAR_NOW.ps1`
3. 📊 **DIÁRIO**: Abra dashboard HTML (atalho na área de trabalho)

---

**COMECE AGORA: `SETUP_COMPLETO_OCULTO_ADMIN.ps1`** 🚀
