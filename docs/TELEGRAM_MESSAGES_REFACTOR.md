# 📱 Telegram Messages Refactor — 2026-05-26

## 🎯 Objetivo
Simplificar mensagens Telegram de **verbosas (10+ linhas)** para **compactas (2-4 linhas)** mantendo informação crítica.

---

## ✅ Funções Implementadas

### 1. **Format-TgTrailStopHit** (Novo)
Quando trailing stop é atingido:
```
📉 TRAILING STOP HIT — BTCUSDT
+5.2% | Preço: 42500
Stop: 40250 | Lucro: +$1050
```

### 2. **Format-TgTrailPhase** (Novo)
Quando fase de trailing muda:
```
🟠 TRAILING PHASE 1 → 2 — ETHUSDT
Preço: 2250 | Stop: 2100 → 2150
```

### 3. **Wait-TgCallbackApproval** (Novo)
Aguarda aprovação do usuário via Telegram (polling a cada 5s, timeout 300s).

---

## 📊 Mensagens Refatoradas

### Position Opened
**ANTES (11 linhas):**
```
==========================
>> POSITION OPENED <<
==========================

Market: BTCUSDT
Side: LONG
Entry: $42000
Size: 0.5
Leverage: 10x

Stop Loss: $40000
Take Profit: $45000

Capital: $500 USDT
```

**DEPOIS (1 linha):**
```
📈 BTCUSDT | Entry: $42000 | Size: 0.5
Stop: $40000 | TP: $45000
```

---

### Position Closed
**ANTES (10 linhas):**
```
==========================
>> POSITION CLOSED [WIN] <<
==========================

Market: BTCUSDT
Side: LONG
Entry: $42000
Exit: $43500

PnL: +$750 (+1.79%)
Duration: 2h 30m
Reason: take_profit_hit
```

**DEPOIS (2 linhas):**
```
✅ WIN | BTCUSDT | +$750 (+1.79%)
Duration: 2h 30m | Reason: take_profit_hit
```

---

### Trailing Activated
**ANTES (9 linhas):**
```
==========================
>> TRAILING STOP ACTIVE <<
==========================

Market: BTCUSDT
Entry: $42000
Current: $43500
Profit: +3.6%

New Stop: $42500
Locked Profit: +1.2%
```

**DEPOIS (3 linhas):**
```
🎯 TRAILING ACTIVE | BTCUSDT
Entry: $42000 → Current: $43500 (+3.6%)
New Stop: $42500
```

---

### Risk Alert
**ANTES (9 linhas):**
```
==========================
>> RISK ALERT <<
==========================

Market: BTCUSDT
Type: liquidation_warning
Severity: HIGH

Current: $39500
Liquidation: $38000
Distance: 3.8%

Action: reduce_position
```

**DEPOIS (3 linhas):**
```
🔴 RISK ALERT | BTCUSDT
Current: $39500 | Liq: $38000 | Distance: 3.8%
Action: reduce_position
```

---

### Daily Summary
**ANTES (12 linhas):**
```
==========================
>> DAILY SUMMARY [UP] <<
==========================

Date: 2026-05-26

Trades: 5
Wins: 3 | Losses: 2
Win Rate: 60%

Daily PnL: +$1250
Total PnL: +$5680

Open Positions: 2
Capital: $10000 USDT
```

**DEPOIS (2 linhas):**
```
📈 DAILY SUMMARY | Trades: 5 | W/L: 3/2 | WR: 60%
Daily: +$1250 | Total: +$5680 | Open: 2
```

---

### Dashboard Snapshot
**ANTES (13+ linhas):**
```
==========================
>> DASHBOARD SNAPSHOT <<
==========================

Open Positions: 2
Total P&L: +$5680 [UP]
Win Rate: 60% [GOOD]
Capital: $10000 USDT

Sharpe Ratio: 1.45
Max Drawdown: 8.2%
Profit Factor: 2.1

--- Open Positions ---
[LONG] BTCUSDT: +2.5%
[SHORT] ETHUSDT: -1.2%
```

**DEPOIS (3-4 linhas):**
```
📈 DASHBOARD | P&L: +$5680 | WR: 60% | Open: 2
Capital: $10000 | Sharpe: 1.45 | DD: 8.2%
[L] BTCUSDT: +2.5%
[S] ETHUSDT: -1.2%
```

