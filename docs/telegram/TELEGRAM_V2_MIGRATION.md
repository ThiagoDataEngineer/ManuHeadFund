# 📱 TELEGRAM V2 - Migração para Mensagens Limpas

**Data**: 2026-05-26  
**Status**: ✅ PRONTO PARA DEPLOY  
**Objetivo**: Substituir mensagens verbosas por **concisas, claras e acionáveis**

---

## 🎯 O Problema (V1)

### ❌ ANTES (Verboso):
```
==========================
>> POSITION OPENED <<
==========================

Market: ZKJUSDT
Side: LONG
Entry: $0.45
Size: 30.8
Leverage: 5x

Stop Loss: $0.225
Take Profit: $1.35

Capital: $13.81 USDT
```

**Problemas**:
- Muita informação desnecessária
- Difícil de ler rapidamente
- Não é acionável (usuário não sabe o que fazer)
- Poluição visual

---

## ✅ A Solução (V2)

### ✅ DEPOIS (Limpo):
```
🟢 LONG | ZKJUSDT | 5x
Entry: $0.45 | Size: 30.8
Stop: -50% | Target: +200%
Capital: $13.81
```

**Benefícios**:
- ✅ Informação crítica primeiro
- ✅ Fácil de ler em 2 segundos
- ✅ Emojis para contexto visual
- ✅ Acionável e clara

---

## 📊 Comparação Completa

### TRADE OPENED

**V1 (Antes)**:
```
==========================
>> POSITION OPENED <<
==========================

Market: ZKJUSDT
Side: LONG
Entry: $0.45
Size: 30.8
Leverage: 5x

Stop Loss: $0.225
Take Profit: $1.35

Capital: $13.81 USDT
```

**V2 (Depois)**:
```
🟢 LONG | ZKJUSDT | 5x
Entry: $0.45 | Size: 30.8
Stop: -50% | Target: +200%
Capital: $13.81
```

---

### TRADE CLOSED

**V1 (Antes)**:
```
==========================
>> POSITION CLOSED [WIN] <<
==========================

Market: ZKJUSDT
Side: LONG
Entry: $0.45
Exit: $0.90

PnL: +$13.81 (+200%)
Duration: 2h 15m
Reason: Take Profit Hit
```

**V2 (Depois)**:
```
✅ WIN | ZKJUSDT [LONG]
Entry: $0.45 → Exit: $0.90
P&L: +$13.81 (+200%)
Duration: 2h 15m | Reason: Take Profit Hit
```

---

### GEM FOUND

**V1 (Antes)**:
```
🔬 GEM ALERT — ZKJUSDT [DISCOVERY]
Score: 85/100 | Modo: DISCOVERY
📊 Vol spike: 3.2x | Chg 24h: 22.5%
MCap: 45.2M | FP: PUMP_CLASSIC
Gates: G1 G2 G3
💰 Sizing: 0.5% ($13.81)
Stop: 50% | Target: +200%
✅ APROVAR este gem?
```

**V2 (Depois)**:
```
🔬 GEM | ZKJUSDT | 🟢 Score: 85/100
Vol: 3.2x ↑22.5% | Tamanho: $13.81
Stop: -50% | Target: +200%
```

---

### DAILY SUMMARY

**V1 (Antes)**:
```
==========================
>> DAILY SUMMARY [UP] <<
==========================

Date: 2026-05-26

Trades: 5
Wins: 4 | Losses: 1
Win Rate: 80%

Daily PnL: +$45.23
Total PnL: +$234.56

Open Positions: 2
Capital: $1,234.56 USDT
```

**V2 (Depois)**:
```
📈 RESUMO DIÁRIO | 26/05/2026
Trades: 5 | Wins: 4 | Losses: 1
Win Rate: ✅ 80%
P&L Diário: +$45.23 | Total: +$234.56
Posições Abertas: 2 | Capital: $1,234.56
```

---

## 🔄 Como Migrar

### Passo 1: Ativar V2

```powershell
# Editar seu script que carrega as libs
# ANTES:
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

### Passo 2: Atualizar Chamadas

**Exemplo 1: Trade Aberto**

```powershell
# ANTES:
Telegram-SendPositionOpened -Position @{
    market = "ZKJUSDT"
    side = "long"
    entry_price = 0.45
    size = 30.8
    leverage = 5
    stop_loss = 0.225
    take_profit = 1.35
    capital = 13.81
}

# DEPOIS:
Telegram-SendTradeOpened -Trade @{
    market = "ZKJUSDT"
    side = "long"
    entry_price = 0.45
    size = 30.8
    leverage = 5
    stop_pct = 50
    target_pct = 200
    capital = 13.81
}
```

**Exemplo 2: Gem Encontrado**

```powershell
# ANTES:
Send-GemAlert -Gem $gem

