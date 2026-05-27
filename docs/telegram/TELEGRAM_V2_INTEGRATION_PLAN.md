# 📱 TELEGRAM V2 - Plano de Integração

**Data**: 2026-05-26  
**Objetivo**: Integrar V2 em todos os scripts que usam Telegram  
**Tempo Estimado**: 2-3 horas  
**Risco**: BAIXO (compatibilidade total com V1)

---

## 📋 Scripts a Atualizar

### 1. `scan_master.ps1` — Descoberta de Gems
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\agents\scan_master.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~50):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES (linha ~446):
$msg = Format-TgGemApproval -Gem $gem
Telegram-SendMessage -Message $msg

# DEPOIS:
Telegram-SendGemApprovalRequest -Gem $gem
```

**Impacto**: Mensagens de aprovação de gems mais limpas

---

### 2. `gem_agent.ps1` — Análise de Gems
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\agents\gem_agent.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~30):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES:
Send-GemAlert -Gem $gem

# DEPOIS:
Telegram-SendGemFound -Gem $gem
```

**Impacto**: Alertas de gems encontrados mais concisos

---

### 3. `gem_executor.ps1` — Execução de Gems
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\agents\gem_executor.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~30):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES (linha ~642):
$msg = Format-TgGemExecuted -ExecResult $result -Gem $gem
Telegram-SendMessage -Message $msg

# DEPOIS:
Telegram-SendGemExecuted -Gem $gem -ExecResult $result
```

**Impacto**: Confirmação de execução mais clara

---

### 4. `trailing_stop_monitor.ps1` — Monitoramento de Posições
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\scripts\trailing_stop_monitor.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~50):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES:
Telegram-SendTrailingActivated -Position @{
    market = $pos.market
    entry_price = $pos.entry_price
    current_price = $pos.current_price
    profit_pct = $pos.profit_pct
    new_stop = $pos.new_stop
    locked_profit_pct = $pos.locked_profit_pct
}

# DEPOIS (sem mudança necessária - compatível):
Telegram-SendTrailingActivated -Position @{
    market = $pos.market
    profit_pct = $pos.profit_pct
    new_stop = $pos.new_stop
    locked_profit_pct = $pos.locked_profit_pct
}
```

**Impacto**: Mensagens de trailing mais limpas

---

### 5. `daily_summary_digest.ps1` — Resumo Diário
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\scripts\daily_summary_digest.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~30):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES:
Telegram-SendDailySummary -Summary @{
    trades_count = $stats.trades
    wins = $stats.wins
    losses = $stats.losses
    win_rate = $stats.win_rate
    daily_pnl = $stats.daily_pnl
    total_pnl = $stats.total_pnl
    open_positions = $stats.open_positions
    capital = $stats.capital
}

# DEPOIS (sem mudança necessária - compatível):
Telegram-SendDailySummary -Summary @{
    trades_count = $stats.trades
    wins = $stats.wins
    losses = $stats.losses
    win_rate = $stats.win_rate
    daily_pnl = $stats.daily_pnl
    total_pnl = $stats.total_pnl
    open_positions = $stats.open_positions
    capital = $stats.capital
}
```

**Impacto**: Resumo diário mais legível

---

### 6. `generate_dashboard_elite.ps1` — Dashboard
**Localização**: `c:\Users\thiag\Coinex_AI_USER_API\scripts\generate_dashboard_elite.ps1`

**Mudanças Necessárias**:

```powershell
# ANTES (linha ~50):
. ".\agents\lib_telegram.ps1"

# DEPOIS:
. ".\agents\lib_telegram_v2.ps1"
```

**Chamadas a Atualizar**:

```powershell
# ANTES (linha ~571):
Telegram-SendDashboardSnapshot -Metrics $metrics