---

### Gem Alert
**ANTES (7 linhas):**
```
🔬 GEM ALERT — ZKJUSDT [SPOT]
🟢 Score: 85/100 | Modo: DISCOVERY

📊 Vol spike: 3.2x | Chg 24h: 22.5%
💰 Sizing: 0.5% ($13.81)

Pump classic pattern detected
```

**DEPOIS (2 linhas):**
```
🔬 ZKJUSDT | Score: 🟢85 | Vol: 3.2x ↑22.5%
💰 Size: $13.81 | Mode: DISCOVERY
```

---

### Gem Approval
**ANTES (11 linhas):**
```
🔬 GEM APROVAR — ZKJUSDT
Score: 85/100 | Modo: DISCOVERY

📊 CONTEXTO
Vol spike: 3.2x | Chg 24h: 22.5%
MCap: 45.2M | FP: PUMP_CLASSIC
Gates: G1 G2 G3

💰 SIZING
Tamanho: 0.5% ($13.81)
Stop: 50% | Target: +200%

✅ APROVAR este gem?
```

**DEPOIS (3 linhas):**
```
🔬 APPROVE — ZKJUSDT | Score: 85 | Vol: 3.2x ↑22.5%
💰 $13.81 | Stop: 50% | Target: +200%
✅ Approve?
```

---

### Gem Executed
**ANTES (3 linhas):**
```
✅ EXECUTADO — ZKJUSDT [DISCOVERY]
Score: 85/100 | Tamanho: $13.81
```

**DEPOIS (1 linha):**
```
✅ ZKJUSDT [DISCOVERY] | Score: 85 | Size: $13.81
```

---

## 🎨 Padrão de Emojis

| Situação | Emoji | Significado |
|----------|-------|-------------|
| Posição LONG | 📈 | Subindo |
| Posição SHORT | 📉 | Descendo |
| Trailing Ativo | 🎯 | Alvo |
| Risco ALTO | 🔴 | Crítico |
| Risco MÉDIO | 🟠 | Atenção |
| Risco BAIXO | 🟡 | Aviso |
| Tendência UP | 📈 | Positivo |
| Tendência DOWN | 📉 | Negativo |
| Gem Discovery | 🔬 | Descoberta |
| Gem Momentum | 🚀 | Impulso |
| Score Alto (80+) | 🟢 | Excelente |
| Score Médio (65-79) | 🟡 | Bom |
| Score Baixo (<65) | 🟠 | Fraco |
| Fase 1 | 🟡 | Inicial |
| Fase 2 | 🟠 | Intermediária |
| Fase 3 | 🟢 | Avançada |

---

## 📏 Limites de Linhas

- **Position Opened**: 2 linhas
- **Position Closed**: 2 linhas
- **Trailing Activated**: 3 linhas
- **Risk Alert**: 3 linhas
- **Daily Summary**: 2 linhas
- **Dashboard**: 3-4 linhas (com posições)
- **Gem Alert**: 2 linhas
- **Gem Approval**: 3 linhas
- **Gem Executed**: 1 linha

**Total redução**: ~70% menos linhas, ~80% menos caracteres

---

## 🔧 Implementação

Todas as funções estão em:
```
C:\Users\thiag\Coinex_AI_USER_API\agents\lib_telegram.ps1
```

Carregadas automaticamente por `scan_master.ps1`.

---

## ✨ Benefícios

✅ **Mais rápido de ler** — Informação crítica em 2-3 linhas  
✅ **Menos ruído** — Sem separadores ou formatação excessiva  
✅ **Emojis visuais** — Status imediato sem ler texto  
✅ **Hierarquia clara** — Crítico → Contexto → Ação  
✅ **Mobile-friendly** — Cabe em tela pequena  
✅ **Consistente** — Mesmo padrão em todas as mensagens  

---

## 📝 Notas

- Mensagens usam HTML formatting do Telegram (`<b>`, `<code>`, `<i>`)
- Quebras de linha com `\n` (não `\r\n`)
- Valores monetários sempre com `$` e 2 casas decimais
- Percentuais com `%` e 1-2 casas decimais
- Emojis no início para identificação rápida

---

**Data**: 2026-05-26  
**Versão**: 1.0  
**Status**: ✅ Produção
