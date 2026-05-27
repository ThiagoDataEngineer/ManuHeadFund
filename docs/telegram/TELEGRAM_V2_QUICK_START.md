# 📱 TELEGRAM V2 - Quick Start

**Objetivo**: Mensagens Telegram **limpas, concisas e acionáveis**

---

## 🚀 Ativar V2 (1 minuto)

### Passo 1: Carregar a lib
```powershell
. ".\agents\lib_telegram_v2.ps1"
```

### Passo 2: Usar as funções

---

## 📋 Funções Principais

### 1️⃣ Trade Aberto
```powershell
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

**Output**:
```
🟢 LONG | ZKJUSDT | 5x
Entry: $0.45 | Size: 30.8
Stop: -50% | Target: +200%
Capital: $13.81
```

---

### 2️⃣ Trade Fechado
```powershell
Telegram-SendTradeClosed -Trade @{
    market = "ZKJUSDT"
    side = "long"
    entry_price = 0.45
    exit_price = 0.90
    pnl = 13.81
    pnl_pct = 200
    duration = "2h 15m"
    close_reason = "Take Profit Hit"
}
```

**Output**:
```
✅ WIN | ZKJUSDT [LONG]
Entry: $0.45 → Exit: $0.90
P&L: +$13.81 (+200%)
Duration: 2h 15m | Reason: Take Profit Hit
```

---

### 3️⃣ Trailing Stop Ativado
```powershell
Telegram-SendTrailingActivated -Position @{
    market = "ZKJUSDT"
    profit_pct = 150
    new_stop = 0.675
    locked_profit_pct = 100
}
```

**Output**:
```
🛡️ TRAILING ATIVO | ZKJUSDT
Lucro: +150% | Novo Stop: $0.675
Lucro Travado: +100%
```

---

### 4️⃣ Alerta de Risco
```powershell
Telegram-SendRiskAlert -Alert @{
    market = "ZKJUSDT"
    type = "LIQUIDATION_NEAR"
    severity = "HIGH"
    current_price = 0.50
    liq_price = 0.225
    distance_pct = 55
    action = "REDUCE_POSITION"
}
```

**Output**:
```
⚠️ ALERTA | ZKJUSDT
Tipo: LIQUIDATION_NEAR | Severidade: HIGH
Preço: $0.50 | Liquidação: $0.225
Distância: 55% | Ação: REDUCE_POSITION
```

---

### 5️⃣ Resumo Diário
```powershell
Telegram-SendDailySummary -Summary @{
    trades_count = 5
    wins = 4
    losses = 1
    win_rate = 80
    daily_pnl = 45.23
    total_pnl = 234.56
    open_positions = 2
    capital = 1234.56
}
```

**Output**:
```
📈 RESUMO DIÁRIO | 26/05/2026
Trades: 5 | Wins: 4 | Losses: 1
Win Rate: ✅ 80%
P&L Diário: +$45.23 | Total: +$234.56
Posições Abertas: 2 | Capital: $1,234.56
```

---

### 6️⃣ Gem Encontrado
```powershell
Telegram-SendGemFound -Gem @{
    market = "ZKJUSDT"
    mode = "DISCOVERY"
    score = 85
    vol_data = @{
        spike_ratio = 3.2
        pct_change_today = 22.5
    }
    sizing = @{
        sizing_usd = 13.81
        stop_pct = 50
        target_pct = 200
    }
}
```

**Output**:
```
🔬 GEM | ZKJUSDT | 🟢 Score: 85/100
Vol: 3.2x ↑22.5% | Tamanho: $13.81
Stop: -50% | Target: +200%
```

---

### 7️⃣ Gem Aprovação
```powershell
Telegram-SendGemApprovalRequest -Gem @{
    market = "ZKJUSDT"
    mode = "DISCOVERY"
    score = 85
    vol_data = @{
        spike_ratio = 3.2
        pct_change_today = 22.5
    }
    sizing = @{
        sizing_usd = 13.81
        stop_pct = 50
        target_pct = 200
    }
}
```

**Output**:
```
🔬 APROVAR? | ZKJUSDT | 🟢 85/100
Vol: 3.2x ↑22.5% | Tamanho: $13.81
Stop: -50% | Target: +200%
✅ Sim | ❌ Não
```

---

### 8️⃣ Gem Executado
```powershell
Telegram-SendGemExecuted -Gem $gem -ExecResult @{
    success = $true
    error = $null
}
```

**Output**:
```
✅ EXECUTADO | ZKJUSDT | Score: 85/100
Tamanho: $13.81 | Modo: DISCOVERY
```

---

### 9️⃣ Dashboard Snapshot
```powershell
Telegram-SendDashboardSnapshot -Metrics @{
    open_positions = 2
    total_pnl = 234.56
    win_rate = 80
    capital = 1234.56
    sharpe_ratio = 1.45
    max_drawdown = -5.2
    profit_factor = 3.2
    open_positions_detail = @(
        @{ market = "ZKJUSDT"; side = "long"; unrealized_pnl_pct = 15.5 },
        @{ market = "BTCUSDT"; side = "short"; unrealized_pnl_pct = -2.3 }
    )
}
```

**Output**:
```
📊 DASHBOARD | 22:30:00
Posições: 2 | P&L: +$234.56 [📈]
Win Rate: ✅ 80% | Capital: $1,234.56
Sharpe: 1.45 | Drawdown: -5.2%

--- Posições Abertas ---
🟢 ZKJUSDT: +15.5%
🔴 BTCUSDT: -2.3%
```

---

### 🔟 Status do Sistema
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

### 1️⃣1️⃣ Progresso Calibração
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

### 1️⃣2️⃣ Aviso de Quota
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

## 🎨 Emojis Usados

| Emoji | Significado |
|---|---|
| 🟢 | LONG / Positivo |
| 🔴 | SHORT / Negativo |
| ✅ | Sucesso / Aprovado |
| ❌ | Falha / Rejeitado |
| 🛡️ | Proteção / Trailing |
| ⚠️ | Aviso / Alerta |
| 🚨 | Crítico / Urgente |
| 📈 | Tendência alta |
| 📉 | Tendência baixa |
| 💎 | Gem |
| 🔬 | Discovery |
| 🚀 | Momentum |
| 📊 | Dashboard |
| ℹ️ | Informação |

---

## 🔄 Compatibilidade

V2 mantém **compatibilidade total** com código antigo:

```powershell
# Essas funções ainda funcionam:
Send-TelegramAlert -Message "..."
Send-GemAlert -Gem $gem
Format-TgGemApproval -Gem $gem
Format-TgGemExecuted -ExecResult $result -Gem $gem
```

---

## 📞 Próximos Passos

1. Copiar `lib_telegram_v2.ps1` para `agents/`
2. Atualizar scripts para usar V2
3. Testar com paper trade
4. Deploy em produção

---

**Criado**: 2026-05-26  
**Status**: ✅ PRONTO