# DEPOIS:
Telegram-SendGemFound -Gem $gem
```

**Exemplo 3: Gem Aprovação**

```powershell
# ANTES:
$msg = Format-TgGemApproval -Gem $gem
Telegram-SendMessage -Message $msg

# DEPOIS:
Telegram-SendGemApprovalRequest -Gem $gem
```

---

## 📋 Mapeamento de Funções

| V1 | V2 | Notas |
|---|---|---|
| `Telegram-SendPositionOpened` | `Telegram-SendTradeOpened` | Renomeado para clareza |
| `Telegram-SendPositionClosed` | `Telegram-SendTradeClosed` | Renomeado para clareza |
| `Telegram-SendTrailingActivated` | `Telegram-SendTrailingActivated` | Sem mudança (compatível) |
| `Telegram-SendRiskAlert` | `Telegram-SendRiskAlert` | Sem mudança (compatível) |
| `Telegram-SendDailySummary` | `Telegram-SendDailySummary` | Sem mudança (compatível) |
| `Telegram-SendDashboardSnapshot` | `Telegram-SendDashboardSnapshot` | Sem mudança (compatível) |
| `Send-GemAlert` | `Telegram-SendGemFound` | Renomeado, mantém compatibilidade |
| `Format-TgGemApproval` | `Format-TgGemApproval` | Sem mudança (compatível) |
| `Format-TgGemExecuted` | `Format-TgGemExecuted` | Sem mudança (compatível) |
| **NOVO** | `Telegram-SendSystemStatus` | Novo: Status do sistema |
| **NOVO** | `Telegram-SendCalibrationProgress` | Novo: Progresso calibração |
| **NOVO** | `Telegram-SendQuotaWarning` | Novo: Aviso de quota |

---

## 🚀 Novas Funções

### 1. System Status
```powershell
Telegram-SendSystemStatus -Status @{
    is_running = $true
    status = "OPERACIONAL"
    uptime_hours = 24
    memory_usage = 45
    cpu_usage = 12
    last_activity = "2026-05-26 22:30:00"
}
```

**Output**:
```
✅ SISTEMA | 26/05/2026 22:30:00
Status: OPERACIONAL | Uptime: 24 h
Memória: 45% | CPU: 12%
Última Atividade: 2026-05-26 22:30:00
```

---

### 2. Calibration Progress
```powershell
Telegram-SendCalibrationProgress -Progress @{
    day = 3
    total_days = 7
    progress_pct = 42
    trades_count = 12
    win_rate = 58
    pnl_pct = 1.2
    eta_days = 4
}
```

**Output**:
```
📈 CALIBRAÇÃO | 3/7 dias
Progresso: [████░░░░░░] 42%
Trades: 12 | Win Rate: 58%
P&L: +1.2% | ETA: 4 dias
```

---

### 3. Quota Warning
```powershell
Telegram-SendQuotaWarning -Quota @{
    usage_pct = 85
    calls_used = 12240
    calls_limit = 14400
    days_remaining = 2
    action = "MESA_SKIP_ENABLED"
}
```

**Output**:
```
⚠️ QUOTA LLM | 26/05/2026
Uso: 85% | Chamadas: 12240/14400
Dias Restantes: 2 | Ação: MESA_SKIP_ENABLED
```

---

## ✅ Checklist de Migração

- [ ] Copiar `lib_telegram_v2.ps1` para `agents/`
- [ ] Atualizar scripts que usam Telegram:
  - [ ] `scan_master.ps1`
  - [ ] `gem_agent.ps1`
  - [ ] `gem_executor.ps1`
  - [ ] `trailing_stop_monitor.ps1`
  - [ ] `daily_summary_digest.ps1`
  - [ ] `generate_dashboard_elite.ps1`
- [ ] Testar cada tipo de mensagem
- [ ] Validar compatibilidade com código antigo
- [ ] Documentar mudanças no projeto

---

## 🔙 Rollback

Se precisar voltar para V1:

```powershell
# Editar scripts e trocar:
# DE: . ".\agents\lib_telegram_v2.ps1"
# PARA: . ".\agents\lib_telegram.ps1"

# Revert chamadas de funções para nomes antigos
```

---

## 📞 Próximos Passos

1. **Agora**: Revisar V2 e aprovar
2. **Depois**: Atualizar scripts principais
3. **Teste**: Rodar com paper trade
4. **Deploy**: Ativar em produção

---

**Criado por**: Kiro Agent  
**Data**: 2026-05-26  
**Status**: ✅ PRONTO