# DEPOIS (sem mudança necessária - compatível):
Telegram-SendDashboardSnapshot -Metrics $metrics
```

**Impacto**: Dashboard snapshot mais compacto

---

## 🔄 Ordem de Integração Recomendada

### Fase 1: Crítico (1-2 horas)
1. ✅ `scan_master.ps1` — Descoberta de gems
2. ✅ `gem_executor.ps1` — Execução de gems
3. ✅ `daily_summary_digest.ps1` — Resumo diário

**Por quê**: Esses são os mais usados e têm maior impacto visual

---

### Fase 2: Importante (30-45 min)
4. ✅ `gem_agent.ps1` — Análise de gems
5. ✅ `trailing_stop_monitor.ps1` — Monitoramento

**Por quê**: Complementam a Fase 1

---

### Fase 3: Opcional (15-30 min)
6. ✅ `generate_dashboard_elite.ps1` — Dashboard

**Por quê**: Menos crítico, pode ser feito depois

---

## 📝 Checklist de Integração

### Para cada script:

- [ ] Fazer backup do arquivo original
- [ ] Atualizar import de lib (`.ps1`)
- [ ] Atualizar chamadas de funções
- [ ] Testar sintaxe (sem erros)
- [ ] Validar com paper trade
- [ ] Documentar mudanças

---

## 🧪 Teste de Integração

### Teste 1: Verificar Sintaxe
```powershell
# Para cada script:
. ".\agents\scan_master.ps1" -ErrorAction Stop
# Se não houver erro, está OK
```

### Teste 2: Teste com Paper Trade
```powershell
# Rodar com PAPER_TRADE_MODE ativo
$env:PAPER_TRADE_MODE = "1"
.\agents\scan_master.ps1
# Verificar se mensagens Telegram são enviadas corretamente
```

### Teste 3: Validar Formatação
```powershell
# Verificar no Telegram:
# - Mensagens aparecem corretamente
# - Emojis estão visíveis
# - Quebras de linha estão OK
# - Nenhuma informação foi perdida
```

---

## 📊 Impacto por Script

| Script | Mudanças | Impacto | Risco |
|---|---|---|---|
| `scan_master.ps1` | 2 | Alto | Baixo |
| `gem_agent.ps1` | 2 | Médio | Baixo |
| `gem_executor.ps1` | 2 | Médio | Baixo |
| `trailing_stop_monitor.ps1` | 1 | Médio | Baixo |
| `daily_summary_digest.ps1` | 1 | Médio | Baixo |
| `generate_dashboard_elite.ps1` | 1 | Baixo | Baixo |

**Risco Total**: BAIXO (compatibilidade total)

---

## 🔙 Rollback Plan

Se algo der errado:

```powershell
# 1. Restaurar backup do script:
Copy-Item "script.ps1.backup" "script.ps1" -Force

# 2. Voltar para V1:
# Editar script e trocar:
# DE: . ".\agents\lib_telegram_v2.ps1"
# PARA: . ".\agents\lib_telegram.ps1"

# 3. Testar novamente
```

**Tempo de rollback**: < 5 minutos

---

## 📞 Próximos Passos

### Hoje (2026-05-26)
1. ✅ Revisar plano de integração
2. ✅ Aprovar mudanças
3. ⏳ Começar Fase 1

### Amanhã (2026-05-27)
1. Completar Fase 1 e 2
2. Testar com paper trade
3. Validar formatação Telegram

### Dia Seguinte (2026-05-28)
1. Completar Fase 3
2. Deploy em produção
3. Monitorar por 24h

---

## 📋 Template de Mudança

Para cada script, use este template:

```powershell
# ============================================================================
# TELEGRAM V2 MIGRATION - 2026-05-26
# ============================================================================
# ANTES: . ".\agents\lib_telegram.ps1"
# DEPOIS: . ".\agents\lib_telegram_v2.ps1"
#
# Mudanças:
# - Linha XXX: Telegram-SendXXX → Telegram-SendXXX (compatível)
# - Linha YYY: Format-TgXXX → Telegram-SendXXX (nova função)
#
# Impacto: Mensagens mais limpas e concisas
# ============================================================================

. ".\agents\lib_telegram_v2.ps1"
```

---

## 🎯 Conclusão

Integração de V2 é **simples, segura e de baixo risco**:

- ✅ Mudanças mínimas por script (1-2 linhas)
- ✅ Compatibilidade total com V1
- ✅ Pode ser feito em paralelo
- ✅ Rollback rápido se necessário

**Recomendação**: Começar integração hoje, completar em 2-3 dias.

---

**Criado por**: Kiro Agent  
**Data**: 2026-05-26  
**Status**: ✅ PRONTO PARA IMPLEMENTAÇÃO
